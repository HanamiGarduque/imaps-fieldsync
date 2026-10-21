import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/services/db_helper.dart';
import '../services/photo_source_resolver.dart';
import '../services/geotag_service.dart';
import '../services/site_location_reference_service.dart';
import '../../../core/services/sync_outbox_service.dart';
import '../../tasks/screens/tasks_screen.dart'; // To access TaskItem class

class InspectionProvider extends ChangeNotifier {
  TaskItem? _activeTask;
  String? _inspectorId;
  void _requireOwner() {
    if (_inspectorId == null) {
      throw StateError('Inspection has no recorded session owner');
    }
    DBHelper.requireSameInspector(_inspectorId!);
  }

  int _currentStep = 1;

  // Checklist State
  final Map<String, bool> _siteCondition = {
    'Structure matches declared use': false,
    'Setback distances compliant': false,
  };
  final Map<String, bool> _zoningObservations = {
    'Accessibility & road frontage': false,
    'Surrounding developments noted': false,
    'Signage / commercial activity present': false,
  };

  // Photo Evidence State
  final List<Map<String, dynamic>> _capturedPhotos = [];
  // Immutable Step 2 verification snapshot for the generated location card.
  GpsVerificationSnapshot? _gpsVerification;
  // Photos that have entered save/upload/queue work in this durable session.
  // A local row alone cannot prove a photo was never uploaded: the live
  // capture path can upload before a local_photos row is acknowledged.
  final Set<String> _photosWithRemoteWork = {};

  // Findings State
  String _actualLandUse = 'Single-detached residential';
  String _notes = '';
  String _discrepancies = '';
  String _recommendations = '';
  String _boundaryStatus = 'Not recorded';
  String _inspectionResult = ''; // No assessment until the inspector chooses.

  bool _isSyncing = false;
  bool _isReworkMode = false;
  // Issue 2 fix: true once rework_started_at has been written for the
  // CURRENT rework session — prevents writing it again on every
  // subsequent edit (only the first real edit needs to set it).
  bool _reworkModifiedMarked = false;

  // Last persistently-accepted findings text (the three fields the Field
  // Findings screen actually owns), separate from the in-memory draft.
  //
  // This is the no-op baseline for the Save action. `observations` is
  // deliberately not part of it: that column is composed from land use and
  // boundary status rather than round-tripped (see hydrateForRework), so it
  // could never tell a real edit from a re-save of the same evidence.
  String? _persistedFindingsSignature;
  // An explicit local Save is durable pending intent, not remote acceptance.
  // Its payload remains in pending_actions; this is only the active UI baseline.
  String? _pendingFindingsSignature;
  String? _findingsObservations;

  String get _findingsSignature => jsonEncode([
    _notes.trim(),
    _discrepancies.trim(),
    _recommendations.trim(),
  ]);

  // Getters
  bool get _visible =>
      _inspectorId != null && _inspectorId == DBHelper.currentInspectorId;
  TaskItem? get activeTask => _visible ? _activeTask : null;
  int get currentStep => _visible ? _currentStep : 1;
  Map<String, bool> get siteCondition => _visible ? _siteCondition : {};
  Map<String, bool> get zoningObservations =>
      _visible ? _zoningObservations : {};
  List<Map<String, dynamic>> get capturedPhotos =>
      _visible ? _capturedPhotos : [];
  GpsVerificationSnapshot? get gpsVerification =>
      _visible ? _gpsVerification : null;
  int get realPhotoCount =>
      capturedPhotos.where((photo) => !isLocationReferencePhoto(photo)).length;
  bool get hasLocationReference => capturedPhotos.any(isLocationReferencePhoto);
  String get actualLandUse => _visible ? _actualLandUse : '';
  String get notes => _visible ? _notes : '';
  String get discrepancies => _visible ? _discrepancies : '';
  String get recommendations => _visible ? _recommendations : '';
  String get boundaryStatus => _visible ? _boundaryStatus : '';
  String get inspectionResult => _visible ? _inspectionResult : '';
  static const assessmentOptions = [
    'Compliant',
    'With Discrepancy',
    'For Review',
    'Requires Reinspection',
  ];

