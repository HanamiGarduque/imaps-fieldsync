import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/insight_theme.dart';
import 'fieldsync_brand.dart';

/// ==================================================================
/// SHARED BOTTOM NAV — used by Home, Tasks, Updates, Profile.
///
/// Layout: the rail (4 tabs: Home, Tasks, Updates, Profile) sits on its
/// own row and does not share horizontal space with the quick-actions
/// trigger, which was the actual cause of Profile getting clipped by the
/// rail's rounded mask on some screen widths. The trigger floats ABOVE
/// the rail, right-aligned, matching Master's "quick action button on
/// top of the nav bar" direction.
///
/// The rail hugs its own items (the reference's `width:max-content`) and
/// is centred in the viewport, capped at 360px wide. It never stretches
/// edge to edge, and a text-scaled label widens it instead of squeezing
/// the chips.
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
/// Three layout fixes still true here:
/// 1. Reveal-by-WIDTH for the active label (`ClipRect` +
///    `AnimatedAlign(widthFactor:)`) — avoids a RenderFlex overflow an
///    opacity-only reveal would cause.
/// 2. Uniform active-pill width (based on the *longest* label across all
///    items, not the active item's own) — keeps the bar from
///    bouncing/re-centering when switching tabs.
/// 3. A pressed down-state (0.97 for 120ms) on every tab, and the moving
///    blue highlight scales with the active tab so the pill and its icon
///    never drift apart.
///
/// PERF NOTE: the RepaintBoundary below isolates this rail's own repaints
/// from whatever the active tab's content is doing.
/// ==================================================================

/// Bottom scroll-padding reserve so list content isn't hidden behind the
/// floating pill bottom nav (trigger + gap + rail + vertical padding +
/// a small buffer). Used by scrollable tab screens as
/// `padding: EdgeInsets.only(bottom: kInsightBottomNavReserve)`.
const double kInsightBottomNavReserve = 180.0;

/// Bottom clearance a floating panel needs to clear the quick-actions trigger.
///
/// Derived once from the nav's own geometry so the two can never drift apart.
/// From the bottom of the screen, upwards: 10px nav padding, the 64px rail, the
/// 12px trigger-to-rail gap, the 64px trigger, then a 12px visual gap above it.
///
/// The trigger therefore occupies offsets 150..214. The previous hardcoded
/// `bottom: 190` fell INSIDE that band, which is exactly why the quick-actions
/// panel sat on top of the trigger button.
const double kInsightBottomNavTriggerClearance =
    10 /* nav vertical padding */ +
    64 /* rail */ +
    12 /* trigger-to-rail gap */ +
    64 /* trigger height */ +
    64 /* trigger width is also its height: the circle */ +
    12 /* visual gap above the trigger */;

/// Widest the bottom-nav pill is allowed to become.
///
/// The rail hugs its own items, so the cap only bites on a wide viewport with
/// a text-scaled label: it stops the pill from stretching edge to edge while
/// still fitting every item. The cap is applied to the OUTER width, and the
/// rail is never allowed to grow past the room the screen actually has.
const double kInsightBottomNavMaxWidth = 360.0;

// Theme — existing InsightTheme values used across the app's screens,
// not new hex. `_chipBg`/`_chipBorder` mirror the reference's neutral
// slate-50/black-5% chip look using the app's own off-white tone.
const _blue1 = InsightTheme.blue1; // canonical brand blue
const _blue2 = InsightTheme.blue2;
const _inactiveIcon = Color.fromARGB(255, 100, 106, 122);
const _orange = Color(0xFFF59E0B); // the reference's amber-500 attention dot
const _chipBg = Color(0xFFF2F4FB); // InsightTheme.bg
const _chipBorder = Color(0x0D000000); // black/5%
const _railBorder = Color(0x1A000000); // black/10%

// Sizing — matches the reference: rail padding p-2 (8), rail/trigger
// corner radius rounded-[2rem] (32), trigger w-16 h-16 (64).
const double _railAndTriggerSize = 64;
const double _outerCornerRadius = 32;
const double _railInnerPad = 8;
/// The rail's 1px border, counted once per side in the width budget.
const double _railBorderWidth = 1;
const double _triggerGap = 12; // gap between trigger and rail

const double _iconSize = 20; // reference: w-5 h-5
const double _activePadH = 20;  // reference active pill: px-5 (20px)
const double _labelGap = 8;     // reference: gap-2
const double _itemGap = 8;      // reference: implicit gap between buttons row

