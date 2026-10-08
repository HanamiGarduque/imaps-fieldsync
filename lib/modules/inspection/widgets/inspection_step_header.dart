import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/theme/insight_theme.dart';
import '../../../core/layout/responsive_layout.dart';

/// ==================================================================
/// INSPECTION STEP HEADER
/// Standardized floating glass containers for Title and Step Progress bar
/// across all 6 inspection step screens (Screenshot 3 design).
/// ==================================================================
class InspectionStepHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final int stepNumber; // 1 to 6
  final String stepSubtitle; // e.g. 'LOCATE TARGET', 'VERIFY COORDINATES'
  final VoidCallback onBack;

  /// Hide the title/subtitle pill and the progress bar, leaving only the back
  /// button.
  ///
  /// A rotated phone or a tablet has very little vertical room, and this header
  /// is ~138px of it — more than a third of a 390px landscape viewport. The
  /// content is what matters there, not the banner.
  ///
  /// Left null it resolves itself from the viewport: shown in portrait, hidden
  /// when the height is scarce. Pass an explicit bool to override. Every call
  /// site keeps the accepted portrait appearance with no changes.
  final bool? compact;

  /// Form steps use roomier text/gutters and retain context on short screens.
  final bool formStyle;
  final Widget? trailing;

  const InspectionStepHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.stepNumber,
    required this.stepSubtitle,
    required this.onBack,
    this.compact,
    this.formStyle = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    // Vertical space is the scarce resource in landscape; spend it on content.
    final isCompact = compact ?? context.responsive.isShortHeight;
    final showContext = !isCompact || formStyle;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        formStyle ? 20 : 16,
        12,
        formStyle ? 20 : 16,
        16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Row 1: Floating back button + Floating title container ──
          // In compact mode only the back button remains, so the step's own
          // content gets the vertical space the banner was using.
          Row(
            children: [
              _StepGlassIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                onTap: onBack,
                tooltip: formStyle ? 'Exit inspection' : 'Back',
              ),
              if (showContext) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: _StepGlassPill(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            title,
                            // Same title size on every step so Steps 1–6 read as
                            // one system.
                            style: InsightTheme.urbanist(
                              16,
                              w: FontWeight.w700,
                              c: InsightTheme.ink,
                            ),
                            maxLines: formStyle ? null : 2,
                            overflow: formStyle ? null : TextOverflow.ellipsis,
                          ),
                        ),
                        if (!isCompact) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: InsightTheme.inter(12, c: InsightTheme.ink2),
                            maxLines: formStyle ? null : 1,
                            overflow: formStyle ? null : TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            ],
          ),

          if (showContext) const SizedBox(height: 10),

          // ── Row 2: Floating Step Progress bar container ──────────────
          // Hidden in compact mode: the step number is already known from the
          // workflow, and this pill costs ~48px of scarce landscape height.
          if (showContext)
            _StepGlassPill(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(
                    child: Row(
                      children: [
                        for (var index = 0; index < 6; index++)
                          Expanded(
                            child: Container(
                              height: 4,
                              margin: EdgeInsets.only(
                                right: index == 5 ? 0 : 4,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(2),
                                color: index == stepNumber - 1
                                    ? InsightTheme.blue1
                                    : index < stepNumber - 1
                                    ? InsightTheme.blue1.withValues(alpha: 0.25)
                                    : InsightTheme.line,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      style: InsightTheme.inter(12, c: InsightTheme.ink3),
                      children: [
                        TextSpan(
                          text: 'STEP $stepNumber OF 6',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: InsightTheme.blueInk,
                          ),
                        ),
                        TextSpan(text: ' — ${stepSubtitle.toUpperCase()}'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StepGlassPill extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _StepGlassPill({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x140B1440),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _StepGlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  const _StepGlassIconButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: 48,
          height: 48,
          decoration: InsightTheme.glassIconButtonDecoration(
            fill: Colors.white.withValues(alpha: 0.88),
          ),
          child: IconButton(
            tooltip: tooltip,
            onPressed: onTap,
            icon: Icon(icon, size: 20, color: InsightTheme.ink),
          ),
        ),
      ),
    );
  }
}
