import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/insight_theme.dart';
import '../layout/responsive_layout.dart';
import 'insight_bottom_nav.dart'
    show kInsightBottomNavTriggerClearance;

/// ==================================================================
/// QUICK ACTIONS SHEET
///
/// New pattern (approved by Master), triggered from the nav-adjacent
/// chevron button in `InsightBottomNav`. Deliberately NOT the app's
/// standard full-width `showModalBottomSheet` convention used elsewhere
/// — Master explicitly asked for the floating, inset, rounded-card look
/// from the reference instead, with each row staggering in on open.
///
/// Fonts: Poppins (title) / Inter (rows) - the canonical pairing.

/// ==================================================================

class QuickAction {
  final IconData icon;
  final String title;
  final String? subtitle; // optional — shown under the title, per the reference row layout
  final VoidCallback onTap;
  const QuickAction({required this.icon, required this.title, this.subtitle, required this.onTap});
}

/// A map-first detail panel: a compact side pane where a split is worthwhile,
/// a content-sized floating card otherwise, with an explicit control to hide
/// it so the spatial surface is never permanently obscured.
///
/// The collapse is local presentation state only — nothing about the map, the
/// location data, or the actions inside is affected.
class MapDetailPanel extends StatefulWidget {
  const MapDetailPanel({
    super.key,
    required this.title,
    required this.child,
    this.sidePanelWidthFactor = 0.36,
    this.minSidePanelWidth = 280,
    this.maxSidePanelWidth = 400,
    this.embedded = false,
    this.footer,
    this.headerKey,
    this.onCollapsedChanged,
    this.collapseLabel = 'location details',
    this.initiallyCollapsed = false,
    this.headerAccessory,
  });

  final String title;
  final Widget child;
  final double sidePanelWidthFactor;
  final double minSidePanelWidth;
  final double maxSidePanelWidth;
  /// A map host that already measures overlays owns sizing in embedded mode.
  final bool embedded;
  final Widget? footer;
  final Key? headerKey;
  final ValueChanged<bool>? onCollapsedChanged;
  final String collapseLabel;
  final bool initiallyCollapsed;
  final Widget? headerAccessory;

  /// Widest the floating form of this panel becomes.
  static const double kCardMaxWidth = 520;

  @override
  State<MapDetailPanel> createState() => _MapDetailPanelState();
}

class _MapDetailPanelState extends State<MapDetailPanel> {
  bool _collapsed = false;

  @override
  void initState() {
    super.initState();
    _collapsed = widget.initiallyCollapsed;
  }

  @override
  Widget build(BuildContext context) {
    final panel = DecoratedBox(decoration: BoxDecoration(color: InsightTheme.surface,
      borderRadius: InsightTheme.roundedMd, border: Border.all(color: InsightTheme.line),
      boxShadow: InsightTheme.cardShadow),
      child: Padding(padding: EdgeInsets.fromLTRB(12, 0, 12, _collapsed ? 0 : 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // The title must scroll too: enlarged text can consume the whole short panel.
          Flexible(child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(key: widget.headerKey, children: [
              Expanded(child: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Semantics(header: true,
                    child: Text(widget.title, style: widget.embedded
                      ? InsightTheme.urbanist(14)
                      : InsightTheme.urbanist(14, w: FontWeight.w700))),
                  if (widget.headerAccessory != null) widget.headerAccessory!,
                ])),
              if (!widget.embedded) const SizedBox(width: 8),
              TextButton(onPressed: () {
                setState(() => _collapsed = !_collapsed);
                widget.onCollapsedChanged?.call(_collapsed);
              },
                style: TextButton.styleFrom(minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 8), foregroundColor: InsightTheme.ink2),
                child: Tooltip(message: '${_collapsed ? 'Show' : 'Hide'} ${widget.collapseLabel}',
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(_collapsed ? 'Show' : 'Hide', style: InsightTheme.inter(12)),
                    const SizedBox(width: 4),
                    Icon(_collapsed ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, size: 18),
                  ]))),
            ]),
            if (!_collapsed) widget.child,
          ]))),
          if (!_collapsed && widget.footer != null) ...[
            const SizedBox(height: 8),
            widget.footer!,
          ],
        ]),
      ),
    );
    if (widget.embedded) return panel;
    final bp = context.responsive;
    return LayoutBuilder(builder: (context, constraints) {
      final split = bp.canSplitTwoPane || (bp.isLandscape && !bp.isCompactWidth);
      final width = split ? (bp.width * widget.sidePanelWidthFactor)
        .clamp(widget.minSidePanelWidth, widget.maxSidePanelWidth).toDouble()
        : MapDetailPanel.kCardMaxWidth;
      return Align(alignment: split ? Alignment.bottomRight : Alignment.bottomCenter,
        widthFactor: 1, heightFactor: 1, child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: math.min(width, constraints.maxWidth),
          maxHeight: split ? constraints.maxHeight : constraints.maxHeight * 0.35),
        child: panel,
      ));
    });
  }
}

