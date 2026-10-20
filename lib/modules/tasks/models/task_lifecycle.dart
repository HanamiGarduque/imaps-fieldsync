import 'package:flutter/foundation.dart';
import '../../../core/utils/calendar_date.dart';

/// Canonical My Tasks presentation model.
///
/// One place decides, for every assignment:
///   * which section it belongs to (Scheduled / Available Anytime / Ongoing /
///     Completed),
///   * how urgent its committed Visit date is (the card border),
///   * whether the Planning Officer's deadline still allows a visit, and
///   * which computed in-app notices the inspector should see.
///
/// Everything is a pure function of the stored facts plus a supplied "today",
/// so the same rules can be unit tested and reused by My Tasks, the Home
/// dashboard, the calendar, the carousel, the filters and the analytics.
///
/// Contract: MY_TASKS_FINAL_FLOW_SPEC_20261020 §1–§5.

/// Which section an assignment belongs to.
enum MyTaskLifecycle {
  completed,
  scheduled,
  ongoing,
  availableAnytime,

  /// A status the app does not recognize. It stays out of the normal sections
  /// and is never coerced into one.
  unknown,
}

/// Card border treatment.
enum MyTaskBorder { blue, orange, red, fullRed, green }

/// State of the Planning Officer's deadline.
enum MyTaskDeadlineState {
  /// No deadline is stored.
  none,

  /// A deadline exists but is further out than the reminder window.
  later,

  /// The deadline is 1–3 days away.
  upcoming,

  /// The deadline is today: no further visit may be scheduled.
  today,

  /// The deadline has passed: the card is fully red.
  passed,

  /// A deadline value exists but cannot be read as a date.
  unknown,
}

/// A computed in-app notice. Visit notices and deadline notices are separate
/// kinds so one is never read as the other.
enum MyTaskNotice {
  visitInDays,
  visitTomorrow,
  visitToday,
  visitMissed,
  deadlineInDays,
  deadlineToday,
  deadlinePassed,
  scheduleConflict,
}

/// The stored facts a presentation is derived from.
@immutable
class MyTaskFacts {
  /// `field_jobs.status` — the raw lifecycle. It does not decide Scheduled vs
  /// Ongoing on its own.
  final String? status;

  /// `field_jobs.is_self_scheduled` — the committed-visit flag. True is the
  /// only evidence that the inspector chose the Visit date.
  final bool isSelfScheduled;

  /// `field_jobs.scheduled_date` — the Visit date when the flag is true; a
  /// PO-supplied placeholder otherwise.
  final String? visitDate;

  /// `field_jobs.deadline_date` — the Planning Officer's deadline.
  final String? deadlineDate;

  /// `field_jobs.current_step`.
  final int currentStep;
  final bool hasStarted;

  const MyTaskFacts({
    required this.status,
    required this.isSelfScheduled,
    this.visitDate,
    this.deadlineDate,
    this.currentStep = 0,
    this.hasStarted = false,
  });
}

/// The derived presentation of one assignment.
@immutable
class MyTaskPresentation {
  final MyTaskLifecycle lifecycle;
  final MyTaskBorder border;
  final MyTaskDeadlineState deadlineState;

  /// The committed Visit day, or null when there is none.
  final DateTime? visitDay;

  /// The PO deadline day, or null when there is none or it cannot be read.
  final DateTime? deadlineDay;

  /// Days from today to the Visit day (negative once it has passed).
  final int? visitDaysUntil;

  /// Days from today to the deadline (negative once it has passed).
  final int? deadlineDaysUntil;

  /// The Visit date has passed while the deadline is still in the future.
  final bool visitMissed;

  /// The missed visit is still actionable: the PO deadline is alive, so the
  /// inspector may pick a new visit date. It is false on PO Deadline Today
  /// and after, where the deadline notice replaces the reschedule call to
  /// action.
  final bool forReschedule;

  /// Scheduled tasks at steps 1–5 only.
  final bool showInProgress;

  /// Whether a new visit may still be scheduled or rescheduled.
  final bool canSchedule;

  /// Why scheduling is closed, in the inspector's language.
  final String? scheduleBlockReason;

  /// The earliest selectable Visit day (tomorrow) and the latest one (the PO
  /// deadline). Both are null while scheduling is closed.
  final DateTime? earliestVisit;
  final DateTime? latestVisit;

  /// The computed notices for this task, deduplicated by kind.
  final List<MyTaskNotice> notices;

  bool get isActive => lifecycle == MyTaskLifecycle.scheduled ||
      lifecycle == MyTaskLifecycle.ongoing ||
      lifecycle == MyTaskLifecycle.availableAnytime;

