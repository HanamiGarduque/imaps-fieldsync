import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/services/db_helper.dart';
import '../services/photo_source_resolver.dart';
import '../../../core/services/sync_outbox_service.dart';
import '../../tasks/screens/tasks_screen.dart'; // To access TaskItem class

class InspectionProvider extends ChangeNotifier {
  TaskItem? _activeTask;
  String? _inspectorId;
  void _requireOwner() {
    if (_inspectorId == null) throw StateError('Inspection has no recorded session owner');
    DBHelper.requireSameInspector(_inspectorId!);
  }
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
  // Photos that have entered save/upload/queue work in this durable session.
  // A local row alone cannot prove a photo was never uploaded: the live
  // capture path can upload before a local_photos row is acknowledged.
  final Set<String> _photosWithRemoteWork = {};

  // Findings State
  String _actualLandUse = 'Single-detached residential';
  String _notes = '';
  String _discrepancies = '';
  String _recommendations = '';
  String _boundaryStatus = 'Compliant';
  String _inspectionResult = 'Compliant'; // Selected assessment result

  bool _isSyncing = false;
  bool _isReworkMode = false;
  // Issue 2 fix: true once rework_started_at has been written for the
  // CURRENT rework session — prevents writing it again on every
  // subsequent edit (only the first real edit needs to set it).
  bool _reworkModifiedMarked = false;

  // Getters
  bool get _visible => _inspectorId != null && _inspectorId == DBHelper.currentInspectorId;
  TaskItem? get activeTask => _visible ? _activeTask : null;
  int get currentStep => _visible ? _currentStep : 1;
  Map<String, bool> get siteCondition => _visible ? _siteCondition : {};
  Map<String, bool> get zoningObservations => _visible ? _zoningObservations : {};
  List<Map<String, dynamic>> get capturedPhotos => _visible ? _capturedPhotos : [];
  String get actualLandUse => _visible ? _actualLandUse : '';
  String get notes => _visible ? _notes : '';
  String get discrepancies => _visible ? _discrepancies : '';
  String get recommendations => _visible ? _recommendations : '';
  String get boundaryStatus => _visible ? _boundaryStatus : '';
  String get inspectionResult => _visible ? _inspectionResult : 'Compliant';
  bool get isSyncing => _isSyncing;
  bool get isReworkMode => _visible && _isReworkMode;

  void requireOwner() => _requireOwner();

  /// Clears every field observation. Used by both entry paths so no session's
  /// answers can reach another session's report.
  void _resetFieldState() {
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
  }

  // --- INITIALIZATION & NAVIGATION ---

  Future<void> startInspection(TaskItem task) async {
  _inspectorId = DBHelper.requireInspector();
  await DBHelper.requireOwnedJob(await DBHelper.database, task.id, _inspectorId!);
  _activeTask = task;
  _isReworkMode = false;

  // Reset defaults first
  _photosWithRemoteWork.clear();
  _resetFieldState();

  // Load persisted draft AFTER reset — this restores checklist, findings,
  // photos, AND current_step from the task's own SQLite row.
  // Each task has its own row so step can never bleed across tasks.
  final draft = await DBHelper.getLocalInspection(task.id);
  _currentStep = (draft?['current_step'] as int?) ?? 1;
  if (_currentStep < 1) _currentStep = 1;

  await _loadLocalDraftIfExists(task.id);
  notifyListeners();
}

  // NOTE (removed 2026-07-24): this class used to have an updateStep(int)
  // method that duplicated current_step persistence (SQLite + Supabase +
  // outbox fallback). Audit confirmed no screen ever called it — the only
  // live path is InspectionProgress.instance.markStepComplete(), which has
  // its own equivalent persistence in inspection_progress.dart's
  // _persistCurrentStep(). Removed instead of "re-fixing" again, since a
  // dead duplicate is a bigger long-term risk (someone edits the wrong copy)
  // than having only one source of truth for current_step writes.
  // If InspectionProvider ever needs to react to step changes (e.g. to
  // recompute checklist/photo state), read from
  // InspectionProgress.instance.currentStep instead of re-adding a second
  // writer.

  // --- CHECKLIST UPDATE METHODS ---