/// Widest the floating quick-actions panel may become.
///
/// A full-bleed sheet read as a cut-off strip in landscape. Bounding it makes it
/// the compact floating panel the design calls for; a phone in portrait lays out
/// under this cap and is completely unchanged.
const double kPanelMaxWidth = 460.0;

/// Wide layouts leave a separate lane for the nav's 64px trigger.
/// Insets come from the view because Scaffold consumes bottom viewPadding and
/// extendBody adds the nav height to body padding.
class QuickActionsOverlay extends StatelessWidget {
  const QuickActionsOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final wide = !context.responsive.isCompactWidth;
    final insets = MediaQueryData.fromView(View.of(context)).viewPadding;
    return Positioned(
      left: 16 + (wide ? insets.left : 0),
      right: wide ? insets.right + 14 + 64 + 12 : 16,
      top: wide ? insets.top + 16 : null,
      // The 64px rail plus its 1px border on each side, with a 12px gap.
      bottom: wide ? insets.bottom + 10 + 66 + 12
          : kInsightBottomNavTriggerClearance,
      child: child,
    );
  }
}

class QuickActionsSheet extends StatefulWidget {
  final List<QuickAction> actions;
  final VoidCallback onClose;
  final bool fillAvailableSpace;

  const QuickActionsSheet({
    super.key,
    required this.actions,
    required this.onClose,
    this.fillAvailableSpace = false,
  });

  static const blue1 = InsightTheme.blue1;
  static const ink = InsightTheme.ink;
  static const ink2 = InsightTheme.ink2;
  static const blueTint = InsightTheme.blueTint;
  static const line = InsightTheme.line;

  @override
  State<QuickActionsSheet> createState() => _QuickActionsSheetState();
}

class _QuickActionsSheetState extends State<QuickActionsSheet> {
  @override
  Widget build(BuildContext context) {
    // Bounded and centred. The host hands this a tight width (left/right
    // positioned), so the cap has to sit ABOVE the container — constraining a
    // child cannot shrink a parent that was given tight constraints. Without
    // this the panel runs edge to edge and reads as a cut-off strip.
    return LayoutBuilder(builder: (context, constraints) {
      final fill = widget.fillAvailableSpace && !context.responsive.isCompactWidth;
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: fill ? constraints.maxHeight : _maxHostHeight(context),
          maxWidth: fill ? InsightBreakpoints.contentMaxWidthWide : kPanelMaxWidth,
        ),
        child: Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        boxShadow: const [
          BoxShadow(color: Color(0x1A000000), blurRadius: 32, offset: Offset(0, 16)),
        ],
      ),
      // The actions scroll inside the bounded panel, so a landscape viewport
      // can never push rows off-screen.
      child: Column(
          mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    'Quick actions',
                    style: InsightTheme.urbanist(20, w: FontWeight.w700, c: QuickActionsSheet.ink, ls: -0.3),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Close quick actions',
                  onPressed: widget.onClose,
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  style: IconButton.styleFrom(backgroundColor: const Color(0xFFF1F2F8)),
                  icon: const Icon(Icons.close_rounded, size: 20, color: QuickActionsSheet.ink2),
                ),
              ],
            ),
          ),
          Flexible(child: SingleChildScrollView(child: LayoutBuilder(
            builder: (context, constraints) => _buildActions(constraints.maxWidth),
          ))),
          ],
        ),
        ),
      ),
    );
    });
  }

  /// Vertical clearance the host must leave below this sheet.
