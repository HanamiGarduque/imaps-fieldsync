import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/theme/insight_theme.dart';

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

  const InspectionStepHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.stepNumber,
    required this.stepSubtitle,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Row 1: Floating back button + Floating title container ──
          Row(
            children: [
              _StepGlassIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                onTap: onBack,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StepGlassPill(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: InsightTheme.poppins(15, w: FontWeight.w700, c: InsightTheme.ink),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        style: InsightTheme.inter(11, c: InsightTheme.ink2),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // ── Row 2: Floating Step Progress bar container ──────────────
          _StepGlassPill(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    height: 5,
                    color: InsightTheme.surface2,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: (stepNumber / 6.0).clamp(0.0, 1.0),
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [InsightTheme.blue1, InsightTheme.blue2],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      'STEP $stepNumber OF 6',
                      style: InsightTheme.jetBrains(10, w: FontWeight.w700, c: InsightTheme.blueInk, ls: 0.5),
                    ),
                    Expanded(
                      child: Text(
                        ' — ${stepSubtitle.toUpperCase()}',
                        style: InsightTheme.jetBrains(10, c: InsightTheme.ink3, ls: 0.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
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
              BoxShadow(color: Color(0x140B1440), blurRadius: 20, offset: Offset(0, 8)),
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

  const _StepGlassIconButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
              boxShadow: const [
                BoxShadow(color: Color(0x140B1440), blurRadius: 20, offset: Offset(0, 8)),
              ],
            ),
            child: Icon(icon, size: 18, color: InsightTheme.ink),
          ),
        ),
      ),
    );
  }
}