  bool get isOverdue => isActive && deadlineState == MyTaskDeadlineState.passed;

  bool get isDueToday => isActive && !isOverdue &&
      (lifecycle == MyTaskLifecycle.scheduled
          ? visitDaysUntil == 0 : deadlineDaysUntil == 0);

  /// Urgent is pre-deadline Visit urgency (including a missed Visit) or the
  /// PO's 0–3 day reminder window. Overdue is a separate, disjoint filter.
  bool get isUrgent => isActive && !isOverdue &&
      ((lifecycle == MyTaskLifecycle.scheduled &&
          visitDaysUntil != null && visitDaysUntil! <= 3) ||
       (deadlineDaysUntil != null && deadlineDaysUntil! >= 0 && deadlineDaysUntil! <= 3));

  DateTime? get activeDay => !isActive ? null :
      lifecycle == MyTaskLifecycle.scheduled ? visitDay : deadlineDay;

  const MyTaskPresentation({
    required this.lifecycle,
    required this.border,
    required this.deadlineState,
    required this.visitMissed,
    required this.forReschedule,
    required this.showInProgress,
    required this.canSchedule,
    required this.scheduleBlockReason,
    required this.earliestVisit,
    required this.latestVisit,
    required this.notices,
    this.visitDay,
    this.deadlineDay,
    this.visitDaysUntil,
    this.deadlineDaysUntil,
  });

  /// Derives the presentation of [facts] as seen on [today] (a local calendar
  /// day).
  factory MyTaskPresentation.of(MyTaskFacts facts, DateTime today) {
    final day = DateTime(today.year, today.month, today.day);
    final lifecycle = lifecycleFor(facts);
    final visit = parseLocalCalendarDate(facts.visitDate);
    final deadline = parseLocalCalendarDate(facts.deadlineDate);
    final visitDiff = visit == null ? null : calendarDaysBetween(day, visit);
    final deadlineDiff = deadline == null ? null : calendarDaysBetween(day, deadline);

    final deadlineState = _deadlineState(facts.deadlineDate, deadlineDiff);
    final isActive = lifecycle == MyTaskLifecycle.scheduled ||
        lifecycle == MyTaskLifecycle.ongoing ||
        lifecycle == MyTaskLifecycle.availableAnytime;

    // Completed wins, then an active PO deadline that has passed (full red),
    // then the Visit urgency of a scheduled task.
    final MyTaskBorder border;
    if (lifecycle == MyTaskLifecycle.completed) {
      border = MyTaskBorder.green;
    } else if (isActive && deadlineState == MyTaskDeadlineState.passed) {
      border = MyTaskBorder.fullRed;
    } else if (lifecycle == MyTaskLifecycle.scheduled && visitDiff != null) {
      if (visitDiff < 0 || visitDiff <= 1) {
        border = MyTaskBorder.red;
      } else if (visitDiff <= 3) {
        border = MyTaskBorder.orange;
      } else {
        border = MyTaskBorder.blue;
      }
    } else {
      border = MyTaskBorder.blue;
    }

    final visitMissed = lifecycle == MyTaskLifecycle.scheduled &&
        visitDiff != null &&
        visitDiff < 0;

    // The deadline decides whether a visit may still be committed.
    final bool canSchedule =
        isActive && deadline != null && deadline.isAfter(day);
    String? blockReason;
    if (!canSchedule) {
      if (lifecycle == MyTaskLifecycle.completed) {
        blockReason = 'This inspection is already completed.';
      } else if (lifecycle == MyTaskLifecycle.unknown) {
        blockReason =
            'This task cannot be scheduled because its status is not recognized.';
      } else if (deadline == null) {
        blockReason =
            'The PO deadline could not be verified, so scheduling is unavailable. '
            'Continue your inspection or ask the Planning Office to confirm it.';
      } else {
        blockReason =
            'The PO deadline is today or has passed. You cannot schedule another '
            'visit. Continue your inspection or coordinate with the Planning Officer.';
      }
    }

    final notices = <MyTaskNotice>[];
    if (lifecycle == MyTaskLifecycle.scheduled && visitDiff != null &&
        deadlineState != MyTaskDeadlineState.passed) {
      if (visitDiff < 0) {
        if (deadlineState == MyTaskDeadlineState.later ||
            deadlineState == MyTaskDeadlineState.upcoming) {
          notices.add(MyTaskNotice.visitMissed);
        }
      } else if (visitDiff == 0) {
        notices.add(MyTaskNotice.visitToday);
      } else if (visitDiff == 1) {
        notices.add(MyTaskNotice.visitTomorrow);
      } else if (visitDiff <= 3) {
        notices.add(MyTaskNotice.visitInDays);
      }
    }
    if (isActive) {
      if (deadlineState == MyTaskDeadlineState.passed) {
        notices.add(MyTaskNotice.deadlinePassed);
      } else if (deadlineState == MyTaskDeadlineState.today) {
        notices.add(MyTaskNotice.deadlineToday);
      } else if (deadlineState == MyTaskDeadlineState.upcoming) {
        notices.add(MyTaskNotice.deadlineInDays);
      }
    }
    if (lifecycle == MyTaskLifecycle.scheduled && visit != null &&
        deadline != null && visit.isAfter(deadline)) {
      notices.add(MyTaskNotice.scheduleConflict);
    }

    return MyTaskPresentation(
      lifecycle: lifecycle,
      border: border,
      deadlineState: deadlineState,
      visitDay: visit,
      deadlineDay: deadline,
      visitDaysUntil: visitDiff,
      deadlineDaysUntil: deadlineDiff,
      visitMissed: visitMissed,
      forReschedule: visitMissed &&
          (deadlineState == MyTaskDeadlineState.later ||
              deadlineState == MyTaskDeadlineState.upcoming),
      showInProgress: lifecycle == MyTaskLifecycle.scheduled &&
          facts.currentStep >= 1 &&
          facts.currentStep <= 5,
      canSchedule: canSchedule,
      scheduleBlockReason: blockReason,
      earliestVisit: canSchedule ? DateTime(day.year, day.month, day.day + 1) : null,
      latestVisit: canSchedule ? deadline : null,
      notices: List.unmodifiable(notices),
    );
  }

