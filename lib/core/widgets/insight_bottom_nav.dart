import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/insight_theme.dart';

/// ==================================================================
/// SHARED BOTTOM NAV — used by Home, Tasks, Updates, Profile.
///
/// Layout (per Master's direction): the rail (4 tabs: Home, Tasks,
/// Updates, Profile) is now full-width on its own row — no longer
/// sharing horizontal space with the quick-actions trigger, which was
/// the actual cause of Profile getting clipped by the rail's rounded
/// mask on some screen widths. The trigger now floats ABOVE the rail,
/// right-aligned (so it visually sits over the Profile tab), matching
/// Master's "quick action button on top of the nav bar" direction.
///
/// The rail remains stable while the page scrolls so it never interrupts a
/// vertical drag gesture or causes the content layout to shift.
///
/// Faithful to Master's reference nav bar structure otherwise:
///   - Solid white floating rail (not glass/blurred).
///   - Each INACTIVE tab is its own small rounded chip.
///   - The ACTIVE tab is a fully-rounded stadium pill with icon + label,
///     filled with the app's own blue (existing `InsightTheme` tokens).
///
/// Two layout fixes still true here:
/// 1. Reveal-by-WIDTH for the active label (`ClipRect` +
///    `AnimatedAlign(widthFactor:)`) — avoids a RenderFlex overflow an
///    opacity-only reveal would cause.
/// 2. Uniform active-pill width (based on the *longest* label across all
///    items, not the active item's own) — keeps the bar from
///    bouncing/re-centering when switching tabs.
///
/// PERF NOTE: the RepaintBoundary below isolates this rail's own repaints
/// from whatever the active tab's content is doing.
/// ==================================================================

/// Bottom scroll-padding reserve so list content isn't hidden behind the
/// floating pill bottom nav (trigger + gap + rail + vertical padding +
/// a small buffer). Used by scrollable tab screens as
/// `padding: EdgeInsets.only(bottom: kInsightBottomNavReserve)`.
const double kInsightBottomNavReserve = 180.0;

class InsightNavItem {
  final IconData icon;
  final String label;
  /// Small badge dot on the icon — reuses the existing notification-dot
  /// pattern from `_NotificationBtn` (home_dashboard_screen.dart).
  /// Defaults to `InsightTheme.orange`, which is the same hex the
  /// reference's `bg-amber-500` already resolves to.
  final bool showBadge;
  final Color? badgeColor;
  const InsightNavItem({
    required this.icon,
    required this.label,
    this.showBadge = false,
    this.badgeColor,
  });
}

/// Cached job statuses that count as an assignment still waiting on the
/// inspector, and therefore a candidate for the attention dot.
///
/// In-progress, ongoing and completed work are excluded on purpose: the dot
/// means NEW / UNSEEN ASSIGNMENT, never "you have ongoing or completed work".
const Set<String> kAwaitingTaskStatuses = {'assigned', 'Pending', 'pending'};

/// The awaiting assignments this inspector has not looked at yet.
///
/// This is the whole meaning of the orange dot: a NEW / UNSEEN task
/// assignment. It is deliberately NOT a count of pending work — an old pending
/// task that has already been opened must never resurrect the dot on the next
/// cold start.
///
/// [awaitingTaskIds] comes from the CURRENT local cache, so an assignment that
/// was completed, reassigned or removed simply stops appearing here and cannot
/// hold the badge alive. [acknowledgedTaskIds] is the persisted, per-inspector
/// set of assignments already opened in Tasks.
Set<String> unseenTaskIds({
  required Iterable<String> awaitingTaskIds,
  required Set<String> acknowledgedTaskIds,
}) =>
    awaitingTaskIds.toSet().difference(acknowledgedTaskIds);

/// Whether the Tasks tab shows its orange attention dot.
bool shouldShowTasksAttentionDot({
  required Iterable<String> awaitingTaskIds,
  required Set<String> acknowledgedTaskIds,
}) =>
    unseenTaskIds(
      awaitingTaskIds: awaitingTaskIds,
      acknowledgedTaskIds: acknowledgedTaskIds,
    ).isNotEmpty;

class InsightBottomNav extends StatelessWidget {
  final int currentIndex;
  final List<InsightNavItem> items;
  final ValueChanged<int> onTap;

  /// Trigger button that opens/closes the Quick Actions sheet. Optional
  /// so this widget still works anywhere it's reused without quick
  /// actions wired in.
  final VoidCallback? onQuickActionsTap;
  final bool isQuickActionsOpen;