  /// Issue 2 fix: writes rework_started_at on the first actual edit of a
  /// rework session — not on entering rework mode (that's what
  /// reopenForRework() used to do, which is why merely opening a step and
  /// backing out with zero changes still showed "Modified"). Best-effort,
  /// no outbox fallback — if this particular write fails while offline,
  /// the badge just won't show until a later successful attempt; the
  /// actual edit itself is unaffected and still saved through its own
  /// (already offline-safe) path. Fire-and-forget so it never blocks the
  /// UI action that triggered it.
  void _markReworkModifiedIfNeeded() {
    if (!_isReworkMode || _reworkModifiedMarked || _activeTask == null) return;
    _reworkModifiedMarked = true;
    SupabaseService.updateJobInspectionProgress(
      jobId: _activeTask!.id,
      updateData: {'rework_started_at': DateTime.now().toIso8601String()},
    ).catchError((e) {
      debugPrint('markReworkModified failed (non-critical): $e');
    });
  }

  void setSiteCondition(String key, bool value) {
    _requireOwner();
    _siteCondition[key] = value;
    _markReworkModifiedIfNeeded();
    notifyListeners();
  }

  void setZoningObservation(String key, bool value) {
    _requireOwner();
    _zoningObservations[key] = value;
    _markReworkModifiedIfNeeded();
    notifyListeners();
  }

  // --- PHOTO METHODS ---

  void _markPhotoHasRemoteWork(Map<String, dynamic> photo) {
    final id = photo['id'] as String?;
    final path = photo['photoPath'] as String?;
    if (id != null && id.isNotEmpty) _photosWithRemoteWork.add(id);
    if (path != null && path.isNotEmpty) _photosWithRemoteWork.add(path);
  }

  bool _photoHasRemoteWork(Map<String, dynamic> photo) {
    final id = photo['id'] as String?;
    final path = photo['photoPath'] as String?;
    return (id != null && _photosWithRemoteWork.contains(id)) ||
        (path != null && _photosWithRemoteWork.contains(path));
  }

  /// Marks the current photo set as having entered the remote submission
  /// path. This is intentionally session-local: a later delete must not claim
  /// the photo is still local-only after an upload/queue attempt.
  void markPhotosSubmitted() {
    _requireOwner();
    for (final photo in _capturedPhotos) {
      _markPhotoHasRemoteWork(photo);
    }
  }

