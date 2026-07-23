import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../services/supabase_service.dart';
import '../services/db_helper.dart';
import '../services/sync_outbox_service.dart';
import '../screens/tasks_screen.dart'; // To access TaskItem class

class InspectionProvider extends ChangeNotifier {
  TaskItem? _activeTask;
  int _currentStep = 1;

  // Checklist State
  final Map<String, bool> _siteCondition = {
    'Structure matches declared use': true,
    'Setback distances compliant': true,
  };
  final Map<String, bool> _zoningObservations = {
    'Accessibility & road frontage': true,
    'Surrounding developments noted': false,
    'Signage / commercial activity present': false,
  };

  // Photo Evidence State
  final List<Map<String, dynamic>> _capturedPhotos = [];

  // Findings State
  String _actualLandUse = 'Single-detached residential';
  String _notes = '';
  String _discrepancies = '';
  String _recommendations = '';
  String _boundaryStatus = 'Compliant';
  String _inspectionResult = 'Compliant'; // Selected assessment result

  bool _isSyncing = false;
  bool _isReworkMode = false;

  // Getters
  TaskItem? get activeTask => _activeTask;
  int get currentStep => _currentStep;
  Map<String, bool> get siteCondition => _siteCondition;
  Map<String, bool> get zoningObservations => _zoningObservations;
  List<Map<String, dynamic>> get capturedPhotos => _capturedPhotos;
  String get actualLandUse => _actualLandUse;
  String get notes => _notes;
  String get discrepancies => _discrepancies;
  String get recommendations => _recommendations;
  String get boundaryStatus => _boundaryStatus;
  String get inspectionResult => _inspectionResult;
  bool get isSyncing => _isSyncing;
  bool get isReworkMode => _isReworkMode;

  // --- INITIALIZATION & NAVIGATION ---

  Future<void> startInspection(TaskItem task) async {
  _activeTask = task;
  _isReworkMode = false;

  // Reset defaults first
  _siteCondition.updateAll(
    (key, value) =>
        key == 'Surrounding developments noted' ||
            key == 'Signage / commercial activity present'
        ? false
        : true,
  );
  _zoningObservations.updateAll(
    (key, value) => key == 'Accessibility & road frontage' ? true : false,
  );
  _capturedPhotos.clear();
  _actualLandUse = 'Single-detached residential';
  _notes = '';
  _discrepancies = '';
  _recommendations = '';
  _boundaryStatus = 'Compliant';
  _inspectionResult = 'Compliant';

  // Load persisted draft AFTER reset — this restores checklist, findings,
  // photos, AND current_step from the task's own SQLite row.
  // Each task has its own row so step can never bleed across tasks.
  final draft = await DBHelper.getLocalInspection(task.id);
  _currentStep = (draft?['current_step'] as int?) ?? 1;
  if (_currentStep < 1) _currentStep = 1;

  await _loadLocalDraftIfExists(task.id);
  notifyListeners();
}

