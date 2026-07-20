import 'package:flutter/foundation.dart';
import '../screens/tasks_screen.dart' show TaskItem;

/// One point on the weekly trend bar chart.
@immutable
class TrendPoint {
  final DateTime date;
  final String label; // e.g. "Mon"
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
  final int currentMonth;
  final int currentYear;
  final List<TypeBreakdownEntry> typeBreakdown;

  const InspectorDashboardStats({
    required this.totalAssigned,
    required this.completedCount,
    required this.pendingCount,
    required this.activeWorkloadCount,
    required this.tasksTodayOrPendingCount,
    required this.completionRate,
    required this.weeklyTrend,
    required this.activeDaysThisMonth,
    required this.currentMonth,
    required this.currentYear,
    required this.typeBreakdown,
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
      currentMonth: now.month,
      currentYear: now.year,
      typeBreakdown: const [],
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
    for (final d in submittedDates) {
      if (d.year == today.year && d.month == today.month) {
        activeDays.add(d.day);
      }
    }

    // ── Zoning / application type distribution.
    final typeCounts = <String, int>{};
    for (final t in tasks) {
      final label = (t.applicationType?.trim().isNotEmpty ?? false)
          ? t.applicationType!.trim()
          : (t.landUseClass.trim().isNotEmpty ? t.landUseClass.trim() : 'Unclassified');
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

    return InspectorDashboardStats(
      totalAssigned: total,
      completedCount: completed,
      pendingCount: pending,
      activeWorkloadCount: activeWorkload,
      tasksTodayOrPendingCount: tasksTodayOrPending,
      completionRate: completionRate,
      weeklyTrend: weeklyTrend,
      activeDaysThisMonth: activeDays,
      currentMonth: today.month,
      currentYear: today.year,
      typeBreakdown: typeBreakdown,
    );
  }
}
