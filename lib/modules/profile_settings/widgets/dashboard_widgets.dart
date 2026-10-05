import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../models/dashboard_stats.dart';
import '../models/analytics_activity_range.dart';
import '../../../core/theme/insight_theme.dart';

/// ==================================================================
/// Second pass on these 4 cards. First pass just scaled up the old
/// small-widget fonts/heights to fill the new full-width page, which
/// read as stretched, not designed. This version rebuilds each card's
/// internal composition instead: a compact header (label + the one
/// number that matters most), the chart as the dominant middle
/// section (an Expanded — it naturally settles around 60-70% of the
/// card since header/footer are their own intrinsic heights, not
/// forced fractions), then a footer stat row for context. Same data
/// in, same neumorphic card wrapper (untouched, in profile_screen.dart)
/// — only what's inside is different.
/// ==================================================================

/// Shared footer: 2-4 stat items in a row, hairline dividers between
/// them. Every card ends on one of these — same primitive, different
/// content — so the four cards read as one family, not one-off layouts.
class _StatRow extends StatelessWidget {
  final List<(String label, String value)> items;
  final Color textColor;
  final Color mutedTextColor;
  final Color dividerColor;

  const _StatRow({required this.items, required this.textColor, required this.mutedTextColor, required this.dividerColor});

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      if (i > 0) {
        children.add(Container(width: 1, height: 38, color: dividerColor, margin: const EdgeInsets.symmetric(horizontal: 10)));
      }
      final (label, value) = items[i];
      children.add(
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value, style: InsightTheme.inter(17, w: FontWeight.w800, c: textColor)),
              const SizedBox(height: 2),
              Text(label, style: InsightTextStyles.caption(color: mutedTextColor), maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      );
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}

/// ==================================================================
/// COMPLETION RATE — Pinterest-style Segmented Radial Block Gauge
/// Matches the reference design:
/// • Top banner pill with crown icon ("You're in the top 15% of performers")
/// • 14 segmented radial rounded block pills in an arch
/// • Large crisp center percentage + "completion goals" label
/// • Dual soft stat cards at the bottom (Applications / Active Tasks)
/// ==================================================================
class CompletionGaugeCard extends StatelessWidget {
  final double rate; // 0.0 - 1.0
  final int totalApplications;
  final int activeWorkload;
  final Color trackColor;
  final Color fillColor;
  final Color textColor;
  final Color mutedTextColor;

  /// When supplied, this card reports the selected Week/Month period instead
  /// of the lifetime figure. A null rate means "no scheduled tasks in this
  /// period", which renders as an explicit N/A rather than 0%.
  final AnalyticsRangeMetrics? periodMetrics;

  /// 'Week' or 'Month' — only used when [periodMetrics] is supplied.
  final String? periodLabel;

  /// The real period percentage chip, or null when there is no cohort.
  String? get periodRateLabel {
    final rate = periodMetrics?.scheduledCompletionRate;
    if (rate == null) return null;
    return '${(rate * 100).toStringAsFixed(0)}%';
  }

  const CompletionGaugeCard({
    super.key,
    required this.rate,
    required this.totalApplications,
    required this.activeWorkload,
    required this.trackColor,
    required this.fillColor,
    required this.textColor,
    required this.mutedTextColor,
    this.periodMetrics,
    this.periodLabel,
  });

