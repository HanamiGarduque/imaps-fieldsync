import 'package:flutter/material.dart';

import '../../../core/theme/insight_theme.dart';
import '../../../core/widgets/field_form_widgets.dart';
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

String _noticeLabel(MyTaskPresentation p, MyTaskNotice notice,
    {bool isTagalog = false}) => switch (notice) {
  MyTaskNotice.deadlinePassed =>
    isTagalog ? 'Lampas sa deadline' : 'Overdue',
  MyTaskNotice.scheduleConflict =>
    isTagalog ? 'Visit lampas sa PO Deadline' : 'Visit after PO Deadline',
  MyTaskNotice.deadlineToday =>
    isTagalog ? 'PO Deadline ngayong araw' : 'PO Deadline today',
  MyTaskNotice.visitMissed => isTagalog
      ? 'Hindi natuloy ang Visit · Maaari pang magtakda muli'
      : 'Missed visit · Reschedule available',
  MyTaskNotice.visitToday => isTagalog ? 'Visit ngayong araw' : 'Visit today',
  MyTaskNotice.visitTomorrow => isTagalog ? 'Visit bukas' : 'Visit tomorrow',
  MyTaskNotice.deadlineInDays => isTagalog
      ? 'PO Deadline sa ${p.deadlineDaysUntil} ${p.deadlineDaysUntil == 1 ? 'araw' : 'araw'}'
      : 'PO Deadline in ${p.deadlineDaysUntil} ${p.deadlineDaysUntil == 1 ? 'day' : 'days'}',
  MyTaskNotice.visitInDays =>
    isTagalog ? 'Visit sa ${p.visitDaysUntil} araw' : 'Visit in ${p.visitDaysUntil} days',
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

String formatTaskNoticeDate(DateTime? day, {bool isTagalog = false}) {
  if (day == null) return isTagalog ? 'Hindi pa nakukumpirma' : 'Not verified';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  if (!isTagalog) return '${months[day.month - 1]} ${day.day}, ${day.year}';
  const monthsTl = ['Ene', 'Peb', 'Mar', 'Abr', 'May', 'Hun',
    'Hul', 'Ago', 'Set', 'Okt', 'Nob', 'Dis'];
  return '${day.day} ${monthsTl[day.month - 1]} ${day.year}';
}

class TaskLanguageSelector extends StatelessWidget {
  const TaskLanguageSelector({
    super.key,
    required this.isTagalog,
    required this.onChanged,
  });

  final bool isTagalog;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => FieldSegmentedControl<bool>(
    labels: const {false: 'English', true: 'Tagalog'},
    value: isTagalog,
    onChanged: onChanged,
    compact: true,
  );
}

String _currentTaskStatus(MyTaskPresentation p, bool isTagalog) {
  if (!isTagalog) {
    return switch (p.lifecycle) {
      MyTaskLifecycle.scheduled => p.showInProgress
          ? 'Scheduled · In Progress. Your chosen Visit date stays in place while the inspection is underway.'
          : 'Scheduled. You have chosen a Visit date for this inspection.',
      MyTaskLifecycle.availableAnytime =>
        'Available Anytime. No Visit date has been chosen. You may inspect before the PO Deadline.',
      MyTaskLifecycle.ongoing =>
        'Ongoing. Inspection work has started without a fixed Visit date.',
      MyTaskLifecycle.completed =>
        'Completed. This task is no longer available for visit scheduling.',
      MyTaskLifecycle.unknown =>
        'Status unavailable. The recorded task state could not be recognized.',
    };
  }
  return switch (p.lifecycle) {
    MyTaskLifecycle.scheduled => p.showInProgress
        ? 'Naka-iskedyul · Sinimulan na. Mananatili ang pinili mong petsa ng Visit habang isinasagawa ang inspeksiyon.'
        : 'Naka-iskedyul. Pumili ka ng petsa ng Visit para sa inspeksiyong ito.',
    MyTaskLifecycle.availableAnytime =>
      'Available Anytime. Wala pang napiling petsa ng Visit. Maaari kang mag-inspeksiyon bago ang PO Deadline.',
    MyTaskLifecycle.ongoing =>
      'Kasalukuyang isinasagawa. Nagsimula na ang inspeksiyon ngunit wala itong takdang petsa ng Visit.',
    MyTaskLifecycle.completed =>
      'Kumpleto na. Hindi na maaaring magtakda ng Visit para sa gawaing ito.',
    MyTaskLifecycle.unknown =>
      'Hindi matukoy ang status. Hindi makilala ang naitalang kalagayan ng task.',
  };
}

String _scheduleBlockReason(MyTaskPresentation p, bool isTagalog) {
  if (!isTagalog) {
    return p.scheduleBlockReason ??
        'No current Visit or PO Deadline warning requires additional action.';
  }
  if (p.lifecycle == MyTaskLifecycle.completed) {
    return 'Kumpleto na ang inspeksiyong ito.';
  }
  if (p.lifecycle == MyTaskLifecycle.unknown) {
    return 'Hindi maiskedyul ang task na ito dahil hindi makilala ang status nito.';
  }
  if (p.deadlineState == MyTaskDeadlineState.none ||
      p.deadlineState == MyTaskDeadlineState.unknown) {
    return 'Hindi makumpirma ang PO Deadline, kaya hindi magagamit ang pag-iskedyul. Ipagpatuloy ang inspeksiyon o humingi ng kumpirmasyon sa Planning Office.';
  }
  if (p.deadlineState == MyTaskDeadlineState.today ||
      p.deadlineState == MyTaskDeadlineState.passed) {
    return 'Ngayong araw na o lumampas na ang PO Deadline. Hindi maaaring magtakda ng panibagong Visit.';
  }
  return 'Walang kasalukuyang babala sa Visit o PO Deadline na nangangailangan ng karagdagang hakbang.';
}

String _taskDetailsNextAction(MyTaskPresentation p, bool isTagalog) {
  if (p.lifecycle == MyTaskLifecycle.completed) {
    return isTagalog
        ? 'Suriin ang natapos na inspeksiyon at tingnan sa Sync Center kung naihatid ito. Hindi katumbas ng resibo mula sa opisina ang lokal na pag-save.'
        : 'Review the completed inspection and check Sync Center for delivery confirmation. A local save is not an office receipt.';
  }
  if (p.lifecycle == MyTaskLifecycle.unknown) {
    return isTagalog
        ? 'I-refresh ang iyong mga assignment o makipag-ugnayan sa Planning Office. Huwag magtakda ng Visit hangga’t hindi nakukumpirma ang status.'
        : 'Refresh your assignments or contact the Planning Office. Do not schedule a Visit until the task status is verified.';
  }
  if (p.deadlineState == MyTaskDeadlineState.passed) {
    return isTagalog
        ? 'Ipagpatuloy lamang ang inspeksiyon kung awtorisado ka pa, o makipag-ugnayan sa Planning Officer. Hindi mabubura ang ebidensiyang lokal nang na-save.'
        : 'Continue the inspection only if you are still authorized, or coordinate with the Planning Officer. Existing locally saved evidence is not deleted.';
  }
  if (p.deadlineState == MyTaskDeadlineState.today) {
    return isTagalog
        ? 'Ipagpatuloy lamang ang inspeksiyon kung awtorisado ka pa, o makipag-ugnayan sa Planning Officer tungkol sa deadline. Hindi pa overdue ang task ngayong araw.'
        : 'Continue the inspection only if you are still authorized, or contact the Planning Officer about the deadline. The task is not overdue today.';
  }
  if (p.deadlineState == MyTaskDeadlineState.none ||
      p.deadlineState == MyTaskDeadlineState.unknown) {
    return isTagalog
        ? 'I-refresh ang iyong mga assignment o ipakumpirma sa Planning Office ang PO Deadline. Ipagpatuloy lamang ang kasalukuyang inspeksiyon habang awtorisado.'
        : 'Refresh your assignments or ask the Planning Office to confirm the PO Deadline. Continue existing inspection work only while authorized.';
  }
  if (p.lifecycle == MyTaskLifecycle.scheduled) {
    return isTagalog
        ? 'Ipagpatuloy ang inspeksiyon bago ang PO Deadline. Para magtakda muli ng Visit, pumili ng petsa mula bukas hanggang sa nakumpirmang PO Deadline.'
        : 'Continue the inspection before the PO Deadline. To reschedule your Visit, choose a date from tomorrow through the verified PO Deadline.';
  }
  if (p.lifecycle == MyTaskLifecycle.availableAnytime) {
    return isTagalog
        ? 'Ipagpatuloy ang inspeksiyon kapag handa ka na. Para magtakda ng Visit, pumili ng petsa mula bukas hanggang sa nakumpirmang PO Deadline.'
        : 'Continue the inspection when ready. To set a Visit, choose a date from tomorrow through the verified PO Deadline.';
  }
  return isTagalog
      ? 'Ipagpatuloy ang inspeksiyon at isumite ang mga natuklasan bago ang PO Deadline.'
      : 'Continue the inspection and submit your findings before the PO Deadline.';
}

String _taskNoticeText(MyTaskPresentation p, MyTaskNotice notice,
    bool isTagalog) {
  if (!isTagalog) return p.noticeText(notice);
  return switch (notice) {
    MyTaskNotice.visitInDays =>
      'Nakatakda ang Visit sa loob ng ${p.visitDaysUntil} araw — ihanda ang inspeksiyon sa lugar.',
    MyTaskNotice.visitTomorrow => 'Nakatakda ang Visit bukas.',
    MyTaskNotice.visitToday =>
      'Nakatakda ang Visit ngayong araw — maaari nang simulan ang inspeksiyon.',
    MyTaskNotice.visitMissed =>
      'Lumampas na ang napiling petsa ng Visit. Magtakda muli bago ang PO Deadline o ipagpatuloy ang inspeksiyon.',
    MyTaskNotice.deadlineInDays =>
      'PO Deadline sa ${p.deadlineDaysUntil} araw.',
    MyTaskNotice.deadlineToday =>
      'Ngayong araw ang PO Deadline. Hindi maaaring magtakda muli; tapusin ang inspeksiyon. Hindi pa ito overdue.',
    MyTaskNotice.deadlinePassed =>
      'Overdue — lumampas na ang PO Deadline.',
    MyTaskNotice.scheduleConflict =>
      'Lampas sa PO Deadline ang petsa ng Visit. Makipag-ugnayan sa Planning Officer; pumili lamang ng petsang pinapayagan kapag bukas ang pag-iskedyul.',
  };
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
  String? borderExplanationTagalog,
}) {
  final p = presentation;
  final scheduled = p.lifecycle == MyTaskLifecycle.scheduled;
  final orderedNotices = _orderedNotices(p);
  var isTagalog = false;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        final currentStatus = _currentTaskStatus(p, isTagalog);
        final reason = _scheduleBlockReason(p, isTagalog);
        final nextAction = _taskDetailsNextAction(p, isTagalog);
        final visitDateTitle = isTagalog ? 'Petsa ng Visit' : 'Visit date';
        final reasonTitle = isTagalog ? 'Dahilan' : 'Reason';
        final entries = <(String, String)>[
          (isTagalog ? 'Kasalukuyang status' : 'Current Status', currentStatus),
          if (scheduled)
            (visitDateTitle,
                formatTaskNoticeDate(p.visitDay, isTagalog: isTagalog)),
          ('PO Deadline',
              formatTaskNoticeDate(p.deadlineDay, isTagalog: isTagalog)),
          if (orderedNotices.isEmpty) (reasonTitle, reason),
          for (final notice in orderedNotices)
            (
              _noticeLabel(p, notice, isTagalog: isTagalog),
              _taskNoticeText(p, notice, isTagalog),
            ),
          (isTagalog ? 'Susunod na hakbang' : 'Next action', nextAction),
          if (borderExplanation != null)
            (
              isTagalog ? 'Kulay ng border' : 'Border color',
              isTagalog
                  ? borderExplanationTagalog ?? borderExplanation
                  : borderExplanation,
            ),
        ];
        final firstDateTitle = scheduled ? visitDateTitle : 'PO Deadline';
        final firstNoticeTitle = orderedNotices.isEmpty
            ? null
            : _noticeLabel(p, orderedNotices.first, isTagalog: isTagalog);
        return AlertDialog(
          backgroundColor: InsightTheme.surface,
          surfaceTintColor: Colors.transparent,
          scrollable: true,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: InsightTheme.roundedMd),
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  isTagalog ? 'Mga detalye ng task' : 'Task details',
                  style: InsightTheme.urbanist(22),
                ),
              ),
              const SizedBox(width: 8),
              TaskLanguageSelector(
                isTagalog: isTagalog,
                onChanged: (value) =>
                    setDialogState(() => isTagalog = value),
              ),
            ],
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          content: SizedBox(
            width: 360,
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
                  if (title == firstDateTitle) ...[
                    Text(isTagalog ? 'Mahahalagang petsa' : 'Important Dates',
                        style: InsightTheme.inter(13, w: FontWeight.w700, c: InsightTheme.blueInk)),
                    const SizedBox(height: 12),
                  ],
                  if (firstNoticeTitle != null && title == firstNoticeTitle) ...[
                    Text(reasonTitle, style: InsightTheme.inter(13, w: FontWeight.w700, c: InsightTheme.blueInk)),
                    const SizedBox(height: 12),
                  ],
                  Text(title, style: InsightTheme.inter(13, w: FontWeight.w700, c: InsightTheme.ink)),
                  const SizedBox(height: 4),
                  Text(body, style: InsightTheme.inter(13, c: InsightTheme.ink2)),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
          actions: [TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(isTagalog ? 'Isara' : 'Close',
                style: InsightTheme.inter(14, w: FontWeight.w700, c: InsightTheme.blueInk)),
          )],
        );
      },
    ),
  );
}
