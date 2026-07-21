import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'db_helper.dart';
import 'supabase_service.dart';

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
  static const _lastSyncPrefsKey = 'field_sync_last_success';

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
  static void start() {
    drain();
    _connSub ??= Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        drain();
      }
    });
  }

  // --- ENQUEUE HELPERS (one per action type) ---

  static Future<void> enqueueGpsConfirm({
    required String jobId,
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    String? locationLabel,
  }) {
    return DBHelper.enqueueAction(
      id: const Uuid().v4(),
      type: 'gps_confirm',
      jobId: jobId,
      payload: {
        'latitude': latitude,
        'longitude': longitude,
        'accuracyMeters': accuracyMeters,
        'locationLabel': locationLabel,
      },
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
  }) {
    return DBHelper.enqueueAction(
      id: 'checklist_update_$jobId',
      type: 'checklist_update',
      jobId: jobId,
      payload: {
        'checklistData': checklistData,
        'checklistCompletedCount': checklistCompletedCount,
        'checklistTotalCount': checklistTotalCount,
      },
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
  }) {
    return DBHelper.enqueueAction(
      id: 'current_step_update_$jobId',
      type: 'current_step_update',
      jobId: jobId,
      payload: {'currentStep': step},
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
    required List<Map<String, dynamic>> photosData, // UPDATED: Changed to expect Map data
    String? locationLabel,
  }) {
    return DBHelper.enqueueAction(
      id: const Uuid().v4(),
      type: 'submit_inspection',
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
  }

  // --- DRAIN LOOP ---

  /// Processes every actionable row in creation order. Safe to call
  /// repeatedly/concurrently — re-entrant calls are ignored while one is
  /// already running.
  static Future<void> drain() async {
    if (_draining) return;
    _draining = true;
    try {
      final actions = await DBHelper.getActionableActions();
      for (final action in actions) {
        final id = action['id'] as String;
        await DBHelper.markActionSyncing(id);
        try {
          await _executeAction(action);
          await DBHelper.markActionSynced(id);
          await _recordSuccessfulSync();
        } catch (e) {
          debugPrint('SyncOutboxService: action $id (${action['type']}) failed: $e');
          await DBHelper.markActionFailed(id, e.toString());
          // Keep draining the rest — one stuck action (e.g. a job that
          // got deleted server-side) shouldn't block everything queued
          // after it.
        }
      }
    } finally {
      _draining = false;
    }
  }

  static Future<void> _executeAction(Map<String, dynamic> action) async {
    final type = action['type'] as String;
    final jobId = action['job_id'] as String;
    final payload = Map<String, dynamic>.from(jsonDecode(action['payload'] as String) as Map);

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
      case 'submit_inspection':
        // Photos couldn't be uploaded while this was queued (that needs a
        // connection too) — do it now, at drain time, using the local
        // paths/metadata captured back on Step 3. If a photo file no longer exists
        // (e.g. cleared cache), uploadInspectionPhotos already skips it
        // rather than failing the whole action.
        
        // UPDATED: Cast the dynamic list back into List<Map<String, dynamic>>
        final photosData = (payload['photosData'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
            
        // UPDATED: Pass photosData instead of localPaths
        final photoPaths = await SupabaseService.uploadInspectionPhotos(jobId: jobId, photosData: photosData);
        
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
}