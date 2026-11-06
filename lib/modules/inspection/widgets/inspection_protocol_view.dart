import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/insight_theme.dart';
import '../../interactive_guide/guide_targets.dart';

class InspectionProtocolStep {
  const InspectionProtocolStep({
    required this.index,
    required this.title,
    required this.description,
    required this.icon,
    this.onTap,
    this.done = false,
    this.current = false,
    this.locked = true,
    this.savedAt,
  });
  final int index;
  final String title, description;
  final IconData icon;
  final VoidCallback? onTap;
  final bool done, current, locked;
  final String? savedAt;
}

/// Presentation only: the owning screen projects progress and authorizes taps.
class InspectionProtocolView extends StatelessWidget {
  const InspectionProtocolView({
    super.key,
    required this.steps,
    required this.completedCount,
    this.isComplete = false,
    this.currentLabel = 'Start Task',
  });
  final List<InspectionProtocolStep> steps;
  final int completedCount;
  final bool isComplete;
  final String currentLabel;

  @override
  Widget build(BuildContext context) {
    final fraction = isComplete ? 1.0 : completedCount.clamp(0, 6) / 6;
    return GuideTarget(id: 'inspection_protocol', child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: InsightTheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: kCardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'INSPECTION PROTOCOL',
              style: InsightTheme.jetBrains(
                10,
                w: FontWeight.w700,
                c: InsightTheme.ink3,
                ls: 1,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: InsightTheme.surface2,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: fraction,
                      child: Container(
                        decoration: BoxDecoration(
                          color: InsightTheme.blue1,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${(fraction * 100).toInt()}%',
                  style: InsightTheme.jetBrains(
                    11,
                    w: FontWeight.w700,
                    c: InsightTheme.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (completedCount >= 2) ...[
              Text(
                'Steps 3–5 are independent: open them in any order and come back to the rest. Each step keeps its own saved status.',
                style: InsightTheme.inter(11, c: InsightTheme.ink3),
              ),
              const SizedBox(height: 12),
            ],
            for (var i = 0; i < steps.length; i++)
              GuideTarget(
                id: 'protocol_step_${steps[i].index}',
                child: _ProtocolRow(
                  step: steps[i],
                  isLast: i == steps.length - 1,
                  isComplete: isComplete,
                  currentLabel: currentLabel,
                ),
              ),
          ],
        ),
    ));
  }
}

class _ProtocolRow extends StatelessWidget {
  const _ProtocolRow({
    required this.step,
    required this.isLast,
    required this.isComplete,
    required this.currentLabel,
  });
  final InspectionProtocolStep step;
  final bool isLast, isComplete;
  final String currentLabel;

  String _formatSavedAt(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
      return '${months[dt.month - 1]} ${dt.day}, $hour:${dt.minute.toString().padLeft(2, '0')} ${dt.hour >= 12 ? 'PM' : 'AM'}';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = step.current && !isComplete;
    final done = step.done || isComplete;
    final markerSize = MediaQuery.textScalerOf(context).scale(12) * 2 + 8;
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 6),
      constraints: const BoxConstraints(minHeight: 48),
      decoration: BoxDecoration(
        color: current ? InsightTheme.surface2 : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: step.onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  step.onTap!();
                },
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    children: [
                      Container(
                        width: markerSize,
                        height: markerSize,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: done
                              ? InsightTheme.greenTint
                              : current
                              ? InsightTheme.blue1
                              : InsightTheme.surface2,
                        ),
                        child: Text(
                          step.index.toString().padLeft(2, '0'),
                          style: InsightTheme.inter(
                            12,
                            w: FontWeight.w700,
                            c: done
                                ? InsightTheme.greenInk
                                : current
                                ? Colors.white
                                : InsightTheme.ink3,
                          ),
                        ),
                      ),
                      if (!isLast)
                        Expanded(
                          child: Container(
                            width: 2,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            color: done
                                ? InsightTheme.green.withValues(alpha: 0.35)
                                : InsightTheme.line,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: isLast ? 0 : 4, top: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                step.title,
                                style: InsightTheme.poppins(
                                  13.5,
                                  w: FontWeight.w600,
                                  c: step.locked
                                      ? InsightTheme.ink3
                                      : InsightTheme.ink,
                                ),
                              ),
                              if (step.locked)
                                const Icon(
                                  Icons.lock_outline_rounded,
                                  size: 14,
                                  color: InsightTheme.ink3,
                                ),
                              if (current)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: InsightTheme.blue1,
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x283563FF),
                                        blurRadius: 6,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    currentLabel,
                                    style: InsightTheme.inter(
                                      10.5,
                                      w: FontWeight.w700,
                                      c: Colors.white,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          if (done)
                            Row(
                              children: [
                                const Icon(
                                  Icons.verified_rounded,
                                  size: 12,
                                  color: InsightTheme.greenInk,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    step.savedAt == null
                                        ? 'Completed'
                                        : 'Saved on ${_formatSavedAt(step.savedAt!)}',
                                    style: InsightTheme.inter(
                                      11,
                                      w: FontWeight.w500,
                                      c: InsightTheme.greenInk,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else
                            Text(
                              step.description,
                              style: InsightTheme.inter(
                                11,
                                w: FontWeight.w400,
                                c: step.locked
                                    ? InsightTheme.ink3
                                    : InsightTheme.ink2,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