  Future<void> updateStep(int step) async {
  _currentStep = step;
  notifyListeners();

  if (_activeTask == null) return;

  // Persist to SQLite immediately — survives app restart, task switching,
  // and internet loss. This is the core fix for Bug 1.
  final draft = await DBHelper.getLocalInspection(_activeTask!.id);
  if (draft != null) {
    final db = await DBHelper.database;
    await db.update(
      'local_inspections',
      {
        'current_step': step,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [_activeTask!.id],
    );
  }

  // Also push to Supabase if online — falls back to the offline outbox
  // if it's not (or the request fails anyway), so the step is guaranteed
  // to reach Supabase eventually instead of being silently lost.
  //
  // RE-FIX (2026-07-23): this outbox fallback was previously implemented
  // (Phase 1 audit item #9) but was found reverted back to the old
  // best-effort-only version — likely from an older inspection_provider.dart
  // getting merged back in during unrelated work elsewhere. The
  // `current_step_update` action type + `enqueueCurrentStepUpdate()` in
  // SyncOutboxService were never removed, only this call site was — so
  // this re-fix is just reconnecting the two, not rebuilding anything.
  try {
    final isConnected = await _checkConnectivity();
    if (isConnected) {
      await SupabaseService.updateJobInspectionProgress(
        jobId: _activeTask!.id,
        updateData: {'current_step': step},
      );
    } else {
      await SyncOutboxService.enqueueCurrentStepUpdate(
        jobId: _activeTask!.id,
        step: step,
      );
    }
  } catch (e) {
    debugPrint('updateStep: direct Supabase push failed, queuing for retry — $e');
    try {
      await SyncOutboxService.enqueueCurrentStepUpdate(
        jobId: _activeTask!.id,
        step: step,
      );
    } catch (e2) {
      debugPrint('updateStep: failed to queue current_step update — $e2');
    }
  }
}

  // --- CHECKLIST UPDATE METHODS ---

  void setSiteCondition(String key, bool value) {
    _siteCondition[key] = value;
    notifyListeners();
  }

  void setZoningObservation(String key, bool value) {
    _zoningObservations[key] = value;
    notifyListeners();
  }

  // --- PHOTO METHODS ---

  void addPhoto({
    required String photoPath,
    required String photoNotes,
    required double? latitude,
    required double? longitude,
  }) {
    _capturedPhotos.add({
      // ROOT-CAUSE FIX (2026-07-23) — Duplicate Photos Bug: this id used
      // to NOT exist here. `saveAllInspectionState()` (and the older,
      // unused `saveInspectionProgress()`) generated a *fresh* random
      // `Uuid().v4()` for every photo, every single time either function
      // ran — so if the inspector's progress got saved more than once
      // while the same photos were still sitting in `_capturedPhotos`
      // (e.g. once per step transition), each save call re-inserted every
      // photo taken so far as a BRAND NEW `local_photos` row with a brand
      // new id. `savePhotoLocally()` uses `ConflictAlgorithm.replace`,
      // which would have safely no-op'd repeat saves of the *same* id —
      // but a fresh id every time defeats that entirely. Each of those
      // "new" rows then looked unsynced and got uploaded to Supabase as
      // its own row too (real, unique captures — 3 photos became 6+ rows
      // in `field_job_photos` after two saves).
      // Fix: generate the id ONCE, here, at capture time, and have every
      // save path below reuse this same id instead of minting a new one.
      'id': const Uuid().v4(),
      'photoPath': photoPath,
      'notes': photoNotes,
      'latitude': latitude,
      'longitude': longitude,
      'capturedAt': DateTime.now().toIso8601String(),
    });
    notifyListeners();
  }

  void removePhoto(int index) {
    _capturedPhotos.removeAt(index);
    notifyListeners();
  }

  // --- FINDINGS METHODS ---

  void updateFindings({
    required String actualLandUse,
    required String notes,
    required String discrepancies,
    required String recommendations,
    required String boundaryStatus,
  }) {
    _actualLandUse = actualLandUse;
    _notes = notes;
    _discrepancies = discrepancies;
    _recommendations = recommendations;
    _boundaryStatus = boundaryStatus;
    notifyListeners();
  }

  // Called by GpsVerificationScreen right after a successful on-site
  // confirmation, so Step 5 (Findings) reflects the real GPS result
  // instead of a hardcoded placeholder string.
  void recordGpsVerification({required double distanceMeters}) {
    _boundaryStatus =
        'Verified on-site — ${distanceMeters.round()}m from declared location';
    notifyListeners();
  }

  void updateResult(String result) {
    _inspectionResult = result;
    notifyListeners();
  }

  /// Rebuilds in-memory state from a completed job's real submitted data,
  /// instead of the blanks `startInspection` uses. Called on "Rework this
  /// step" — unlike startInspection, this does NOT reset anything, so the
  /// inspector doesn't lose the other steps' answers.
  void hydrateForRework(TaskItem task) {
    _activeTask = task;
    _isReworkMode = true;
    _currentStep = 1;
    _isReworkMode = true;

    // Match stored checklist entries back onto the two known maps.
    // Expects each entry to look like {'label': ..., 'value': true/false} —
    // adjust the keys below if your actual checklist_data shape differs.
    for (final entry in task.checklistData) {
      final key = entry['label'] ?? entry['key'];
      final value = entry['value'] ?? entry['checked'];
      if (key == null) continue;
      if (_siteCondition.containsKey(key)) {
        _siteCondition[key] = value == true;
      } else if (_zoningObservations.containsKey(key)) {
        _zoningObservations[key] = value == true;
      }
    }

    // Photos — only paths were persisted on field_jobs.photo_paths (no
    // notes/lat/lng), so those come back empty. If you want that metadata
    // to survive a rework round-trip, pull from field_job_photos instead,
    // which DOES have latitude/longitude/captured_at.
    _capturedPhotos
      ..clear()
      ..addAll(
        task.photoPaths.map(
          (path) => {
            'photoPath': path,
            'notes': '',
            'latitude': null,
            'longitude': null,
            'capturedAt': task.submittedAt,
          },
        ),
      );

    _notes = task.inspectorNotes ?? '';
    _discrepancies = task.discrepancies ?? '';
    _recommendations = task.recommendations ?? '';
    _inspectionResult =
        task.inspectionResult ??
        (task.isCompliant == true ? 'Compliant' : 'With Discrepancy');
    _boundaryStatus = task.isCompliant == false ? 'Non-compliant' : 'Compliant';
    // NOTE: `observations` was historically written as one freeform
    // sentence (e.g. "Actual land use: X. Boundary status: Y.") rather than
    // matching `_actualLandUse` 1:1 — I'm not auto-parsing that back apart
    // since it'd be guesswork. If you want exact round-trip, the fix is
    // upstream: store actualLandUse as its own column instead of folding
    // it into `observations`.

    notifyListeners();
  }
  // --- LOCAL SQLite DRAFT RECOVERY ---

  Future<void> _loadLocalDraftIfExists(String jobId) async {
    final draft = await DBHelper.getLocalInspection(jobId);
    if (draft != null) {
      _actualLandUse = draft['actual_land_use'] ?? _actualLandUse;
      _notes = draft['notes'] ?? _notes;
      _boundaryStatus = draft['boundary_status'] ?? _boundaryStatus;
      _inspectionResult =
          draft['inspection_result'] as String? ??
          (draft['is_compliant'] == 1 ? 'Compliant' : 'With Discrepancy');

      if (draft['checklist_json'] != null) {
        try {
          final Map<String, dynamic> checklist = jsonDecode(
            draft['checklist_json'],
          );
          checklist.forEach((key, value) {
            if (_siteCondition.containsKey(key))
              _siteCondition[key] = value == true;
            if (_zoningObservations.containsKey(key))
              _zoningObservations[key] = value == true;
          });
        } catch (e) {
          debugPrint('Error decoding local checklist: $e');
        }
      }
    }

    final localPhotos = await DBHelper.getLocalPhotos(jobId);
    if (localPhotos.isNotEmpty) {
      _capturedPhotos.clear();
      for (final p in localPhotos) {
        _capturedPhotos.add({
          'id': p['id'], // reuse the existing local_photos row id (see addPhoto() fix)
          'photoPath': p['photo_path'],
          'notes': p['notes'],
          'latitude': p['latitude'],
          'longitude': p['longitude'],
          'capturedAt': p['captured_at'],
        });
      }
    }
    notifyListeners();
  }

  // --- LOCAL SAVE & ONLINE SYNC ---

  Future<bool> saveInspectionProgress() async {
    if (_activeTask == null) return false;

    // Save Checklist observations
    final Map<String, bool> combinedChecklist = {
      ..._siteCondition,
      ..._zoningObservations,
    };

    // 1. Save main inspection details to local sqlite
    await DBHelper.saveInspectionLocally(
      jobId: _activeTask!.id,
      actualLandUse: _actualLandUse,
      notes: _notes,
      isCompliant: _inspectionResult == 'Compliant',
      inspectionResult: _inspectionResult,
      checklist: combinedChecklist,
      boundaryStatus: _boundaryStatus,
      currentStep: _currentStep,
    );

    // 2. Save photos to local sqlite
    for (final photo in _capturedPhotos) {
      // Reuse the stable id set in addPhoto()/reload instead of minting a
      // new one each call — see the fix comment in addPhoto() for why.
      final photoId = photo['id'] as String? ?? const Uuid().v4();
      await DBHelper.savePhotoLocally(
        photoId: photoId,
        jobId: _activeTask!.id,
        photoPath: photo.containsKey('photoPath') ? photo['photoPath'] : '',
        notes: photo.containsKey('notes') ? photo['notes'] : '',
        latitude: photo['latitude'],
        longitude: photo['longitude'],
      );
    }

    notifyListeners();

    // 3. Attempt to Sync automatically if online
    final isConnected = await _checkConnectivity();
    if (isConnected) {
      await syncToServer();
      return true;
    }
    return false; // Stored offline
  }


  // --- REWORK: PER-STEP SAVE (writes immediately, no need to reach Submit) ---

  Future<bool> saveStepPhotos() async {
    if (_activeTask == null) return false;
    try {
      // Filter out any entries without a valid photo path, but keep the full Map structure
      final photosToUpload = _capturedPhotos
          .where((p) => (p['photoPath'] as String?)?.isNotEmpty == true)
          .toList();

      // Pass the full list of maps as photosData
      final uploadedUrls = await SupabaseService.uploadInspectionPhotos(
        jobId: _activeTask!.id,
        photosData: photosToUpload,
      );

      // Update the main field_jobs table to maintain the array of URLs for quick access
      await SupabaseService.updateJobInspectionProgress(
        jobId: _activeTask!.id,
        updateData: {
          'photo_paths': uploadedUrls,
          'photo_count': uploadedUrls.length,
        },
      );
      return true;
    } catch (e) {
      debugPrint('saveStepPhotos failed: $e');
      return false;
    }
  }

  Future<bool> saveStepChecklist() async {
    if (_activeTask == null) return false;
    try {
      final checklist = <Map<String, dynamic>>[
        ..._siteCondition.entries.map(
          (e) => {'item': e.key, 'checked': e.value},
        ),
        ..._zoningObservations.entries.map(
          (e) => {'item': e.key, 'checked': e.value},
        ),
      ];
      final done = checklist.where((c) => c['checked'] == true).length;
      await SupabaseService.updateJobInspectionProgress(
        jobId: _activeTask!.id,
        updateData: {
          'checklist_data': checklist,
          'checklist_completed_count': done,
          'checklist_total_count': checklist.length,
        },
      );
      return true;
    } catch (e) {
      debugPrint('saveStepChecklist failed: $e');
      return false;
    }
  }

  Future<bool> saveStepFindings() async {
    if (_activeTask == null) return false;
    try {
      await SupabaseService.updateJobInspectionProgress(
        jobId: _activeTask!.id,
        updateData: {
          'observations':
              'Actual land use: $_actualLandUse. Boundary status: $_boundaryStatus.',
          'discrepancies': _discrepancies.isNotEmpty ? _discrepancies : null,
          'recommendations': _recommendations.isNotEmpty
              ? _recommendations
              : null,
          'inspector_notes': _notes,
        },
      );
      return true;
    } catch (e) {
      debugPrint('saveStepFindings failed: $e');
      return false;
    }
  }

  /// "Save All" — pushes everything currently in the provider back to the
  /// job, and restores status to 'completed' so the rework session closes
  /// cleanly instead of leaving the job stuck as in_progress.
  Future<bool> saveAllAndClose() async {
    if (_activeTask == null) return false;
    try {
      await saveStepPhotos();
      await saveStepChecklist();
      await saveStepFindings();
      await SupabaseService.updateJobInspectionProgress(
        jobId: _activeTask!.id,
        updateData: {'status': 'completed'},
      );
      await SupabaseService.logActivity(
        eventType: 'inspection_completed',
        title: 'Rework saved',
        subtitle: _activeTask!.location,
        fieldJobId: _activeTask!.id,
      );
      _isReworkMode = false;
      return true;
    } catch (e) {
      debugPrint('saveAllAndClose failed: $e');
      return false;
    }
  }

  /// Comprehensive save-all helper that persists the current inspection
  /// snapshot and also preserves the current rework mode alongside the
  /// task context for later resume/review flows.
  Future<bool> saveAllInspectionState() async {
    if (_activeTask == null) return false;

    final Map<String, bool> combinedChecklist = {
      ..._siteCondition,
      ..._zoningObservations,
    };

    await DBHelper.saveInspectionLocally(
      jobId: _activeTask!.id,
      actualLandUse: _actualLandUse,
      notes: _notes,
      isCompliant: _inspectionResult == 'Compliant',
      inspectionResult: _inspectionResult,
      checklist: combinedChecklist,
      boundaryStatus: _boundaryStatus,
      currentStep: _currentStep,
    );

    for (final photo in _capturedPhotos) {
      // ROOT-CAUSE FIX (2026-07-23) — see addPhoto() for the full
      // explanation. Reusing the stable id set at capture time means a
      // repeat call to this function (e.g. on a second step transition
      // while the same photos are still in memory) safely replaces the
      // same local_photos row (ConflictAlgorithm.replace) instead of
      // inserting a brand new one — so photos captured once are only
      // ever uploaded/counted once, no matter how many times progress
      // gets auto-saved.
      final photoId = photo['id'] as String? ?? const Uuid().v4();
      await DBHelper.savePhotoLocally(
        photoId: photoId,
        jobId: _activeTask!.id,
        photoPath: photo.containsKey('photoPath') ? photo['photoPath'] : '',
        notes: photo.containsKey('notes') ? photo['notes'] : '',
        latitude: photo['latitude'],
        longitude: photo['longitude'],
      );
    }

    notifyListeners();

    final isConnected = await _checkConnectivity();
    if (isConnected) {
      await syncToServer();
      return true;
    }
    return false;
  }

  Future<bool> _checkConnectivity() async {
    final dynamic result = await Connectivity().checkConnectivity();
    if (result is ConnectivityResult) {
      return result != ConnectivityResult.none;
    }
    if (result is List) {
      return result.cast<ConnectivityResult>().any(
        (status) => status != ConnectivityResult.none,
      );
    }
    return false;
  }

  Future<void> syncToServer() async {
    if (_isSyncing) return;
    _isSyncing = true;
    notifyListeners();

    try {
      final supabase = SupabaseService.client;

      // 1. Sync Pending Photos first (needed for database metadata joins)
      final pendingPhotos = await DBHelper.getPendingPhotos();
      // BUG FIX #4B — Image Presentation Bug.
      // This used to only upsert into field_job_photos and never touch
      // field_jobs.photo_paths, so that column kept whatever local device
      // paths were written when the photo was first captured. Any screen
      // that reads task.photoPaths (which comes straight from
      // field_jobs.photo_paths) then tried Image.network() on a local
      // filesystem path and fell straight into the gray/broken-image
      // fallback — even though the photo really did make it to storage.
      // Track uploaded public URLs per job here and patch field_jobs too.
      final Map<String, List<String>> uploadedUrlsByJob = {};
      for (final photo in pendingPhotos) {
        final file = File(photo['photo_path']);
        if (!await file.exists()) {
          await DBHelper.markPhotoSynced(photo['id']);
          continue;
        }

        final fileName = 'photo_${photo['id']}.jpg';
        final storagePath = 'inspections/${photo['job_id']}/$fileName';

        await supabase.storage
            .from('inspection-photos')
            .upload(
              storagePath,
              file,
              fileOptions: const FileOptions(
                cacheControl: '3600',
                upsert: true,
              ),
            );

        final publicUrl = supabase.storage
            .from('inspection-photos')
            .getPublicUrl(storagePath);

        await supabase.from('field_job_photos').upsert({
          'id': photo['id'],
          'field_job_id': photo['job_id'],
          'photo_url': publicUrl,
          'latitude': photo['latitude'],
          'longitude': photo['longitude'],
          'captured_at': photo['captured_at'],
        });

        uploadedUrlsByJob.putIfAbsent(photo['job_id'], () => []).add(publicUrl);
        await DBHelper.markPhotoSynced(photo['id']);
      }

      // Patch field_jobs.photo_paths / photo_count for every job that had a
      // photo land in storage this pass — merging with whatever real (http)
      // URLs were already there so re-syncs don't clobber earlier uploads.
      for (final entry in uploadedUrlsByJob.entries) {
        try {
          final existing = await supabase
              .from('field_jobs')
              .select('photo_paths')
              .eq('id', entry.key)
              .maybeSingle();
          final existingPaths = ((existing?['photo_paths'] as List?) ?? [])
              .cast<String>()
              .where((p) => p.startsWith('http'))
              .toList();
          final merged = {...existingPaths, ...entry.value}.toList();
          await supabase
              .from('field_jobs')
              .update({'photo_paths': merged, 'photo_count': merged.length})
              .eq('id', entry.key);
        } catch (e) {
          debugPrint(
            'Could not patch field_jobs.photo_paths for ${entry.key}: $e',
          );
        }
      }

      if (pendingPhotos.isNotEmpty) {
        await SupabaseService.logActivity(
          eventType: 'photos_synced',
          title: 'Offline photos synced',
          subtitle: '${pendingPhotos.length} photo(s) uploaded',
        );
      }

      // 2. Sync Pending Inspections
      final pendingInspections = await DBHelper.getPendingInspections();
      for (final insp in pendingInspections) {
        final Map<String, dynamic> checklist = jsonDecode(
          insp['checklist_json'],
        );
        final checklistSummary = checklist.entries
            .map((e) => '${e.key}: ${e.value == true ? "Yes" : "No"}')
            .join('; ');

        await supabase
            .from('field_jobs')
            .update({
              'status': 'completed',
              'findings': '${insp['notes']}\n\nChecklist: $checklistSummary',
              'is_compliant': insp['is_compliant'] == 1,
              'inspection_result':
                  insp['inspection_result'] as String? ??
                  (insp['is_compliant'] == 1
                      ? 'Compliant'
                      : 'With Discrepancy'),
              'remarks': insp['boundary_status'],
              'updated_at': insp['updated_at'],
            })
            .eq('id', insp['id']);

        await DBHelper.markInspectionSynced(insp['id']);
      }

      if (pendingInspections.isNotEmpty) {
        await SupabaseService.logActivity(
          eventType: 'inspection_completed',
          title: 'Offline inspection synced',
          subtitle: '${pendingInspections.length} report(s) uploaded',
        );
      }
    } catch (e) {
      debugPrint('Sync failed: $e');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }
}