  String? get assessmentValidationMessage {
    if (!assessmentOptions.contains(inspectionResult)) {
      return 'Choose an assessment before submitting the inspection.';
    }
    if (inspectionResult != 'Compliant' && discrepancies.trim().isEmpty) {
      return 'Explain what you observed and why it differs or needs review/reinspection before submitting.';
    }
    // Unchecked criteria are not negative findings. Only explicitly recorded
    // discrepancy evidence contradicts an unqualified Compliant assessment.
    if (inspectionResult == 'Compliant' && discrepancies.trim().isNotEmpty) {
      return 'Compliant does not match the recorded discrepancy / explanation. Review the evidence and choose the assessment yourself; nothing has been changed automatically.';
    }
    return null;
  }

  /// The `observations` text actually on file for this rework session, so a
  /// summary can show the same value instead of re-composing it. Land use and
  /// boundary status are folded into one freeform column and cannot be parsed
  /// back apart, so the stored sentence wins until its inputs change.
  String get observations => _visible
      ? _findingsObservations ??
            'Actual land use: $_actualLandUse. Boundary status: $_boundaryStatus.'
      : '';

  /// Draft or saved-pending findings must overlay a stale remote summary.
  bool get hasReworkFindings =>
      _visible &&
      _isReworkMode &&
      (_pendingFindingsSignature != null ||
          _findingsSignature != _persistedFindingsSignature);
  bool get isSyncing => _isSyncing;
  bool get isReworkMode => _visible && _isReworkMode;

  void requireOwner() => _requireOwner();

  /// Clears every field observation. Used by both entry paths so no session's
  /// answers can reach another session's report.
  void _resetFieldState() {
    _siteCondition.updateAll((key, value) => false);
    _zoningObservations.updateAll((key, value) => false);
    _capturedPhotos.clear();
    _actualLandUse = 'Single-detached residential';
    _notes = '';
    _discrepancies = '';
    _recommendations = '';
    _boundaryStatus = 'Not recorded';
    _inspectionResult = '';
    _persistedFindingsSignature = null;
    _pendingFindingsSignature = null;
    _findingsObservations = null;
    _gpsVerification = null;
  }

  // --- INITIALIZATION & NAVIGATION ---

  Future<void> startInspection(TaskItem task) async {
    _inspectorId = DBHelper.requireInspector();
    await DBHelper.requireOwnedJob(
      await DBHelper.database,
      task.id,
      _inspectorId!,
    );
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
    _gpsVerification = _snapshotFromRow(
      await DBHelper.getGpsVerification(task.id),
    );
    _gpsVerification ??= _snapshotFromTask(task);
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
    SupabaseService.markReworkModified(
      jobId: _activeTask!.id,
      locationLabel: _activeTask!.location,
    ).then<void>((_) {}).catchError((e) {
      // Best-effort: if this particular write fails the marker may be seen as
      // unset again on a later attempt, but the edit itself is unaffected and
      // still saved through its own offline-safe path.
      _reworkModifiedMarked = false;
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
    DateTime? capturedAt,
    String? photoId,
    bool isLocationReference = false,
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
      'id': photoId ?? const Uuid().v4(),
      'photoPath': photoPath,
      'notes': photoNotes,
      'latitude': latitude,
      'longitude': longitude,
      'capturedAt': GeotagService.storageTimestamp(
        capturedAt ?? DateTime.now(),
      ),
      if (isLocationReference) 'isLocationReference': true,
    });
    notifyListeners();
  }

  void _requirePhotoContext(TaskItem task, String inspectorId) {
    _requireOwner();
    DBHelper.requireSameInspector(inspectorId);
    if (_inspectorId != inspectorId ||
        _activeTask?.id != task.id ||
        _activeTask?.inspectionRoundNumber != task.inspectionRoundNumber) {
      throw StateError(
        'The active inspection changed. Evidence was not attached to another task.',
      );
    }
  }

