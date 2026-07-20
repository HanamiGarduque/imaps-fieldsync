import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../services/supabase_service.dart';
import '../services/db_helper.dart';
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

  void startInspection(TaskItem task) {
    _activeTask = task;
    _currentStep = 1;
    _isReworkMode = false;

    // Reset Checklist
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

    // Reset Photos
    _capturedPhotos.clear();

    // Reset Findings
    _actualLandUse = 'Single-detached residential';
    _notes = '';
    _discrepancies = '';
    _recommendations = '';
    _boundaryStatus = 'Compliant';
    _inspectionResult = 'Compliant';

    _loadLocalDraftIfExists(task.id);
    notifyListeners();
  }

  void updateStep(int step) {
    _currentStep = step;
    notifyListeners();
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
    );

    // 2. Save photos to local sqlite
    for (final photo in _capturedPhotos) {
      final photoId = const Uuid().v4();
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
    );

    for (final photo in _capturedPhotos) {
      final photoId = const Uuid().v4();
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
