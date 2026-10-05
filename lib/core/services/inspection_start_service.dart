import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'db_helper.dart';
import 'supabase_service.dart';

enum InspectionStartResult {
  authorized,
  notAssignedOrUnavailable,
  authRequired,
  offlineOrUnverifiable;

  String get message => switch (this) {
    authorized => '',
    notAssignedOrUnavailable =>
      'This job is no longer available to start from your account. '
          'Refresh your assignments or contact the Planning Office.',
    authRequired => 'Your session has expired. Please sign in again.',
    offlineOrUnverifiable =>
      'Connect to verify that this job is still assigned to you before starting.',
  };
}

/// Phase A gates only new field work. Retained work and persisted drafts keep
/// their existing continuation/recovery path; transferring them belongs to #9.
class InspectionStartService {
  static Future<InspectionStartResult> verifyCurrentInspectorMayStartJob(
    String jobId,
  ) async {
    try {
      final client = SupabaseService.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null || uid.isEmpty) return InspectionStartResult.authRequired;
      if (jobId.isEmpty) return InspectionStartResult.notAssignedOrUnavailable;
      final row = await client
          .from('field_jobs')
          .select('id,assigned_inspector_id')
          .eq('id', jobId)
          .eq('assigned_inspector_id', uid)
          .maybeSingle()
          .retry(enabled: false)
          .timeout(const Duration(seconds: 10));
      // A result from a previous session must not authorize the new session.
      if (client.auth.currentUser?.id != uid) {
        return InspectionStartResult.authRequired;
      }
      // RLS deliberately makes reassigned, unassigned and missing identical.
      if (row == null) return InspectionStartResult.notAssignedOrUnavailable;
      if (row['id'] != jobId || row['assigned_inspector_id'] != uid) {
        debugPrint('[INSPECTION_START] Unexpected assignment response; blocked.');
        return InspectionStartResult.offlineOrUnverifiable;
      }
      return InspectionStartResult.authorized;
    } on AuthException {
      return InspectionStartResult.authRequired;
    } on PostgrestException catch (e) {
      if (const {'401', '403', 'PGRST301', 'PGRST302', 'PGRST303', '28000', '28P01'}
          .contains(e.code)) {
        return InspectionStartResult.authRequired;
      }
      debugPrint('[INSPECTION_START] Server verification failed; blocked.');
      return InspectionStartResult.offlineOrUnverifiable;
    } on IOException {
      return InspectionStartResult.offlineOrUnverifiable;
    } on TimeoutException {
      return InspectionStartResult.offlineOrUnverifiable;
    } catch (e) {
      // Includes malformed responses/programming errors: fail closed, but do
      // not disguise them as a known offline condition or log response/PII.
      debugPrint('[INSPECTION_START] Unexpected verification failure '
          '(${e.runtimeType}); blocked.');
      return InspectionStartResult.offlineOrUnverifiable;
    }
  }

  /// The single normal step-entry seam. No denied attempt writes the cache,
  /// retention, inspection, photos or outbox. A cache row alone is not proof of
  /// prior field work; a durable retention marker or actual saved draft is.
  static Future<InspectionStartResult> prepareJob(
    String jobId, {
    Map<String, dynamic>? fetchedJob,
  }) async {
    final db = await DBHelper.database;
    final started = await db.rawQuery('''
      SELECT job_id FROM inspection_job_retention WHERE job_id = ?
      UNION ALL SELECT id FROM local_inspections WHERE id = ?
      LIMIT 1
    ''', [jobId, jobId]);
    if (started.isEmpty) {
      final result = await verifyCurrentInspectorMayStartJob(jobId);
      if (result != InspectionStartResult.authorized) return result;
    }
    // This is client-local, not a server lease. Later server writes still rely
    // on authenticated ownership predicates/RLS if assignment changes now.
    await DBHelper.retainInspectionJob(jobId, fetchedJob: fetchedJob);
    return InspectionStartResult.authorized;
  }
}
