import 'package:flutter/foundation.dart';

import '../models/report_models.dart';
import 'auth_service.dart';
import 'db_helper.dart';
import 'supabase_service.dart';

/// One task this inspector may file an Application Support report against.
///
/// Identity is the exact remote triple carried by the job row itself:
/// `field_jobs.id`, `supabase_application_id`, `bridge_source_id`. Nothing
/// here is ever inferred from a reference number, a display string, app
/// configuration, or the current environment.
class ReportableTask {
  const ReportableTask({
    required this.fieldJobId,
    required this.referenceNumber,
    required this.applicantName,
    required this.barangay,
    required this.applicationType,
    required this.status,
    this.supabaseApplicationId,
    this.bridgeSourceId,
  });

  final String fieldJobId;
  final String? supabaseApplicationId;
  final String? bridgeSourceId;
  final String referenceNumber;
  final String applicantName;
  final String barangay;
  final String applicationType;
  final String status;

  /// True only when all three identity members are present. An incomplete row
  /// stays visible to the inspector but cannot be filed against.
  bool get identityComplete =>
      fieldJobId.trim().isNotEmpty &&
      supabaseApplicationId?.trim().isNotEmpty == true &&
      bridgeSourceId?.trim().isNotEmpty == true;

  String get displayTitle {
    final ref = referenceNumber.trim().isEmpty
        ? 'No reference number'
        : referenceNumber;
    return '$ref — $applicantName';
  }

  static String _text(Object? value, [String fallback = '']) {
    final raw = value is String ? value.trim() : value?.toString().trim();
    return (raw == null || raw.isEmpty) ? fallback : raw;
  }

  /// Reads the application embed under either PostgREST alias used by the two
  /// inspector-scoped job reads.
  static Map<String, dynamic> _app(Map<String, dynamic> row) {
    for (final key in row.keys) {
      if (!key.startsWith('supabase_zoning_applications')) continue;
      final embed = row[key];
      if (embed is Map) return Map<String, dynamic>.from(embed);
    }
    return const {};
  }

  /// Builds from either a `local_jobs` cache row or a live inspector-scoped job
  /// row. Both carry the same identity columns.
  factory ReportableTask.fromRow(Map<String, dynamic> row) {
    final app = _app(row);
    return ReportableTask(
      fieldJobId: row['id'] as String,
      supabaseApplicationId: row['supabase_application_id'] as String?,
      bridgeSourceId: row['bridge_source_id'] as String?,
      referenceNumber: _text(
        row['reference_number'] ?? app['reference_number'],
        'No reference number',
      ),
      applicantName: _text(
        row['applicant_name'] ?? app['applicant_name'],
        'Unknown applicant',
      ),
      barangay: _text(row['barangay'] ?? app['barangay'], 'No barangay listed'),
      applicationType: _text(
        row['application_type'] ?? app['application_type'],
        'Application',
      ),
      status: _text(row['status'], 'assigned'),
    );
  }
}

/// The Application Support submit gate, in one place.
///
/// Returned message is shown to the inspector verbatim; `null` means the form
/// may submit. Extracted so the ordering is testable without a widget tree, and
/// so the screen cannot drift into rejecting a form it should accept.
class ApplicationSupportValidation {
  ApplicationSupportValidation._();

  /// "Choose the task this concerns." is reachable ONLY when [task] is null.
  /// A selected task with the exact identity triple can never produce it.
  static String? errorFor({
    required ReportableTask? task,
    required String? supportCategory,
    required String description,
  }) {
    if (task == null) return 'Choose the task this concerns.';
    if (!task.identityComplete) {
      return 'Refresh this task online before reporting an application concern.';
    }
    return ReportInput.categoryError(supportCategory) ??
        ReportInput.descriptionError(description);
  }
}

/// Builds and maintains the Application Support task population.
class ReportableTasks {
  ReportableTasks._();

  /// Test seams for the three external reads this loader depends on. The real
  /// implementations are the inspector-scoped services; production never sets
  /// these.
  @visibleForTesting
  static Future<bool> Function()? onlineOverride;
  @visibleForTesting
  static Future<List<Map<String, dynamic>>> Function()? assignedJobsOverride;
  @visibleForTesting
  static Future<List<Map<String, dynamic>>> Function()? completedJobsOverride;

  @visibleForTesting
  static void resetTestHooks() {
    onlineOverride = null;
    assignedJobsOverride = null;
    completedJobsOverride = null;
  }

  static Future<bool> _hasNetwork() async => onlineOverride != null
      ? onlineOverride!()
      : AuthService.hasConnectivity();

  /// The selector population for the inspector.
  ///
  /// ONLINE: the two existing authenticated, inspector-scoped reads My Tasks
  /// already uses (`fetchMyJobs` for currently assigned work, and
  /// `fetchCompletedJobs` for the legitimately available completed/submitted
  /// history) are combined and written through the EXISTING `local_jobs` cache
  /// path, so nothing the inspector legitimately has is evicted. The refreshed
  /// cache is then read back, which is also what makes the identity available
  /// offline afterwards.
  ///
  /// OFFLINE, or if either read fails: the cached `local_jobs` population only.
  /// No unscoped `field_jobs` query and no reference-number lookup ever happen.
  static Future<List<ReportableTask>> loadForInspector() async {
    final cached = await _fromCache();

    if (!await _hasNetwork()) return cached;

    try {
      final assigned = assignedJobsOverride != null
          ? await assignedJobsOverride!()
          : await SupabaseService.fetchMyJobs();
      final completed = completedJobsOverride != null
          ? await completedJobsOverride!()
          : await SupabaseService.fetchCompletedJobs();
      final combined = <String, Map<String, dynamic>>{
        for (final job in assigned) job['id'] as String: job,
        for (final job in completed) job['id'] as String: job,
      };
      if (combined.isNotEmpty) {
        // The EXISTING cache path, so the identities this report needs are also
        // available offline afterwards.
        await DBHelper.cacheJobs(combined.values.toList());
        return await _fromCache();
      }
    } catch (e) {
      // A failed refresh must never destroy or hide a usable cached population.
      return cached;
    }
    return cached;
  }

  static Future<List<ReportableTask>> _fromCache() async {
    try {
      final rows = await DBHelper.getCachedJobs();
      return rows.map(ReportableTask.fromRow).toList()
        ..sort((a, b) => a.displayTitle.compareTo(b.displayTitle));
    } catch (_) {
      return const [];
    }
  }

  /// Keeps a selection across a rebuild or an async refresh.
  ///
  /// Retained ONLY by exact `fieldJobId` — never by reference number or display
  /// text. A selection is dropped only when that exact task is gone from the
  /// authorized population or has lost the exact identity the report needs; the
  /// caller is then expected to say so explicitly rather than silently
  /// clearing.
  static ReportableTask? retainSelection(
    List<ReportableTask> population,
    ReportableTask? selected,
  ) {
    if (selected == null) return null;
    for (final task in population) {
      if (task.fieldJobId != selected.fieldJobId) continue;
      // Refresh the held selection from the authoritative refreshed row so the
      // identity stays exactly what the server now says.
      return task.identityComplete ? task : null;
    }
    return null;
  }
}
