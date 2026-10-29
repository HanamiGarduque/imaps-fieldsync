import 'package:flutter/material.dart';

import '../../../core/theme/insight_theme.dart';
import '../models/task_lifecycle.dart';

// Display priority only; the canonical presentation owns notice membership.
List<MyTaskNotice> _orderedNotices(MyTaskPresentation p) => [
  for (final notice in const [
    MyTaskNotice.deadlinePassed, MyTaskNotice.scheduleConflict,
    MyTaskNotice.deadlineToday, MyTaskNotice.visitMissed,
    MyTaskNotice.visitToday, MyTaskNotice.visitTomorrow,
    MyTaskNotice.deadlineInDays, MyTaskNotice.visitInDays,
  ])
    if (p.notices.contains(notice)) notice,
];

String _noticeLabel(MyTaskPresentation p, MyTaskNotice notice) => switch (notice) {
  MyTaskNotice.deadlinePassed => 'Overdue',
  MyTaskNotice.scheduleConflict => 'Visit after PO Deadline',
  MyTaskNotice.deadlineToday => 'PO Deadline today',
  MyTaskNotice.visitMissed => 'Missed visit · Reschedule available',
  MyTaskNotice.visitToday => 'Visit today',
  MyTaskNotice.visitTomorrow => 'Visit tomorrow',
  MyTaskNotice.deadlineInDays =>
    'PO Deadline in ${p.deadlineDaysUntil} ${p.deadlineDaysUntil == 1 ? 'day' : 'days'}',
  MyTaskNotice.visitInDays => 'Visit in ${p.visitDaysUntil} days',
};

bool hasCriticalTaskNotice(MyTaskPresentation p) => p.notices.any(
  (notice) => switch (notice) {
    MyTaskNotice.deadlinePassed || MyTaskNotice.scheduleConflict ||
    MyTaskNotice.deadlineToday || MyTaskNotice.visitMissed ||
    MyTaskNotice.visitToday || MyTaskNotice.visitTomorrow => true,
    MyTaskNotice.deadlineInDays => p.deadlineDaysUntil == 1,
    _ => false,
  },
);

String formatTaskNoticeDate(DateTime? day) {
  if (day == null) return 'Not verified';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[day.month - 1]} ${day.day}, ${day.year}';
}

/// One summary, with the same disclosure available from either task surface.
class TaskNoticeSummary extends StatelessWidget {
  const TaskNoticeSummary({super.key, required this.presentation,
    required this.applicantName, required this.onDetails, this.inset = false});

  final MyTaskPresentation presentation;
  final String applicantName;
  final VoidCallback onDetails;
  final bool inset;

  @override
  Widget build(BuildContext context) {
    final p = presentation;
    if (!p.isActive) return const SizedBox.shrink();
    final labels = [
      if (!p.canSchedule && (p.deadlineState == MyTaskDeadlineState.none ||
          p.deadlineState == MyTaskDeadlineState.unknown))
        'PO Deadline not verified',
      for (final notice in _orderedNotices(p)) _noticeLabel(p, notice),
    ];
    if (labels.isEmpty) return const SizedBox.shrink();
    final critical = hasCriticalTaskNotice(p);
    final color = critical ? InsightTheme.redInk
        : p.notices.isEmpty ? InsightTheme.ink3 : InsightTheme.orangeInk;
    final extra = labels.length - 2;
    return Padding(
      padding: inset ? const EdgeInsets.fromLTRB(36, 12, 36, 8)
          : const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (!inset) const Divider(height: 1, color: InsightTheme.line),
        Semantics(
          label: 'Scheduling notices for $applicantName',
          button: true,
          child: Material(
            color: !inset ? Colors.transparent : critical ? InsightTheme.redTint
                : p.notices.isEmpty ? InsightTheme.surface2 : InsightTheme.orangeTint,
            borderRadius: InsightTheme.roundedSm,
            child: InkWell(
              onTap: onDetails,
              borderRadius: InsightTheme.roundedSm,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: inset ? 12 : 0, vertical: 8),
                  child: Row(children: [
                    Icon(critical ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
                        size: 20, color: color),
                    const SizedBox(width: 8),
                    Expanded(child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(labels.take(2).join(' · '),
                            style: InsightTheme.inter(12, w: FontWeight.w700, c: color, h: 1.5)),
                        if (extra > 0)
                          Text('+$extra more ${extra == 1 ? 'notice' : 'notices'}',
                              style: InsightTheme.inter(12, c: InsightTheme.ink3)),
                      ],
                    )),
                    const SizedBox(width: 8),
                    if (inset) Text('Details',
                        style: InsightTheme.inter(12, w: FontWeight.w700, c: color)),
                    Icon(Icons.chevron_right_rounded, size: 18, color: color),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

Future<void> showTaskNoticeDetails(BuildContext context, {
  required MyTaskPresentation presentation,
  required String applicantName,
  required String referenceNumber,
  String? roundLabel,
  String? borderExplanation,
}) {
  final p = presentation;
  final scheduled = p.lifecycle == MyTaskLifecycle.scheduled;
  final entries = <(String, String)>[
    if (scheduled) ('Visit date', formatTaskNoticeDate(p.visitDay)),
    ('PO Deadline', formatTaskNoticeDate(p.deadlineDay)),
    for (final notice in _orderedNotices(p))
      (_noticeLabel(p, notice), p.noticeText(notice)),
    ('Next action', p.scheduleBlockReason ??
        'Continue your inspection before the PO Deadline. To ${scheduled ? 'reschedule' : 'schedule'} a Visit, choose a date from tomorrow through the verified PO Deadline.'),
    if (scheduled)
      ('Scheduled', 'You have chosen a visit date for this task. The task stays Scheduled until the inspection is completed and submitted. You can reschedule the visit when needed, as long as the new date is still allowed by the deadline.'),
    if (p.showInProgress)
      ('In Progress', 'You have already started this scheduled inspection. Continue working through the remaining steps until it is completed.'),
    if (p.lifecycle == MyTaskLifecycle.ongoing)
      ('Ongoing', 'This task is already being worked on, but no fixed visit date was set. You can continue the inspection without scheduling a visit.'),
    if (p.lifecycle == MyTaskLifecycle.availableAnytime)
      ('Available Anytime', 'This task does not have a fixed visit date yet. You can inspect it anytime before the admin-set deadline. If you want a specific visit date, you can schedule one.'),
    if (borderExplanation != null) ('Border color', borderExplanation),
  ];
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: InsightTheme.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: InsightTheme.roundedMd),
      title: Text('Task details', style: InsightTheme.urbanist(22)),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      content: SizedBox(width: 360, child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(applicantName, style: InsightTheme.inter(15, w: FontWeight.w700, c: InsightTheme.ink)),
            const SizedBox(height: 4),
            Text([referenceNumber, ?roundLabel].join(' · '),
                style: InsightTheme.inter(12, c: InsightTheme.ink3)),
            const SizedBox(height: 16),
            for (final (title, body) in entries) ...[
              Text(title, style: InsightTheme.inter(13, w: FontWeight.w700, c: InsightTheme.ink)),
              const SizedBox(height: 4),
              Text(body, style: InsightTheme.inter(13, c: InsightTheme.ink2)),
              const SizedBox(height: 16),
            ],
          ],
        ),
      )),
      actions: [TextButton(
        style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
        onPressed: () => Navigator.pop(dialogContext),
        child: Text('Close', style: InsightTheme.inter(14, w: FontWeight.w700, c: InsightTheme.blueInk)),
      )],
    ),
  );
}
