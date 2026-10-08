// Performance Analytics — Week/Month range + Activity calendar.
//
// Two defects are guarded here:
//
//  1. The Week/Month pills toggled `_analyticsIsWeek` but NOTHING read it, so
//     the calendar always rendered the current MONTH regardless of selection.
//  2. The calendar wrapper assumed a hardcoded 24px cell, while the grid's
//     aspect-ratio delegate renders square cells derived from the real width.
//     On wider phones the wrapper was shorter than the grid, clipping the last
//     calendar row.
//
// Range semantics are locked to existing app evidence, not invented here:
//   Week  = current Monday–Sunday calendar week, with daily Bars.
//   Month = the current calendar month, Monday-first grid.
//           Bars group days 1–7, 8–14, 15–21, 22–28 and 29–month end.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/modules/profile_settings/models/analytics_activity_range.dart';
import 'package:imaps_fieldsync/modules/profile_settings/models/dashboard_stats.dart';
import 'package:imaps_fieldsync/modules/profile_settings/widgets/dashboard_widgets.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

// Real calendar facts (verified):
//   Feb 2028 = 29 days, starts Tuesday   -> 1 leading blank, 5 rows
//   Feb 2026 = 28 days, starts Sunday    -> 6 leading blanks, 5 rows
//   Aug 2026 = 31 days, starts Saturday  -> 5 leading blanks, 6 ROWS (the clip case)
//   Jun 2026 = 30 days, starts Monday    -> 0 leading blanks, 5 rows
//   Feb 2027 = 28 days, starts Monday    -> 0 leading blanks, 4 rows
final febLeap = AnalyticsActivityRange.month(2028, 2, const {});
final febNormal = AnalyticsActivityRange.month(2026, 2, const {});
final april30 = AnalyticsActivityRange.month(2026, 4, const {});
final jan31 = AnalyticsActivityRange.month(2026, 1, const {});
final aug2026 = AnalyticsActivityRange.month(2026, 8, const {});
final may2026 = AnalyticsActivityRange.month(2026, 5, const {});
final june2026 = AnalyticsActivityRange.month(2026, 6, const {});
final feb2027 = AnalyticsActivityRange.month(2027, 2, const {});

/// Minimal TaskItem fixture. Only the fields the analytics aggregation reads
/// are populated; everything else keeps its model default.
TaskItem _task(
  String id, {
  String status = 'completed',
  String? submittedAt,
  String? scheduledDate,
  String? type,
  String landUse = '',
}) => TaskItem.fromJob({
  'id': id,
  'status': status,
  'submitted_at': submittedAt,
  'scheduled_date': scheduledDate,
  'supabase_zoning_applications': {
    'applicant_name': 'Applicant $id',
    'barangay': 'Mavalor',
    'reference_number': 'REF-$id',
    'application_type': type,
  },
  'supabase_parcels': {'land_use_class': landUse},
});

