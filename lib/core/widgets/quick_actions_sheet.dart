import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// ==================================================================
/// QUICK ACTIONS SHEET
///
/// New pattern (approved by Master), triggered from the nav-adjacent
/// chevron button in `InsightBottomNav`. Deliberately NOT the app's
/// standard full-width `showModalBottomSheet` convention used elsewhere
/// — Master explicitly asked for the floating, inset, rounded-card look
/// from the reference instead, with each row staggering in on open.
///
/// Fonts: spaceGrotesk (title) / ibmPlexSans (row labels) — reused from
/// the same pairing already established in
/// active_assignments_folder_card.dart, not a new import.
/// ==================================================================

class QuickAction {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  const QuickAction({required this.icon, required this.title, required this.onTap});
}

class QuickActionsSheet extends StatefulWidget {
  final List<QuickAction> actions;
  final VoidCallback onClose;

  const QuickActionsSheet({
    super.key,
    required this.actions,
    required this.onClose,
  });

  static const blue1 = Color(0xFF3563FF);
  static const ink = Color(0xFF0F111A);
  static const ink2 = Color(0xFF595E73);
  static const blueTint = Color(0xFFE4EBFF);
  static const line = Color(0x15141628);

  @override
  State<QuickActionsSheet> createState() => _QuickActionsSheetState();
}

class _QuickActionsSheetState extends State<QuickActionsSheet> {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        boxShadow: const [
          BoxShadow(color: Color(0x1A000000), blurRadius: 32, offset: Offset(0, 16)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Quick actions',
                  style: GoogleFonts.spaceGrotesk(fontSize: 17, fontWeight: FontWeight.w700, color: QuickActionsSheet.ink),
                ),
                GestureDetector(
                  onTap: widget.onClose,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F6FB),
                      shape: BoxShape.circle,
                      border: Border.all(color: QuickActionsSheet.line),
                    ),
                    child: const Icon(Icons.close_rounded, size: 18, color: QuickActionsSheet.ink2),
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: QuickActionsSheet.line, margin: const EdgeInsets.symmetric(horizontal: 4)),
          const SizedBox(height: 6),
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
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: _pressed ? const Color(0xFFF4F6FB) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        // 44px+ tap target floor (UDAS §2.3) — row height comfortably
        // exceeds it once padding + icon + text are accounted for.
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: QuickActionsSheet.blueTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(widget.action.icon, size: 20, color: QuickActionsSheet.blue1),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                widget.action.title,
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: QuickActionsSheet.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}