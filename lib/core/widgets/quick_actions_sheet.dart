import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/insight_theme.dart';

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

class QuickActionsSheet extends StatefulWidget {
  final List<QuickAction> actions;
  final VoidCallback onClose;

  const QuickActionsSheet({
    super.key,
    required this.actions,
    required this.onClose,
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
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        boxShadow: const [
          BoxShadow(color: Color(0x1A000000), blurRadius: 32, offset: Offset(0, 16)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Quick actions',
                  style: InsightTheme.urbanist(20, w: FontWeight.w700, c: QuickActionsSheet.ink, ls: -0.3),
                ),
                GestureDetector(
                  onTap: widget.onClose,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF1F2F8),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded, size: 20, color: QuickActionsSheet.ink2),
                  ),
                ),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < widget.actions.length; i++)
                _StaggeredEntry(
                  index: i,
                  child: _QuickActionRow(action: widget.actions[i], onClose: widget.onClose),
                ),
            ],
          ),
        ],
      ),
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
  const _QuickActionRow({required this.action, required this.onClose});

  @override
  State<_QuickActionRow> createState() => _QuickActionRowState();
}

class _QuickActionRowState extends State<_QuickActionRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final subtitle = widget.action.subtitle;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onClose();
        widget.action.onTap();
      },
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: QuickActionsSheet.blueTint,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: QuickActionsSheet.blue1.withValues(alpha: 0.12)),
                ),
                child: Icon(widget.action.icon, size: 22, color: QuickActionsSheet.blue1),
              ),
            ),
            const SizedBox(width: 16),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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