void main() {
  group('week range semantics (Monday-Sunday calendar week)', () {
    final now = DateTime(2026, 10, 3); // Saturday
    final range = AnalyticsActivityRange.week(now, const {});

    test('denominator is exactly 7, Monday first, containing today', () {
      expect(range.range, AnalyticsRange.week);
      expect(range.dayCount, 7);
      expect(range.days.first, DateTime(2026, 9, 28)); // Monday
      expect(range.days.last, DateTime(2026, 10, 4)); // Sunday
      expect(range.contains(now), isTrue, reason: 'today is inside its week');
      expect(range.days.first.weekday, 1, reason: 'Monday');
      expect(range.days.last.weekday, 7, reason: 'Sunday');
      for (var i = 1; i < range.days.length; i++) {
        expect(range.days[i].difference(range.days[i - 1]).inDays, 1);
      }
      expect(range.days.toSet(), hasLength(7));
    });

    test('a week strip never reserves monthly-grid height', () {
      expect(range.leadingBlanks, 0);
      expect(range.calendarWeeks, 1);
      expect(range.cellCount, 7);
    });

    test('every weekday maps to the same calendar week', () {
      final mon = AnalyticsActivityRange.week(DateTime(2026, 9, 28), const {});
      final sun = AnalyticsActivityRange.week(DateTime(2026, 10, 4), const {});
      expect(mon.days, sun.days);
      final wed = AnalyticsActivityRange.week(DateTime(2026, 9, 30), const {});
      expect(wed.days.first, DateTime(2026, 9, 28));
    });

    test('week crossing a month boundary keeps all 7 distinct dates', () {
      // Mon 2026-02-23: week runs Feb 23 .. Mar 1, crossing the boundary.
      final cross = AnalyticsActivityRange.week(
        DateTime(2026, 2, 23),
        const {},
      );
      expect(cross.days.first, DateTime(2026, 2, 23));
      expect(cross.days.last, DateTime(2026, 3, 1));
      expect(cross.days.toSet(), hasLength(7));
      expect(cross.days.where((d) => d.month == 2), hasLength(6));
      expect(cross.days.where((d) => d.month == 3), hasLength(1));
    });

    test('week crossing a year boundary keeps all 7 distinct dates', () {
      // Mon 2025-12-29: week runs Dec 29 2025 .. Jan 4 2026.
      final cross = AnalyticsActivityRange.week(
        DateTime(2025, 12, 29),
        const {},
      );
      expect(cross.days.first, DateTime(2025, 12, 29));
      expect(cross.days.last, DateTime(2026, 1, 4));
      expect(cross.days.toSet(), hasLength(7));
      expect(cross.days.where((d) => d.year == 2025), hasLength(3));
      expect(cross.days.where((d) => d.year == 2026), hasLength(4));
    });

    test('completed count only counts days inside the week', () {
      final active = {
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 3),
        DateTime(2026, 9, 20), // outside the 7-day window
      };
      final r = AnalyticsActivityRange.week(DateTime(2026, 10, 3), active);
      expect(r.completedCount, 2);
      expect(r.percentage, 29); // 2/7
    });

    test('streak counts back from today only while completed', () {
      final now = DateTime(2026, 10, 3);
      final r = AnalyticsActivityRange.week(now, {
        DateTime(2026, 10, 3),
        DateTime(2026, 10, 2),
        DateTime(2026, 10, 1),
      });
      expect(r.currentStreak(now), 3);

      // Today NOT completed breaks the streak at zero.
      final r2 = AnalyticsActivityRange.week(now, {
        DateTime(2026, 10, 2),
        DateTime(2026, 10, 1),
      });
      expect(r2.currentStreak(now), 0);
    });

    test('future days in the range do not zero an earned streak', () {
      // Sat 2026-10-03 with Thu..Sat completed. Sunday Oct 4 is still in the
      // week and is NOT completed — the streak must survive it.
      final now = DateTime(2026, 10, 3);
      final r = AnalyticsActivityRange.week(now, {
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 2),
        DateTime(2026, 10, 3),
      });
      expect(r.days.last, DateTime(2026, 10, 4));
      expect(r.currentStreak(now), 3);
    });

    test('month streak ignores the remaining future days of the month', () {
      final now = DateTime(2026, 10, 3);
      final r = AnalyticsActivityRange.month(2026, 10, {
        DateTime(2026, 10, 2),
        DateTime(2026, 10, 3),
      });
      expect(r.days.length, 31);
      expect(r.currentStreak(now), 2);
    });
  });

  group('month range semantics (calendar month, Monday-first)', () {
    test('denominator equals the real day count of the month', () {
      expect(febLeap.dayCount, 29); // 2028 is a leap year
      expect(febNormal.dayCount, 28); // 2026 is not
      expect(april30.dayCount, 30);
      expect(jan31.dayCount, 31);
      expect(aug2026.dayCount, 31);
      expect(may2026.dayCount, 31);
      expect(june2026.dayCount, 30);
    });

    test('calendar needs 4, 5 or 6 rows depending on start weekday', () {
      // 2026-08-01 is a Saturday -> 6 rows needed.
      expect(aug2026.firstWeekday, 6);
      expect(aug2026.leadingBlanks, 5);
      expect(aug2026.calendarWeeks, 6);
      // 2026-02-01 is a Sunday -> 6 leading blanks, 5 rows.
      expect(febNormal.firstWeekday, 7);
      expect(febNormal.leadingBlanks, 6);
      expect(febNormal.calendarWeeks, 5);
      // 2028-02-01 is a Tuesday (leap February).
      expect(febLeap.firstWeekday, 2);
      expect(febLeap.leadingBlanks, 1);
      expect(febLeap.calendarWeeks, 5);
      // A month starting Monday: 30 days -> 5 rows, 28 days -> exactly 4 rows.
      expect(june2026.firstWeekday, 1);
      expect(june2026.leadingBlanks, 0);
      expect(june2026.calendarWeeks, 5);
      expect(feb2027.firstWeekday, 1);
      expect(feb2027.calendarWeeks, 4);
    });

    test('a 6-row month is not clipped: cells cover blanks plus every day', () {
      expect(aug2026.calendarWeeks, 6);
      expect(aug2026.cellCount, 5 + 31);
      // Cells fill the last row partially — the grid never needs a 7th column,
      // and no real date is dropped to make it rectangular.
      expect(aug2026.cellCount, lessThanOrEqualTo(6 * 7));
      expect(aug2026.cellCount, greaterThan(5 * 7));
      // The last rendered cell is day 31, never dropped.
      final lastIndex = aug2026.cellCount - 1;
      expect(lastIndex - aug2026.leadingBlanks, 30);
      expect(aug2026.days.last, DateTime(2026, 8, 31));
    });

    test('every date appears exactly once, in order, for any month length', () {
      for (final r in [
        febLeap,
        febNormal,
        feb2027,
        april30,
        jan31,
        aug2026,
        may2026,
        june2026,
      ]) {
        expect(r.days.toSet(), hasLength(r.dayCount));
        for (var i = 1; i < r.days.length; i++) {
          expect(r.days[i].day, r.days[i - 1].day + 1);
        }
        expect(r.days.first.day, 1);
        expect(r.days.last.day, r.dayCount);
      }
    });

    test('percentage uses the true month length', () {
      final r = AnalyticsActivityRange.month(2026, 4, {
        DateTime(2026, 4, 1),
        DateTime(2026, 4, 2),
        DateTime(2026, 4, 3),
      });
      expect(r.completedCount, 3);
      expect(r.percentage, 10); // 3/30
    });

    test('streak is zero when today is outside the displayed month', () {
      final past = AnalyticsActivityRange.month(2026, 1, {
        DateTime(2026, 1, 30),
        DateTime(2026, 1, 31),
      });
      expect(past.currentStreak(DateTime(2026, 10, 3)), 0);
    });
  });

  group('selector wiring — the pills actually drive the range', () {
    test('profile screen reads _analyticsIsWeek when building the range', () {
      // The range is built once above the switch, so the whole body reads it.
      final body = profileSource.substring(
        profileSource.indexOf('Widget _buildAnalyticsBody()'),
      );
      expect(
        body,
        contains('_analyticsIsWeek'),
        reason: 'the selected range must be read, not just stored',
      );
      expect(body, contains('AnalyticsActivityRange.selected('));
      // The old code read only month/year, which is why Week did nothing.
      expect(body, isNot(contains('month: _stats.currentMonth')));
      expect(body, isNot(contains('year: _stats.currentYear')));
    });

    test('range factories are pure and repeatable (no stale state)', () {
      final now = DateTime(2026, 10, 3);
      final active = {DateTime(2026, 10, 2)};
      for (var i = 0; i < 5; i++) {
        final w = AnalyticsActivityRange.week(now, active);
        final m = AnalyticsActivityRange.month(2026, 10, active);
        expect(w.dayCount, 7);
        expect(m.dayCount, 31);
        expect(w.completedCount, 1);
        expect(m.completedCount, 1);
      }
    });

    test('toggling ranges never mutates the submitted-date source', () {
      final source = {DateTime(2026, 10, 1)};
      AnalyticsActivityRange.week(DateTime(2026, 10, 3), source);
      AnalyticsActivityRange.month(2026, 10, source);
      expect(source, hasLength(1));
    });
  });

  group('stats expose one authoritative submission-day set', () {
    test('activeSubmissionDates carries real submission days', () {
      final stats = InspectorDashboardStats.fromTasks([
        _task('a', submittedAt: '2026-10-01T10:00:00.000'),
        _task('b', submittedAt: '2026-10-02T10:00:00.000'),
        _task('c'), // no submission
      ]);
      expect(stats.activeSubmissionDates, {
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 2),
      });
      // The pre-existing month set is unchanged by this addition.
      expect(stats.activeDaysThisMonth, {1, 2});
    });

    test(
      'weekly and monthly ranges agree because they share the same source',
      () {
        final stats = InspectorDashboardStats.fromTasks([
          _task('a', submittedAt: '2026-10-01T10:00:00.000'),
          _task('b', submittedAt: '2026-10-03T10:00:00.000'),
        ]);
        final week = AnalyticsActivityRange.week(
          DateTime(2026, 10, 3),
          stats.activeSubmissionDates,
        );
        final month = AnalyticsActivityRange.month(
          2026,
          10,
          stats.activeSubmissionDates,
        );
        expect(week.completedCount, 2);
        expect(month.completedCount, 2);
        expect(week.days.length, 7);
        expect(month.days.length, 31);
      },
    );
  });

  group('all four tabs read the same range', () {
    test('every tab derives from one shared AnalyticsActivityRange', () {
      // A single range instance feeds Bars, Activity, Gauge and Sectors, so the
      // four tabs cannot drift out of sync when the selector is toggled.
      expect(profileSource, contains('AnalyticsActivityRange.selected('));
      expect(activityBranch, isNot(contains('AnalyticsActivityRange.week(')));
      expect(activityBranch, isNot(contains('AnalyticsActivityRange.month(')));
    });

    test('profile builds the range once and passes it to each tab', () {
      for (final consumer in [
        'submissionTrendFor(range.days)',
        'activityRange: range',
        'periodMetrics: range.metricsFor(_stats.scheduledCohort)',
        'completedTypeBreakdownFor(range.days)',
      ]) {
        expect(profileSource, contains(consumer));
      }
    });

    testWidgets('Gauge shows N/A when the period has no scheduled tasks', (
      tester,
    ) async {
      final empty = AnalyticsActivityRange.week(
        DateTime(2026, 10, 3),
        const {},
      ).metricsFor(const []);
      expect(empty.scheduledCompletionRate, isNull);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 380,
                child: CompletionGaugeCard(
                  rate: 0.5,
                  totalApplications: 9,
                  activeWorkload: 4,
                  trackColor: const Color(0xFFE9EEF6),
                  fillColor: Colors.blue,
                  textColor: Colors.black,
                  mutedTextColor: const Color(0xFF5D6472),
                  periodMetrics: empty,
                  periodLabel: 'Week',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('N/A'), findsOneWidget);
      // The removed hardcoded percentage chips must not come back.
      expect(find.text('3.5% ↗'), findsNothing);
      expect(find.text('4.5% ↘'), findsNothing);
    });

    testWidgets('Gauge shows the real rate when the cohort is non-empty', (
      tester,
    ) async {
      final stats = InspectorDashboardStats.fromTasks([
        _task('a', scheduledDate: '2026-10-01', status: 'completed'),
        _task('b', scheduledDate: '2026-10-02', status: 'completed'),
        _task('c', scheduledDate: '2026-10-03', status: 'in_progress'),
      ]);
      final metrics = AnalyticsActivityRange.week(
        DateTime(2026, 10, 3),
        const {},
      ).metricsFor(stats.scheduledCohort);
      expect(metrics.scheduledCompletionRate, closeTo(2 / 3, 1e-9));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 380,
                child: CompletionGaugeCard(
                  rate: 0.5,
                  totalApplications: 99,
                  activeWorkload: 88,
                  trackColor: const Color(0xFFE9EEF6),
                  fillColor: Colors.blue,
                  textColor: Colors.black,
                  mutedTextColor: const Color(0xFF5D6472),
                  periodMetrics: metrics,
                  periodLabel: 'Week',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('66.7%'), findsOneWidget);
      // The cohort size replaces the lifetime total; the "done" chip is the
      // real completed count, and the open tile shows what is left.
      expect(find.text('3'), findsOneWidget);
      expect(find.text('2 done'), findsOneWidget);
      expect(find.text('Scheduled'), findsOneWidget);
      expect(find.text('Still open'), findsOneWidget);
      expect(find.text('99'), findsNothing);
      expect(find.text('88'), findsNothing);
    });
  });

  group('calendar layout — no clipping on any width', () {
    Widget host(AnalyticsActivityRange range, double width, double height) =>
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Center(
                child: SizedBox(
                  width: width,
                  height: height,
                  child: ActivityHeatmapCard(
                    activityRange: range,
                    activeColor: Colors.green,
                    inactiveColor: const Color(0xFFE9EEF6),
                    textColor: Colors.black,
                    mutedTextColor: const Color(0xFF5D6472),
                    now: () => DateTime(2026, 8, 15),
                  ),
                ),
              ),
            ),
          ),
        );

    testWidgets('6-row month grid is fully visible, not clipped', (
      tester,
    ) async {
      // 2026-08 needs 6 rows — the exact case the old 24px wrapper cut off.
      await tester.pumpWidget(host(aug2026, 360, 800));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final grid = tester.getRect(find.byType(GridView));
      final cell = (360 - (6.0 * 6)) / 7;
      final expected = 6 * cell + 5 * 6;
      expect(grid.height, closeTo(expected, 0.5));
      // Day 31 is on screen.
      expect(find.text('31'), findsOneWidget);
    });

    testWidgets('wrapper height always equals rendered grid height', (
      tester,
    ) async {
      for (final width in [280.0, 320.0, 360.0, 420.0]) {
        await tester.pumpWidget(host(aug2026, width, 900));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final grid = tester.getRect(find.byType(GridView));
        final cell = (width - (6.0 * 6)) / 7;
        final expected = 6 * cell + 5 * 6;
        expect(
          grid.height,
          closeTo(expected, 0.5),
          reason: 'wrapper must track the real cell size at width $width',
        );
      }
    });

    testWidgets('every day of a 31-day month renders exactly once', (
      tester,
    ) async {
      await tester.pumpWidget(host(jan31, 360, 900));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (var d = 1; d <= 31; d++) {
        expect(find.text('$d'), findsOneWidget, reason: 'day $d missing');
      }
    });

    testWidgets('week strip renders 7 cells in a single row', (tester) async {
      final week = AnalyticsActivityRange.week(DateTime(2026, 10, 3), const {});
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: ActivityHeatmapCard(
                  activityRange: week,
                  activeColor: Colors.green,
                  inactiveColor: const Color(0xFFE9EEF6),
                  textColor: Colors.black,
                  mutedTextColor: const Color(0xFF5D6472),
                  now: () => DateTime(2026, 10, 3),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('0 of 7 days completed'), findsOneWidget);
      final grid = tester.getRect(find.byType(GridView));
      expect(grid.height, lessThan(80));
      // Calendar week containing Sat 2026-10-03 = Mon Sep 28 .. Sun Oct 4.
      for (final d in ['28', '29', '30', '1', '2', '3', '4']) {
        expect(find.text(d), findsOneWidget, reason: 'missing day $d');
      }
    });

    testWidgets('bottom metrics remain reachable in both ranges', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(AnalyticsActivityRange.month(2026, 8, const {}), 360, 900),
      );
      await tester.pumpAndSettle();
      expect(find.text('Current Streak'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Monthly'), findsOneWidget);
      expect(find.text('Weekly'), findsNothing);
      expect(find.text('August'), findsOneWidget);

      await tester.pumpWidget(
        host(
          AnalyticsActivityRange.week(DateTime(2026, 10, 3), const {}),
          360,
          900,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Current Streak'), findsOneWidget);
      expect(find.text('Weekly'), findsOneWidget);
      expect(find.text('Monthly'), findsNothing);
      expect(find.text('This week'), findsOneWidget);
    });

    testWidgets('today outline is independent from completed state', (
      tester,
    ) async {
      final now = DateTime(2026, 8, 15);
      // Today present but NOT completed.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: ActivityHeatmapCard(
                  activityRange: AnalyticsActivityRange.month(
                    2026,
                    8,
                    const {},
                  ),
                  activeColor: Colors.green,
                  inactiveColor: const Color(0xFFE9EEF6),
                  textColor: Colors.black,
                  mutedTextColor: const Color(0xFF5D6472),
                  now: () => now,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Not completed: today's cell must use the inactive colour, and the
      // completed count must not include it.
      final todayCell = tester.widget<Container>(
        find
            .ancestor(of: find.text('15'), matching: find.byType(Container))
            .first,
      );
      final decoration = todayCell.decoration! as BoxDecoration;
      expect(decoration.color, const Color(0xFFE9EEF6));
      expect(decoration.border, isNotNull, reason: 'today keeps its outline');
      expect(find.text('0 of 31 days completed'), findsOneWidget);
    });

    testWidgets('a completed day keeps filled colour and no outline', (
      tester,
    ) async {
      final day20 = DateTime(2026, 8, 20);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: ActivityHeatmapCard(
                  activityRange: AnalyticsActivityRange.month(2026, 8, {day20}),
                  activeColor: Colors.green,
                  inactiveColor: const Color(0xFFE9EEF6),
                  textColor: Colors.black,
                  mutedTextColor: const Color(0xFF5D6472),
                  now: () => DateTime(2026, 8, 15),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final cell = tester.widget<Container>(
        find
            .ancestor(of: find.text('20'), matching: find.byType(Container))
            .first,
      );
      final decoration = cell.decoration! as BoxDecoration;
      expect(decoration.color, Colors.green);
      expect(decoration.border, isNull);
      expect(find.text('1 of 31 days completed'), findsOneWidget);
    });

    testWidgets('screen scrolls when content is taller than the viewport', (
      tester,
    ) async {
      // A deliberately short viewport: the card is taller than the window, exactly
      // the situation the clipped calendar produced. It must scroll, not clip.
      tester.view.physicalSize = const Size(360, 300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Center(
                child: SizedBox(
                  width: 360,
                  child: ActivityHeatmapCard(
                    activityRange: aug2026,
                    activeColor: Colors.green,
                    inactiveColor: const Color(0xFFE9EEF6),
                    textColor: Colors.black,
                    mutedTextColor: const Color(0xFF5D6472),
                    now: () => DateTime(2026, 8, 15),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'must scroll, not overflow',
      );
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      // The last day exists in the tree and can be scrolled to.
      expect(find.text('31'), findsOneWidget);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('31'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
    });
  });

  group('BARS — Weekly Performance follows the range', () {
    test('week has daily bars and month has readable weekly bars', () {
      final stats = InspectorDashboardStats.fromTasks(const []);
      final now = DateTime(2026, 10, 3);
      final week = AnalyticsActivityRange.week(now, const {});
      final month = AnalyticsActivityRange.month(2026, 10, const {});
      expect(stats.submissionTrendFor(week.days), hasLength(7));
      expect(stats.submissionTrendFor(month.days), hasLength(5));
    });

    test('monthly weeks preserve all submissions at every bucket boundary', () {
      final stats = InspectorDashboardStats.fromTasks([
        _task('outside-before', submittedAt: '2026-09-30T10:00:00'),
        _task('first', submittedAt: '2026-10-01T10:00:00'),
        _task('seventh', submittedAt: '2026-10-07T10:00:00'),
        _task('same-day', submittedAt: '2026-10-07T11:00:00'),
        _task('eighth', submittedAt: '2026-10-08T10:00:00'),
        _task('fourteenth', submittedAt: '2026-10-14T10:00:00'),
        _task('fifteenth', submittedAt: '2026-10-15T10:00:00'),
        _task('twenty-first', submittedAt: '2026-10-21T10:00:00'),
        _task('twenty-second', submittedAt: '2026-10-22T10:00:00'),
        _task('twenty-eighth', submittedAt: '2026-10-28T10:00:00'),
        _task('twenty-ninth', submittedAt: '2026-10-29T10:00:00'),
        _task('last', submittedAt: '2026-10-31T23:59:59'),
        _task('outside-after', submittedAt: '2026-11-01T00:00:00'),
        _task('invalid', submittedAt: 'not-a-date'),
      ]);
      final points = stats.submissionTrendFor(
        AnalyticsActivityRange.month(2026, 10, const {}).days,
      );
      expect(points.map((point) => point.label), [
        '1st week',
        '2nd week',
        '3rd week',
        '4th week',
        '5th week',
      ]);
      expect(points.map((point) => point.date.day), [1, 8, 15, 22, 29]);
      expect(points.map((point) => point.count), [3, 2, 2, 2, 2]);
      expect(points.fold<int>(0, (sum, point) => sum + point.count), 11);
    });

    test(
      'monthly bars include the short final week without a phantom fifth',
      () {
        for (final (range, expected) in [
          (febNormal, [7, 7, 7, 7]),
          (febLeap, [7, 7, 7, 7, 1]),
          (april30, [7, 7, 7, 7, 2]),
          (jan31, [7, 7, 7, 7, 3]),
        ]) {
          final stats = InspectorDashboardStats.fromTasks([
            for (final day in range.days)
              _task(
                '${day.day}',
                submittedAt:
                    '${day.toIso8601String().substring(0, 10)}T12:00:00',
              ),
          ]);
          expect(
            stats.submissionTrendFor(range.days).map((point) => point.count),
            expected,
          );
          final empty = InspectorDashboardStats.empty().submissionTrendFor(
            range.days,
          );
          expect(empty.length, expected.length);
          expect(empty.every((point) => point.count == 0), isTrue);
        }
      },
    );

    test('labels run Mon..Sun and counts come from real submissions', () {
      final stats = InspectorDashboardStats.fromTasks([
        _task('a', submittedAt: '2026-10-05T09:00:00.000'), // Monday
        _task('b', submittedAt: '2026-10-05T11:00:00.000'), // same day
        _task('c', submittedAt: '2026-09-28T09:00:00.000'), // previous week
      ]);
      // Week of Mon 2026-10-05 .. Sun 2026-10-11
      final week = AnalyticsActivityRange.week(DateTime(2026, 10, 7), const {});
      final points = stats.submissionTrendFor(week.days);
      expect(points.map((p) => p.label).toList(), [
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
        'Sun',
      ]);
      expect(points.first.count, 2, reason: 'both Monday submissions');
      expect(points.last.count, 0);
      // The submission outside the week must not leak in.
      expect(points.fold<int>(0, (a, p) => a + p.count), 2);
    });
  });

  group('GAUGE — scheduled-cohort completion rate', () {
    ScheduledCohortTask cohort(String id, String date, {bool done = false}) =>
        ScheduledCohortTask(
          id: id,
          scheduledDate: DateTime.parse(date),
          isCompleted: done,
        );

    test('rate is completed-within-cohort divided by cohort size', () {
      final week = AnalyticsActivityRange.week(DateTime(2026, 10, 3), const {});
      final metrics = week.metricsFor([
        cohort('1', '2026-10-01', done: true), // Thu, same week
        cohort('2', '2026-10-02'), // Fri, same week
        cohort('3', '2026-10-03', done: true), // Sat, same week
        cohort('4', '2026-09-20', done: true), // PRIOR week - excluded
      ]);
      expect(metrics.scheduledCohortCount, 3);
      expect(metrics.scheduledCompletedCount, 2);
      expect(metrics.scheduledOpenCount, 1);
      expect(metrics.scheduledCompletionRate, closeTo(2 / 3, 1e-9));
    });

    test('a completion scheduled OUTSIDE the range is never counted', () {
      final week = AnalyticsActivityRange.week(DateTime(2026, 10, 3), const {});
      final metrics = week.metricsFor([
        cohort('1', '2026-10-05', done: true), // next week - excluded
        cohort('2', '2026-10-02'), // this week - denominator only
      ]);
      expect(metrics.scheduledCohortCount, 1);
      expect(metrics.scheduledCompletedCount, 0);
      expect(metrics.scheduledCompletionRate, 0.0);
    });

    test('empty cohort yields a null rate, never a misleading 0%', () {
      final week = AnalyticsActivityRange.week(DateTime(2026, 10, 3), const {});
      final metrics = week.metricsFor([cohort('1', '2026-09-20', done: true)]);
      expect(metrics.scheduledCohortCount, 0);
      expect(
        metrics.scheduledCompletionRate,
        isNull,
        reason: 'null means "nothing scheduled", which is not the same as 0%',
      );
      // Null must be distinguishable from a genuine zero.
      final full = week.metricsFor([cohort('2', '2026-10-01')]);
      expect(full.scheduledCompletionRate, 0.0);
      expect(full.scheduledCompletionRate, isNotNull);
    });

    test('month cohort uses the calendar month', () {
      final month = AnalyticsActivityRange.month(2026, 10, const {});
      final metrics = month.metricsFor([
        cohort('1', '2026-10-05', done: true),
        cohort('2', '2026-10-06', done: true),
        cohort('3', '2026-10-07'),
        cohort('4', '2026-11-01', done: true), // next month - excluded
        cohort('5', '2026-09-30', done: true), // prev month - excluded
      ]);
      expect(metrics.scheduledCohortCount, 3);
      expect(metrics.scheduledCompletedCount, 2);
    });

    test('unscheduled tasks never enter the cohort', () {
      final stats = InspectorDashboardStats.fromTasks([
        _task('scheduled', scheduledDate: '2026-10-01', status: 'completed'),
        _task('unscheduled', status: 'completed'), // no scheduled_date
      ]);
      expect(stats.scheduledCohort.map((t) => t.id), ['scheduled']);
      expect(stats.scheduledCohort.single.isCompleted, isTrue);
    });

    test(
      'a task with an unparseable scheduled date is skipped, not defaulted',
      () {
        final stats = InspectorDashboardStats.fromTasks([
          _task('bad', scheduledDate: 'not-a-date'),
          _task('good', scheduledDate: '2026-10-01'),
        ]);
        expect(stats.scheduledCohort.map((t) => t.id), ['good']);
      },
    );
  });

  group('SECTORS — completed-only zoning distribution', () {
    test('counts only inspections completed inside the range', () {
      final stats = InspectorDashboardStats.fromTasks([
        _task('a', submittedAt: '2026-10-01T09:00:00.000', type: 'Petition'),
        _task('b', submittedAt: '2026-10-02T09:00:00.000', type: 'Petition'),
        _task('c', submittedAt: '2026-10-03T09:00:00.000', type: 'Variance'),
        _task('d', submittedAt: '2026-09-01T09:00:00.000', type: 'Petition'),
      ]);
      final month = AnalyticsActivityRange.month(2026, 10, const {});
      final entries = stats.completedTypeBreakdownFor(month.days);
      expect(entries.first.label, 'Petition');
      expect(entries.first.count, 2);
      expect(entries.first.share, closeTo(2 / 3, 1e-9));
      // September's Petition is outside October.
      expect(entries.fold<int>(0, (a, e) => a + e.count), 3);
    });

    test('pending/ongoing work is excluded entirely', () {
      final stats = InspectorDashboardStats.fromTasks([
        _task('done', submittedAt: '2026-10-01T09:00:00.000', type: 'Petition'),
        _task('pending', status: 'assigned', type: 'Variance'),
        _task('ongoing', status: 'in_progress', type: 'Variance'),
      ]);
      final month = AnalyticsActivityRange.month(2026, 10, const {});
      final entries = stats.completedTypeBreakdownFor(month.days);
      expect(entries, hasLength(1));
      expect(entries.single.label, 'Petition');
      expect(entries.single.count, 1);
    });

    test('no completed work in range yields an honest empty result', () {
      final stats = InspectorDashboardStats.fromTasks([
        _task('pending', status: 'assigned', type: 'Variance'),
      ]);
      final month = AnalyticsActivityRange.month(2026, 10, const {});
      expect(stats.completedTypeBreakdownFor(month.days), isEmpty);
    });

    test('existing zoning vocabulary is reused, never invented', () {
      final stats = InspectorDashboardStats.fromTasks([
        _task(
          'a',
          submittedAt: '2026-10-01T09:00:00.000',
          type: 'Petition for Rezoning',
        ),
        _task(
          'b',
          submittedAt: '2026-10-02T09:00:00.000',
          landUse: 'Residential',
        ),
        _task('c', submittedAt: '2026-10-03T09:00:00.000'), // neither
      ]);
      final month = AnalyticsActivityRange.month(2026, 10, const {});
      final labels = stats
          .completedTypeBreakdownFor(month.days)
          .map((e) => e.label)
          .toSet();
      expect(labels, {'Petition for Rezoning', 'Residential', 'Unclassified'});
    });
  });

  group('other analytics tabs are untouched by the range', () {
    test('Bars / Gauge / Sectors now consume the selected range', () {
      // All three take the shared range; none is left on a fixed lifetime view.
      expect(
        profileSource,
        contains('points: _stats.submissionTrendFor(range.days)'),
      );
      expect(
        profileSource,
        contains('periodMetrics: range.metricsFor(_stats.scheduledCohort)'),
      );
      expect(
        profileSource,
        contains('entries: _stats.completedTypeBreakdownFor(range.days)'),
      );
      // The fixed rolling series must no longer drive the chart.
      expect(profileSource, isNot(contains('points: _stats.weeklyTrend')));
      expect(profileSource, isNot(contains('entries: _stats.typeBreakdown,')));
    });

    test(
      'Bars heading follows the range instead of always claiming weekly',
      () {
        expect(profileSource, contains('periodLabel: periodLabel'));
        expect(dashboardWidgetsSource, contains('WEEKLY PERFORMANCE'));
        expect(dashboardWidgetsSource, contains('periodLabel!.toUpperCase()'));
      },
    );

    test('the fabricated gauge badges are gone', () {
      // '3.5% ↗' and '4.5% ↘' were hardcoded literals, never computed. Comments
      // explaining their removal are stripped first so only real code counts.
      final code = dashboardWidgetsSource
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code, isNot(contains('3.5%')));
      expect(code, isNot(contains('4.5%')));
      // And the real replacement chips are wired to computed values.
      expect(code, contains('periodRateLabel!'));
      expect(code, contains('scheduledCompletedCount'));
    });
  });

  group('no persistence or sync side effects', () {
    test('no DB / Supabase / outbox reference in the new range code', () {
      for (final forbidden in [
        'DBHelper',
        'SupabaseService',
        'SyncOutboxService',
        'local_route_cache',
        'InspectionProgress',
      ]) {
        expect(rangeModelSource, isNot(contains(forbidden)));
        expect(activityBranch, isNot(contains(forbidden)));
      }
    });
  });
}

/// Sources asserted as contracts.
final profileSource = File(
  'lib/modules/profile_settings/screens/profile_screen.dart',
).readAsStringSync();
final rangeModelSource = File(
  'lib/modules/profile_settings/models/analytics_activity_range.dart',
).readAsStringSync();

/// Just the Activity tab branch of `_buildAnalyticsBody`, so unrelated parts of
/// ProfileScreen (sign-out, Supabase, other cards) cannot satisfy or break it.
final activityBranch = profileSource.substring(
  profileSource.indexOf('case 1:'),
  profileSource.indexOf('case 2:'),
);

/// The Week/Month pills and the range they feed.
final rangeBuilderSource = activityBranch;

/// The analytics widget library, asserted for the fabricated-badge removal.
final dashboardWidgetsSource = File(
  'lib/modules/profile_settings/widgets/dashboard_widgets.dart',
).readAsStringSync();