  /// Accepts new evidence only AFTER its local row is durable. The initiating
  /// task/owner are explicit so an asynchronous capture cannot attach to a
  /// different task which happens to be active when SQLite finishes.
  Future<bool> persistPhoto(
    Map<String, dynamic> photo, {
    required TaskItem task,
    required String inspectorId,
  }) async {
    _requirePhotoContext(task, inspectorId);
    final photoId = photo['id'] as String?;
    final photoPath = photo['photoPath'] as String?;
    if (photoId == null || photoPath == null || photoPath.isEmpty) {
      return false;
    }
    await DBHelper.savePhotoLocally(
      photoId: photoId,
      jobId: task.id,
      photoPath: photoPath,
      notes: photo['notes'] as String? ?? '',
      latitude: (photo['latitude'] as num?)?.toDouble(),
      longitude: (photo['longitude'] as num?)?.toDouble(),
      capturedAt: photo['capturedAt'] as String?,
    );
    _requirePhotoContext(task, inspectorId);
    if (!_capturedPhotos.any((saved) => saved['id'] == photoId)) {
      _capturedPhotos.add(Map<String, dynamic>.from(photo));
      _markReworkModifiedIfNeeded();
      notifyListeners();
    }
    return true;
  }

  /// Local acceptance is a navigation gate; slow/offline remote delivery is not.
  Future<void> persistCapturedPhotos() async {
    _requireOwner();
    final task = _activeTask;
    final inspectorId = _inspectorId!;
    if (task == null) throw StateError('No active inspection');
    for (final photo in List<Map<String, dynamic>>.of(_capturedPhotos)) {
      if (!await persistPhoto(photo, task: task, inspectorId: inspectorId)) {
        throw StateError('Photo evidence could not be saved on this device');
      }
    }
    _requirePhotoContext(task, inspectorId);
  }

  /// Removes one captured photo only when it is still local, unacknowledged
  /// evidence. Submitted, completed, or rework evidence is immutable here.
  /// Returns false without changing memory when removal is not permitted or
  /// local cleanup fails, so the caller cannot report a false success.
  Future<bool> removePhoto(int index) async {
    _requireOwner();
    if (index < 0 || index >= _capturedPhotos.length) return false;

    final photo = _capturedPhotos[index];
    if (isLocationReferencePhoto(photo)) {
      // Generated location evidence is regenerated, never user-deleted.
      return false;
    }
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
    final knownRemote =
        photo['isRemoteUrl'] == true || _photoHasRemoteWork(photo);
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
    final before = _findingsSignature;
    if (actualLandUse != _actualLandUse || boundaryStatus != _boundaryStatus) {
      _findingsObservations = null;
    }
    _actualLandUse = actualLandUse;
    _notes = notes;
    _discrepancies = discrepancies;
    _recommendations = recommendations;
    _boundaryStatus = boundaryStatus;
    // Findings are a draft until the accepted Save path persists them; the
    // marker is written only once that save lands.
    if (before != _findingsSignature && _shouldMarkModified) {
      _markReworkModifiedIfNeeded();
    }
    notifyListeners();
  }

  /// False while a completed job's findings edit is still a draft. Reopening
  /// or leaving the step without pressing Save must not write the marker just
  /// to show a "Modified" badge.
  bool get _shouldMarkModified => !_isReworkMode;

  // Called by GpsVerificationScreen right after a successful on-site
  // confirmation, so Step 5 (Findings) reflects the real GPS result
  // instead of a hardcoded placeholder string. The same accepted fix is
  // stored locally as the immutable Step 3 Site Location Reference source.
  Future<void> recordGpsVerification({
    required double distanceMeters,
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    required DateTime fixAt,
  }) async {
    _requireOwner();
    final verifiedAt = DateTime.now();
    _gpsVerification = GpsVerificationSnapshot(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters,
      fixAt: fixAt,
      verifiedAt: verifiedAt,
    );
    _boundaryStatus =
        'Verified on-site — ${distanceMeters.round()}m from declared location';
    final jobId = _activeTask?.id;
    if (jobId != null) {
      try {
        await DBHelper.saveGpsVerification(
          jobId: jobId,
          latitude: latitude,
          longitude: longitude,
          accuracyMeters: accuracyMeters,
          fixAt: fixAt,
          verifiedAt: verifiedAt,
        );
      } catch (e) {
        // The confirmation itself already happened; failing to persist this
        // local copy must not block the inspector, but it is never invented.
        debugPrint('recordGpsVerification: local snapshot not saved — $e');
      }
    }
    notifyListeners();
  }

