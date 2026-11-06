import 'package:flutter/material.dart';

import '../../../core/theme/insight_theme.dart';

class TaskCardHeader extends StatelessWidget {
  const TaskCardHeader({
    super.key,
    required this.name,
    required this.reference,
    required this.leading,
    required this.controls,
  });
  final String name, reference;
  final Widget leading, controls;

  @override
  Widget build(BuildContext context) {
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: InsightTheme.urbanist(
            16.5,
            w: FontWeight.w800,
            c: InsightTheme.ink,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 3),
        Text(
          reference,
          style: InsightTheme.inter(
            12,
            w: FontWeight.w600,
            c: InsightTheme.ink3,
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 270 ||
            (constraints.maxWidth < 480 &&
                MediaQuery.textScalerOf(context).scale(12) >= 18);
        return stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [leading, const Spacer(), controls]),
                  const SizedBox(height: 8),
                  identity,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  leading,
                  const SizedBox(width: 12),
                  Expanded(child: identity),
                  controls,
                ],
              );
      },
    );
  }
}

class TaskDateFields extends StatelessWidget {
  const TaskDateFields({
    super.key,
    this.visitDate,
    required this.deadline,
    this.isOverdue = false,
  });
  final String? visitDate;
  final String deadline;
  final bool isOverdue;

  Widget _date(
    String label,
    String value, {
    bool deadlineField = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(
            deadlineField ? Icons.outlined_flag : Icons.calendar_today_outlined,
            size: 14,
            color: deadlineField && isOverdue
                ? InsightTheme.redInk
                : InsightTheme.ink3,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: InsightTheme.inter(
              11.5,
              w: FontWeight.w500,
              c: deadlineField && isOverdue
                  ? InsightTheme.redInk
                  : InsightTheme.ink3,
            ),
          ),
        ],
      ),
      const SizedBox(height: 3),
      Text(
        value,
        style: InsightTheme.inter(
          13.5,
          w: deadlineField ? FontWeight.w800 : FontWeight.w700,
          c: deadlineField && isOverdue ? InsightTheme.red : InsightTheme.ink,
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final twoColumns =
          visitDate != null &&
          constraints.maxWidth >= 240 &&
          MediaQuery.textScalerOf(context).scale(12) < 18;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: InsightTheme.surface2.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: InsightTheme.line.withValues(alpha: 0.5)),
        ),
        child: twoColumns
            ? Row(
                children: [
                  Expanded(child: _date('Visit date', visitDate!)),
                  Container(
                    width: 1,
                    height: 28,
                    color: InsightTheme.line.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _date('PO Deadline', deadline, deadlineField: true),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (visitDate != null) ...[
                    _date('Visit date', visitDate!),
                    const SizedBox(height: 8),
                  ],
                  _date('PO Deadline', deadline, deadlineField: true),
                ],
              ),
      );
    },
  );
}

class TaskProgressView extends StatelessWidget {
  const TaskProgressView({
    super.key,
    required this.step,
    required this.color,
    this.statusLabel,
    this.deliveryBadge = false,
  });
  final int step;
  final Color color;
  final String? statusLabel;
  final bool deliveryBadge;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (statusLabel != null)
            Expanded(
              child: deliveryBadge
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        statusLabel!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: InsightTheme.inter(
                          12,
                          w: FontWeight.w700,
                          c: color,
                        ),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            statusLabel!,
                            style: InsightTheme.inter(
                              13,
                              w: FontWeight.w700,
                              c: InsightTheme.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
            )
          else
            const SizedBox.shrink(),
          const SizedBox(width: 8),
          Text(
            'STEP $step/6',
            textAlign: TextAlign.end,
            style: InsightTheme.inter(
              11.5,
              w: FontWeight.w700,
              c: InsightTheme.ink3,
              ls: 0.5,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: LinearProgressIndicator(
          value: step.clamp(0, 6) / 6,
          minHeight: 4.5,
          backgroundColor: InsightTheme.surface2,
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
    ],
  );
}

/// A display projection, not a TaskItem: no identity, scheduling or persistence.
class TaskCardContent extends StatelessWidget {
  const TaskCardContent({
    super.key,
    required this.name,
    required this.reference,
    required this.location,
    this.visitDate,
    required this.deadline,
    required this.statusLabel,
    required this.step,
    required this.statusColor,
  });
  final String name, reference, location, deadline, statusLabel;
  final String? visitDate;
  final int step;
  final Color statusColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: InsightTheme.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: statusColor, width: 1.4),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TaskCardHeader(
          name: name,
          reference: reference,
          leading: Icon(
            Icons.assignment_outlined,
            color: statusColor,
            size: 46,
          ),
          controls: const Icon(
            Icons.info_outline_rounded,
            color: InsightTheme.blueInk,
          ),
        ),
        const SizedBox(height: 8),
        Text(location, style: InsightTheme.inter(12, w: FontWeight.w600)),
        const SizedBox(height: 12),
        TaskDateFields(visitDate: visitDate, deadline: deadline),
        const SizedBox(height: 12),
        TaskProgressView(
          step: step,
          color: statusColor,
          statusLabel: statusLabel,
        ),
      ],
    ),
  );
}