  @override
  Widget build(BuildContext context) {
    final scoped = periodMetrics;
    // In period mode the gauge is the scheduled-cohort rate; null means there
    // is nothing scheduled, which must not be drawn as a confident 0.0%.
    final effectiveRate = scoped == null
        ? (rate.isNaN ? 0.0 : rate.clamp(0.0, 1.0))
        : scoped.scheduledCompletionRate;
    final hasNoScheduled = scoped != null && effectiveRate == null;
    final clamped = hasNoScheduled
        ? 0.0
        : (effectiveRate!.isNaN ? 0.0 : effectiveRate.clamp(0.0, 1.0));
    final percentLabel = hasNoScheduled ? 'N/A' : '${(clamped * 100).toStringAsFixed(1)}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 1. Segmented Radial Bar Arch ─────────────────────────────
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _SegmentedGaugePainter(
                    progress: clamped,
                    fill: fillColor,
                    track: trackColor,
                  ),
                ),
              ),
              Positioned(
                bottom: 6,
                left: 0,
                right: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        percentLabel,
                        style: InsightTheme.urbanist(
                          26,
                          w: FontWeight.w800,
                          c: textColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'completion goals',
                      style: InsightTheme.inter(
                        11,
                        w: FontWeight.w500,
                        c: mutedTextColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // ── 2. Bottom Dual Stat Cards (No Overflow) ──────────────────
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: InsightTheme.surface2,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              scoped == null ? 'Applications' : 'Scheduled',
                              style: InsightTheme.inter(11, w: FontWeight.w500, c: InsightTheme.ink3),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        // The old hardcoded '3.5%' chip was a literal string,
                        // never a computed value. Now it shows the real period
                        // figure, or nothing when there is no scheduled cohort.
                        if (periodRateLabel != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3563FF),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              periodRateLabel!,
                              style: InsightTheme.inter(8, w: FontWeight.w700, c: Colors.white),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${scoped?.scheduledCohortCount ?? totalApplications}',
                      style: InsightTheme.poppins(18, w: FontWeight.w800, c: InsightTheme.ink),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: InsightTheme.surface2,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              scoped == null ? 'Workload' : 'Still open',
                              style: InsightTheme.inter(11, w: FontWeight.w500, c: InsightTheme.ink3),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        // Same as above: the old '4.5%' chip was also a literal.
                        // In period mode this reports the real completed count.
                        if (scoped != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F111A),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${scoped.scheduledCompletedCount} done',
                              style: InsightTheme.inter(8, w: FontWeight.w700, c: Colors.white),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${scoped?.scheduledOpenCount ?? activeWorkload}',
                      style: InsightTheme.poppins(18, w: FontWeight.w800, c: InsightTheme.ink),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SegmentedGaugePainter extends CustomPainter {
  final double progress; // 0.0 - 1.0
  final Color fill;
  final Color track;

  static const int totalSegments = 14;

  _SegmentedGaugePainter({
    required this.progress,
    required this.fill,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height - 4);
    final outerRadius = math.min(size.width / 2 - 14, size.height - 8);
    final innerRadius = outerRadius * 0.65;
    final strokeWidth = (outerRadius - innerRadius) * 0.44;

    final activeCount = (progress * totalSegments).round();

    for (int i = 0; i < totalSegments; i++) {
      final t = i / (totalSegments - 1);
      final angle = math.pi + (t * math.pi);

      final p1 = Offset(
        center.dx + innerRadius * math.cos(angle),
        center.dy + innerRadius * math.sin(angle),
      );
      final p2 = Offset(
        center.dx + outerRadius * math.cos(angle),
        center.dy + outerRadius * math.sin(angle),
      );

      final isFilled = i < activeCount;
      final blockColor = isFilled ? fill : track;

      final paint = Paint()
        ..color = blockColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(p1, p2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SegmentedGaugePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.fill != fill || oldDelegate.track != track;
}

/// ==================================================================
/// WEEKLY TREND — bar chart is the whole middle; footer distills it to
/// the three numbers a supervisor actually scans for.
/// ==================================================================
class WeeklyTrendCard extends StatelessWidget {
  final List<TrendPoint> points;
  final Color barColor;
  final Color textColor;
  final Color mutedTextColor;

  /// 'Week' or 'Month' — keeps the heading honest now that the card can show
  /// either range, instead of always claiming to be weekly.
  final String? periodLabel;

  const WeeklyTrendCard({
    super.key,
    required this.points,
    required this.barColor,
    required this.textColor,
    required this.mutedTextColor,
    this.periodLabel,
  });

  @override
  Widget build(BuildContext context) {
    final counts = points.map((p) => p.count).toList();
    final maxCount = counts.isEmpty ? 1 : counts.reduce(math.max);
    final chartMax = (maxCount < 4 ? 4 : maxCount).toDouble();
    final highestIdx = counts.isEmpty ? -1 : counts.indexOf(counts.reduce(math.max));
    final lowestIdx = counts.isEmpty ? -1 : counts.indexOf(counts.reduce(math.min));
    final avg = counts.isEmpty ? 0.0 : counts.reduce((a, b) => a + b) / counts.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          periodLabel == null ? 'WEEKLY PERFORMANCE' : '${periodLabel!.toUpperCase()} PERFORMANCE',
          style: InsightTextStyles.sectionHeaderPill(color: mutedTextColor),
        ),
        const SizedBox(height: 4),
        Text('Inspections submitted per day', style: InsightTextStyles.caption(color: mutedTextColor)),
        const SizedBox(height: 14),
        Expanded(
          child: BarChart(
            BarChartData(
              maxY: chartMax,
              alignment: BarChartAlignment.spaceAround,
              // Manual-test fix (#4): the faint horizontal gridlines
              // duplicated the full-height backDraw rods' structure and read
              // as stray parallel reference lines. Removed; the bars plus the
              // backDraw panels carry the chart.
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= points.length) return const SizedBox.shrink();
                      final isPeak = i == highestIdx;
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(points[i].label,
                            style: TextStyle(
                              fontSize: 12,
                              color: isPeak ? textColor : mutedTextColor,
                              fontWeight: isPeak ? FontWeight.w800 : FontWeight.w600,
                            )),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(enabled: false),
              barGroups: [
                for (int i = 0; i < points.length; i++)
                  BarChartGroupData(x: i, barRods: [
                    BarChartRodData(
                      toY: points[i].count.toDouble(),
                      // Peak day stands out at full color; the rest sit a
                      // shade lighter so the eye lands on the highest bar
                      // first, matching the "Highest Day" footer stat.
                      color: i == highestIdx ? barColor : barColor.withValues(alpha: 0.45),
                      width: 22,
                      borderRadius: BorderRadius.circular(6),
                      backDrawRodData: BackgroundBarChartRodData(
                        show: true,
                        toY: chartMax,
                        color: barColor.withValues(alpha: 0.06),
                      ),
                    ),
                  ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Divider(height: 1, color: barColor.withValues(alpha: 0.12)),
        const SizedBox(height: 12),
        _StatRow(
          items: [
            ('Highest Day', highestIdx >= 0 ? '${points[highestIdx].label} · ${points[highestIdx].count}' : '—'),
            ('Average', avg.toStringAsFixed(1)),
            ('Lowest Day', lowestIdx >= 0 ? '${points[lowestIdx].label} · ${points[lowestIdx].count}' : '—'),
          ],
          textColor: textColor,
          mutedTextColor: mutedTextColor,
          dividerColor: barColor.withValues(alpha: 0.12),
        ),
      ],
    );
  }
}

/// ==================================================================
/// ACTIVITY TRACKER — weekday header makes the calendar scannable at a
/// glance; footer surfaces the streak, which the raw grid can't show.
/// ==================================================================
/// Largest day-cell the activity calendar will draw.
///
/// The grid is always seven square columns filling the available width, so on a
/// wide viewport each cell grew to ~165px and the card became ~1000px tall.
/// Capping the cell keeps the calendar a readable size and centred; the column
/// count and every date calculation are untouched.
const double kAnalyticsHeatmapMaxCell = 56.0;

class ActivityHeatmapCard extends StatelessWidget {
  /// Exactly which days are shown and which of them were completed. The
  /// denominator, calendar shape and "today" outline all come from this — never
  /// from a hardcoded month or a guessed cell size.
  final AnalyticsActivityRange activityRange;
  final Color activeColor;
  final Color inactiveColor;
  final Color textColor;
  final Color mutedTextColor;

  /// Injectable for deterministic tests; defaults to the real clock.
  final DateTime Function() now;

  const ActivityHeatmapCard({
    super.key,
    required this.activityRange,
    required this.activeColor,
    required this.inactiveColor,
    required this.textColor,
    required this.mutedTextColor,
    DateTime Function()? now,
  }) : now = now ?? _systemNow;

  static DateTime _systemNow() => DateTime.now();

  static const List<String> _weekdayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  bool get _isWeek => activityRange.range == AnalyticsRange.week;

  static String _monthName(int month) => const [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December',
      ][month - 1];

  @override
  Widget build(BuildContext context) {
    final range = activityRange;
    final today = now();
    final streak = range.currentStreak(today);
    final periodLabel = _isWeek ? 'This week' : _monthName(range.days.first.month);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ACTIVITY TRACKER', style: InsightTextStyles.sectionHeaderPill(color: mutedTextColor)),
        const SizedBox(height: 4),
        Text('${range.completedCount} of ${range.dayCount} days completed',
            style: InsightTheme.inter(14.5, w: FontWeight.w600, c: textColor)),
        const SizedBox(height: 2),
        Text(periodLabel, style: InsightTheme.inter(11.5, c: mutedTextColor)),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final d in _weekdayLabels)
              Expanded(
                child: Center(
                  child: Text(d, style: InsightTheme.inter(12, w: FontWeight.w700, c: mutedTextColor)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        // Square cells sized from the REAL available width. The previous fixed
        // 24px assumption made this wrapper shorter than the grid the
        // aspect-ratio delegate actually renders, clipping the final row.
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 6.0;
            // Seven square columns fill the width, which on a wide viewport
            // produced ~165px cells and a ~1000px-tall card. The cells stay
            // square (that is what the gridHeight maths relies on) but stop
            // growing past a readable size; the grid itself stays full width.
            final fullCell = (constraints.maxWidth - (spacing * 6)) / 7;
            final cell = fullCell.clamp(0.0, kAnalyticsHeatmapMaxCell);
            final rows = range.calendarWeeks;
            final gridHeight = rows * cell + (rows - 1) * spacing;
            return SizedBox(
              height: gridHeight,
              child: Center(
                child: SizedBox(
                  width: cell * 7 + spacing * 6,
                  child: GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: range.cellCount,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisSpacing: spacing,
                      crossAxisSpacing: spacing,
                      childAspectRatio: 1,
                    ),
                itemBuilder: (context, index) {
                  if (index < range.leadingBlanks) return const SizedBox.shrink();
                  final date = range.days[index - range.leadingBlanks];
                  final isActive = range.isActive(date);
                  // Today and completed are independent: an incomplete today
                  // keeps only its outline and is never counted as completed.
                  final isToday = range.contains(today) &&
                      today.year == date.year &&
                      today.month == date.month &&
                      today.day == date.day;
                  return Container(
                    decoration: BoxDecoration(
                      color: isActive ? activeColor : inactiveColor,
                      borderRadius: BorderRadius.circular(8),
                      border: isToday ? Border.all(color: activeColor, width: 2) : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${date.day}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isActive ? Colors.white : mutedTextColor,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    ),
        const SizedBox(height: 12),
        Divider(height: 1, color: inactiveColor),
        const SizedBox(height: 12),
        _StatRow(
          items: [
            ('Current Streak', '$streak d'),
            ('Completed', '${range.completedCount}'),
            (_isWeek ? 'Weekly' : 'Monthly', '${range.percentage}%'),
          ],
          textColor: textColor,
          mutedTextColor: mutedTextColor,
          dividerColor: inactiveColor,
        ),
      ],
    );
  }
}

/// ==================================================================
/// ZONING DISTRIBUTION — bars are the body; footer settles on the one
/// number that matters most once you've scanned the breakdown: total.
/// ==================================================================
class ZoningTypeBreakdownCard extends StatelessWidget {
  final List<TypeBreakdownEntry> entries;
  final Color barColor;
  final Color trackColor;
  final Color textColor;
  final Color mutedTextColor;
  /// Palette cycled across segments, in order. Falls back to [barColor]
  /// repeated if not supplied, so existing callers don't break.
  final List<Color>? segmentColors;

  /// 'Week' or 'Month' — the subtitle must describe what is actually counted,
  /// which is completions inside the range, not all assigned applications.
  final String? periodLabel;

  const ZoningTypeBreakdownCard({
    super.key,
    required this.entries,
    required this.barColor,
    required this.trackColor,
    required this.textColor,
    required this.mutedTextColor,
    this.segmentColors,
    this.periodLabel,
  });

  @override
  Widget build(BuildContext context) {
    final visible = entries.take(5).toList();
    final total = entries.fold<int>(0, (sum, e) => sum + e.count);
    final palette = (segmentColors != null && segmentColors!.isNotEmpty) ? segmentColors! : [barColor];
    Color colorFor(int i) => palette[i % palette.length];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('ZONING DISTRIBUTION', style: InsightTextStyles.sectionHeaderPill(color: mutedTextColor)),
                  const SizedBox(height: 4),
                  Text(
                  periodLabel == null
                      ? 'Share of assigned applications'
                      : 'Completed this ${periodLabel!.toLowerCase()}',
                  style: InsightTextStyles.caption(color: mutedTextColor),
                ),
                ],
              ),
            ),
            Text('$total total', style: InsightTextStyles.caption(color: mutedTextColor)),
          ],
        ),
        const SizedBox(height: 18),
        if (visible.isEmpty)
          Expanded(
            child: Center(
              child: Text('No records yet', style: TextStyle(fontSize: 14, color: mutedTextColor)),
            ),
          )
        else ...[
          // Single segmented bar — the whole picture (share of total) in
          // one glance, instead of scanning N separate bars.
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 18,
              child: Row(
                children: [
                  for (int i = 0; i < visible.length; i++)
                    Expanded(
                      flex: () {
                        final v = (visible[i].share * 1000).round();
                        return v < 1 ? 1 : v;
                      }(),
                      child: Container(
                        color: colorFor(i),
                        margin: EdgeInsets.only(right: i == visible.length - 1 ? 0 : 1.5),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: visible.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final e = visible[i];
                return Row(
                  children: [
                    Container(
                      width: 9, height: 9,
                      decoration: BoxDecoration(color: colorFor(i), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(e.label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor)),
                    ),
                    Text('${(e.share * 100).round()}%',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: mutedTextColor)),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 24,
                      child: Text('${e.count}',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: textColor)),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}