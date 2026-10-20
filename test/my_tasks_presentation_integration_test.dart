import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/modules/analytics_dashboard/screens/home_dashboard_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/models/dashboard_stats.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

void main() {
  TaskItem task({String status = 'in_progress', bool scheduled = true, int step = 3}) => TaskItem(
    id: 'fictional-task', name: 'Fictional Applicant', location: 'Fictional Site',
    parcels: '', inspectionNo: 'TEST-001', status: status,
    isSelfScheduled: scheduled, currentStep: step,
    scheduledDate: '2026-10-24', deadlineDate: '2026-10-25',
  );

  test('started committed Visits stay Pending/Scheduled through steps 1–6', () {
    for (var step = 1; step <= 6; step++) {
      final t = task(step: step);
      expect(t.category, 'Pending', reason: 'step $step');
      expect(t.pendingSection, PendingTaskSection.scheduled);
      expect(homeDashboardTaskPresentationCategory(t), 'Scheduled');
      expect(t.status, 'in_progress', reason: 'presentation must not falsify lifecycle');
    }
  });

  test('only non-committed started tasks occupy the Ongoing bucket', () {
    final rows = [task(), task(scheduled: false)];
    expect(rows.where((t) => t.category == 'Pending').length, 1);
    expect(rows.where((t) => t.category == 'Ongoing').length, 1);
    expect(rows.where(isHomeDashboardActiveAssignment).length, 2);
  });

  test('Profile scheduled cohort excludes a PO placeholder and unknown status', () {
    final stats = InspectorDashboardStats.fromTasks([
      task(), task(scheduled: false, step: 0, status: 'assigned'),
      task(status: 'completed', step: 6), task(status: 'cancelled'),
    ]);
    expect(stats.scheduledCohort.length, 2);
    expect(stats.scheduledCohort.where((t) => t.isCompleted).length, 1);
  });
}
