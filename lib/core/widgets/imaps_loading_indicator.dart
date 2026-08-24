import 'package:flutter/material.dart';

import '../theme/insight_theme.dart';

enum ImapsLoadingState {
  syncingData,
  loadingMaps,
  verifyingGps,
  processing,
}

extension ImapsLoadingStateLabel on ImapsLoadingState {
  String get label {
    switch (this) {
      case ImapsLoadingState.syncingData:
        return "Syncing data...";
      case ImapsLoadingState.loadingMaps:
        return "Loading maps...";
      case ImapsLoadingState.verifyingGps:
        return "Verifying GPS...";
      case ImapsLoadingState.processing:
        return "Processing...";
    }
  }
}

class ImapsLoadingIndicator extends StatefulWidget {
  final double size;
  final String? label;

  const ImapsLoadingIndicator({
    super.key,
    this.size = 100,
    this.label,
  });

  @override
  State<ImapsLoadingIndicator> createState() => _ImapsLoadingIndicatorState();
}

class _ImapsLoadingIndicatorState extends State<ImapsLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Canonical blue ramp (InsightTheme tokens). Replaces the old private
  // E7F0FF/A9C4FF/5A8CFF/255DFF family so every loading state shares the
  // same brand blues as the rest of the app.
  static final _ringColors = [
    InsightTheme.blueTint,
    InsightTheme.blue1.withValues(alpha: 0.55),
    InsightTheme.blue1,
  ];
  static final _centerColor = InsightTheme.blue2;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  for (int i = 0; i < 3; i++) _buildRing(i),
                  Container(
                    width: widget.size * 0.22,
                    height: widget.size * 0.22,
                    decoration: BoxDecoration(
                      color: _centerColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        if (widget.label != null) ...[
          const SizedBox(height: 12),
          Text(
            widget.label!,
            style: InsightTheme.inter(14, w: FontWeight.w500, c: InsightTheme.ink),
          ),
        ],
      ],
    );
  }

  Widget _buildRing(int index) {
    final double staggerOffset = index * 0.33;
    final double t = (_controller.value + staggerOffset) % 1.0;

    final double scale = 0.2 + (t * 0.8);
    final double opacity = (1.0 - t).clamp(0.0, 1.0);

    return Opacity(
      opacity: opacity,
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: _ringColors[index],
              width: 2,
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen overlay version, para magamit mo kahit saan sa app.
/// Usage: ImapsLoadingOverlay.show(context, state: ImapsLoadingState.syncingData);
///        ImapsLoadingOverlay.hide();
class ImapsLoadingOverlay {
  static OverlayEntry? _entry;

  static void show(
    BuildContext context, {
    ImapsLoadingState state = ImapsLoadingState.processing,
  }) {
    hide(); // remove existing overlay muna kung meron

    final overlay = Overlay.of(context, rootOverlay: true);
    _entry = OverlayEntry(
      builder: (context) => Container(
        color: Colors.black.withValues(alpha: 0.35),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 32,
              vertical: 28,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ImapsLoadingIndicator(
              size: 90,
              label: state.label,
            ),
          ),
        ),
      ),
    );

    overlay.insert(_entry!);
  }

  static void hide() {
    _entry?.remove();
    _entry = null;
  }
}