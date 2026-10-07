import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' show Database;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'db_helper.dart';
import 'supabase_service.dart';
export 'inspection_authority.dart';

/// Retained CURRENT work keeps its existing offline continuation. Unknown
/// legacy metadata requires fresh online assignment verification before repair.
class InspectionStartService {
  static Future<InspectionStartResult> verifyCurrentInspectorMayStartJob(
    String jobId,
  ) async => (await _verifiedAssignment(jobId)).$1;

  /// The exact remote job, returned only when assigned to the current session.
  static Future<(InspectionStartResult, Map<String, dynamic>?)> _verifiedAssignment(
    String jobId, {bool legacyMetadata = false}
  ) async {
    const denied = InspectionStartResult.notAssignedOrUnavailable;
    try {
      final client = SupabaseService.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null || uid.isEmpty) return (InspectionStartResult.authRequired, null);
      if (jobId.isEmpty) return (denied, null);
      final row = await client.from('field_jobs')
          .select(legacyMetadata
              ? 'id,assigned_inspector_id,bridge_source_id,local_inspection_id'
              : 'id,assigned_inspector_id')
          .eq('id', jobId)
          .eq('assigned_inspector_id', uid)
          .maybeSingle()
          .retry(enabled: false)
          .timeout(const Duration(seconds: 10));
      // A result from a previous session must not authorize the new session.
      if (client.auth.currentUser?.id != uid) return (InspectionStartResult.authRequired, null);
      // RLS deliberately makes reassigned, unassigned and missing identical.
      if (row == null) return (denied, null);
      if (row['id'] != jobId || row['assigned_inspector_id'] != uid) {
        debugPrint('[INSPECTION_START] Unexpected assignment response; blocked.');
        return (InspectionStartResult.offlineOrUnverifiable, null);
      }
      return (InspectionStartResult.authorized, row);
    } on AuthException {
      return (InspectionStartResult.authRequired, null);
    } on PostgrestException catch (e) {
      if (const {'401', '403', 'PGRST301', 'PGRST302', 'PGRST303', '28000', '28P01'}
          .contains(e.code)) {
        return (InspectionStartResult.authRequired, null);
      }
      debugPrint('[INSPECTION_START] Server verification failed; blocked.');
      return (InspectionStartResult.offlineOrUnverifiable, null);
    } on IOException {
      return (InspectionStartResult.offlineOrUnverifiable, null);
    } on TimeoutException {
      return (InspectionStartResult.offlineOrUnverifiable, null);
    } catch (e) {
      // Includes malformed responses/programming errors: fail closed, but do
      // not disguise them as a known offline condition or log response/PII.
      debugPrint('[INSPECTION_START] Unexpected verification failure '
          '(${e.runtimeType}); blocked.');
      return (InspectionStartResult.offlineOrUnverifiable, null);
    }
  }

  /// The single normal step-entry seam. No denied attempt writes the cache,
  /// retention, inspection, photos or outbox. A cache row alone is not proof of
  /// prior field work; a durable retention marker or actual saved draft is.
  static Future<InspectionStartResult> prepareJob(
    String jobId, {
    Map<String, dynamic>? fetchedJob,
  }) async {
    final uid = DBHelper.currentInspectorId;
    if (uid == null) return InspectionStartResult.authRequired;
    if (jobId.isEmpty || (fetchedJob != null && fetchedJob['id'] != jobId)) {
      return InspectionStartResult.notAssignedOrUnavailable;
    }
    final db = await DBHelper.database;
    var repairedLegacy = false;
    try { await DBHelper.requireOwnedJob(db, jobId, uid); }
    on StateError {
      final resolved = await _resolveLegacyMetadata(db, jobId, uid, fetchedJob);
      if (resolved != InspectionStartResult.authorized) return resolved;
      // The strict gate always has the final word, repaired or not.
      try { await DBHelper.requireOwnedJob(db, jobId, uid); }
      on StateError { return InspectionStartResult.notAssignedOrUnavailable; }
      repairedLegacy = true;
    }
    final started = await db.rawQuery('''
      SELECT job_id FROM inspection_job_retention WHERE job_id = ? AND inspector_id = ?
      UNION ALL SELECT id FROM local_inspections WHERE id = ? AND inspector_id = ?
      LIMIT 1
    ''', [jobId, uid, jobId, uid]);
    if (started.isEmpty && !repairedLegacy) {
      final result = await verifyCurrentInspectorMayStartJob(jobId);
      if (result != InspectionStartResult.authorized) return result;
    }
    // This is client-local, not a server lease. Later server writes still rely
    // on authenticated ownership predicates/RLS if assignment changes now.
    if (DBHelper.currentInspectorId != uid) return InspectionStartResult.authRequired;
    await DBHelper.retainInspectionJob(jobId, fetchedJob: repairedLegacy ? null : fetchedJob);
    return InspectionStartResult.authorized;
  }

  /// Repair only NULL access metadata after an exact online assignment check.
  /// Authored evidence is never attributed here, and queued work is never replayed.
  static Future<InspectionStartResult> _resolveLegacyMetadata(
      Database db, String jobId, String uid, Map<String, dynamic>? fetchedJob) async {
    try {
      final session = SupabaseService.client.auth.currentSession;
      if (session == null || session.user.id != uid) return InspectionStartResult.authRequired;
      void requireSameSession() {
        DBHelper.requireSameInspector(uid);
        if (!identical(SupabaseService.client.auth.currentSession, session)) {
          throw StateError('Inspector session changed');
        }
      }
      if (await DBHelper.classifyJobOwnership(db, jobId, uid)
          != LocalOwnershipResult.legacyUnknown) {
        return InspectionStartResult.notAssignedOrUnavailable;
      }
      final (result, remote) = await _verifiedAssignment(jobId, legacyMetadata: true);
      if (result != InspectionStartResult.authorized) return result;
      final repaired = await db.transaction((txn) async {
        requireSameSession();
        if (await DBHelper.classifyJobOwnership(txn, jobId, uid)
            != LocalOwnershipResult.legacyUnknown) {
          return false;
        }
        for (final (table, column) in const [
          ('local_inspections', 'id'), ('local_photos', 'job_id'),
        ]) {
          if ((await txn.query(table, columns: [column], limit: 1,
              where: '$column = ? AND inspector_id IS NULL', whereArgs: [jobId])).isNotEmpty) {
            return false;
          }
        }
        // ponytail: any queued row blocks repair; add action-specific clearance
        // only when independent replay-safety validation is required.
        if ((await txn.query('pending_actions', columns: ['id'], limit: 1,
            where: 'job_id = ?', whereArgs: [jobId])).isNotEmpty) {
          return false;
        }
        final jobs = await txn.query('local_jobs', where: 'id = ?', whereArgs: [jobId]);
        if (jobs.length != 1) return false;
        final cached = jobs.single;
        for (final key in ['bridge_source_id', 'local_inspection_id']) {
          if (cached[key] != null && cached[key] != remote![key]) return false;
          if (fetchedJob?[key] != null && fetchedJob![key] != remote![key]) return false;
        }
        requireSameSession();
        await txn.update('local_jobs', {'inspector_id': uid},
            where: 'id = ? AND inspector_id IS NULL', whereArgs: [jobId]);
        await txn.update('inspection_job_retention', {'inspector_id': uid},
            where: 'job_id = ? AND inspector_id IS NULL', whereArgs: [jobId]);
        await DBHelper.requireOwnedJob(txn, jobId, uid);
        requireSameSession();
        return true;
      });
      return repaired ? InspectionStartResult.authorized
          : InspectionStartResult.localOwnershipIncomplete;
    } on StateError {
      return InspectionStartResult.authRequired;
    }
  }
}
