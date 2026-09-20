import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

void main() {
  TaskItem buildTask({
    required String? status,
    bool isSelfScheduled = false,
    String scheduledDate = '2026-09-15',
  }) {
    return TaskItem(
      id: '1',
      name: 'Test Task',
      location: 'Test Location',
      parcels: 'Test Parcel',
      status: status,
      inspectionNo: 'INS-001',
      scheduledDate: scheduledDate,
      isSelfScheduled: isSelfScheduled,
      createdAt: '2026-09-01T00:00:00.000Z',
      currentStep: 1,
    );
  }

  group('exact transitional status mapping', () {
    final cases = <String?, TaskLifecycleCategory>{
      'assigned': TaskLifecycleCategory.pending,
      'Pending': TaskLifecycleCategory.pending,
      'pending': TaskLifecycleCategory.pending,
      'in_progress': TaskLifecycleCategory.ongoing,
      'in-progress': TaskLifecycleCategory.ongoing,
      'ongoing': TaskLifecycleCategory.ongoing,
      'completed': TaskLifecycleCategory.completed,
      'Completed': TaskLifecycleCategory.completed,
      'submitted': TaskLifecycleCategory.completed,
      'onprocess': TaskLifecycleCategory.unknown,
      'cancelled': TaskLifecycleCategory.unknown,
      null: TaskLifecycleCategory.unknown,
      '': TaskLifecycleCategory.unknown,
      '   ': TaskLifecycleCategory.unknown,
      'random_unknown_value': TaskLifecycleCategory.unknown,
      'not_completed': TaskLifecycleCategory.unknown,
      'progress_error': TaskLifecycleCategory.unknown,
      'done_later': TaskLifecycleCategory.unknown,
    };

    for (final entry in cases.entries) {
      test('${entry.key ?? '<null>'} maps to ${entry.value.name}', () {
        expect(mapTaskStatusToLifecycle(entry.key), entry.value);
      });
    }

    test('case and whitespace near-misses are not coerced', () {
      expect(
        mapTaskStatusToLifecycle(' assigned'),
        TaskLifecycleCategory.unknown,
      );
      expect(
        mapTaskStatusToLifecycle('IN_PROGRESS'),
        TaskLifecycleCategory.unknown,
      );
      expect(
        mapTaskStatusToLifecycle('completed '),
        TaskLifecycleCategory.unknown,
      );
    });
  });

  group('TaskItem category and scheduling precedence', () {
    test('assigned + not self-scheduled is Pending / Available Anytime', () {
      final task = buildTask(status: 'assigned');
      expect(task.category, 'Pending');
      expect(task.pendingSection, PendingTaskSection.availableAnytime);
    });

    test('assigned + self-scheduled is Pending / Scheduled', () {
      final task = buildTask(status: 'assigned', isSelfScheduled: true);
      expect(task.category, 'Pending');
      expect(task.pendingSection, PendingTaskSection.scheduled);
    });

    test('legacy Pending + self-scheduled is Pending / Scheduled', () {
      final task = buildTask(status: 'Pending', isSelfScheduled: true);
      expect(task.category, 'Pending');
      expect(task.pendingSection, PendingTaskSection.scheduled);
    });

    for (final status in ['in_progress', 'ongoing']) {
      test('$status remains Ongoing when self-scheduled', () {
        final task = buildTask(status: status, isSelfScheduled: true);
        expect(task.category, 'Ongoing');
        expect(task.pendingSection, isNull);
      });
    }

    test('in_progress + not self-scheduled is Ongoing', () {
      final task = buildTask(status: 'in_progress');
      expect(task.category, 'Ongoing');
      expect(task.pendingSection, isNull);
    });

    for (final status in ['completed', 'submitted']) {
      test('$status remains Completed when self-scheduled', () {
        final task = buildTask(status: status, isSelfScheduled: true);
        expect(task.category, 'Completed');
        expect(task.pendingSection, isNull);
      });
    }

    test('unknown + self-scheduled is excluded from normal categories', () {
      final task = buildTask(
        status: 'random_unknown_value',
        isSelfScheduled: true,
      );
      expect(task.category, 'Unknown');
      expect(task.pendingSection, isNull);
    });

    for (final status in <String?>[
      'onprocess',
      'cancelled',
      null,
      '',
      '   ',
      'not_completed',
      'progress_error',
      'done_later',
    ]) {
      test('${status ?? '<null>'} is not placed in a normal category', () {
        final task = buildTask(status: status);
        expect(task.category, 'Unknown');
      });
    }
  });

  group('online/offline source parity', () {
    test('fromJob preserves SQL null status as Unknown', () {
      final task = TaskItem.fromJob({'id': 'offline-null', 'status': null});
      expect(task.status, isNull);
      expect(task.category, 'Unknown');
    });

    test('fromJob applies the same mapping to cached status strings', () {
      final task = TaskItem.fromJob({
        'id': 'offline-legacy',
        'status': 'submitted',
        'is_self_scheduled': true,
      });
      expect(task.status, 'submitted');
      expect(task.category, 'Completed');
      expect(task.pendingSection, isNull);
    });
  });
}