  GpsVerificationSnapshot? _snapshotFromRow(Map<String, dynamic>? row) {
    if (row == null) return null;
    final latitude = (row['latitude'] as num?)?.toDouble();
    final longitude = (row['longitude'] as num?)?.toDouble();
    final fixAt = DateTime.tryParse(row['fix_at'] as String? ?? '');
    final verifiedAt = DateTime.tryParse(row['verified_at'] as String? ?? '');
    if (latitude == null ||
        longitude == null ||
        fixAt == null ||
        verifiedAt == null) {
      return null;
    }
    return GpsVerificationSnapshot(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: (row['accuracy_meters'] as num?)?.toDouble(),
      fixAt: fixAt,
      verifiedAt: verifiedAt,
    );
  }

  GpsVerificationSnapshot? _snapshotFromTask(TaskItem task) {
    final latitude = task.confirmedLatitude;
    final longitude = task.confirmedLongitude;
    final verifiedAt = DateTime.tryParse(task.gpsConfirmedAt ?? '');
    if (latitude == null || longitude == null || verifiedAt == null) {
      return null;
    }
    return GpsVerificationSnapshot(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: task.gpsAccuracyM,
      fixAt: verifiedAt,
      verifiedAt: verifiedAt,
    );
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
    // Keep this owner's same-job draft across a revisit: entering rework
    // again after leaving without Save must not wipe unsaved text. Anything
    // else hydrates normally; another job or session starts fresh.
    final keepFindings =
        _visible &&
        _isReworkMode &&
        _activeTask?.id == task.id &&
        (_pendingFindingsSignature != null ||
            _findingsSignature != _persistedFindingsSignature);
    final findings = (
      notes: _notes,
      discrepancies: _discrepancies,
      recommendations: _recommendations,
      observations: _findingsObservations,
      pending: _pendingFindingsSignature,
    );
    _inspectorId = DBHelper.requireInspector();
    _activeTask = task;
    _isReworkMode = true;
    _currentStep = 6;
    // A revisit of a job that was already marked keeps that marker and shows
    // the existing Modified badge without writing or logging anything new.
    _reworkModifiedMarked = task.reworkStartedAt != null;
    _photosWithRemoteWork.clear();
    // A previous session's in-memory field observations must never survive
    // into this one. The rework payload below re-populates what it actually
    // carries; anything it does not carry starts from the same defaults
    // startInspection() uses rather than leaking a prior inspector's answer.
    _resetFieldState();
    _gpsVerification = _snapshotFromTask(task);

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
    _findingsObservations = task.observations;
    _persistedFindingsSignature = _findingsSignature;
    if (keepFindings) {
      _notes = findings.notes;
      _discrepancies = findings.discrepancies;
      _recommendations = findings.recommendations;
      _findingsObservations = findings.observations;
      _pendingFindingsSignature = findings.pending;
    }
    _inspectionResult = task.inspectionResult ?? '';
    // The legacy boolean cannot distinguish a procedural review/reinspection
    // from a boundary failure, so `false` never invents "Non-compliant".
    _boundaryStatus = task.isCompliant == true ? 'Compliant' : 'Not recorded';
    // NOTE: `observations` was historically written as one freeform
    // sentence (e.g. "Actual land use: X. Boundary status: Y.") rather than
    // matching `_actualLandUse` 1:1 — I'm not auto-parsing that back apart
    // since it'd be guesswork. If you want exact round-trip, the fix is
    // upstream: store actualLandUse as its own column instead of folding
    // it into `observations`.

    notifyListeners();
  }