  const InsightBottomNav({
    super.key,
    required this.currentIndex,
    required this.items,
    required this.onTap,
    this.onQuickActionsTap,
    this.isQuickActionsOpen = false,
  });

  // Theme — existing InsightTheme values used across the app's screens,
  // not new hex. `_chipBg`/`_chipBorder` mirror the reference's neutral
  // slate-50/black-5% chip look using the app's own off-white tone.
  static const _blue1 = InsightTheme.blue1; // canonical brand blue
  static const _blue2 = InsightTheme.blue2;
  static const _inactiveIcon = Color.fromARGB(255, 100, 106, 122);
  static const _orange = Color(0xFFF59E0B); // InsightTheme.orange (== amber-500)
  static const _chipBg = Color(0xFFF2F4FB); // InsightTheme.bg
  static const _chipBorder = Color(0x0D000000); // black/5%
  static const _railBorder = Color(0x1A000000); // black/10%

  // Sizing — matches the reference: rail padding p-2 (8), rail/trigger
  // corner radius rounded-[2rem] (32), trigger w-16 h-16 (64).
  static const double _railAndTriggerSize = 64;
  static const double _outerCornerRadius = 32;
  static const double _railInnerPad = 8;
  static const double _triggerGap = 12; // gap between trigger and rail

  static const double _iconSize = 20; // reference: w-5 h-5
  static const double _activePadH = 20;  // reference active pill: px-5 (20px)
  static const double _labelGap = 8;     // reference: gap-2
  static const double _itemGap = 8;      // reference: implicit gap between buttons row

  static const _transitionDuration = Duration(milliseconds: 320);
  static const _transitionCurve = Curves.easeOutCubic;

  static TextStyle get _labelStyle => InsightTheme.inter(14, w: FontWeight.w500);

  double get _itemHeight => _railAndTriggerSize - _railInnerPad * 2; // 48, matches reference w-12/h-12
  double get _itemRadius => _itemHeight / 2; // rounded-full

  double _labelWidth(String label) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: _labelStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  double _compactWidth() => _itemHeight; // perfect circle, width == height

