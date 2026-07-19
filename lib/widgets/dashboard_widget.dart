import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../models/dashboard_stats.dart';

/// ==================================================================
/// SEMI-CIRCULAR GAUGE — Inspection Completion Rate
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
    final percentLabel = '${(clamped * 100).round()}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('INSPECTION COMPLETION RATE',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: mutedTextColor, letterSpacing: 0.6)),
        const SizedBox(height: 14),
        SizedBox(
          height: 110,
          width: double.infinity,
          child: CustomPaint(
            painter: _GaugePainter(progress: clamped, track: trackColor, fill: fillColor),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(percentLabel,
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: textColor)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Divider(height: 1),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _footerStat('Total Applications', '$totalApplications', textColor, mutedTextColor),
            _footerStat('Active Workload', '$activeWorkload', textColor, mutedTextColor),
          ],
        ),
      ],
    );
  }

  Widget _footerStat(String label, String value, Color textColor, Color mutedColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textColor)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 10.5, color: mutedColor)),
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
    final strokeWidth = size.height * 0.20;
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

    // Track: full semicircle from 180° to 360°.
    canvas.drawArc(rect, math.pi, math.pi, false, trackPaint);
    // Fill: proportion of that same semicircle.
    canvas.drawArc(rect, math.pi, math.pi * progress, false, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.fill != fill || oldDelegate.track != track;
}

/// ==================================================================
/// WEEKLY TREND BAR CHART — inspections submitted per day, last 7 days
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
    final maxCount = points.isEmpty ? 1 : points.map((p) => p.count).fold<int>(0, math.max);
    final chartMax = (maxCount < 4 ? 4 : maxCount).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('WEEKLY PERFORMANCE TREND',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: mutedTextColor, letterSpacing: 0.6)),
        const SizedBox(height: 14),
        SizedBox(
          height: 90,
          child: BarChart(
            BarChartData(
              maxY: chartMax,
              alignment: BarChartAlignment.spaceAround,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 20,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= points.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(points[i].label,
                            style: TextStyle(fontSize: 9.5, color: mutedTextColor, fontWeight: FontWeight.w600)),
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
                      color: barColor,
                      width: 14,
                      borderRadius: BorderRadius.circular(5),
                      backDrawRodData: BackgroundBarChartRodData(
                        show: true,
                        toY: chartMax,
                        color: barColor.withOpacity(0.08),
                      ),
                    ),
                  ]),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// ==================================================================
/// ACTIVITY HEATMAP — mini calendar grid, current month
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

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    // Monday-first offset for the 1st of the month.
    final firstWeekday = DateTime(year, month, 1).weekday; // 1 = Mon .. 7 = Sun
    final leadingBlanks = firstWeekday - 1;
    final today = DateTime.now();
    final isCurrentMonth = today.year == year && today.month == month;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ACTIVITY TRACKER',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: mutedTextColor, letterSpacing: 0.6)),
        const SizedBox(height: 2),
        Text('${activeDays.length} days completed',
            style: TextStyle(fontSize: 11.5, color: textColor, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: leadingBlanks + daysInMonth,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemBuilder: (context, index) {
            if (index < leadingBlanks) return const SizedBox.shrink();
            final day = index - leadingBlanks + 1;
            final isActive = activeDays.contains(day);
            final isToday = isCurrentMonth && today.day == day;
            return Container(
              decoration: BoxDecoration(
                color: isActive ? activeColor : inactiveColor,
                borderRadius: BorderRadius.circular(4),
                border: isToday ? Border.all(color: activeColor, width: 1.4) : null,
              ),
              alignment: Alignment.center,
              child: Text(
                '$day',
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w600,
                  color: isActive ? Colors.white : mutedTextColor,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// ==================================================================
/// ZONING TYPE DISTRIBUTION — micro horizontal breakdown rows
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
    final visible = entries.take(4).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ZONING TYPE PROGRESS',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: mutedTextColor, letterSpacing: 0.6)),
        const SizedBox(height: 12),
        if (visible.isEmpty)
          Text('No records yet', style: TextStyle(fontSize: 11.5, color: mutedTextColor))
        else
          Column(
            children: [
              for (final e in visible) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(e.label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textColor)),
                    ),
                    const SizedBox(width: 6),
                    Text('${e.count}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textColor)),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: e.share,
                    minHeight: 6,
                    backgroundColor: trackColor,
                    valueColor: AlwaysStoppedAnimation<Color>(barColor),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
      ],
    );
  }
}
