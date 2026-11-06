import 'dart:math' as math;
import 'package:flutter/painting.dart';

class GuidePlacement {
  const GuidePlacement({
    required this.bubble,
    required this.spotlight,
    required this.overview,
    this.viewportInsets = EdgeInsets.zero,
    this.arrowTip,
  });
  final Rect bubble;
  final Rect? spotlight;
  final bool overview;
  final EdgeInsets viewportInsets;
  final Offset? arrowTip;

  static GuidePlacement resolve({
    required Rect safe,
    required Rect? target,
    required Rect? anchor,
    required Size desiredCoach,
    required Size minimumCoach,
    EdgeInsets viewportInsets = EdgeInsets.zero,
  }) {
    const gap = 12.0;
    // The overlay already clips targets to their actual visible viewport.
    // The coach's gesture-safe lane must not trim the highlighted feature.
    final visible = target;
    GuidePlacement placed(Rect bubble, EdgeInsets insets) {
      final highlighted = visible != null && !bubble.overlaps(visible)
          ? visible
          : null;
      final center = bubble.center;
      final tip = highlighted == null
          ? null
          : Offset(
              center.dx.clamp(highlighted.left, highlighted.right),
              center.dy.clamp(highlighted.top, highlighted.bottom),
            );
      return GuidePlacement(
        bubble: bubble,
        spotlight: highlighted,
        overview: highlighted == null,
        viewportInsets: insets,
        arrowTip: tip,
      );
    }

    // The fingerprint speaks from its normal stationary navigation position.
    // Use the same compact footprint while first measuring, never a white
    // screen-sized placeholder between explanations.
    final speaker =
        anchor ?? Rect.fromLTWH(safe.right - 64, safe.bottom - 140, 64, 64);
    final width = math.min(
      desiredCoach.width,
      math.max(0.0, math.min(safe.width, speaker.left - gap - safe.left)),
    );
    final height = math.min(
      safe.height,
      math.max(
        minimumCoach.height,
        math.min(desiredCoach.height, safe.height < 600 ? 220.0 : 280.0),
      ),
    );
    final bubble = Rect.fromLTWH(
      math.max(safe.left, speaker.left - gap - width),
      (speaker.bottom - height).clamp(safe.top, safe.bottom - height),
      width,
      height,
    );
    var insets = viewportInsets;
    if (visible != null && bubble.inflate(gap).overlaps(visible)) {
      // Reflow only the guide-owned page; the real retained shell is untouched.
      insets = safe.width > safe.height
          ? EdgeInsets.only(
              right: math.max(
                insets.right,
                safe.right - bubble.left + gap + 12,
              ),
            )
          : EdgeInsets.only(
              bottom: math.max(
                insets.bottom,
                safe.bottom - bubble.top + gap + 12,
              ),
            );
    }
    return placed(bubble, insets);
  }
}
