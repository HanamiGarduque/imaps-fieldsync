import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'db_helper.dart';
import 'supabase_service.dart';

/// Phase 5 — Sync Progress Indicator.
///   Snapshot of "where the drain loop is right now", published via
///   [SyncOutboxService.progress] so any widget (the Sync Center's own
///   status card, or a small banner on another screen) can show live
///   text like "Syncing item 2 of 5" and, for a submit_inspection action
///   with photos, "Uploading photo 3 of 12" underneath it.
///   `null` means nothing is syncing right now.
class SyncProgress {
  final int actionIndex; // 1-based — "this is the Nth action"
  final int actionTotal;
  final String actionType;
  final int? photoIndex; // 1-based, only set while uploading photos
  final int? photoTotal;

  const SyncProgress({
    required this.actionIndex,
    required this.actionTotal,
    required this.actionType,
    this.photoIndex,
    this.photoTotal,
  });

  SyncProgress copyWithPhoto({required int photoIndex, required int photoTotal}) {
    return SyncProgress(
      actionIndex: actionIndex,
      actionTotal: actionTotal,
      actionType: actionType,
      photoIndex: photoIndex,
      photoTotal: photoTotal,
    );
  }

  /// Short human label for the action itself, e.g. "Submitting inspection".
  String get actionLabel {
    switch (actionType) {
      case 'gps_confirm':
        return 'Syncing GPS verification';
      case 'mark_ongoing':
        return 'Syncing task status';
      case 'checklist_update':
        return 'Syncing checklist';
      case 'current_step_update':
        return 'Syncing progress';
      case 'submit_inspection':
        return 'Submitting inspection';
      default:
        return 'Syncing';
    }
  }

  /// Full display line, e.g. "Submitting inspection (2 of 5) — Uploading
  /// photo 3 of 12", or just "Syncing GPS verification (1 of 3)" when
  /// there's no photo sub-progress for this action type.
  String get displayText {
    final base = '$actionLabel ($actionIndex of $actionTotal)';
    if (photoIndex != null && photoTotal != null && photoTotal! > 0) {
      return '$base — Uploading photo $photoIndex of $photoTotal';
    }
    return base;
  }
}

/// FieldSync's single outbox drain engine (Phase A/C of the offline
/// roadmap). Every offline-capable action becomes one `pending_actions`
/// row (see DBHelper); this service is the only thing that reads that
/// table and replays it against Supabase, in order, when connectivity
/// allows.
///
/// Action types wired so far: `gps_confirm`. Submit / checklist / photo
/// upload are the next rounds — same table, same drain loop, just a new
/// case in `_executeAction`.
class SyncOutboxService {
  SyncOutboxService._();

  static bool _draining = false;
  static StreamSubscription<List<ConnectivityResult>>? _connSub;
  static Timer? _debounce;
  static const _lastSyncPrefsKey = 'field_sync_last_success';
  static const _conflictSnapshotKey = 'cachedUpdatedAtSnapshot';
  static const _forceSyncAnywayKey = 'forceSyncAnyway';
  static const Set<String> _conflictSensitiveTypes = {
    'gps_confirm',
    'submit_inspection',
    'checklist_update',
    'current_step_update',
  };

  /// Live progress of the current drain pass. Any widget can do
  /// `ValueListenableBuilder<SyncProgress?>(valueListenable:
  /// SyncOutboxService.progress, ...)` to show live sync status without
  /// polling. `null` while idle/not draining.
  static final ValueNotifier<SyncProgress?> progress =
      ValueNotifier<SyncProgress?>(null);


  static bool get isDraining => _draining;

  static Future<DateTime?> getLastSuccessfulSync() async {
    final prefs = await SharedPreferences.getInstance();
    final iso = prefs.getString(_lastSyncPrefsKey);
    if (iso == null) return null;
    return DateTime.tryParse(iso);
  }

