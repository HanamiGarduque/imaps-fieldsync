import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/modules/tasks/models/task_lifecycle.dart';

/// Canonical My Tasks presentation — MY_TASKS_FINAL_FLOW_SPEC_20261020 §2–§5.
/// Pure unit tests: no network, no storage, no device.
void main() {
  final today = DateTime(2026, 10, 20);

  MyTaskPresentation present({
    String? status = 'assigned',
    bool selfScheduled = false,
    String? visit,
    String? deadline = '2026-10-25',
    int step = 0,
  }) =>
      MyTaskPresentation.of(
        MyTaskFacts(
          status: status,
          isSelfScheduled: selfScheduled,
          visitDate: visit,
          deadlineDate: deadline,
          currentStep: step,
        ),
        today,
      );

  group('category precedence', () {
    test('saved progress without a Visit is Ongoing even before status refresh', () {
      expect(present(status: 'pending', step: 3).lifecycle, MyTaskLifecycle.ongoing);
    });
    test('completed wins over every other signal', () {
      final p = present(
          status: 'completed', selfScheduled: true, visit: '2026-10-21');
      expect(p.lifecycle, MyTaskLifecycle.completed);
      expect(p.border, MyTaskBorder.green);
    });

    test('a self-scheduled task is Scheduled, never Ongoing', () {
      for (final status in ['assigned', 'Pending', 'pending', 'in_progress']) {
        final p = present(
            status: status, selfScheduled: true, visit: '2026-10-21');
        expect(p.lifecycle, MyTaskLifecycle.scheduled, reason: status);
      }
    });

    test('a started task without a committed visit is Ongoing', () {
      final p = present(status: 'in_progress');
      expect(p.lifecycle, MyTaskLifecycle.ongoing);
    });

    test('an unstarted task without a committed visit is Available Anytime',
        () {
      final p = present(status: 'assigned');
      expect(p.lifecycle, MyTaskLifecycle.availableAnytime);
    });

    test('an unrecognized status stays unknown', () {
      for (final status in ['onprocess', 'cancelled', '', 'IN_PROGRESS']) {
        final p = present(status: status, selfScheduled: true);
        expect(p.lifecycle, MyTaskLifecycle.unknown, reason: status);
      }
      expect(present(status: null).lifecycle, MyTaskLifecycle.unknown);
      expect(present(status: 'cancelled', deadline: '2026-10-19').border,
          MyTaskBorder.blue, reason: 'only active tasks become Overdue');
    });
  });

  group('visit border', () {
    test('four or more days away is blue', () {
      final p = present(
          status: 'pending', selfScheduled: true, visit: '2026-10-24');
      expect(p.border, MyTaskBorder.blue);
      expect(p.visitDaysUntil, 4);
    });

    test('two or three days away is orange', () {
      expect(
        present(status: 'pending', selfScheduled: true, visit: '2026-10-23')
            .border,
        MyTaskBorder.orange,
      );
      expect(
        present(status: 'pending', selfScheduled: true, visit: '2026-10-22')
            .border,
        MyTaskBorder.orange,
      );
    });

    test('tomorrow and today are red', () {
      expect(
        present(status: 'pending', selfScheduled: true, visit: '2026-10-21')
            .border,
        MyTaskBorder.red,
      );
      expect(
        present(status: 'pending', selfScheduled: true, visit: '2026-10-20')
            .border,
        MyTaskBorder.red,
      );
    });

    test('a missed visit stays red while the deadline is still alive', () {
      final p = present(
          status: 'pending', selfScheduled: true, visit: '2026-10-18');
      expect(p.border, MyTaskBorder.red);
      expect(p.visitMissed, isTrue);
    });

    test('a passed PO deadline is the only full red card', () {
      final p = present(
        status: 'pending',
        selfScheduled: true,
        visit: '2026-10-24',
        deadline: '2026-10-19',
      );
      expect(p.border, MyTaskBorder.fullRed);
      expect(p.deadlineState, MyTaskDeadlineState.passed);
    });

    test('PO Deadline Today keeps the visit border', () {
      final p = present(
        status: 'pending',
        selfScheduled: true,
        visit: '2026-10-24',
        deadline: '2026-10-20',
      );
      expect(p.border, MyTaskBorder.blue);
      expect(p.deadlineState, MyTaskDeadlineState.today);
    });

    test('a plain active task is blue', () {
      expect(present(status: 'in_progress').border, MyTaskBorder.blue);
    });
  });

  group('scheduling window', () {
    for (final malformed in ['2027-02-30', '2026/10/25', '2026-10-25junk', '0000-10-25']) {
      test('malformed date $malformed never creates a scheduling window', () {
        expect(present(deadline: malformed).canSchedule, isFalse);
      });
    }
    test('tomorrow is the earliest visit and the deadline the latest', () {
      final p = present(status: 'assigned', deadline: '2026-10-25');
      expect(p.canSchedule, isTrue);
      expect(p.earliestVisit, DateTime(2026, 10, 21));
      expect(p.latestVisit, DateTime(2026, 10, 25));
    });

    test('a deadline today closes scheduling', () {
      final p = present(status: 'assigned', deadline: '2026-10-20');
      expect(p.canSchedule, isFalse);
      expect(p.earliestVisit, isNull);
      expect(p.latestVisit, isNull);
      expect(p.scheduleBlockReason, contains('today or has passed'));
    });

    test('a deadline in the past closes scheduling', () {
      final p = present(status: 'assigned', deadline: '2026-10-19');
      expect(p.canSchedule, isFalse);
      expect(p.scheduleBlockReason, contains('today or has passed'));
    });

    test('a missing or unreadable deadline closes scheduling', () {
      expect(present(status: 'assigned', deadline: null).canSchedule, isFalse);
      expect(
        present(status: 'assigned', deadline: 'not-a-date').canSchedule,
        isFalse,
      );
    });

    test('a completed or unknown task is never schedulable', () {
      expect(present(status: 'completed').canSchedule, isFalse);
      expect(present(status: 'onprocess').canSchedule, isFalse);
    });

    test('a scheduled task can still be rescheduled while the deadline lives',
        () {
      final p = present(
          status: 'pending', selfScheduled: true, visit: '2026-10-22');
      expect(p.canSchedule, isTrue);
    });
  });

  group('in progress badge', () {
    test('only a scheduled task at steps 1 to 5 shows it', () {
      for (var step = 1; step <= 5; step++) {
        final p = present(
            status: 'pending', selfScheduled: true, visit: '2026-10-24', step: step);
        expect(p.showInProgress, isTrue, reason: 'step $step');
      }
      expect(
        present(
                status: 'pending', selfScheduled: true, visit: '2026-10-24', step: 0)
            .showInProgress,
        isFalse,
      );
      expect(
        present(
                status: 'pending', selfScheduled: true, visit: '2026-10-24', step: 6)
            .showInProgress,
        isFalse,
      );
    });

    test('an ongoing task never shows it', () {
      final p = present(status: 'in_progress', step: 3);
      expect(p.lifecycle, MyTaskLifecycle.ongoing);
      expect(p.showInProgress, isFalse);
    });
  });

  group('computed notices', () {
    test('an inspector Visit beyond the PO deadline is reported, not repaired', () {
      final p = present(selfScheduled: true, visit: '2026-10-26');
      expect(p.visitDay, DateTime(2026, 10, 26));
      expect(p.notices.map(p.noticeText).join(' '), contains('after the PO Deadline'));
    });
    test('upcoming visit days are announced', () {
      final p = present(
          status: 'pending', selfScheduled: true, visit: '2026-10-22');
      expect(p.notices, contains(MyTaskNotice.visitInDays));
      expect(p.noticeText(MyTaskNotice.visitInDays), contains('in 2 days'));
    });

    test('tomorrow and today are announced separately', () {
      expect(
        present(status: 'pending', selfScheduled: true, visit: '2026-10-21')
            .notices,
        contains(MyTaskNotice.visitTomorrow),
      );
      expect(
        present(status: 'pending', selfScheduled: true, visit: '2026-10-20')
            .notices,
        contains(MyTaskNotice.visitToday),
      );
    });

    test('a missed visit is announced only while the deadline is alive', () {
      final missed = present(
          status: 'pending', selfScheduled: true, visit: '2026-10-18');
      expect(missed.notices, contains(MyTaskNotice.visitMissed));
      expect(missed.forReschedule, isTrue,
          reason: 'the deadline is alive, so a new visit may still be chosen');

      final deadlineToday = present(
        status: 'pending',
        selfScheduled: true,
        visit: '2026-10-18',
        deadline: '2026-10-20',
      );
      expect(deadlineToday.notices, isNot(contains(MyTaskNotice.visitMissed)));
      expect(deadlineToday.notices, contains(MyTaskNotice.deadlineToday));
      expect(deadlineToday.forReschedule, isFalse,
          reason: 'on PO Deadline Today the deadline notice replaces the CTA');
    });

    test('the PO deadline is announced on its own, never as a visit', () {
      final p = present(status: 'assigned', deadline: '2026-10-22');
      expect(p.notices, contains(MyTaskNotice.deadlineInDays));
      expect(p.notices, isNot(contains(MyTaskNotice.visitInDays)));
      expect(p.noticeText(MyTaskNotice.deadlineInDays), contains('PO Deadline in 2 days'));
    });

    test('a passed deadline is announced as overdue, once', () {
      final p = present(status: 'assigned', deadline: '2026-10-19');
      expect(p.notices, contains(MyTaskNotice.deadlinePassed));
      expect(p.notices.where((n) => n == MyTaskNotice.deadlinePassed).length, 1);
    });

    test('notices are deduplicated per kind', () {
      final p = present(
          status: 'pending', selfScheduled: true, visit: '2026-10-22');
      final unique = p.notices.toSet();
      expect(p.notices.length, unique.length);
    });
  });
}