///
/// The nav's quick-actions trigger is a 64px circle sitting `_triggerGap` (12)
/// above the 64px rail, and the nav block itself is padded 10 and wrapped in a
/// SafeArea. The previous fixed `bottom: 190` overlapped that trigger by
/// roughly 16px on a device with a gesture bar. Deriving the offset from the
/// nav's own geometry keeps the panel clear of the trigger on every device.
  static const double kHostBottomOffset = kInsightBottomNavTriggerClearance;

  /// Height the host can give this sheet.
  ///
  /// Always leaves room for the header plus one row, so the close control and
  /// the first action can never be scrolled out of reach.
  static const double kHeaderAllowance = 72.0;

  double _maxHostHeight(BuildContext context) {
    final media = MediaQuery.of(context);
    final insets = media.padding.top + media.padding.bottom;
    final usable = media.size.height - kHostBottomOffset - insets;
    // Never hand back less than the header plus one row, or the close control
    // and the first action would be scrolled out of reach.
    return math.max(kHeaderAllowance + 48.0, usable);
  }

  /// Width below which two columns would squeeze a row's icon, label and
  /// chevron into an overflow. Two columns need real room, not just width.
  static const double kTwoColumnMinWidth = 400.0;

  /// Every action, always all of them and in the same order.
  ///
  /// Portrait keeps the accepted single-column list. Where the panel is wide
  /// enough the same actions flow into two columns, so a landscape viewport
  /// stops spending its height on a tall portrait-shaped sheet.
  Widget _buildActions(double availableWidth) {
    final actions = widget.actions;

    Widget entry(int i, Widget child) =>
        _StaggeredEntry(index: i, child: child);

    // Use the panel's actual width and chosen text size, rather than assuming
    // a wide screen also means wide columns inside this inset overlay.
    final twoColumns = context.responsive.canSplitTwoPane &&
        availableWidth >= MediaQuery.textScalerOf(context).scale(kTwoColumnMinWidth);
    // Height is the scarce dimension on any wide-but-short viewport, not only
    // where two columns happen to fit: without this a landscape panel cuts its
    // last row in half instead of showing every action whole.
    final compactRows = twoColumns || MediaQuery.sizeOf(context).height < 400;
    if (!twoColumns) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < actions.length; i++)
            entry(i, _QuickActionRow(action: actions[i], onClose: widget.onClose, compact: compactRows)),
        ],
      );
    }

    // Split the list in half so the two columns hold a similar number of rows.
    final split = (actions.length / 2).ceil();
    final left = actions.sublist(0, split);
    final right = actions.sublist(split);
    Widget column(List<QuickAction> items, int offset) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < items.length; i++)
              entry(offset + i,
                  _QuickActionRow(action: items[i], onClose: widget.onClose, compact: true)),
          ],
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: column(left, 0)),
        const SizedBox(width: 8),
        Flexible(child: column(right, split)),
      ],
    );
  }
}

/// Cubic-bezier slide-up-and-fade-in, delayed by [index] * a fixed step —
/// runs once, the moment this row is first built (i.e. the moment the
/// sheet mounts), giving the reference's staggered-menu-item feel.
class _StaggeredEntry extends StatefulWidget {
  final int index;
  final Widget child;
  const _StaggeredEntry({required this.index, required this.child});

  @override
  State<_StaggeredEntry> createState() => _StaggeredEntryState();
}

class _StaggeredEntryState extends State<_StaggeredEntry> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  late final Animation<double> _curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 45 * widget.index), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) {
        return Opacity(
          opacity: _curve.value,
          child: Transform.translate(
            offset: Offset(0, (1 - _curve.value) * 14),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _QuickActionRow extends StatefulWidget {
  final QuickAction action;
  final VoidCallback onClose;

  /// Tighter metrics where height is the scarce dimension, so a landscape
  /// panel never cuts its last row in half.
  final bool compact;
  const _QuickActionRow({
    required this.action,
    required this.onClose,
    this.compact = false,
  });

  @override
  State<_QuickActionRow> createState() => _QuickActionRowState();
}

class _QuickActionRowState extends State<_QuickActionRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final subtitle = widget.action.subtitle;
    final iconSize = widget.compact ? 44.0 : 48.0;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onClose();
        widget.action.onTap();
      },
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: widget.compact ? 8 : 12),
        decoration: BoxDecoration(
          // Matches the reference: no per-row card/border — a flat list,
          // whitespace-separated, with only a soft highlight on press.
          // (Also lines up with "prefer whitespace over dividers" from
          // the UI-tips doc: cleaner, less visual noise than a bordered
          // card per row.)
          color: _pressed ? const Color(0xFFF8F9FC) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        // 44px+ tap target floor (UDAS §2.3) — row height comfortably
        // exceeds it once padding + icon + text are accounted for.
        child: Row(
          children: [
            AnimatedScale(
              duration: const Duration(milliseconds: 120),
              scale: _pressed ? 0.95 : 1.0,
              child: Container(
                width: iconSize,
                height: iconSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: QuickActionsSheet.blueTint,
                  borderRadius: BorderRadius.circular(widget.compact ? 12 : 14),
                  border: Border.all(color: QuickActionsSheet.blue1.withValues(alpha: 0.12)),
                ),
                child: Icon(widget.action.icon, size: widget.compact ? 20 : 22, color: QuickActionsSheet.blue1),
              ),
            ),
            SizedBox(width: widget.compact ? 12 : 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.action.title,
                    style: InsightTheme.inter(15.5, w: FontWeight.w700, c: QuickActionsSheet.ink, ls: -0.2),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: InsightTheme.inter(12, w: FontWeight.w400, c: InsightTheme.ink3, ls: 0.1),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Plain chevron, no circle backing — matches the reference's
            // minimal trailing affordance.
            Icon(Icons.chevron_right_rounded, size: 22, color: QuickActionsSheet.ink2.withValues(alpha: 0.55)),
          ],
        ),
      ),
    );
  }
}
