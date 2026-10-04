import 'package:flutter/foundation.dart';
import 'dashboard_stats.dart';

/// Which period the Profile analytics calendar describes.
enum AnalyticsRange {
  /// The calendar week (Monday–Sunday) containing today.
  week,

  /// The current calendar month, drawn as a Monday-first month grid.
  month,
}

/// Range-scoped results for the tabs that follow the selector.
@immutable
class AnalyticsRangeMetrics {
  /// Completed ÷ scheduled-cohort size, or **null** when nothing in the period
  /// is scheduled. Null is deliberately distinct from 0.0: "no scheduled work
  /// this period" is not the same claim as "scheduled work, none finished".
  final double? scheduledCompletionRate;
  final int scheduledCohortCount;
  final int scheduledCompletedCount;

  /// Tasks still open inside the scheduled cohort.
  final int scheduledOpenCount;

  const AnalyticsRangeMetrics({
    required this.scheduledCompletionRate,
    required this.scheduledCohortCount,
    required this.scheduledCompletedCount,
    required this.scheduledOpenCount,
  });
}

/// The exact set of days an Activity calendar displays, and which of them had
/// at least one submitted inspection.
///
/// This is pure date arithmetic with no I/O, so every range/day-count/grid
/// question is answerable without a widget tree.
///
/// SEMANTICS — product contract, confirmed by HEAD:
///  * Week  = the calendar week (Monday–Sunday) containing today.
///  * Month = the current calendar month.
///
/// The Monday-first basis is not a guess: the existing heatmap derived its
/// leading blanks from `DateTime(year, month, 1).weekday` (1 = Monday) under an
/// `M T W T F S S` header, so Monday is the app's established first weekday.
@immutable
class AnalyticsActivityRange {
  final AnalyticsRange range;

  /// Every day in the range, oldest first. Length is the denominator.
  final List<DateTime> days;

  /// The subset of [days] on which at least one inspection was submitted.
  final Set<DateTime> activeDays;

  /// Which weekday this range starts on, 1 = Monday.
  final int firstWeekday;

  const AnalyticsActivityRange._({
    required this.range,
    required this.days,
    required this.activeDays,
    required this.firstWeekday,
  });

  /// The Monday–Sunday calendar week containing [now]. Denominator is always 7.
  factory AnalyticsActivityRange.week(DateTime now, Set<DateTime> activeDays) {
    final today = DateTime(now.year, now.month, now.day);
    // DateTime.weekday is 1 = Monday .. 7 = Sunday.
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final days = <DateTime>[
      for (int i = 0; i < 7; i++) monday.add(Duration(days: i)),
    ];
    return AnalyticsActivityRange._(
      range: AnalyticsRange.week,
      days: List.unmodifiable(days),
      activeDays: _restricted(activeDays, days),
      firstWeekday: 1,
    );
  }

  /// Current calendar month of [year]/[month]. Denominator is the real day
  /// count, so February is 28 (or 29 in a leap year) and other months 30/31.
  factory AnalyticsActivityRange.month(
    int year,
    int month,
    Set<DateTime> activeDays,
  ) {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final days = <DateTime>[
      for (int d = 1; d <= daysInMonth; d++) DateTime(year, month, d),
    ];
    return AnalyticsActivityRange._(
      range: AnalyticsRange.month,
      days: List.unmodifiable(days),
      activeDays: _restricted(activeDays, days),
      firstWeekday: DateTime(year, month, 1).weekday,
    );
  }

  /// Builds whichever range the selector is currently on.
  factory AnalyticsActivityRange.selected({
    required AnalyticsRange range,
    required DateTime now,
    required Set<DateTime> activeDays,
  }) => range == AnalyticsRange.week
      ? AnalyticsActivityRange.week(now, activeDays)
      : AnalyticsActivityRange.month(now.year, now.month, activeDays);

  static Set<DateTime> _restricted(Set<DateTime> all, List<DateTime> days) =>
      days.where(all.contains).toSet();

  /// Number of days displayed — the denominator of "X of N days completed".
  int get dayCount => days.length;

  int get completedCount => activeDays.length;

  int get percentage =>
      dayCount == 0 ? 0 : ((completedCount / dayCount) * 100).round();

  /// Consecutive completed days ending today, counting back within the range.
  ///
  /// Counts back from **today's own position**, not from the end of the range:
  /// a week or month contains future days, and those must not zero out a streak
  /// the inspector has actually earned. Zero when today is not in the range
  /// (e.g. a past month).
  int currentStreak(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final index = days.lastIndexWhere((d) => d == today);
    if (index < 0) return 0;
    var streak = 0;
    for (int i = index; i >= 0; i--) {
      if (!activeDays.contains(days[i])) break;
      streak++;
    }
    return streak;
  }

  /// Empty leading cells so day 1 lands under the correct weekday column.
  int get leadingBlanks => range == AnalyticsRange.month ? firstWeekday - 1 : 0;

  /// Total grid cells, including leading blanks.
  int get cellCount => leadingBlanks + days.length;

  /// How many rows the month grid needs. Always 1 for the 7-day week strip.
  /// A month needs 4, 5 or 6 depending on where it starts.
  ///
  /// `ceil(cells / 7)` — deliberately NOT `(cells + 6) / 7` rounded up, which
  /// reserves a phantom extra row for any month whose cell count is not a
  /// multiple of 7 (34 cells became 6 rows instead of 5).
  int get calendarWeeks =>
      range == AnalyticsRange.week ? 1 : (cellCount / 7).ceil();

  /// True when [date] is inside this range — used to decide whether the
  /// "today" outline may be drawn at all.
  bool contains(DateTime date) => days.contains(date);

  bool isActive(DateTime date) => activeDays.contains(date);

  /// GAUGE — scheduled-cohort completion rate for this range.
  ///
  /// Numerator: tasks whose `scheduled_date` falls in THIS range AND which are
  /// Completed. Completions scheduled outside the range are deliberately not
  /// counted, and tasks with no `scheduled_date` never appear at all.
  ///
  /// Returns a null rate when the cohort is empty, so the UI can show an
  /// honest "no scheduled tasks" state instead of a misleading 0%.
  AnalyticsRangeMetrics metricsFor(List<ScheduledCohortTask> cohort) {
    final inRange = cohort.where((t) => contains(t.scheduledDate)).toList();
    final done = inRange.where((t) => t.isCompleted).length;
    return AnalyticsRangeMetrics(
      scheduledCompletionRate: inRange.isEmpty ? null : done / inRange.length,
      scheduledCohortCount: inRange.length,
      scheduledCompletedCount: done,
      scheduledOpenCount: inRange.length - done,
    );
  }
}