  static Future<void> _recordSuccessfulSync() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncPrefsKey, DateTime.now().toIso8601String());
  }

  /// Call once at app startup. Attempts an immediate drain (in case
  /// something was queued last session and connectivity is already back),
  /// then keeps listening so a queued action syncs automatically the
  /// moment signal returns — not just on the next app open.
  ///
  /// Phase 2 hardening: connectivity events are debounced (900ms) before
  /// triggering a drain. `drain()` itself already no-ops on a re-entrant
  /// call via the `_draining` guard, so this isn't needed to prevent
  /// overlapping drains — it's to stop a flaky/flapping signal (a few
  /// on/off/on events within a second, common on weak field signal) from
  /// firing several back-to-back `getActionableActions()` queries for
  /// what is, in practice, a single reconnect.
  static void start() {
    drain();
    _connSub ??= Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 900), drain);
      }
    });
  }

  // --- ENQUEUE HELPERS (one per action type) ---

  /// Queues a GPS confirmation. Deterministic id per job (same dedup
  /// pattern as `enqueueChecklistUpdate`/`enqueueCurrentStepUpdate`) —
  /// added after real-device testing surfaced 8 separate
  /// "GPS Verification Coordinates" cards in the Sync Center for a
  /// single job, caused by this previously using a fresh
  /// `Uuid().v4()` on every call. Re-visiting/re-confirming GPS several
  /// times while offline now overwrites the same queued row with the
  /// latest coordinates instead of piling up one row per confirm.
  static Future<void> enqueueGpsConfirm({
    required String jobId,
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    String? locationLabel,
  }) async {
    final payload = await _withConflictSnapshot(
      jobId: jobId,
      payload: {
        'latitude': latitude,
        'longitude': longitude,
        'accuracyMeters': accuracyMeters,
        'locationLabel': locationLabel,
      },
    );
    return DBHelper.enqueueAction(
      id: 'gps_confirm_$jobId',
      type: 'gps_confirm',
      jobId: jobId,
      payload: payload,
    );
  }

  /// Queues the Pending/Scheduled → Ongoing status flip. Deterministic id
  /// per job (same dedup pattern as the others) — if the inspector exits
  /// and re-enters a couple of times while offline, each call just
  /// overwrites the same queued row rather than piling up duplicates.
  ///
  /// Ongoing-phase audit fix: `markJobOngoing()` used to be the one write
  /// in this app with no outbox fallback at all — it swallowed its own
  /// exceptions and returned `false`, and the exit-confirm dialog then
  /// told the inspector "Saved offline — will sync when back online" even
  /// though nothing was actually queued. That status flip was silently
  /// lost for good unless the inspector later passed through GPS
  /// confirmation (which does reliably set status — see
  /// `enqueueGpsConfirm`). No payload needed beyond the job id — the
  /// status/started_at update itself is inherently safe to retry
  /// (`.not('status','ilike','completed')` / `started_at is null` guards
  /// in `markJobOngoing` already make it idempotent), so this isn't in
  /// `_conflictSensitiveTypes`.
  static Future<void> enqueueMarkOngoing({required String jobId}) async {
    return DBHelper.enqueueAction(
      id: 'mark_ongoing_$jobId',
      type: 'mark_ongoing',
      jobId: jobId,
      payload: const {},
    );
  }

  /// Queues a checklist snapshot. Deliberately uses one deterministic id
  /// per job (not a fresh UUID each call) — DBHelper.enqueueAction
  /// replaces on conflict, so if the inspector toggles several boxes while
  /// offline, each call overwrites the same queued row with the latest
  /// state instead of piling up N redundant rows for one job.
  static Future<void> enqueueChecklistUpdate({
    required String jobId,
    required List<Map<String, dynamic>> checklistData,
    required int checklistCompletedCount,
    required int checklistTotalCount,
  }) async {
    final payload = await _withConflictSnapshot(
      jobId: jobId,
      payload: {
        'checklistData': checklistData,
        'checklistCompletedCount': checklistCompletedCount,
        'checklistTotalCount': checklistTotalCount,
      },
    );
    return DBHelper.enqueueAction(
      id: 'checklist_update_$jobId',
      type: 'checklist_update',
      jobId: jobId,
      payload: payload,
    );
  }

  /// Queues a `current_step` update. Deterministic id per job (same
  /// pattern as `enqueueChecklistUpdate`) — if the inspector advances
  /// steps several times while offline, each call overwrites the same
  /// queued row with the latest step instead of piling up stale ones.
  ///
  /// Added as the Phase 1 audit fix for item #9 (Data Consistency):
  /// `InspectionProvider.updateStep()` used to push `current_step` to
  /// Supabase best-effort only, with no outbox fallback — a failed push
  /// while offline was silently lost forever, which is why a sample row
  /// was found with `current_step: 0` despite real checklist progress.
  static Future<void> enqueueCurrentStepUpdate({
    required String jobId,
    required int step,
  }) async {
    final payload = await _withConflictSnapshot(
      jobId: jobId,
      payload: {'currentStep': step},
    );
    return DBHelper.enqueueAction(
      id: 'current_step_update_$jobId',
      type: 'current_step_update',
      jobId: jobId,
      payload: payload,
    );
  }

  /// Queues the whole final submission — findings, checklist, and the
  /// *local* photo map data (not yet uploaded; that happens at drain time,
  /// since it needs a connection too). Carries everything ReviewSubmit
  /// already has so nothing the inspector typed gets lost to a bad signal.
  static Future<void> enqueueSubmitInspection({
    required String jobId,
    required String findings,
    required bool isCompliant,
    required String inspectionResult,
    required String observations,
    String? discrepancies,
    String? recommendations,
    required String inspectorNotes,
    required List<Map<String, dynamic>> checklistData,
    required int checklistCompletedCount,
    required int checklistTotalCount,
    required List<Map<String, dynamic>>
    photosData, // UPDATED: Changed to expect Map data
    String? locationLabel,
  }) async {
    final payload = await _withConflictSnapshot(
      jobId: jobId,
      payload: {
        'findings': findings,
        'isCompliant': isCompliant,
        'inspectionResult': inspectionResult,
        'observations': observations,
        'discrepancies': discrepancies,
        'recommendations': recommendations,
        'inspectorNotes': inspectorNotes,
        'checklistData': checklistData,
        'checklistCompletedCount': checklistCompletedCount,
        'checklistTotalCount': checklistTotalCount,
        'photosData': photosData, // UPDATED: Storing photosData instead
        'locationLabel': locationLabel,
      },
    );
    return DBHelper.enqueueAction(
      id: const Uuid().v4(),
      type: 'submit_inspection',
      jobId: jobId,
      payload: payload,
    );
  }

  // --- DRAIN LOOP ---

  /// Processes every actionable row in creation order. Safe to call
  /// repeatedly/concurrently — re-entrant calls are ignored while one is
  /// already running.
  ///
  /// [trigger] is purely for the Phase 6 sync log — 'manual' when the
  /// inspector tapped "Sync Now", 'automatic' (default) when a
  /// connectivity change or app-startup drain fired it. Doesn't affect
  /// behavior, only what the "Synchronization Activity" history says
  /// started the queue.
  ///
  /// [onlyJobId] — Phase 8 (Selective Sync). `null` (default) is the
  /// original, unchanged full-drain behavior: every actionable row,
  /// queue-wide. When set, only rows belonging to that job are processed
  /// — same order, same per-action status handling, same conflict/error
  /// paths — everything else in the queue is left completely untouched
  /// (not read, not marked syncing/failed, still `pending` in its
  /// original position) so a later full drain picks it up normally.
  static Future<void> drain({String trigger = 'automatic', String? onlyJobId}) async {
    if (_draining) return;
    _draining = true;
    try {
      final allActions = await DBHelper.getActionableActions();
      final actions = onlyJobId == null
          ? allActions
          : allActions.where((a) => a['job_id'] == onlyJobId).toList();
      final total = actions.length;
      if (total == 0) return;

      await DBHelper.logSyncEvent(
        eventType: 'queue_started',
        result: 'info',
        message: total == 1
            ? 'Synchronization started — 1 item to send.'
            : 'Synchronization started — $total items to send.',
        technicalDetails: {'trigger': trigger, 'itemCount': total, if (onlyJobId != null) 'onlyJobId': onlyJobId},
      );

      var successCount = 0;
      var failCount = 0;
      var conflictCount = 0;

      for (var i = 0; i < actions.length; i++) {
        final action = actions[i];
        final id = action['id'] as String;
        final type = action['type'] as String;
        final jobId = action['job_id'] as String;
        progress.value = SyncProgress(
          actionIndex: i + 1,
          actionTotal: total,
          actionType: type,
        );
        await DBHelper.markActionSyncing(id);
        await DBHelper.logSyncEvent(
          eventType: 'upload_started',
          result: 'info',
          message: '${_friendlyActionName(type)} — sending...',
          jobId: jobId,
          pendingActionId: id,
        );
        try {
          await _executeAction(action);
          await DBHelper.markActionSynced(id);
          await _recordSuccessfulSync();
          successCount++;
          await DBHelper.logSyncEvent(
            eventType: 'upload_completed',
            result: 'success',
            message: '${_friendlyActionName(type)} completed successfully.',
            jobId: jobId,
            pendingActionId: id,
          );
        } on _OutboxConflictException catch (e) {
          debugPrint(
            'SyncOutboxService: action $id (${action['type']}) conflict: ${e.message}',
          );
          await DBHelper.markActionConflict(id, e.message);
          conflictCount++;
          await DBHelper.logSyncEvent(
            eventType: 'conflict_detected',
            result: 'warning',
            message:
                'This record changed elsewhere before your update could sync. Review needed.',
            jobId: jobId,
            pendingActionId: id,
            technicalDetails: {'reason': e.message},
          );
        } catch (e) {
          debugPrint(
            'SyncOutboxService: action $id (${action['type']}) failed: $e',
          );
          final retryCount = (action['retry_count'] as int? ?? 0) + 1;
          await DBHelper.markActionFailed(id, e.toString());
          failCount++;
          await DBHelper.logSyncEvent(
            eventType: 'upload_failed',
            result: 'error',
            message: _friendlyErrorMessage(e),
            jobId: jobId,
            pendingActionId: id,
            technicalDetails: {
              'retryCount': retryCount,
              'exceptionType': e.runtimeType.toString(),
              // .toString() on most Dart exceptions is already just a
              // human-readable description (no tokens/keys/SQL by
              // construction in this codebase's own exception types) —
              // still, this is the one place raw error text is persisted,
              // so nothing beyond this string is ever stored.
              'rawError': e.toString(),
            },
          );
          // Keep draining the rest — one stuck action (e.g. a job that
          // got deleted server-side) shouldn't block everything queued
          // after it.
        }
      }

      await DBHelper.logSyncEvent(
        eventType: 'queue_finished',
        result: failCount > 0
            ? 'warning'
            : (conflictCount > 0 ? 'warning' : 'success'),
        message:
            'Synchronization finished — $successCount succeeded'
            '${failCount > 0 ? ', $failCount failed' : ''}'
            '${conflictCount > 0 ? ', $conflictCount need review' : ''}.',
        technicalDetails: {
          'successCount': successCount,
          'failCount': failCount,
          'conflictCount': conflictCount,
        },
      );

      // Phase 7: routine maintenance — keeps sync_log_entries from
      // growing unbounded on a long-lived install. Cheap no-op when
      // under the cap (single COUNT query), so safe to call every drain.
      await DBHelper.pruneSyncLogEntries();
    } finally {
      progress.value = null;
      _draining = false;
    }
  }

  /// User-facing label for an action type, used in sync log messages.
  /// Deliberately separate from [SyncProgress.actionLabel] (which is
  /// tuned for a short live-progress line) — this one reads naturally in
  /// a completed sentence like "GPS verification completed successfully."
  static String _friendlyActionName(String actionType) {
    switch (actionType) {
      case 'gps_confirm':
        return 'GPS verification';
      case 'mark_ongoing':
        return 'Task status update';
      case 'checklist_update':
        return 'Checklist update';
      case 'current_step_update':
        return 'Progress update';
      case 'submit_inspection':
        return 'Inspection submission';
      default:
        return 'Synchronization';
    }
  }

  /// Maps a raw exception to the sanitized, user-friendly line shown by
  /// default in the Sync tab (Phase 6). Technical specifics (exception
  /// type, raw message) still get stored, but only inside
  /// `technical_details` — never surfaced here.
  static String _friendlyErrorMessage(Object error) {
    final text = error.toString();
    if (text.contains('SocketException') ||
        text.contains('Failed host lookup')) {
      return 'Network connection lost. Will retry automatically.';
    }
    if (text.contains('TimeoutException') || text.contains('timeout')) {
      return 'Connection timed out. Will retry automatically.';
    }
    if (text.contains('PostgrestException') || text.contains('storage')) {
      return 'Server rejected this update. Will retry automatically.';
    }
    return 'Synchronization failed. Will retry automatically.';
  }

  static Future<void> _executeAction(Map<String, dynamic> action) async {
    final type = action['type'] as String;
    final jobId = action['job_id'] as String;
    final payload = Map<String, dynamic>.from(
      jsonDecode(action['payload'] as String) as Map,
    );
    await _throwIfServerVersionConflict(
      type: type,
      jobId: jobId,
      payload: payload,
    );

    switch (type) {
      case 'gps_confirm':
        await SupabaseService.confirmGpsOnSite(
          jobId: jobId,
          latitude: (payload['latitude'] as num).toDouble(),
          longitude: (payload['longitude'] as num).toDouble(),
          accuracyMeters: (payload['accuracyMeters'] as num).toDouble(),
          locationLabel: payload['locationLabel'] as String?,
        );
        break;
      case 'mark_ongoing':
        // markJobOngoing() catches its own exceptions and returns a bool
        // rather than throwing (unlike confirmGpsOnSite) — so unlike every
        // other case here, a plain `await` wouldn't surface a failure to
        // the drain loop's try/catch above, and the action would get
        // marked synced even though nothing actually happened server-side.
        // Explicitly throw on `false` so retry/failed-action handling
        // above behaves the same as it does for every other action type.
        final ok = await SupabaseService.markJobOngoing(jobId);
        if (!ok) throw Exception('markJobOngoing did not succeed');
        break;
      case 'submit_inspection':
        // Photos couldn't be uploaded while this was queued (that needs a
        // connection too) — do it now, at drain time, using the local
        // paths/metadata captured back on Step 3. If a photo file no longer exists
        // (e.g. cleared cache), uploadInspectionPhotos already skips it
        // rather than failing the whole action.
        //
        // Phase 1 audit item #5 — DECISION (documented, not changed):
        // photos are uploaded FIRST, then submitInspection() finalizes the
        // field_jobs record (findings/checklist/status/photo_paths) SECOND.
        // This is the opposite order from the original spec draft ("text
        // uploads first... photos upload last"), but it's the safer order
        // and is being kept as-is:
        //   - Uploading photos first means submitInspection() always
        //     receives the REAL uploaded photoPaths/photoCount, so the
        //     final field_jobs row is written once, complete and correct.
        //   - The reverse order (submit first, photos after) would create
        //     a window where field_jobs.status is already "submitted" but
        //     photo_paths is empty/incomplete — if the photo upload then
        //     failed or the app was killed mid-upload, the record would
        //     look finished to any admin/reviewer viewing it in Supabase,
        //     while actually missing its evidence photos. That's a worse
        //     partial state than the current one (nothing shows as
        //     submitted until it verifiably has everything).
        //   - If this action fails partway (e.g. mid photo-upload), the
        //     whole action stays `pending`/`failed` and retries as a
        //     whole on the next drain — submitInspection() is never
        //     called with incomplete data.

        // UPDATED: Cast the dynamic list back into List<Map<String, dynamic>>
        final dynamicPhotos = payload['photosData'] as List?;
        final legacyPaths =
            (payload['localPhotoPaths'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const <String>[];
        final photosData = dynamicPhotos != null
            ? dynamicPhotos
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList()
            : legacyPaths
                  .map((p) => <String, dynamic>{'photoPath': p})
                  .toList();

        // UPDATED: Pass photosData instead of localPaths, plus a progress
        // callback so the current SyncProgress (already set with the
        // action-level index/total above) gains photo-level detail too —
        // Phase 5: "Uploading photo 3 of 12".
        final photoPaths = await SupabaseService.uploadInspectionPhotos(
          jobId: jobId,
          photosData: photosData,
          onProgress: (photoIndex, photoTotal) {
            final current = progress.value;
            if (current == null) return;
            progress.value = current.copyWithPhoto(
              photoIndex: photoIndex,
              photoTotal: photoTotal,
            );
          },
        );

        final checklistData = (payload['checklistData'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        await SupabaseService.submitInspection(
          jobId: jobId,
          findings: payload['findings'] as String,
          isCompliant: payload['isCompliant'] as bool,
          inspectionResult: payload['inspectionResult'] as String,
          observations: payload['observations'] as String,
          discrepancies: payload['discrepancies'] as String?,
          recommendations: payload['recommendations'] as String?,
          inspectorNotes: payload['inspectorNotes'] as String,
          checklistData: checklistData,
          checklistCompletedCount: payload['checklistCompletedCount'] as int,
          checklistTotalCount: payload['checklistTotalCount'] as int,
          photoPaths: photoPaths,
          photoCount: photoPaths.length,
          locationLabel: payload['locationLabel'] as String?,
        );
        break;
      case 'checklist_update':
        final checklistData = (payload['checklistData'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        await SupabaseService.updateJobInspectionProgress(
          jobId: jobId,
          updateData: {
            'checklist_data': checklistData,
            'checklist_completed_count': payload['checklistCompletedCount'],
            'checklist_total_count': payload['checklistTotalCount'],
          },
        );
        break;
      case 'current_step_update':
        await SupabaseService.updateJobInspectionProgress(
          jobId: jobId,
          updateData: {'current_step': payload['currentStep']},
        );
        break;
      // 'photo_upload' as its own standalone action (outside of submit)
      // lands here in a future round if ever needed.
      default:
        debugPrint('SyncOutboxService: unknown action type "$type", skipping');
    }
  }

  static Future<Map<String, dynamic>> _withConflictSnapshot({
    required String jobId,
    required Map<String, dynamic> payload,
  }) async {
    final snapshot = await DBHelper.getCachedJobUpdatedAt(jobId);
    return {...payload, _conflictSnapshotKey: snapshot};
  }

  static Future<void> _throwIfServerVersionConflict({
    required String type,
    required String jobId,
    required Map<String, dynamic> payload,
  }) async {
    if (!_conflictSensitiveTypes.contains(type)) return;
    if (payload[_forceSyncAnywayKey] == true) return;

    final cachedUpdatedAt = payload[_conflictSnapshotKey] as String?;
    if (cachedUpdatedAt == null || cachedUpdatedAt.isEmpty) return;

    final serverUpdatedAt = await SupabaseService.fetchJobUpdatedAt(jobId);
    if (serverUpdatedAt == null || serverUpdatedAt.isEmpty) return;

    if (_sameInstant(cachedUpdatedAt, serverUpdatedAt)) return;

    throw _OutboxConflictException(
      'Conflict detected: job changed on server after this offline action was created. '
      'Cached: $cachedUpdatedAt, Server: $serverUpdatedAt.',
    );
  }

  static bool _sameInstant(String a, String b) {
    final da = DateTime.tryParse(a);
    final db = DateTime.tryParse(b);
    if (da != null && db != null) {
      return da.toUtc().isAtSameMomentAs(db.toUtc());
    }
    return a == b;
  }
}

class _OutboxConflictException implements Exception {
  final String message;
  _OutboxConflictException(this.message);

  @override
  String toString() => message;
}