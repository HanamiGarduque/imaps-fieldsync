import 'package:flutter/foundation.dart';
import '../../tasks/screens/tasks_screen.dart' show TaskItem;
import '../../../core/utils/calendar_date.dart';

/// One daily (Week) or weekly (Month) submission bar.
@immutable
class TrendPoint {
  final DateTime date;
  final String label; // e.g. "Mon" or "1st week"
  final int count;
  const TrendPoint({required this.date, required this.label, required this.count});
}

/// One row on the zoning-type breakdown card.
@immutable
class TypeBreakdownEntry {
  final String label;
  final int count;
  final double share; // 0.0 - 1.0 of total
  const TypeBreakdownEntry({required this.label, required this.count, required this.share});
}

/// The existing zoning label for a task: application type when present, else
/// declared land use, else "Unclassified". Shared by the lifetime breakdown and
/// the range-scoped one so both speak the same vocabulary.
String _zoningLabel(TaskItem t) =>
    (t.applicationType?.trim().isNotEmpty ?? false)
        ? t.applicationType!.trim()
        : (t.landUseClass.trim().isNotEmpty
            ? t.landUseClass.trim()
            : 'Unclassified');

/// A completed inspection with the day it was submitted and the zoning label it
/// already carries. Produced once during aggregation so the Sectors tab never
/// has to re-parse timestamps or invent a label.
@immutable
class CompletedTaskDay {
  final DateTime date;
  final String label;

  const CompletedTaskDay({required this.date, required this.label});
}

/// An inspector-committed Visit in the Gauge cohort. Missing/invalid dates and
/// PO placeholders are excluded from both numerator and denominator.
@immutable
class ScheduledCohortTask {
  final String id;
  final DateTime scheduledDate;
  final bool isCompleted;

  const ScheduledCohortTask({
    required this.id,
    required this.scheduledDate,
    required this.isCompleted,
  });
}

/// All numbers the Profile analytics dashboard needs, derived once from the
/// inspector's own job list (already scoped server-side to
/// assigned_inspector_id by SupabaseService.fetchMyJobs()). Keeping this as
/// a plain, synchronous data class means the widgets underneath never touch
/// Supabase directly and just render whatever this holds.
@immutable
class InspectorDashboardStats {
  final int totalAssigned;
  final int completedCount;
  final int pendingCount; // category == 'Pending'
  final int activeWorkloadCount; // Pending + Scheduled + Ongoing (not yet Completed)
  final int tasksTodayOrPendingCount; // Card 1
  final double completionRate; // 0.0 - 1.0, completed / totalAssigned
  final List<TrendPoint> weeklyTrend; // last 7 days, oldest -> newest
  final Set<int> activeDaysThisMonth; // day-of-month numbers with a submission
  /// Every calendar day that had at least one submission. The lossless form of
  /// [activeDaysThisMonth], so a weekly range is derived from the same
  /// authoritative set rather than a second, separately-computed one.
  final Set<DateTime> activeSubmissionDates;

  /// Every submission date, **with duplicates** — two inspections finished on
  /// the same day must count as two submissions on the Bars chart, not one.
  /// [activeSubmissionDates] is the de-duplicated form used by the heatmap.
  final List<DateTime> submissionDates;
  final int currentMonth;
  final int currentYear;
  final List<TypeBreakdownEntry> typeBreakdown;

  /// Recognized inspector-committed Visits (including Completed). PO-supplied
  /// placeholders are never evidence that the inspector chose a Visit.
  final List<ScheduledCohortTask> scheduledCohort;

  /// Completed tasks paired with their real submission day and their existing
  /// zoning label. Consumed by [completedTypeBreakdownFor].
  final List<CompletedTaskDay> completedTasksWithDate;

  const InspectorDashboardStats({
    required this.totalAssigned,
    required this.completedCount,
    required this.pendingCount,
    required this.activeWorkloadCount,
    required this.tasksTodayOrPendingCount,
    required this.completionRate,
    required this.weeklyTrend,
    required this.activeDaysThisMonth,
    required this.activeSubmissionDates,
    required this.submissionDates,
    required this.currentMonth,
    required this.currentYear,
    required this.typeBreakdown,
    required this.scheduledCohort,
    required this.completedTasksWithDate,
  });

  factory InspectorDashboardStats.empty() {
    final now = DateTime.now();
    return InspectorDashboardStats(
      totalAssigned: 0,
      completedCount: 0,
      pendingCount: 0,
      activeWorkloadCount: 0,
      tasksTodayOrPendingCount: 0,
      completionRate: 0,
      weeklyTrend: const [],
      activeDaysThisMonth: const {},
      activeSubmissionDates: const {},
      submissionDates: const [],
      currentMonth: now.month,
      currentYear: now.year,
      typeBreakdown: const [],
      scheduledCohort: const [],
      completedTasksWithDate: const [],
    );
  }

  /// Pure, synchronous aggregation over a list of TaskItem — no I/O here,
  /// so calling this from setState() never blocks or jank the UI thread;
  /// the only actual async work already happened in fetchMyJobs().
  factory InspectorDashboardStats.fromTasks(List<TaskItem> tasks) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final total = tasks.length;
    final completed = tasks.where((t) => t.category == 'Completed').length;
    final pending = tasks.where((t) => t.category == 'Pending').length;
    final activeWorkload = tasks.where((t) => t.category != 'Completed').length;

    final tasksTodayOrPending = tasks.where((t) {
      return t.category == 'Pending' || t.category == 'Ongoing';
    }).length;