  void addPhoto({
    required String photoPath,
    required String photoNotes,
    required double? latitude,
    required double? longitude,
  }) {
    _requireOwner();
    _markReworkModifiedIfNeeded();
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

  /// Removes one captured photo only when it is still local, unacknowledged
  /// evidence. Submitted, completed, or rework evidence is immutable here.
  /// Returns false without changing memory when removal is not permitted or
  /// local cleanup fails, so the caller cannot report a false success.
  Future<bool> removePhoto(int index) async {
    _requireOwner();
    if (index < 0 || index >= _capturedPhotos.length) return false;

    final photo = _capturedPhotos[index];
    final photoId = photo['id'] as String?;
    final photoPath = photo['photoPath'] as String?;
    if (photoId == null || photoPath == null || photoPath.isEmpty) {
      return false;
    }
    if (PhotoSourceResolver.classify(photoPath) != PhotoSourceKind.localFile) {
      return false;
      }

    if (_isReworkMode ||
        _activeTask?.lifecycleCategory == TaskLifecycleCategory.completed) {
      return false;
    }

    final localRow = await DBHelper.getLocalPhoto(photoId);
    final locallyAcknowledged = localRow?['is_synced'] == 1;
    final knownRemote = photo['isRemoteUrl'] == true || _photoHasRemoteWork(photo);
    if (locallyAcknowledged || knownRemote) {
      return false;
    }

      try {
      await DBHelper.deleteLocalPhoto(photoId, photoPath: photoPath);
      } catch (e) {
      debugPrint('removePhoto: local file/row delete failed — $e');
      return false;
    }

    _markReworkModifiedIfNeeded();
    _capturedPhotos.removeAt(index);
    notifyListeners();
    return true;
  }

  // --- FINDINGS METHODS ---

  void updateFindings({
    required String actualLandUse,
    required String notes,
    required String discrepancies,
    required String recommendations,
    required String boundaryStatus,
  }) {
    _requireOwner();
    // Unlike the checklist toggles above, this is called from the step's
    // exit-save regardless of whether the inspector actually changed
    // anything — so mark-modified only if something genuinely differs,
    // otherwise merely visiting and leaving Findings during rework would
    // trip the same false "Modified" badge Issue 2 was about.
    final changed =
        actualLandUse != _actualLandUse ||
        notes != _notes ||
        discrepancies != _discrepancies ||
        recommendations != _recommendations ||
        boundaryStatus != _boundaryStatus;
    _actualLandUse = actualLandUse;
    _notes = notes;
    _discrepancies = discrepancies;
    _recommendations = recommendations;
    _boundaryStatus = boundaryStatus;
    if (changed) _markReworkModifiedIfNeeded();
    notifyListeners();
  }

  // Called by GpsVerificationScreen right after a successful on-site
  // confirmation, so Step 5 (Findings) reflects the real GPS result
  // instead of a hardcoded placeholder string.
  void recordGpsVerification({required double distanceMeters}) {
    _requireOwner();
    _boundaryStatus =
        'Verified on-site — ${distanceMeters.round()}m from declared location';
    notifyListeners();
  }

  void updateResult(String result) {
    _requireOwner();
    _inspectionResult = result;
    notifyListeners();
  }

  /// Rebuilds in-memory state from a completed job's real submitted data,
  /// instead of the blanks `startInspection` uses. Called on "Rework this
  /// step" — unlike startInspection, this does NOT reset anything, so the
  /// inspector doesn't lose the other steps' answers.
  void hydrateForRework(TaskItem task) {
    _inspectorId = DBHelper.requireInspector();
    _activeTask = task;
    _isReworkMode = true;
    _currentStep = 1;
    // Issue 2 fix (device-test finding — "Modified" badge appeared just
    // from opening Rework and backing out, with zero edits): this flag
    // gates the first actual write of rework_started_at to the first real
    // edit in THIS session, not to entering rework mode itself. Reset
    // here so a fresh rework session starts clean.
    _reworkModifiedMarked = false;
    _photosWithRemoteWork.clear();
    // A previous session's in-memory field observations must never survive
    // into this one. The rework payload below re-populates what it actually
    // carries; anything it does not carry starts from the same defaults
    // startInspection() uses rather than leaking a prior inspector's answer.
    _resetFieldState();

    // Match stored checklist entries back onto the two known maps.
    // FIX (Completed/Rework audit, Finding 2): this used to read
    // entry['label'] ?? entry['key'], but the checklist is actually
    // written as {'item': e.key, 'checked': e.value} everywhere it's
    // saved (submit, and every per-toggle autosave in
    // inspection_checklist_screen.dart) — 'label'/'key' never existed,
    // so `key` was always null here and every entry was silently
    // skipped. Rework's checklist step always reset to the hardcoded
    // defaults below instead of the inspector's actual prior answers,
    // directly contradicting the rework dialog's own promise that
    // "the rest of the submitted inspection stays as-is."
    for (final entry in task.checklistData) {
      final key = entry['item'];
      final value = entry['checked'];
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
    //
    // FIX (Completed/Rework audit, Finding 1): `path` here is a remote
    // Supabase Storage URL (field_jobs.photo_paths), not a local device
    // path. uploadInspectionPhotos() used to have no way to tell the
    // difference — it would compute a resume-check key from the URL
    // string itself (which never matches the row created from the
    // *original* local path at first upload), fall through to
    // File(url).exists() (always false for a URL), and silently `continue`
    // — dropping the photo from the resubmission with no error at all.
    // `isRemoteUrl: true` lets uploadInspectionPhotos short-circuit
    // straight to reusing this URL instead of touching the filesystem.
    _capturedPhotos
      ..clear()
      ..addAll(
        PhotoSourceResolver.evidence(task.photoDetails, task.photoPaths).map((
          photo,
        ) {
            final path = photo['photoPath'] as String;
            // Existing upload API uses this flag to preserve remote evidence;
            // never mark an arbitrary local/invalid value as remote.
            bool remote = PhotoSourceResolver.isObjectPath(path);
          if (PhotoSourceResolver.classify(path) ==
              PhotoSourceKind.remoteHttp) {
              try {
                remote = inspectionPhotoResolver().objectPath(path) != null;
              } catch (_) {
                remote = false;
              }
            }
            return {
              ...photo,
              'notes': photo['notes'] ?? '',
              'capturedAt': photo['captured_at'] ?? task.submittedAt,
              'isRemoteUrl': remote,
            };
        }),
      );

    for (final photo in _capturedPhotos) {
      _markPhotoHasRemoteWork(photo);
    }
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
    // Ownership was already established at entry, and every read below is
    // inspector-scoped, so this only hydrates memory.
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
            if (_siteCondition.containsKey(key)) {
              _siteCondition[key] = value == true;
            }
            if (_zoningObservations.containsKey(key)) {
              _zoningObservations[key] = value == true;
            }
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
          'id':
              p['id'], // reuse the existing local_photos row id (see addPhoto() fix)
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
    _requireOwner();
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
      _requireOwner();
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
    _requireOwner();
    if (_activeTask == null) return false;
    // Filter out any entries without a valid photo path, but keep the full Map structure
    final photosToUpload = _capturedPhotos
        .where((p) => (p['photoPath'] as String?)?.isNotEmpty == true)
        .toList();
    for (final photo in photosToUpload) {
      _markPhotoHasRemoteWork(photo);
    }
    try {
      // Pass the full list of maps as photosData
      final uploadedUrls = await SupabaseService.uploadInspectionPhotos(
        jobId: _activeTask!.id,
        photosData: photosToUpload,
      );

      // Update the main field_jobs table to maintain the array of URLs for quick access
      _requireOwner();
      await SupabaseService.updateJobInspectionProgress(
        jobId: _activeTask!.id,
        updateData: {
          'photo_paths': uploadedUrls,
          'photo_count': uploadedUrls.length,
        },
      );
      return true;
    } catch (e) {
      // Issue 4 fix (device-test finding — Task Overview showed "no
      // photos on file" for a finished step): this used to have no
      // offline fallback at all — a failed push (e.g. no connection) was
      // just logged and lost. Queue it instead, same as every other
      // step's save.
      debugPrint('saveStepPhotos: direct push failed, queuing for retry — $e');
      try {
        _requireOwner();
        await SyncOutboxService.enqueuePhotosUpdate(
          jobId: _activeTask!.id,
          photosData: photosToUpload,
        );
        return true; // queued — not lost, will apply once synced
      } catch (e2) {
        debugPrint('saveStepPhotos: failed to queue photos update — $e2');
        return false;
      }
    }
  }

  Future<bool> saveStepChecklist() async {
    _requireOwner();
    if (_activeTask == null) return false;
    final checklist = <Map<String, dynamic>>[
      ..._siteCondition.entries.map((e) => {'item': e.key, 'checked': e.value}),
      ..._zoningObservations.entries.map(
        (e) => {'item': e.key, 'checked': e.value},
      ),
    ];
    final done = checklist.where((c) => c['checked'] == true).length;
    try {
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
      // Consistency fix (offline/sync validation pass): this used to have
      // no fallback at all — a failed direct push (e.g. offline) just
      // returned false and the rework-mode "Save" button on the Checklist
      // screen showed "Save failed.", even though the per-toggle autosave
      // in inspection_checklist_screen.dart (_syncChecklistProgress) had
      // already queued the same state via SyncOutboxService moments
      // earlier — so no data was actually lost, but the message was
      // misleading. Now matches the same queue-on-failure pattern already
      // used by saveStepPhotos and saveStepFindings above.
      debugPrint(
        'saveStepChecklist: direct push failed, queuing for retry — $e',
      );
      try {
        _requireOwner();
        await SyncOutboxService.enqueueChecklistUpdate(
          jobId: _activeTask!.id,
          checklistData: checklist,
          checklistCompletedCount: done,
          checklistTotalCount: checklist.length,
        );
        return true; // queued — not lost, will apply once synced
      } catch (e2) {
        debugPrint('saveStepChecklist: failed to queue checklist update — $e2');
        return false;
      }
    }
  }

  Future<bool> saveStepFindings() async {
    _requireOwner();
    if (_activeTask == null) return false;
    final observations =
        'Actual land use: $_actualLandUse. Boundary status: $_boundaryStatus.';
    final discrepancies = _discrepancies.isNotEmpty ? _discrepancies : null;
    final recommendations = _recommendations.isNotEmpty
        ? _recommendations
        : null;
    try {
      await SupabaseService.updateJobInspectionProgress(
        jobId: _activeTask!.id,
        updateData: {
          'observations': observations,
          'discrepancies': discrepancies,
          'recommendations': recommendations,
          'inspector_notes': _notes,
        },
      );
      return true;
    } catch (e) {
      // Issue 4 fix — same rationale as saveStepPhotos above: no offline
      // fallback existed here before, so a failed push while offline was
      // silently lost instead of queued.
      debugPrint(
        'saveStepFindings: direct push failed, queuing for retry — $e',
      );
      try {
        _requireOwner();
        await SyncOutboxService.enqueueFindingsUpdate(
          jobId: _activeTask!.id,
          observations: observations,
          discrepancies: discrepancies,
          recommendations: recommendations,
          inspectorNotes: _notes,
        );
        return true;
      } catch (e2) {
        debugPrint('saveStepFindings: failed to queue findings update — $e2');
        return false;
      }
    }
  }

  /// Rework redesign: this used to be "Save All" — an explicit save button
  /// that pushed everything to Supabase and restored status to
  /// 'completed' (because entering rework used to flip it away). Neither
  /// is needed anymore: every step already auto-saves on its own exit
  /// (saveStepPhotos/saveStepChecklist/saveStepFindings, plus per-toggle
  /// checklist sync), and reopenForRework() no longer touches `status` at
  /// all, so there's nothing left to "restore." This is now just closing
  /// the rework session locally — rework_started_at intentionally stays
  /// set (the "Modified" badge should persist) until the inspector
  /// actually finalizes via Review & Submit, not just because they backed
  /// out of editing early.
  void exitReworkMode() {
    _isReworkMode = false;
    notifyListeners();
  }

  /// Comprehensive save-all helper that persists the current inspection
  /// snapshot and also preserves the current rework mode alongside the
  /// task context for later resume/review flows.
  Future<bool> saveAllInspectionState() async {
    _requireOwner();
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
      _requireOwner();
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
      _requireOwner();
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
      final uid = DBHelper.requireInspector();
      final supabase = SupabaseService.client;

      // 1. Sync pending local photos through the one canonical remote writer.
      // Legacy local_photos rows are adapted here; all NEW remote identities
      // now use job ID + stable local path + UUIDv5 through the service path.
      final pendingPhotos = await DBHelper.getPendingPhotos();
      final pendingPhotosByJob = <String, List<Map<String, dynamic>>>{};
      for (final photo in pendingPhotos) {
        final jobId = photo['job_id'] as String?;
        final photoPath = photo['photo_path'] as String?;
        if (jobId == null ||
            jobId.isEmpty ||
            photoPath == null ||
            photoPath.isEmpty) {
          continue;
        }
        pendingPhotosByJob.putIfAbsent(jobId, () => []).add({
          'localPhotoId': photo['id'],
          ...SupabaseService.photoUploadPayloadFromLegacyLocalRow(photo),
        });
      }

      final Map<String, List<String>> uploadedUrlsByJob = {};
      for (final entry in pendingPhotosByJob.entries) {
        DBHelper.requireSameInspector(uid);
        for (final photo in entry.value) {
          _markPhotoHasRemoteWork(photo);
        }
        final uploadedUrls = await SupabaseService.uploadInspectionPhotos(
          jobId: entry.key,
          photosData: entry.value,
        );
        uploadedUrlsByJob[entry.key] = uploadedUrls;
      }

      // Patch field_jobs.photo_paths / photo_count using the canonical
      // writer's returned projection, preserving any prior remote evidence.
      for (final entry in uploadedUrlsByJob.entries) {
        try {
          final existing = await supabase
              .from('field_jobs')
              .select('photo_paths')
              .eq('id', entry.key)
              .maybeSingle();
          final existingPaths = ((existing?['photo_paths'] as List?) ?? [])
              .cast<String>()
              .where(
                (p) => p.startsWith('http') || p.startsWith('inspections/'),
              )
              .toList();
          final merged = {...existingPaths, ...entry.value}.toList();
          DBHelper.requireSameInspector(uid);
          await SupabaseService.updateJobInspectionProgress(jobId: entry.key,
            updateData: {'photo_paths': merged, 'photo_count': merged.length});
          DBHelper.requireSameInspector(uid);
          await DBHelper.markPhotosSynced(pendingPhotosByJob[entry.key]!
            .map((p) => p['localPhotoId'] as String?));
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
        DBHelper.requireSameInspector(uid);
        final Map<String, dynamic> checklist = jsonDecode(
          insp['checklist_json'],
        );
        final checklistSummary = checklist.entries
            .map((e) => '${e.key}: ${e.value == true ? "Yes" : "No"}')
            .join('; ');

        // A saved draft is evidence, not final-submit intent. Only the explicit
        // submission path may prove completion and release retention.
        await SupabaseService.updateJobInspectionProgress(jobId: insp['id'] as String,
            updateData: {
              'findings': '${insp['notes']}\n\nChecklist: $checklistSummary',
              'is_compliant': insp['is_compliant'] == 1,
              'inspection_result':
                  insp['inspection_result'] as String? ??
                  (insp['is_compliant'] == 1
                      ? 'Compliant'
                      : 'With Discrepancy'),
            });
        DBHelper.requireSameInspector(uid);
        await DBHelper.markInspectionSynced(insp['id']);
      }

      if (pendingInspections.isNotEmpty) {
        await SupabaseService.logActivity(
          eventType: 'inspection_progress_synced',
          title: 'Offline inspection draft synced',
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
