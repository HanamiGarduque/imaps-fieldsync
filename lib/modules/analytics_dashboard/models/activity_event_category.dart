/// Recent Activity classification for the dashboard filter chips and tiles.
///
/// Extracted from the dashboard widget so the mapping is testable without a
/// widget tree or a network, following the same reasoning as
/// `ApplicationSupportValidation` in `core/services/reportable_tasks.dart`.
///
/// WHY REPORTS & SUPPORT IS ITS OWN BUCKET
/// ---------------------------------------
/// `activity_log.event_type` is free-form text written by several systems, and
/// anything unrecognised used to fall through to `profile`. That default is a
/// reasonable last resort, but it is actively wrong for report events: a
/// Site Inspector whose report was resolved would see their own notification
/// labelled "Profile", next to genuine profile and security edits. That reads
/// as noise and teaches the inspector to ignore the one feed that matters.
///
/// Every Reports & Support event the app writes or receives is named here
/// explicitly, so adding one is a one-line change that cannot silently regress
/// into the profile bucket.
class ActivityEventCategory {
  ActivityEventCategory._();

  static const String reports = 'reports';

  /// Event types written by FieldSync itself, plus the two terminal events iMAPS
  /// writes to `activity_log` when a report reaches its official response.
  static const Set<String> reportEventTypes = {
    'diagnostic_report_submitted',
    'report_resolved',
    'report_wont_fix',
  };

  /// All filter buckets, in display order.
  static const List<String> filters = ['all', 'tasks', 'sync', reports, 'profile'];

  /// Which bucket an event belongs to.
  ///
  /// An unrecognised type falls through to `profile`, which stays the safe
  /// default: it is the account-level bucket, so a genuinely unknown
  /// system event is at least still visible under "All".
  static String categoryFor(String? eventType) {
    switch (eventType) {
      case 'inspection_completed':
      case 'rework_started':
      case 'step_completed':
      case 'gps_confirmed':
      case 'field_findings_updated':
        return 'tasks';
      case 'photos_synced':
      case 'sync_manual':
      case 'sync_inspection':
      case 'cache_cleared':
        return 'sync';
      case 'diagnostic_report_submitted':
      case 'report_resolved':
      case 'report_wont_fix':
        return reports;
      default:
        return 'profile';
    }
  }

  /// Human-readable chip label for a bucket.
  static String labelFor(String category) => switch (category) {
        reports => 'Reports',
        'tasks' => 'Task',
        'sync' => 'Sync',
        _ => 'Profile',
      };
}