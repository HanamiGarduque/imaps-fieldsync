import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

void main() {
  TaskItem buildTask({
    required String status,
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

  group('TaskItem.category ground truth', () {
    test('completed tasks are classified as Completed regardless of self-scheduling', () {
      final task = buildTask(status: 'completed', isSelfScheduled: true);
      expect(task.category, 'Completed');
    });

    test('self-scheduled tasks are classified as Scheduled', () {
      final task = buildTask(status: 'in_progress', isSelfScheduled: true);
      expect(task.category, 'Scheduled');
    });

    test('non self-scheduled in_progress tasks are classified as Ongoing', () {
      final task = buildTask(status: 'in_progress', isSelfScheduled: false);
      expect(task.category, 'Ongoing');
    });

    test('non self-scheduled assigned tasks are classified as Pending', () {
      final task = buildTask(status: 'assigned', isSelfScheduled: false);
      expect(task.category, 'Pending');
    });
  });
}