    final completionRate = total == 0 ? 0.0 : completed / total;

    // ── Weekly trend: last 7 days (oldest -> newest), counting jobs whose
    // submitted_at falls on that calendar day.
    const dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final submittedDates = <DateTime>[];
    for (final t in tasks) {
      if (t.submittedAt == null || t.submittedAt!.isEmpty) continue;
      try {
        final d = DateTime.parse(t.submittedAt!).toLocal();
        submittedDates.add(DateTime(d.year, d.month, d.day));
      } catch (_) {}
    }

    final weeklyTrend = <TrendPoint>[];
    for (int i = 6; i >= 0; i--) {
      final day = today.subtract(Duration(days: i));
      final count = submittedDates.where((d) => d == day).length;
      weeklyTrend.add(TrendPoint(date: day, label: dayLabels[day.weekday - 1], count: count));
    }

    // ── Activity heatmap: which days *this month* had a submission.
    final activeDays = <int>{};
    // Same submission days, kept as real dates so both the month heatmap and a
    // weekly range come from one authoritative set.
    final activeDates = <DateTime>{};
    for (final d in submittedDates) {
      if (d.year == today.year && d.month == today.month) {
        activeDays.add(d.day);
      }
      activeDates.add(d);
    }

    // ── Zoning / application type distribution.
    final typeCounts = <String, int>{};
    for (final t in tasks) {
      final label = _zoningLabel(t);
      typeCounts[label] = (typeCounts[label] ?? 0) + 1;
    }
    final typeTotal = typeCounts.values.fold<int>(0, (a, b) => a + b);
    final typeBreakdown = typeCounts.entries
        .map((e) => TypeBreakdownEntry(
              label: e.key,
              count: e.value,
              share: typeTotal == 0 ? 0 : e.value / typeTotal,
            ))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));

    // Only a recognized task with an inspector-committed Visit joins the cohort.
    final cohort = <ScheduledCohortTask>[];
    for (final t in tasks) {
      if (!t.isSelfScheduled || t.category == 'Unknown') continue;
      final parsed = parseLocalCalendarDate(t.scheduledDate);
      if (parsed == null) continue;
      cohort.add(ScheduledCohortTask(
        id: t.id,
        scheduledDate: DateTime(parsed.year, parsed.month, parsed.day),
        isCompleted: t.category == 'Completed',
      ));
    }

    // ── Completed tasks with their submission day and zoning label, so the
    // Sectors tab can filter by period without re-parsing anything.
    final completedTasks = <CompletedTaskDay>[];
    for (final t in tasks) {
      if (t.category != 'Completed') continue;
      if (t.submittedAt == null || t.submittedAt!.isEmpty) continue;
      DateTime d;
      try {
        d = DateTime.parse(t.submittedAt!).toLocal();
      } catch (_) {
        continue;
      }
      completedTasks.add(CompletedTaskDay(
        date: DateTime(d.year, d.month, d.day),
        label: _zoningLabel(t),
      ));
    }

    return InspectorDashboardStats(
      totalAssigned: total,
      completedCount: completed,
      pendingCount: pending,
      activeWorkloadCount: activeWorkload,
      tasksTodayOrPendingCount: tasksTodayOrPending,
      completionRate: completionRate,
      weeklyTrend: weeklyTrend,
      activeDaysThisMonth: activeDays,
      activeSubmissionDates: activeDates,
      submissionDates: List.unmodifiable(submittedDates),
      currentMonth: today.month,
      currentYear: today.year,
      typeBreakdown: typeBreakdown,
      scheduledCohort: cohort,
      completedTasksWithDate: completedTasks,
    );
  }

  /// SECTORS — zoning/application-type distribution restricted to inspections
  /// actually COMPLETED inside [days].
  ///
  /// Pending/Ongoing work is excluded: this is a distribution of output, not of
  /// workload. Scheduling plays no part here — completion date decides. Uses the
  /// exact same label vocabulary as the lifetime breakdown, so no new zoning
  /// classification is ever introduced.
  List<TypeBreakdownEntry> completedTypeBreakdownFor(List<DateTime> days) {
    final inRange = days.toSet();
    final counts = <String, int>{};
    for (final t in completedTasksWithDate) {
      if (!inRange.contains(t.date)) continue;
      counts[t.label] = (counts[t.label] ?? 0) + 1;
    }
    if (counts.isEmpty) return const [];
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    return counts.entries
        .map((e) => TypeBreakdownEntry(
              label: e.key,
              count: e.value,
              share: e.value / total,
            ))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
  }

  /// Selected calendar Week: seven daily bars. Selected calendar Month: totals
  /// for days 1–7, 8–14, 15–21, 22–28 and, when present, 29–month end.
  /// Membership uses the exact range dates, counting every submission once.
  List<TrendPoint> submissionTrendFor(List<DateTime> days) {
    const dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const weekLabels = ['1st week', '2nd week', '3rd week', '4th week', '5th week'];
    // ponytail: callers supply a 7-day week or a full 28–31-day month;
    // use an explicit range if custom periods are introduced.
    final daysPerBar = days.length > 7 ? 7 : 1;
    final points = <TrendPoint>[];
    for (var index = 0; index < days.length; index += daysPerBar) {
      final bucket = days.skip(index).take(daysPerBar).toSet();
      points.add(TrendPoint(
        date: days[index],
        label: daysPerBar == 1
            ? dayLabels[days[index].weekday - 1]
            : weekLabels[index ~/ 7],
        count: submissionDates.where(bucket.contains).length,
      ));
    }
    return points;
  }
}
