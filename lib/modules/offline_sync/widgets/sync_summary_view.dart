import 'package:flutter/material.dart';

import '../../../core/theme/insight_theme.dart';
import '../../interactive_guide/guide_targets.dart';

/// No subscriptions or sync/cache actions: the container owns those effects.
class SyncSummaryView extends StatelessWidget {
  const SyncSummaryView({
    super.key,
    required this.headline,
    required this.detail,
    required this.hasWaiting,
    required this.stats,
    this.help,
    this.composition,
    this.action,
  });
  final String headline, detail;
  final bool hasWaiting;
  final List<Widget> stats;
  final Widget? help, composition, action;

  @override
  Widget build(BuildContext context) => GuideTarget(id: 'sync_summary', child: Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: InsightTheme.surface,
      borderRadius: InsightTheme.roundedLg,
      border: Border.all(color: InsightTheme.line),
      boxShadow: InsightTheme.cardShadow,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: hasWaiting
                    ? InsightTheme.blueTint
                    : InsightTheme.greenTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                hasWaiting ? Icons.sync_rounded : Icons.cloud_done_rounded,
                size: 22,
                color: hasWaiting ? InsightTheme.blue1 : InsightTheme.greenInk,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    headline,
                    style: InsightTheme.urbanist(
                      20,
                      w: FontWeight.w800,
                      c: InsightTheme.ink,
                      ls: -0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    style: InsightTheme.inter(12, c: InsightTheme.ink3),
                  ),
                ],
              ),
            ),
            ?help,
          ],
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < stats.length; i++) ...[
              if (i != 0) const SizedBox(width: 8),
              Expanded(child: stats[i]),
            ],
          ],
        ),
        ?composition,
        ?action,
      ],
    ),
  ));
}

class SyncStatItem extends StatelessWidget {
  const SyncStatItem({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.backgroundColor,
  });
  final String label, value;
  final Color? valueColor, backgroundColor;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 58),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    decoration: BoxDecoration(
      color: backgroundColor ?? InsightTheme.surface2.withValues(alpha: 0.65),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: InsightTheme.line.withValues(alpha: 0.5)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          value,
          style: InsightTheme.urbanist(
            16,
            w: FontWeight.w800,
            c: valueColor ?? InsightTheme.ink,
            h: 1.2,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          softWrap: true,
          style: InsightTheme.inter(
            11,
            w: FontWeight.w600,
            c: InsightTheme.ink3,
            h: 1.25,
          ),
        ),
      ],
    ),
  );
}

class SyncLegendItem extends StatelessWidget {
  const SyncLegendItem({
    super.key,
    required this.color,
    required this.label,
    required this.value,
  });
  final Color color;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 5),
      Text(
        '$label $value',
        style: InsightTheme.inter(
          10.5,
          w: FontWeight.w600,
          c: InsightTheme.ink3,
        ),
      ),
    ],
  );
}