  /// The text of a computed notice. Visit and deadline notices are worded
  /// separately so they can never be mistaken for one another.
  String noticeText(MyTaskNotice notice) => switch (notice) {
        MyTaskNotice.visitInDays =>
          'Scheduled visit in $visitDaysUntil days — prepare your site inspection.',
        MyTaskNotice.visitTomorrow => 'Scheduled visit tomorrow.',
        MyTaskNotice.visitToday =>
          'Scheduled visit today — proceed with the inspection.',
        MyTaskNotice.visitMissed =>
          'You missed your Visit date. Reschedule before the PO Deadline or '
              'continue the inspection.',
        MyTaskNotice.deadlineInDays =>
          'PO Deadline in $deadlineDaysUntil ${deadlineDaysUntil == 1 ? 'day' : 'days'}.',
        MyTaskNotice.deadlineToday =>
          'PO Deadline today. Rescheduling is unavailable; complete your inspection.',
        MyTaskNotice.deadlinePassed =>
          'Overdue — the PO deadline has passed.',
        MyTaskNotice.scheduleConflict =>
          'Your Visit date is after the PO Deadline. Coordinate with the Planning Officer; '
              'choose a valid Visit only while scheduling is available.',
      };

  /// A short label of the date a row refers to, so a Visit date is never shown
  /// as a deadline and the other way round.
  static String visitDateLabel() => 'Visit date';
  static String deadlineDateLabel() => 'PO Deadline';

  static MyTaskLifecycle lifecycleFor(MyTaskFacts facts) {
    final status = facts.status;
    if (status == null) return MyTaskLifecycle.unknown;
    switch (status) {
      case 'completed':
      case 'Completed':
      case 'submitted':
        return MyTaskLifecycle.completed;
      case 'assigned':
      case 'Pending':
      case 'pending':
        return facts.isSelfScheduled
            ? MyTaskLifecycle.scheduled
            : facts.currentStep > 0 || facts.hasStarted
                ? MyTaskLifecycle.ongoing
                : MyTaskLifecycle.availableAnytime;
      case 'in_progress':
      case 'in-progress':
      case 'ongoing':
        return facts.isSelfScheduled
            ? MyTaskLifecycle.scheduled
            : MyTaskLifecycle.ongoing;
      default:
        return MyTaskLifecycle.unknown;
    }
  }

  static MyTaskDeadlineState _deadlineState(
    String? raw,
    int? daysUntil,
  ) {
    if (raw == null || raw.isEmpty) return MyTaskDeadlineState.none;
    if (daysUntil == null) return MyTaskDeadlineState.unknown;
    if (daysUntil < 0) return MyTaskDeadlineState.passed;
    if (daysUntil == 0) return MyTaskDeadlineState.today;
    if (daysUntil <= 3) return MyTaskDeadlineState.upcoming;
    return MyTaskDeadlineState.later;
  }

}
