import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/modules/analytics_dashboard/screens/home_dashboard_screen.dart';
import 'package:imaps_fieldsync/modules/analytics_dashboard/widgets/active_assignments_folder_card.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

void main() {
  TaskItem buildTask({
    required String id,
    required String status,
    bool isSelfScheduled = false,
    int currentStep = 0,
    int photoCount = 0,
  }) {
    return TaskItem(
      id: id,
      name: 'Applicant $id',
      location: 'Rosario',
      parcels: 'Parcel $id',
      status: status,
      inspectionNo: 'INS-$id',
      scheduledDate: '2026-10-15',
      deadlineDate: '2026-10-31',
      isSelfScheduled: isSelfScheduled,
      currentStep: currentStep,
      photoCount: photoCount,
      createdAt: '2026-10-01T00:00:00.000Z',
    );
  }

  group('Home Active Assignments canonical filtering', () {
    test('pending task appears', () {
      final task = buildTask(id: 'pending', status: 'assigned');

      expect(task.lifecycleCategory, TaskLifecycleCategory.pending);
      expect(isHomeDashboardActiveAssignment(task), isTrue);
    });

    test('Ongoing task appears using the My Tasks lifecycle mapping', () {
      final task = buildTask(id: 'ongoing', status: 'in_progress');

      expect(task.category, 'Ongoing');
      expect(isHomeDashboardActiveAssignment(task), isTrue);
    });

    test('completed task does not appear', () {
      final task = buildTask(id: 'completed', status: 'completed');

      expect(task.lifecycleCategory, TaskLifecycleCategory.completed);
      expect(isHomeDashboardActiveAssignment(task), isFalse);
    });

    test('pending and ongoing appear together while completed is excluded', () {
      final tasks = [
        buildTask(id: 'pending', status: 'assigned'),
        buildTask(id: 'ongoing', status: 'in_progress'),
        buildTask(id: 'completed', status: 'completed'),
      ];

      final active = tasks.where(isHomeDashboardActiveAssignment).toList();

      expect(active.map((task) => task.id), ['pending', 'ongoing']);
    });

    test('scheduled tasks remain in the Pending bucket and appear', () {
      final task = buildTask(
        id: 'scheduled',
        status: 'assigned',
        isSelfScheduled: true,
      );

      expect(task.lifecycleCategory, TaskLifecycleCategory.pending);
      expect(task.pendingSection, PendingTaskSection.scheduled);
      expect(isHomeDashboardActiveAssignment(task), isTrue);
    });

    test('cached pending and ongoing rows use the same filtering rule', () {
      final cachedTasks = [
        TaskItem.fromJob({'id': 'cached-pending', 'status': 'assigned'}),
        TaskItem.fromJob({'id': 'cached-ongoing', 'status': 'in_progress'}),
        TaskItem.fromJob({'id': 'cached-completed', 'status': 'completed'}),
      ];

      final active = cachedTasks
          .where(isHomeDashboardActiveAssignment)
          .toList();

      expect(active.map((task) => task.id), [
        'cached-pending',
        'cached-ongoing',
      ]);
    });

    test('task progress remains derived from each task only', () {
      final pending = buildTask(id: 'pending', status: 'assigned');
      final ongoing = buildTask(
        id: 'ongoing',
        status: 'in_progress',
        photoCount: 1,
      );

      expect(pending.derivedHighestStep, 0);
      expect(ongoing.derivedHighestStep, 3);
      expect(pending.derivedHighestStep, 0);
    });

    test('My Tasks categories remain unchanged', () {
      expect(
        mapTaskStatusToLifecycle('assigned'),
        TaskLifecycleCategory.pending,
      );
      expect(
        mapTaskStatusToLifecycle('in_progress'),
        TaskLifecycleCategory.ongoing,
      );
      expect(
        mapTaskStatusToLifecycle('completed'),
        TaskLifecycleCategory.completed,
      );
      expect(
        mapTaskStatusToLifecycle('onprocess'),
        TaskLifecycleCategory.unknown,
      );
    });

    test('dashboard keeps the existing task-specific overview navigation', () {
      final source = File(
        'lib/modules/analytics_dashboard/screens/home_dashboard_screen.dart',
      ).readAsStringSync();

      expect(source, contains('task: _upcomingTasks[index]'));
      expect(
        source,
        contains('fetchedJob: _entryJobs[_upcomingTasks[index].id]'),
      );
    });
  });

  testWidgets('tapping a card invokes the callback for the correct task', (
    tester,
  ) async {
    String? openedTaskId;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 260,
            child: ActiveAssignmentsFolderCard(
              key: const ValueKey('ongoing-card'),
              inspectionId: 'ongoing',
              referenceNo: 'INS-ongoing',
              date: 'Oct 15, 2026',
              location: 'Rosario',
              applicantName: 'Ongoing Applicant',
              applicationType: 'Residential',
              lifecycleCategory: TaskLifecycleCategory.ongoing,
              onTap: () => openedTaskId = 'ongoing',
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ongoing-card')));
    await tester.pump();

    expect(openedTaskId, 'ongoing');
  });
}
