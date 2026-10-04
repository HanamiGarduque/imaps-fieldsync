import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/modules/analytics_dashboard/models/activity_event_category.dart';

void main() {
  // Guards the audit finding: an inspector's own terminal report notification
  // must never be filed under the Profile bucket.
  test('every Reports & Support event maps to the Reports bucket', () {
    for (final event in ActivityEventCategory.reportEventTypes) {
      expect(
        ActivityEventCategory.categoryFor(event),
        ActivityEventCategory.reports,
        reason: '$event must not fall through to another bucket',
      );
      expect(ActivityEventCategory.labelFor(ActivityEventCategory.reports), 'Reports');
    }
  });

  test('the iMAPS terminal events are classified, not defaulted', () {
    // These two are written by iMAPS, not FieldSync, and are the exact events the
    // notification work introduced.
    expect(ActivityEventCategory.categoryFor('report_resolved'), 'reports');
    expect(ActivityEventCategory.categoryFor('report_wont_fix'), 'reports');
    expect(ActivityEventCategory.categoryFor('diagnostic_report_submitted'), 'reports');
  });

  test('no report event resolves to the Profile label', () {
    for (final event in ActivityEventCategory.reportEventTypes) {
      final label = ActivityEventCategory.labelFor(
        ActivityEventCategory.categoryFor(event),
      );
      expect(label, isNot('Profile'));
      expect(label, 'Reports');
    }
  });

  test('existing buckets keep their previous behaviour', () {
    for (final event in ['inspection_completed', 'rework_started', 'step_completed', 'gps_confirmed']) {
      expect(ActivityEventCategory.categoryFor(event), 'tasks');
    }
    for (final event in ['photos_synced', 'sync_manual', 'sync_inspection', 'cache_cleared']) {
      expect(ActivityEventCategory.categoryFor(event), 'sync');
    }
    for (final event in ['push_received', 'profile_updated', 'security_updated']) {
      expect(ActivityEventCategory.categoryFor(event), 'profile');
    }
    expect(ActivityEventCategory.categoryFor('some_future_event'), 'profile');
    expect(ActivityEventCategory.categoryFor(null), 'profile');
  });

  test('every non-All filter has a label', () {
    for (final filter in ActivityEventCategory.filters) {
      if (filter == 'all') continue;
      expect(ActivityEventCategory.labelFor(filter), isNotEmpty);
    }
    expect(ActivityEventCategory.filters, contains('all'));
    expect(ActivityEventCategory.filters, contains(ActivityEventCategory.reports));
  });
}