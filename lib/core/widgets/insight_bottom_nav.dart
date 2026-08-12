import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// ==================================================================
/// SHARED BOTTOM NAV — used by Home, Tasks, Updates, Profile.
///
/// Two things that broke the first pass, both fixed here:
///
/// 1. Yellow/black "RenderFlex overflow" warning while switching — the
///    label used to reveal via AnimatedSwitcher (opacity only). Opacity
///    doesn't shrink layout width, so a fading-out label kept its full
///    text width while its slot was already animating narrower, and the
///    Row briefly needed more space than it had. Fixed by reveal-by-WIDTH
///    instead: `ClipRect` + `AnimatedAlign(widthFactor: ...)` — the
///    label's occupied width is always bounded by the animation itself,
///    so the Row can never be asked for more room than it's been given.
///
/// 2. The whole bar "bouncing"/re-centering on every switch — the active
///    pill's width used to be sized off *that item's own* label ("Home"
///    is short, "Updates" is long), so the combined total width of all
///    slots changed depending on which tab was active, and the centered
///    row would nudge to keep itself centered. Fixed by giving the
///    active pill one uniform width (based on the *longest* label across
///    all items) regardless of which item is active — so total width
///    never changes and the bar's position is genuinely steady.
/// ==================================================================

/// Bottom scroll-padding reserve so list content isn't hidden behind the
/// floating pill bottom nav (nav vertical padding + pill height + a
/// small buffer). Used by scrollable tab screens as
/// `padding: EdgeInsets.only(bottom: kInsightBottomNavReserve)`.
const double kInsightBottomNavReserve = 100.0;

class InsightNavItem {
  final IconData icon;
  final String label;
  const InsightNavItem({required this.icon, required this.label});
}

class InsightBottomNav extends StatelessWidget {
  final int currentIndex;
  final List<InsightNavItem> items;
  final ValueChanged<int> onTap;

  const InsightBottomNav({
    super.key,
    required this.currentIndex,
    required this.items,
    required this.onTap,
  });

  static const _blue1 = Color(0xFF3D6BFF);
  static const _blue2 = Color(0xFF0B2FBF);
  static const _inactiveIcon = Color.fromARGB(255, 136, 139, 145);

  static const double _iconSize = 21;
  static const double _compactPadH = 15; // icon-only slot, left+right padding
  static const double _activePadH = 18;  // icon+label slot, left+right padding
  static const double _labelGap = 7;     // gap between icon and label
  static const double _itemGap = 8;      // fixed gap between adjacent slots
  static const double _railHeight = 46;

  static const _transitionDuration = Duration(milliseconds: 320);
  static const _transitionCurve = Curves.easeOutCubic;

  static final _labelStyle = GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600);

  double _labelWidth(String label) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: _labelStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  double _compactWidth() => _iconSize + _compactPadH * 2;

  @override
  Widget build(BuildContext context) {
    // Uniform active width, based on the LONGEST label of the whole set —
    // not the currently-active item's own label. That's what keeps the
    // bar's total width (and therefore its centered position) constant
    // no matter which tab is selected.
    final maxLabelWidth = items
        .map((it) => _labelWidth(it.label))
        .fold<double>(0, (a, b) => a > b ? a : b);
    final activeWidth = _iconSize + _labelGap + maxLabelWidth + _activePadH * 2;
    final compactWidth = _compactWidth();

    final widths = [
      for (int i = 0; i < items.length; i++)
        i == currentIndex ? activeWidth : compactWidth,
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color.fromARGB(255, 225, 230, 232).withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
                boxShadow: const [
                  BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 2)),
                  BoxShadow(color: Color(0x15000000), blurRadius: 24, offset: Offset(0, 12)),
                ],
              ),
              child: SizedBox(
                height: _railHeight,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final totalItemsWidth = widths.fold<double>(0, (a, b) => a + b);
                    final totalGapWidth = _itemGap * (items.length - 1);
                    final rawLeftover = constraints.maxWidth - totalItemsWidth - totalGapWidth;
                    final leftover = rawLeftover < 0 ? 0.0 : rawLeftover;
                    // Constant regardless of currentIndex now — this is
                    // what keeps the bar steady instead of nudging sideways.
                    final startX = leftover / 2;

                    final lefts = <double>[];
                    double cursor = startX;
                    for (int i = 0; i < items.length; i++) {
                      lefts.add(cursor);
                      cursor += widths[i] + _itemGap;
                    }

                    return Stack(
                      children: [
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
                              borderRadius: BorderRadius.circular(15),
                              boxShadow: [BoxShadow(color: _blue1.withValues(alpha: 0.28), blurRadius: 10, offset: const Offset(0, 4))],
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
  final VoidCallback onTap;

  const _NavPillItem({required this.item, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              item.icon,
              size: InsightBottomNav._iconSize,
              color: isActive ? Colors.white : InsightBottomNav._inactiveIcon,
            ),
            // Reveal-by-width, not reveal-by-opacity: ClipRect + AnimatedAlign
            // means this widget's actual occupied width is always exactly
            // `widthFactor * textWidth`, which is what the Row is told it
            // needs — never more than the slot has room for, so it can't
            // trigger a RenderFlex overflow no matter where mid-animation
            // this frame lands.
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
                    style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white),
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
    );
  }
}