  /// Load this owner's latest explicit local Save before opening rework. A
  /// fresh provider restores its durable text; an in-session unsaved draft
  /// remains in memory above that pending baseline.
  Future<void> restorePendingFindings({bool afterSave = false}) async {
    _requireOwner();
    final jobId = _activeTask?.id;
    if (!_isReworkMode || jobId == null) return;
    final signature = _findingsSignature;
    final draft =
        signature != (_pendingFindingsSignature ?? _persistedFindingsSignature);
    final pending = await DBHelper.getPendingFindingsSave(jobId);
    _requireOwner();
    if (_activeTask?.id != jobId ||
        !_isReworkMode ||
        _findingsSignature != signature) {
      return;
    }
    if (pending == null) {
      if (_pendingFindingsSignature != null) {
        if (afterSave) {
          _persistedFindingsSignature = _pendingFindingsSignature;
        } else if (!draft) {
          // Re-entry supplied fresh remote evidence. Once the latest Save
          // synced, its old UI pending state must not cover that fresh row.
          _notes = _activeTask!.inspectorNotes ?? '';
          _discrepancies = _activeTask!.discrepancies ?? '';
          _recommendations = _activeTask!.recommendations ?? '';
          _findingsObservations = _activeTask!.observations;
          _persistedFindingsSignature = _findingsSignature;
        }
      }
      _pendingFindingsSignature = null;
    } else {
      final notes = pending['inspectorNotes'] as String;
      final discrepancies = pending['discrepancies'] as String? ?? '';
      final recommendations = pending['recommendations'] as String? ?? '';
      _pendingFindingsSignature = jsonEncode([
        notes.trim(),
        discrepancies.trim(),
        recommendations.trim(),
      ]);
      if (!draft) {
        _notes = notes;
        _discrepancies = discrepancies;
        _recommendations = recommendations;
        _findingsObservations = pending['observations'] as String;
      }
    }
    notifyListeners();
  }
  // --- LOCAL SQLite DRAFT RECOVERY ---