/// The narrowest the active pill may become: its icon, the gap, and a sliver
/// of the label. Below this the pill would stop reading as a tab.
const double _activeMinWidth = _iconSize + _labelGap + 8;

/// The reference's down-state: a 0.97 scale for 120ms, matching the
/// quick-action trigger's existing 0.94 press.
const double _pressedScale = 0.97;
const Duration _pressDuration = Duration(milliseconds: 120);

const _transitionDuration = Duration(milliseconds: 320);
const _transitionCurve = Curves.easeOutCubic;

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

class InsightBottomNav extends StatefulWidget {
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

  @override
  State<InsightBottomNav> createState() => _InsightBottomNavState();
}

class _InsightBottomNavState extends State<InsightBottomNav> {
  /// The tab that is being held down right now, so it can paint the
  /// reference's pressed state (0.97 for 120ms). The moving blue highlight
  /// reads the same value, so an active tab's pill and its icon scale
  /// together and never drift apart.
  int? _pressedIndex;

  /// Safety net for a lost pointer-up (the app is backgrounded mid-press):
  /// a tab must never stay stuck at the pressed scale.
  Timer? _pressTimer;

  void _pressStart(int index) {
    _pressTimer?.cancel();
    setState(() => _pressedIndex = index);
    _pressTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _pressedIndex = null);
    });
  }

  void _pressEnd() {
    _pressTimer?.cancel();
    _pressTimer = null;
    if (mounted && _pressedIndex != null) {
      setState(() => _pressedIndex = null);
    }
  }

  @override
  void dispose() {
    _pressTimer?.cancel();
    super.dispose();
  }

  static TextStyle get _labelStyle => InsightTheme.inter(14, w: FontWeight.w500);

  double get _itemHeight => _railAndTriggerSize - _railInnerPad * 2; // 48, matches reference w-12/h-12
  double get _itemRadius => _itemHeight / 2; // rounded-full

  /// Width of the longest label at the CURRENT text scale.
  ///
  /// The label is painted with the ambient `textScaler`, so measuring it
  /// without one under-reports the width: at 1.3x the active pill stayed sized
  /// for the unscaled text and its ClipRect cut the label's tail off.
  double _labelWidth(String label, TextScaler textScaler) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: _labelStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      textScaler: textScaler,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  double _compactWidth() => _itemHeight; // perfect circle, width == height

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final currentIndex = widget.currentIndex;
    final maxLabelWidth = items
        .map((it) => _labelWidth(it.label, MediaQuery.textScalerOf(context)))
        .fold<double>(0, (a, b) => a > b ? a : b);
    final compactWidth = _compactWidth();

    // The rail is `border + padding + SizedBox + padding + border`, so every
    // width here is measured OUTSIDE that chrome, and the chrome is
    // subtracted only where the content box is built. Forgetting the 1px
    // border is how a "360px cap" silently shipped a 362px rail.
    const chrome = _railInnerPad * 2 + _railBorderWidth * 2;

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
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The room the rail really has, measured from the layout: this
          // builder already sits inside the rail's padding and border, so the
          // outer room is the inner width plus the chrome back.
          final available = constraints.maxWidth + chrome;

          // The active pill is the only item that can give up room: its
          // label is revealed by width, so the side padding goes first and
          // every tab still ends up inside the rail on a narrow phone. The
          // pill never shrinks below its icon and a sliver of the label.
          var activeWidth =
              _iconSize + _labelGap + maxLabelWidth + _activePadH * 2;
          double totalFor(double active) =>
              compactWidth * (items.length - 1) +
              active +
              _itemGap * (items.length - 1) +
              chrome;
          final overflow = totalFor(activeWidth) - available;
          if (overflow > 0) {
            activeWidth -= math.min(
              math.max(0.0, activeWidth - _activeMinWidth),
              overflow,
            );
          }

          final widths = [
            for (int i = 0; i < items.length; i++)
              i == currentIndex ? activeWidth : compactWidth,
          ];
          final naturalWidth = totalFor(activeWidth);

          // The rail hugs its own items — the reference's `width:max-content` —
          // is centred in the viewport, and never grows past the 360px cap or
          // past the room the screen has.
          final outerWidth = math.min(
            math.min(naturalWidth, kInsightBottomNavMaxWidth),
            available,
          );
          return SizedBox(
            width: outerWidth - chrome,
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
                      child: AnimatedScale(
                        // Same down-state as the item it sits under, so the blue
                        // pill and its icon scale as one.
                        scale: _pressedIndex == currentIndex
                            ? _pressedScale
                            : 1,
                        duration: _pressDuration,
                        curve: Curves.easeOut,
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
                          isPressed: _pressedIndex == i,
                          itemRadius: _itemRadius,
                          // The label never gets more room than the chip can
                          // give it, so a label that paints wider than it was
                          // measured is clipped instead of overflowing.
                          labelMaxWidth: math.max(
                            0.0,
                            widths[i] - _iconSize - _labelGap,
                          ),
                          onPressStart: () => _pressStart(i),
                          onPressEnd: _pressEnd,
                          onTap: () {
                            if (i != currentIndex) HapticFeedback.selectionClick();
                            widget.onTap(i);
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          );
        },
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
              // Rail — anchored at the bottom of this box, and centred when the
              // viewport is wider than the capped pill.
              Positioned(
                left: 0, right: 0, bottom: 0,
                child: Center(child: rail),
              ),
              // Trigger stays fully visible and interactive above the rail.
              if (widget.onQuickActionsTap != null)
                Positioned(
                  right: 0,
                  bottom: _railAndTriggerSize + _triggerGap,
                  child: _QuickActionsTrigger(
                    isOpen: widget.isQuickActionsOpen,
                    onTap: widget.onQuickActionsTap!,
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

/// Quick-actions trigger — opens/closes the Quick Actions sheet.
///
/// Bare FieldSync fingerprint with an invisible 64px tap target. Opening the
/// sheet replaces the mark with a close glyph; neither state paints a tile.
class _QuickActionsTrigger extends StatefulWidget {
  final bool isOpen;
  final VoidCallback onTap;
  const _QuickActionsTrigger({required this.isOpen, required this.onTap});

  @override
  State<_QuickActionsTrigger> createState() => _QuickActionsTriggerState();
}

class _QuickActionsTriggerState extends State<_QuickActionsTrigger> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    const size = _railAndTriggerSize; // 64
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        label: 'Quick actions',
        button: true,
        child: AnimatedScale(
          scale: _pressed ? 0.94 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              child: AnimatedSwitcher(
                duration: _transitionDuration,
                switchInCurve: _transitionCurve,
                transitionBuilder: (child, animation) => RotationTransition(
                  turns: Tween<double>(begin: -0.12, end: 0).animate(animation),
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: widget.isOpen
                    ? const Icon(
                        Icons.close_rounded,
                        key: ValueKey<bool>(true),
                        size: 26,
                        color: InsightTheme.blue2,
                      )
                    : const FieldSyncBrand(
                        key: ValueKey<bool>(false),
                        variant: FieldSyncBrandVariant.symbol,
                        height: 48,
                      ),
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
  final bool isPressed;
  final double itemRadius;
  /// The room the label may occupy inside this chip.
  final double labelMaxWidth;
  final VoidCallback onTap;
  final VoidCallback onPressStart;
  final VoidCallback onPressEnd;

  const _NavPillItem({
    required this.item,
    required this.isActive,
    required this.isPressed,
    required this.itemRadius,
    required this.labelMaxWidth,
    required this.onTap,
    required this.onPressStart,
    required this.onPressEnd,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onTapDown: (_) => onPressStart(),
      onTapUp: (_) => onPressEnd(),
      onTapCancel: onPressEnd,
      behavior: HitTestBehavior.opaque,
      // The reference's down-state: the chip sinks to 0.97 for 120ms, so a
      // held tab is visibly pressed instead of showing nothing until release.
      child: AnimatedScale(
        scale: isPressed ? _pressedScale : 1,
        duration: _pressDuration,
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: _transitionDuration,
          curve: _transitionCurve,
          decoration: BoxDecoration(
          // Inactive tabs get their own visible chip (reference:
          // `bg-slate-50 border-black/5 rounded-full`) — the moving blue
          // highlight sits underneath the active one, so this stays
          // transparent for the active state.
          color: isActive ? Colors.transparent : _chipBg,
          borderRadius: BorderRadius.circular(itemRadius),
          border: isActive ? null : Border.all(color: _chipBorder),
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
                    size: _iconSize,
                    color: isActive ? Colors.white : _inactiveIcon,
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
                          color: item.badgeColor ?? _orange,
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
                  duration: _transitionDuration,
                  curve: _transitionCurve,
                  alignment: Alignment.centerLeft,
                  widthFactor: isActive ? 1.0 : 0.0,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: labelMaxWidth),
                    child: Padding(
                      padding: const EdgeInsets.only(left: _labelGap),
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
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
