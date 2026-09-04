import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../models/dashboard_stats.dart';
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

  const CompletionGaugeCard({
    super.key,
    required this.rate,
    required this.totalApplications,
    required this.activeWorkload,
    required this.trackColor,
    required this.fillColor,
    required this.textColor,
    required this.mutedTextColor,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = rate.isNaN ? 0.0 : rate.clamp(0.0, 1.0);
    final percentLabel = '${(clamped * 100).toStringAsFixed(1)}%';

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
                              'Applications',
                              style: InsightTheme.inter(11, w: FontWeight.w500, c: InsightTheme.ink3),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3563FF),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '3.5% ↗',
                            style: InsightTheme.inter(8, w: FontWeight.w700, c: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '$totalApplications',
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
                              'Workload',
                              style: InsightTheme.inter(11, w: FontWeight.w500, c: InsightTheme.ink3),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F111A),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '4.5% ↘',
                            style: InsightTheme.inter(8, w: FontWeight.w700, c: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '$activeWorkload',
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

  const WeeklyTrendCard({
    super.key,
    required this.points,
    required this.barColor,
    required this.textColor,
    required this.mutedTextColor,
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
        Text('WEEKLY PERFORMANCE', style: InsightTextStyles.sectionHeaderPill(color: mutedTextColor)),
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
                      color: i == highestIdx ? barColor : barColor.withOpacity(0.45),
                      width: 22,
                      borderRadius: BorderRadius.circular(6),
                      backDrawRodData: BackgroundBarChartRodData(
                        show: true,
                        toY: chartMax,
                        color: barColor.withOpacity(0.06),
                      ),
                    ),
                  ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Divider(height: 1, color: barColor.withOpacity(0.12)),
        const SizedBox(height: 12),
        _StatRow(
          items: [
            ('Highest Day', highestIdx >= 0 ? '${points[highestIdx].label} · ${points[highestIdx].count}' : '—'),
            ('Average', avg.toStringAsFixed(1)),
            ('Lowest Day', lowestIdx >= 0 ? '${points[lowestIdx].label} · ${points[lowestIdx].count}' : '—'),
          ],
          textColor: textColor,
          mutedTextColor: mutedTextColor,
          dividerColor: barColor.withOpacity(0.12),
        ),
      ],
    );
  }
}

/// ==================================================================
/// ACTIVITY TRACKER — weekday header makes the calendar scannable at a
/// glance; footer surfaces the streak, which the raw grid can't show.
/// ==================================================================
class ActivityHeatmapCard extends StatelessWidget {
  final Set<int> activeDays;
  final int month;
  final int year;
  final Color activeColor;
  final Color inactiveColor;
  final Color textColor;
  final Color mutedTextColor;

  const ActivityHeatmapCard({
    super.key,
    required this.activeDays,
    required this.month,
    required this.year,
    required this.activeColor,
    required this.inactiveColor,
    required this.textColor,
    required this.mutedTextColor,
  });

  int get _currentStreak {
    final today = DateTime.now();
    final isCurrentMonth = today.year == year && today.month == month;
    if (!isCurrentMonth) return 0;
    int streak = 0;
    int day = today.day;
    while (day >= 1 && activeDays.contains(day)) {
      streak++;
      day--;
    }
    return streak;
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstWeekday = DateTime(year, month, 1).weekday; // 1 = Mon .. 7 = Sun
    final leadingBlanks = firstWeekday - 1;
    final totalCells = leadingBlanks + daysInMonth;
    final calendarWeeks = ((totalCells + 6) / 7).ceil();
    final cellSize = 24.0;
    final gridHeight = (calendarWeeks * cellSize) + ((calendarWeeks - 1) * 6.0) + 4.0;
    final today = DateTime.now();
    final isCurrentMonth = today.year == year && today.month == month;
    final monthlyPct = daysInMonth == 0 ? 0 : ((activeDays.length / daysInMonth) * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ACTIVITY TRACKER', style: InsightTextStyles.sectionHeaderPill(color: mutedTextColor)),
        const SizedBox(height: 4),
        Text('${activeDays.length} of $daysInMonth days completed',
            style: InsightTheme.inter(14.5, w: FontWeight.w600, c: textColor)),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Expanded(
                child: Center(
                  child: Text(d, style: InsightTheme.inter(12, w: FontWeight.w700, c: mutedTextColor)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: gridHeight,
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: totalCells,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 1,
            ),
            itemBuilder: (context, index) {
              if (index < leadingBlanks) return const SizedBox.shrink();
              final day = index - leadingBlanks + 1;
              final isActive = activeDays.contains(day);
              final isToday = isCurrentMonth && today.day == day;
              return Container(
                decoration: BoxDecoration(
                  color: isActive ? activeColor : inactiveColor,
                  borderRadius: BorderRadius.circular(8),
                  border: isToday ? Border.all(color: activeColor, width: 2) : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$day',
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
        const SizedBox(height: 12),
        Divider(height: 1, color: inactiveColor),
        const SizedBox(height: 12),
        _StatRow(
          items: [
            ('Current Streak', '$_currentStreak d'),
            ('Completed', '${activeDays.length}'),
            ('Monthly', '$monthlyPct%'),
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

  const ZoningTypeBreakdownCard({
    super.key,
    required this.entries,
    required this.barColor,
    required this.trackColor,
    required this.textColor,
    required this.mutedTextColor,
    this.segmentColors,
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
                  Text('Share of assigned applications', style: InsightTextStyles.caption(color: mutedTextColor)),
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
              separatorBuilder: (_, __) => const SizedBox(height: 12),
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