  Future<void> _loadLocalDraftIfExists(String jobId) async {
    // Ownership was already established at entry, and every read below is
    // inspector-scoped, so this only hydrates memory.
    final draft = await DBHelper.getLocalInspection(jobId);
    _requireOwner();
    var hasFindingsSnapshot = false;
    if (draft != null) {
      _actualLandUse = draft['actual_land_use'] ?? _actualLandUse;
      _notes = draft['notes'] ?? _notes;
      _boundaryStatus = draft['boundary_status'] ?? _boundaryStatus;
      _inspectionResult = draft['inspection_result'] as String? ?? '';

      if (draft['checklist_json'] != null) {
        try {
          final Map<String, dynamic> checklist = jsonDecode(
            draft['checklist_json'],
          );
          final findings = checklist[DBHelper.inspectionDraftFindingsKey];
          if (findings is Map) {
            hasFindingsSnapshot = true;
            _discrepancies = findings['discrepancies'] as String? ?? '';
            _recommendations = findings['recommendations'] as String? ?? '';
            _findingsObservations = findings['observations'] as String?;
          }
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

    final pending = await DBHelper.getLocalFindingsIntent(jobId);
    _requireOwner();
    final queuedAt = DateTime.tryParse(
      pending?['localCreatedAt'] as String? ?? '',
    );
    final draftAt = DateTime.tryParse(draft?['updated_at'] as String? ?? '');
    if (pending != null &&
        (!hasFindingsSnapshot ||
            (queuedAt != null &&
                draftAt != null &&
                queuedAt.isAfter(draftAt)))) {
      _notes = pending['inspectorNotes'] as String? ?? _notes;
      _discrepancies = pending['discrepancies'] as String? ?? '';
      _recommendations = pending['recommendations'] as String? ?? '';
      _findingsObservations = pending['observations'] as String?;
      _inspectionResult =
          pending['inspectionResult'] as String? ?? _inspectionResult;
    }

    final localPhotos = await DBHelper.getLocalPhotos(jobId);
    _requireOwner();
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

  Future<void> _saveLocalInspection() {
    _requireOwner();
    return DBHelper.saveInspectionLocally(
      jobId: _activeTask!.id,
      expectedInspectorId: _inspectorId,
      actualLandUse: _actualLandUse,
      notes: _notes,
      isCompliant: _inspectionResult == 'Compliant',
      inspectionResult: _inspectionResult,
      checklist: {..._siteCondition, ..._zoningObservations},
      boundaryStatus: _boundaryStatus,
      currentStep: _currentStep,
      findings: {
        'discrepancies': _discrepancies,
        'recommendations': _recommendations,
        'observations': observations,
      },
    );
  }

  void _syncSavedStep(String jobId) {
    // Delivery runs separately: a successful local save must not wait on radio
    // availability. Startup/reconnect and manual sync retain the same outbox.
    unawaited(
      SyncOutboxService.drain(onlyJobId: jobId).catchError((Object e) {
        debugPrint('Step saved locally; delivery remains queued — $e');
      }),
    );
  }

  Future<bool> saveInspectionProgress() async {
    _requireOwner();
    if (_activeTask == null) return false;

    // 1. Save main inspection details to local sqlite
    await _saveLocalInspection();

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
        capturedAt: photo['capturedAt'] as String?,
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
    final task = _activeTask!;
    final inspectorId = _inspectorId!;
    // Durable first: every accepted photo gets its local_photos row before any
    // upload/queue attempt, so a crash or offline exit cannot lose the list.
    try {
      await persistCapturedPhotos();
      _requirePhotoContext(task, inspectorId);
    } catch (e) {
      debugPrint('saveStepPhotos: local photo persistence failed — $e');
      return false;
    }
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
        jobId: task.id,
        photosData: photosToUpload,
      );

      // Update the main field_jobs table to maintain the array of URLs for quick access
      _requireOwner();
      DBHelper.requireSameInspector(inspectorId);
      await SupabaseService.updateJobInspectionProgress(
        jobId: task.id,
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
        DBHelper.requireSameInspector(inspectorId);
        await SyncOutboxService.enqueuePhotosUpdate(
          jobId: task.id,
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
    final jobId = _activeTask!.id;
    try {
      await _saveLocalInspection();
      _requireOwner();
      await SyncOutboxService.enqueueChecklistUpdate(
        jobId: jobId,
        checklistData: checklist,
        checklistCompletedCount: done,
        checklistTotalCount: checklist.length,
        isRework: _isReworkMode,
      );
      _syncSavedStep(jobId);
      return true;
    } catch (e) {
      debugPrint('saveStepChecklist: local save failed — $e');
      return false;
    }
  }

  /// Persists this step's evidence and, only when [isExplicitSave] is set
  /// (the Field Findings Save button), records one Save event.
  ///
  /// The event is never emitted by the caller: it travels inside the same
  /// durable outbox action as the evidence and is written only after that
  /// action's findings mutation is accepted. So an offline save can never
  /// claim a remote success before it happened, and a retry cannot add a
  /// second row — no new schema or table is involved.
  ///
  /// Returns true only after the complete local snapshot and delivery intent
  /// are durable, or when an explicit Save is a genuine no-op.
  Future<bool> saveStepFindings({bool isExplicitSave = false}) async {
    _requireOwner();
    if (_activeTask == null) return false;
    final observations = this.observations;
    final discrepancies = _discrepancies.isNotEmpty ? _discrepancies : null;
    final recommendations = _recommendations.isNotEmpty
        ? _recommendations
        : null;
    final jobId = _activeTask!.id;
    final notes = _notes;
    final signature = _findingsSignature;

    if (isExplicitSave) {
      // A Save of byte-identical text changes nothing: it must not be queued
      // and must not produce an activity row.
      if (signature ==
          (_pendingFindingsSignature ?? _persistedFindingsSignature)) {
        return true;
      }
      try {
        // Durable first, remote second: the action (and its event id) exists
        // before any write, so a lost response is recoverable rather than
        // unrecoverable work.
        await _saveLocalInspection();
        _requireOwner();
        await SyncOutboxService.enqueueFindingsUpdate(
          jobId: jobId,
          observations: observations,
          discrepancies: discrepancies,
          recommendations: recommendations,
          inspectorNotes: notes,
          activityId: const Uuid().v4(),
          activitySubtitle: _activeTask!.location,
          isRework: _isReworkMode,
        );
        _requireOwner();
        _pendingFindingsSignature = signature;
      } catch (e) {
        debugPrint('saveStepFindings: failed to queue findings save — $e');
        return false;
      }
      try {
        // Online this delivers immediately; offline the row stays pending and
        // the activity is written only once it succeeds.
        await SyncOutboxService.drain(onlyJobId: jobId);
        await restorePendingFindings(afterSave: true);
      } catch (e) {
        debugPrint(
          'saveStepFindings: saved locally; sync remains pending — $e',
        );
      }
      return true;
    }

    try {
      await _saveLocalInspection();
      _requireOwner();
      await SyncOutboxService.enqueueFindingsUpdate(
        jobId: jobId,
        observations: observations,
        discrepancies: discrepancies,
        recommendations: recommendations,
        inspectorNotes: notes,
        isRework: _isReworkMode,
      );
      _persistedFindingsSignature = signature;
      _syncSavedStep(jobId);
      return true;
    } catch (e) {
      debugPrint('saveStepFindings: local save failed — $e');
      return false;
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
  Future<bool> saveAllInspectionState({bool syncOnline = true}) async {
    _requireOwner();
    if (_activeTask == null) return false;

    await _saveLocalInspection();

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
        capturedAt: photo['capturedAt'] as String?,
      );
    }

    notifyListeners();

    if (!syncOnline) return true;
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

      // Final-submit intent owns delivery of its evidence. The legacy draft
      // drainer must neither race it nor replay a completed round afterward.
      final protectedJobs = <String>{
        for (final a in await DBHelper.getSyncCenterQueueActions())
          if (a['type'] == 'submit_inspection') a['job_id'] as String,
        for (final job in await DBHelper.getCachedJobs())
          if (const [
            'completed',
            'Completed',
            'submitted',
          ].contains(job['status']))
            job['id'] as String,
      };
      DBHelper.requireSameInspector(uid);

      // 1. Sync pending local photos through the one canonical remote writer.
      // Legacy local_photos rows are adapted here; all NEW remote identities
      // now use job ID + stable local path + UUIDv5 through the service path.
      final pendingPhotos = (await DBHelper.getPendingPhotos())
          .where((p) => !protectedJobs.contains(p['job_id']))
          .toList();
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
          await SupabaseService.updateJobInspectionProgress(
            jobId: entry.key,
            updateData: {'photo_paths': merged, 'photo_count': merged.length},
          );
          DBHelper.requireSameInspector(uid);
          await DBHelper.markPhotosSynced(
            pendingPhotosByJob[entry.key]!.map(
              (p) => p['localPhotoId'] as String?,
            ),
          );
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
      final pendingInspections = (await DBHelper.getPendingInspections())
          .where((d) => !protectedJobs.contains(d['id']))
          .toList();
      for (final insp in pendingInspections) {
        DBHelper.requireSameInspector(uid);
        final Map<String, dynamic> checklist = jsonDecode(
          insp['checklist_json'],
        );
        final checklistSummary = checklist.entries
            .where((e) => e.value is bool)
            .map((e) => '${e.key}: ${e.value == true ? "Yes" : "No"}')
            .join('; ');

        // A fresh Step 6 has no recorded assessment: never send '' (the
        // server CHECK accepts only the four explicit outcomes) and never
        // invent "With Discrepancy" from a missing value. A legacy binary row
        // that is explicitly compliant may still carry its Compliant boundary.
        final savedResult = insp['inspection_result'] as String?;
        final legacyCompliant = insp['is_compliant'] == 1;
        final resultToSend = savedResult != null && savedResult.isNotEmpty
            ? savedResult
            : (legacyCompliant ? 'Compliant' : null);

        // A saved draft is evidence, not final-submit intent. Only the explicit
        // submission path may prove completion and release retention.
        await SupabaseService.updateJobInspectionProgress(
          jobId: insp['id'] as String,
          updateData: {
            'findings': '${insp['notes']}\n\nChecklist: $checklistSummary',
            'is_compliant': legacyCompliant,
            'inspection_result': ?resultToSend,
          },
        );
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

/// Accepted Step 2 on-site fix for this job/round. Read-only evidence: the
/// Site Location Reference uses it, and it never substitutes a photo's own
/// shutter GPS.
class GpsVerificationSnapshot {
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final DateTime fixAt;
  final DateTime verifiedAt;

  const GpsVerificationSnapshot({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.fixAt,
    required this.verifiedAt,
  });
}
