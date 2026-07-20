import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../models/dashboard_stats.dart';

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

const _kLabelStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8);
const _kCaptionStyle = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500);

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
        children.add(Container(width: 1, height: 28, color: dividerColor, margin: const EdgeInsets.symmetric(horizontal: 12)));
      }
      final (label, value) = items[i];
      children.add(
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: textColor)),
              const SizedBox(height: 2),
              Text(label, style: _kCaptionStyle.copyWith(color: mutedTextColor), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      );
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}

/// ==================================================================
/// COMPLETION RATE — big KPI number up top for instant scanning, the
/// gauge itself carries a qualitative status word instead of repeating
/// the same percentage a second time.
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

  String get _status {
    final r = rate.isNaN ? 0.0 : rate;
    if (r >= 0.8) return 'Excellent';
    if (r >= 0.5) return 'On Track';
    if (r > 0) return 'Needs Attention';
    return 'No Data Yet';
  }

  @override
  Widget build(BuildContext context) {
    final clamped = rate.isNaN ? 0.0 : rate.clamp(0.0, 1.0);
    final percentLabel = '${(clamped * 100).round()}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('COMPLETION RATE', style: _kLabelStyle.copyWith(color: mutedTextColor)),
                  const SizedBox(height: 6),
                  Text(percentLabel, style: TextStyle(fontSize: 38, fontWeight: FontWeight.w800, color: textColor, height: 1)),
                ],
              ),
            ),
            Text('Updated today', style: _kCaptionStyle.copyWith(color: mutedTextColor)),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: _GaugePainter(progress: clamped, track: trackColor, fill: fillColor),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: fillColor)),
                        const SizedBox(width: 6),
                        Text(_status, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: textColor)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Divider(height: 1, color: trackColor),
        const SizedBox(height: 12),
        _StatRow(
          items: [
            ('Applications', '$totalApplications'),
            ('Active', '$activeWorkload'),
          ],
          textColor: textColor,
          mutedTextColor: mutedTextColor,
          dividerColor: trackColor,
        ),
      ],
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double progress; // 0.0 - 1.0
  final Color track;
  final Color fill;

  _GaugePainter({required this.progress, required this.track, required this.fill});

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = math.max(14.0, size.height * 0.16);
    final radius = math.min(size.width / 2, size.height) - strokeWidth / 2;
    final center = Offset(size.width / 2, size.height);
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..shader = SweepGradient(
        colors: [fill.withOpacity(0.55), fill],
        startAngle: math.pi,
        endAngle: 2 * math.pi,
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, math.pi, math.pi, false, trackPaint);
    canvas.drawArc(rect, math.pi, math.pi * progress, false, fillPaint);

    // End-of-progress marker dot — small design detail that makes the
    // gauge read as a deliberate instrument, not a plain arc.
    if (progress > 0.01) {
      final angle = math.pi + math.pi * progress;
      final dot = Offset(center.dx + radius * math.cos(angle), center.dy + radius * math.sin(angle));
      canvas.drawCircle(dot, strokeWidth * 0.42, Paint()..color = Colors.white);
      canvas.drawCircle(dot, strokeWidth * 0.42, Paint()..color = fill..style = PaintingStyle.stroke..strokeWidth = 2.5);
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
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
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('WEEKLY PERFORMANCE', style: _kLabelStyle.copyWith(color: mutedTextColor)),
        const SizedBox(height: 4),
        Text('Inspections submitted per day', style: _kCaptionStyle.copyWith(color: mutedTextColor)),
        const SizedBox(height: 14),
        Expanded(
          child: BarChart(
            BarChartData(
              maxY: chartMax,
              alignment: BarChartAlignment.spaceAround,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: (chartMax / 4).clamp(1, double.infinity),
                getDrawingHorizontalLine: (_) => FlLine(color: mutedTextColor.withOpacity(0.08), strokeWidth: 1),
              ),
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
    final today = DateTime.now();
    final isCurrentMonth = today.year == year && today.month == month;
    final monthlyPct = daysInMonth == 0 ? 0 : ((activeDays.length / daysInMonth) * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('ACTIVITY TRACKER', style: _kLabelStyle.copyWith(color: mutedTextColor)),
        const SizedBox(height: 4),
        Text('${activeDays.length} of $daysInMonth days completed',
            style: TextStyle(fontSize: 14.5, color: textColor, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Expanded(
                child: Center(
                  child: Text(d, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: mutedTextColor)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            itemCount: leadingBlanks + daysInMonth,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
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
                    fontSize: 11.5,
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

  const ZoningTypeBreakdownCard({
    super.key,
    required this.entries,
    required this.barColor,
    required this.trackColor,
    required this.textColor,
    required this.mutedTextColor,
  });

  @override
  Widget build(BuildContext context) {
    final visible = entries.take(5).toList();
    final total = entries.fold<int>(0, (sum, e) => sum + e.count);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('ZONING DISTRIBUTION', style: _kLabelStyle.copyWith(color: mutedTextColor)),
        const SizedBox(height: 4),
        Text('Share of assigned applications', style: _kCaptionStyle.copyWith(color: mutedTextColor)),
        const SizedBox(height: 14),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Text('No records yet', style: TextStyle(fontSize: 14, color: mutedTextColor)),
                )
              : ListView.separated(
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (context, i) {
                    final e = visible[i];
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 92,
                          child: Text(e.label,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor)),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: e.share,
                              minHeight: 12,
                              backgroundColor: trackColor,
                              valueColor: AlwaysStoppedAnimation<Color>(barColor),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 26,
                          child: Text('${e.count}',
                              textAlign: TextAlign.right,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textColor)),
                        ),
                      ],
                    );
                  },
                ),
        ),
        const SizedBox(height: 12),
        Divider(height: 1, color: trackColor),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Total Inspections', style: _kCaptionStyle.copyWith(color: mutedTextColor, fontWeight: FontWeight.w600)),
            Text('$total', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: textColor)),
          ],
        ),
      ],
    );
  }
}