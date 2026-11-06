import 'package:flutter/material.dart';

import '../../../core/theme/insight_theme.dart';
import '../../../core/widgets/imaps_loading_indicator.dart';
import '../../../core/widgets/motion/spring_entrance.dart';
import '../../interactive_guide/guide_targets.dart';

/// Home's identity presentation. Navigation and unread refresh belong to Home.
class HomeInspectorSection extends StatelessWidget {
  const HomeInspectorSection({
    super.key,
    required this.initials,
    required this.displayName,
    required this.greeting,
    required this.online,
    this.hasUnread = false,
    this.avatarUrl,
    this.onEditProfile,
    this.onNotifications,
    this.entrance = const AlwaysStoppedAnimation<double>(1),
  });

  final String initials, displayName, greeting;
  final bool online, hasUnread;
  final String? avatarUrl;
  final VoidCallback? onEditProfile, onNotifications;
  final Animation<double> entrance;

  @override
  Widget build(BuildContext context) {
    Widget initialsView() => Center(
      child: Text(
        initials,
        style: InsightTheme.urbanist(13, w: FontWeight.w700, c: Colors.white),
      ),
    );
    return GuideTarget(id: 'home_content', child: GuideTarget(id: 'inspector_section', child: Container(
      key: const ValueKey('inspector_section'),
      width: double.infinity,
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: InsightTheme.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SpringSlide(
            animation: entrance,
            beginOffset: const Offset(0, -32),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final style = InsightTheme.urbanist(
                    16,
                    w: FontWeight.w700,
                    c: InsightTheme.ink,
                  );
                  final painter = TextPainter(
                    text: TextSpan(text: 'FieldSync', style: style),
                    textScaler: MediaQuery.textScalerOf(context),
                    textDirection: Directionality.of(context),
                  )..layout();
                  final fits =
                      constraints.maxWidth >= 60 + painter.width + 24 + 48;
                  painter.dispose();
                  final identity = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        button: onEditProfile != null,
                        label: 'Edit profile',
                        child: GestureDetector(
                          onTap: onEditProfile,
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: InsightTheme.blue1,
                              border: Border.all(
                                color: InsightTheme.blue1,
                                width: 2,
                              ),
                            ),
                            child: ClipOval(
                              child: avatarUrl?.isNotEmpty == true
                                  ? Image.network(
                                      avatarUrl!,
                                      width: 44,
                                      height: 44,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, error, stack) =>
                                          initialsView(),
                                    )
                                  : initialsView(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('FieldSync', style: style),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: online
                                      ? InsightTheme.green
                                      : InsightTheme.red,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                online ? 'Online' : 'Offline',
                                style: InsightTheme.inter(
                                  12,
                                  w: FontWeight.w600,
                                  c: online
                                      ? InsightTheme.greenInk
                                      : InsightTheme.redInk,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  );
                  final notification = IconButton(
                    tooltip: 'Notifications',
                    onPressed: onNotifications,
                    padding: EdgeInsets.zero,
                    style: IconButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      backgroundColor: InsightTheme.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      side: const BorderSide(color: InsightTheme.line),
                    ),
                    icon: SizedBox(
                      width: 48,
                      height: 48,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          const Icon(
                            Icons.notifications_outlined,
                            color: InsightTheme.ink,
                            size: 22,
                          ),
                          if (hasUnread)
                            Positioned(
                              right: 10,
                              top: 10,
                              child: Container(
                                key: const ValueKey(
                                  'notification_unread_badge',
                                ),
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: InsightTheme.red,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                  return fits
                      ? Row(children: [identity, const Spacer(), notification])
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            identity,
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: notification,
                            ),
                          ],
                        );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SpringSlide(
              animation: entrance,
              beginOffset: const Offset(0, -20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    greeting,
                    style: InsightTheme.inter(
                      13,
                      w: FontWeight.w500,
                      c: InsightTheme.ink3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    displayName,
                    style: InsightTheme.urbanist(
                      24,
                      w: FontWeight.w700,
                      c: InsightTheme.ink,
                      ls: -0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    )));
  }
}

/// A calendar view only. Controllers and any saved view preference stay outside.
class HomeCalendarPreview extends StatelessWidget {
  const HomeCalendarPreview({
    super.key,
    required this.month,
    required this.selectedDay,
    required this.dayColors,
    this.onPick,
    this.onPreviousMonth,
    this.onNextMonth,
    this.controller,
    this.dayExtent,
    this.headerHeight,
  });

  final DateTime month;
  final int selectedDay;
  final Map<int, List<Color>> dayColors;
  final ValueChanged<int>? onPick;
  final VoidCallback? onPreviousMonth, onNextMonth;
  final ScrollController? controller;
  final double? dayExtent, headerHeight;

  @override
  Widget build(BuildContext context) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final monthLabel = '${months[month.month - 1]} ${month.year}';
    final scaler = MediaQuery.textScalerOf(context);
    final days = DateTime(month.year, month.month + 1, 0).day;
    return Container(
      key: const ValueKey('calendar_preview'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: InsightTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: InsightTheme.line),
      ),
      child: Column(
        children: [
          SizedBox(
            key: const ValueKey('calendar_preview_header'),
            height: headerHeight ?? scaler.scale(48),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Previous preview month',
                  onPressed: onPreviousMonth,
                  icon: const Icon(
                    Icons.chevron_left_rounded,
                    color: InsightTheme.ink2,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      monthLabel,
                      textAlign: TextAlign.center,
                      style: InsightTheme.urbanist(
                        14,
                        w: FontWeight.w700,
                        h: 1.2,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Next preview month',
                  onPressed: onNextMonth,
                  icon: const Icon(
                    Icons.chevron_right_rounded,
                    color: InsightTheme.ink2,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              key: const ValueKey('calendar_preview_days'),
              controller: controller,
              scrollDirection: Axis.horizontal,
              itemExtent: dayExtent ?? scaler.scale(48) + 6,
              itemCount: days,
              itemBuilder: (context, index) {
                final day = index + 1;
                final selected = selectedDay.clamp(1, days) == day;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Semantics(
                    container: true,
                    button: onPick != null,
                    selected: selected,
                    label: '$monthLabel, $day',
                    child: Material(
                      color: selected
                          ? InsightTheme.blue1
                          : InsightTheme.surface2,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: onPick == null ? null : () => onPick!(day),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              const [
                                'Mon',
                                'Tue',
                                'Wed',
                                'Thu',
                                'Fri',
                                'Sat',
                                'Sun',
                              ][DateTime(month.year, month.month, day).weekday -
                                  1],
                              style: InsightTheme.inter(
                                12,
                                w: FontWeight.w500,
                                h: 1.2,
                                c: selected ? Colors.white : InsightTheme.ink2,
                              ),
                            ),
                            Text(
                              '$day',
                              style: InsightTheme.urbanist(
                                20,
                                w: FontWeight.w700,
                                h: 1.2,
                                c: selected ? Colors.white : InsightTheme.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            SizedBox(
                              height: 4,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (final color
                                      in dayColors[day] ?? const <Color>[])
                                    Container(
                                      width: 4,
                                      height: 4,
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: selected ? Colors.white : color,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class HomeSectionActionButton extends StatelessWidget {
  const HomeSectionActionButton({super.key, required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: InsightTheme.inter(
              12,
              w: FontWeight.w700,
              c: InsightTheme.blueInk,
            ),
          ),
          const SizedBox(width: 3),
          const Icon(
            Icons.arrow_forward_rounded,
            size: 12,
            color: InsightTheme.blueInk,
          ),
        ],
      ),
    ),
  );
}

class HomeTaskStatusChart extends StatelessWidget {
  const HomeTaskStatusChart({
    super.key,
    required this.total,
    required this.labels,
    required this.colors,
    required this.counts,
    required this.overdueCount,
    required this.isLoading,
    required this.hasTasks,
    this.onMoreDetails,
  });

  final int total, overdueCount;
  final List<String> labels;
  final List<Color> colors;
  final List<int> counts;
  final bool isLoading, hasTasks;
  final VoidCallback? onMoreDetails;

  Color _countColor(Color background) {
    final luminance = background.computeLuminance();
    return 1.05 / (luminance + 0.05) >
            (luminance + 0.05) / (InsightTheme.ink.computeLuminance() + 0.05)
        ? Colors.white
        : InsightTheme.ink;
  }

  @override
  Widget build(BuildContext context) {
    final statuses = <({String label, int count, Color color})>[
      for (var i = 0; i < labels.length; i++)
        (label: labels[i], count: counts[i], color: colors[i]),
      (label: 'Overdue', count: overdueCount, color: InsightTheme.red),
    ];
    final bubbles = SizedBox(
      key: const ValueKey('completion_bubble_chart'),
      width: 138,
      height: 102,
      child: Stack(
        key: const ValueKey('completion_bubbles'),
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < statuses.length; i++)
            Builder(
              builder: (context) {
                const centers = [
                  Offset(31.5, 31.5),
                  Offset(67.5, 31.5),
                  Offset(103.5, 31.5),
                  Offset(49.5, 70.5),
                  Offset(85.5, 70.5),
                ];
                final status = statuses[i];
                final diameter = 42.0 + 3.0 * status.count.clamp(0, 7);
                return Positioned(
                  left: centers[i].dx - diameter / 2,
                  top: centers[i].dy - diameter / 2,
                  width: diameter,
                  height: diameter,
                  child: Semantics(
                    label: status.label == 'Overdue'
                        ? '${status.count} overdue tasks'
                        : '${status.label}: ${status.count} tasks',
                    child: Container(
                      key: ValueKey('completion_bubble_${status.label}'),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: status.color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: InsightTheme.surface,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: status.color.withValues(alpha: 0.12),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            '${status.count}',
                            style: InsightTheme.urbanist(
                              13,
                              w: FontWeight.w800,
                              c: _countColor(status.color),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
    final legend = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final status in statuses)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Container(
              key: ValueKey('completion_${status.label}'),
              child: Row(
                children: [
                  Container(
                    key: ValueKey('completion_icon_${status.label}'),
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: status.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      status.label,
                      style: InsightTheme.inter(
                        11,
                        w: FontWeight.w500,
                        c: status.label == 'Overdue'
                            ? InsightTheme.redInk
                            : InsightTheme.ink2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${status.count}',
                    style: InsightTheme.inter(
                      12,
                      w: FontWeight.w700,
                      c: status.label == 'Overdue'
                          ? InsightTheme.redInk
                          : InsightTheme.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
    return LayoutBuilder(
      key: const ValueKey('completion_chart'),
      builder: (context, constraints) => GuideTarget(id: 'completion_chart', child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: InsightTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: InsightTheme.line),
          boxShadow: [
            BoxShadow(
              color: InsightTheme.ink.withValues(alpha: 0.04),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, header) => Semantics(
                header: true,
                child: Text(
                  'Task Status Overview',
                  maxLines:
                      header.maxWidth < 320 ||
                          MediaQuery.textScalerOf(context).scale(16) > 24
                      ? 2
                      : 1,
                  overflow: TextOverflow.ellipsis,
                  style: InsightTheme.urbanist(
                    16,
                    w: FontWeight.w700,
                    c: InsightTheme.ink,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Tasks grouped by status',
              style: InsightTheme.inter(
                11,
                w: FontWeight.w400,
                c: InsightTheme.inkMuted,
              ),
            ),
            const SizedBox(height: 12),
            if (isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: ImapsLoadingIndicator(size: 40)),
              )
            else if (!hasTasks)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Text(
                    'No tasks yet.',
                    style: InsightTheme.inter(12, c: InsightTheme.ink2),
                  ),
                ),
              )
            else
              Row(
                children: [
                  bubbles,
                  const SizedBox(width: 8),
                  Expanded(child: legend),
                ],
              ),
            if (!isLoading && hasTasks) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: HomeSectionActionButton(
                  label: 'More details',
                  onTap: onMoreDetails,
                ),
              ),
            ],
          ],
        ),
      )),
    );
  }
}