  @override
  Widget build(BuildContext context) {
    final maxLabelWidth = items
        .map((it) => _labelWidth(it.label))
        .fold<double>(0, (a, b) => a > b ? a : b);
    final activeWidth = _iconSize + _labelGap + maxLabelWidth + _activePadH * 2;
    final compactWidth = _compactWidth();

    final widths = [
      for (int i = 0; i < items.length; i++)
        i == currentIndex ? activeWidth : compactWidth,
    ];

    final rail = Container(
      padding: const EdgeInsets.all(_railInnerPad),
      decoration: BoxDecoration(
        color: Colors.white, // solid — matches reference `bg-white`
        borderRadius: BorderRadius.circular(_outerCornerRadius),
        border: Border.all(color: _railBorder),
        boxShadow: const [
          BoxShadow(color: Color(0x1A0B1440), blurRadius: 24, offset: Offset(0, 10)),
        ],
      ),
      child: SizedBox(
        height: _itemHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final totalItemsWidth = widths.fold<double>(0, (a, b) => a + b);
            final totalGapWidth = _itemGap * (items.length - 1);
            final rawLeftover = constraints.maxWidth - totalItemsWidth - totalGapWidth;
            final leftover = rawLeftover < 0 ? 0.0 : rawLeftover;
            final startX = leftover / 2;

            final lefts = <double>[];
            double cursor = startX;
            for (int i = 0; i < items.length; i++) {
              lefts.add(cursor);
              cursor += widths[i] + _itemGap;
            }

            return Stack(
              children: [
                // The moving highlight — morphs from a 48px circle into
                // the wider active pill, filled with the app's blue.
                AnimatedPositioned(
                  duration: _transitionDuration,
                  curve: _transitionCurve,
                  left: lefts[currentIndex],
                  width: widths[currentIndex],
                  top: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_blue1, _blue2],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(_itemRadius),
                      boxShadow: [BoxShadow(color: _blue1.withValues(alpha: 0.30), blurRadius: 14, offset: const Offset(0, 6))],
                    ),
                  ),
                ),
                for (int i = 0; i < items.length; i++)
                  AnimatedPositioned(
                    duration: _transitionDuration,
                    curve: _transitionCurve,
                    left: lefts[i],
                    width: widths[i],
                    top: 0,
                    bottom: 0,
                    child: _NavPillItem(
                      item: items[i],
                      isActive: i == currentIndex,
                      itemRadius: _itemRadius,
                      onTap: () {
                        if (i != currentIndex) HapticFeedback.selectionClick();
                        onTap(i);
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: SizedBox(
          // Fixed total height keeps the bottomNavigationBar slot stable
          // while the page content scrolls behind it.
          height: _railAndTriggerSize + _triggerGap + _railAndTriggerSize,
          child: RepaintBoundary(
            child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Rail — anchored at the bottom of this box.
              Positioned(
                left: 0, right: 0, bottom: 0,
                child: rail,
              ),
              // Trigger stays fully visible and interactive above the rail.
              if (onQuickActionsTap != null)
                Positioned(
                  right: 0,
                  bottom: _railAndTriggerSize + _triggerGap,
                  child: _QuickActionsTrigger(
                    isOpen: isQuickActionsOpen,
                    onTap: onQuickActionsTap!,
                  ),
                ),
            ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Circular trigger button — opens/closes the Quick Actions sheet. Solid
/// white, same family as the rail (not glass), matching the reference's
/// `w-16 h-16 bg-white rounded-[2rem] border shadow-xl`. Now sits above
/// the rail (right-aligned, over the Profile tab) instead of beside it.
class _QuickActionsTrigger extends StatelessWidget {
  final bool isOpen;
  final VoidCallback onTap;
  const _QuickActionsTrigger({required this.isOpen, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        label: 'Quick actions',
        button: true,
        child: AnimatedContainer(
          duration: InsightBottomNav._transitionDuration,
          curve: InsightBottomNav._transitionCurve,
          width: InsightBottomNav._railAndTriggerSize,
          height: InsightBottomNav._railAndTriggerSize,
          decoration: BoxDecoration(
            color: Colors.white, // solid — matches reference
            borderRadius: BorderRadius.circular(InsightBottomNav._outerCornerRadius),
            border: Border.all(color: InsightBottomNav._railBorder),
            boxShadow: const [
              BoxShadow(color: Color(0x1A0B1440), blurRadius: 24, offset: Offset(0, 10)),
            ],
          ),
          child: Center(
            child: AnimatedRotation(
              duration: InsightBottomNav._transitionDuration,
              curve: InsightBottomNav._transitionCurve,
              turns: isOpen ? 0.5 : 0,
              child: Icon(
                Icons.keyboard_arrow_up_rounded,
                size: 24, // reference: w-6 h-6
                color: isOpen ? InsightBottomNav._blue1 : InsightBottomNav._inactiveIcon,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavPillItem extends StatelessWidget {
  final InsightNavItem item;
  final bool isActive;
  final double itemRadius;
  final VoidCallback onTap;

  const _NavPillItem({
    required this.item,
    required this.isActive,
    required this.itemRadius,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: InsightBottomNav._transitionDuration,
        curve: InsightBottomNav._transitionCurve,
        decoration: BoxDecoration(
          // Inactive tabs get their own visible chip (reference:
          // `bg-slate-50 border-black/5 rounded-full`) — the moving blue
          // highlight sits underneath the active one, so this stays
          // transparent for the active state.
          color: isActive ? Colors.transparent : InsightBottomNav._chipBg,
          borderRadius: BorderRadius.circular(itemRadius),
          border: isActive ? null : Border.all(color: InsightBottomNav._chipBorder),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    item.icon,
                    size: InsightBottomNav._iconSize,
                    color: isActive ? Colors.white : InsightBottomNav._inactiveIcon,
                  ),
                  // Same dot pattern as _NotificationBtn (home dashboard).
                  // Only shown on the inactive chip; once the tab is open
                  // the badge's job is done.
                  if (item.showBadge && !isActive)
                    Positioned(
                      top: -6,
                      right: -8,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: item.badgeColor ?? InsightBottomNav._orange,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              // Reveal-by-width, not reveal-by-opacity: ClipRect +
              // AnimatedAlign means this widget's actual occupied width is
              // always exactly `widthFactor * textWidth`, which is what
              // the Row is told it needs — never more than the slot has
              // room for, so it can't trigger a RenderFlex overflow no
              // matter where mid-animation this frame lands.
              ClipRect(
                child: AnimatedAlign(
                  duration: InsightBottomNav._transitionDuration,
                  curve: InsightBottomNav._transitionCurve,
                  alignment: Alignment.centerLeft,
                  widthFactor: isActive ? 1.0 : 0.0,
                  child: Padding(
                    padding: const EdgeInsets.only(left: InsightBottomNav._labelGap),
                    child: Text(
                      item.label,
                      style: InsightTheme.inter(14, w: FontWeight.w500, c: Colors.white),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.clip,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}