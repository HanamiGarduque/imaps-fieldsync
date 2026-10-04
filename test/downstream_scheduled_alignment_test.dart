import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/modules/analytics_dashboard/screens/home_dashboard_screen.dart';
import 'package:imaps_fieldsync/modules/analytics_dashboard/widgets/active_assignments_folder_card.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

void main() {
  TaskItem buildTask({required String status, required bool isSelfScheduled}) {
    return TaskItem(
      id: 'downstream-$status-$isSelfScheduled',
      name: 'Downstream Test Task',
      location: 'Test Location',
      parcels: 'Test Parcel',
      status: status,
      inspectionNo: 'INS-DOWNSTREAM',
      scheduledDate: '2026-09-15',
      isSelfScheduled: isSelfScheduled,
      createdAt: '2026-09-01T00:00:00.000Z',
      currentStep: 0,
    );
  }

  void expectConsumerBehavior({
    required String status,
    required bool isSelfScheduled,
    required bool isActiveAssignment,
    required String? dashboardPresentation,
    required String cardLabel,
  }) {
    final task = buildTask(status: status, isSelfScheduled: isSelfScheduled);

    expect(isHomeDashboardActiveAssignment(task), isActiveAssignment);
    expect(homeDashboardTaskPresentationCategory(task), dashboardPresentation);
    expect(
      activeAssignmentStatusLabel(task.lifecycleCategory, task.pendingSection),
      cardLabel,
    );
  }

  group('Home Dashboard and Active Assignments lifecycle alignment', () {
    test('assigned without self-scheduling is Pending', () {
      expectConsumerBehavior(
        status: 'assigned',
        isSelfScheduled: false,
        isActiveAssignment: true,
        dashboardPresentation: 'Pending',
        cardLabel: 'Pending',
      );
    });

    test('assigned with self-scheduling is Pending with Scheduled display', () {
      expectConsumerBehavior(
        status: 'assigned',
        isSelfScheduled: true,
        isActiveAssignment: true,
        dashboardPresentation: 'Scheduled',
        cardLabel: 'Scheduled',
      );
    });

    test('in_progress with self-scheduling remains Ongoing', () {
      expectConsumerBehavior(
        status: 'in_progress',
        isSelfScheduled: true,
        isActiveAssignment: true,
        dashboardPresentation: 'Ongoing',
        cardLabel: 'Ongoing',
      );
    });

    test('completed with self-scheduling remains Completed', () {
      expectConsumerBehavior(
        status: 'completed',
        isSelfScheduled: true,
        isActiveAssignment: false,
        dashboardPresentation: 'Completed',
        cardLabel: 'Completed',
      );
    });

    test('legacy Pending with self-scheduling keeps Scheduled display', () {
      expectConsumerBehavior(
        status: 'Pending',
        isSelfScheduled: true,
        isActiveAssignment: true,
        dashboardPresentation: 'Scheduled',
        cardLabel: 'Scheduled',
      );
    });

    test('submitted with self-scheduling remains Completed', () {
      expectConsumerBehavior(
        status: 'submitted',
        isSelfScheduled: true,
        isActiveAssignment: false,
        dashboardPresentation: 'Completed',
        cardLabel: 'Completed',
      );
    });

    test('cancelled with self-scheduling is not Pending or Scheduled', () {
      expectConsumerBehavior(
        status: 'cancelled',
        isSelfScheduled: true,
        isActiveAssignment: false,
        dashboardPresentation: null,
        cardLabel: 'Unknown',
      );
    });

    test('onprocess with self-scheduling is not Pending or Scheduled', () {
      expectConsumerBehavior(
        status: 'onprocess',
        isSelfScheduled: true,
        isActiveAssignment: false,
        dashboardPresentation: null,
        cardLabel: 'Unknown',
      );
    });
  });
}
