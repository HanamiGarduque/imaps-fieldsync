import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/insight_theme.dart';

/// One non-blocking notification above the current screen, using the app's
/// existing Sync Center toast presentation. The caller owns the outcome.
class AppFeedback {
  AppFeedback._();

  static VoidCallback? _dismissCurrent;

  static void dismiss() => _dismissCurrent?.call();

  /// Returns a dismissal bound to this message, so an old screen cannot close
  /// a newer notification. Action results may survive their following pop/push;
  /// screen-specific status explanations opt into [dismissOnNavigation].
  static VoidCallback show(
    BuildContext context, {
    required String message,
    Color color = InsightTheme.blueInk,
    IconData icon = Icons.info_outline_rounded,
    VoidCallback? onRetry,
    bool dismissOnNavigation = false,
  }) {
    dismiss();
    final overlay = Overlay.of(context, rootOverlay: true);
    final route = dismissOnNavigation ? ModalRoute.of(context) : null;
    late OverlayEntry entry;
    var visible = true;
    void close() {
      if (!visible) return;
      visible = false;
      entry.remove();
      entry.dispose();
      if (identical(_dismissCurrent, close)) _dismissCurrent = null;
    }

    entry = OverlayEntry(
      builder: (_) => _FeedbackPopup(
        message: message,
        color: color,
        icon: icon,
        onRetry: onRetry,
        onClose: close,
        route: route,
      ),
    );
    _dismissCurrent = close;
    overlay.insert(entry);
    return close;
  }
}

class _FeedbackPopup extends StatefulWidget {
  const _FeedbackPopup({
    required this.message,
    required this.color,
    required this.icon,
    required this.onClose,
    this.onRetry,
    this.route,
  });

  final String message;
  final Color color;
  final IconData icon;
  final VoidCallback onClose;
  final VoidCallback? onRetry;
  final ModalRoute<dynamic>? route;

  @override
  State<_FeedbackPopup> createState() => _FeedbackPopupState();
}

class _FeedbackPopupState extends State<_FeedbackPopup> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    widget.route?.secondaryAnimation?.addStatusListener(_onCovered);
    widget.route?.animation?.addStatusListener(_onLeaving);
  }

  void _onCovered(AnimationStatus status) {
    if (status == AnimationStatus.forward) widget.onClose();
  }

  void _onLeaving(AnimationStatus status) {
    if (status == AnimationStatus.reverse) widget.onClose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _timer?.cancel();
    // A recovery action stays available; screen-reader users control dismissal.
    if (widget.onRetry == null && !MediaQuery.accessibleNavigationOf(context)) {
      _timer = Timer(const Duration(seconds: 4), widget.onClose);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.route?.secondaryAnimation?.removeStatusListener(_onCovered);
    widget.route?.animation?.removeStatusListener(_onLeaving);
    widget.onClose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Align(
            heightFactor: 1,
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 640,
                maxHeight:
                    (media.size.height -
                            media.viewPadding.vertical -
                            media.viewInsets.bottom -
                            32)
                        .clamp(48.0, double.infinity),
              ),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: media.disableAnimations
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) => Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, -12 * (1 - value)),
                    child: child,
                  ),
                ),
                child: Semantics(
                  container: true,
                  liveRegion: true,
                  child: Material(
                    key: const ValueKey('app-feedback-popup'),
                    color: widget.color,
                    borderRadius: InsightTheme.roundedMd,
                    elevation: 6,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: ExcludeSemantics(
                              child: Icon(
                                widget.icon,
                                size: 24,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.message,
                                  style: InsightTheme.inter(
                                    13,
                                    w: FontWeight.w600,
                                    c: Colors.white,
                                  ),
                                ),
                                if (widget.onRetry != null)
                                  TextButton(
                                    key: const ValueKey('app-feedback-retry'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(64, 48),
                                    ),
                                    onPressed: () {
                                      widget.onClose();
                                      widget.onRetry!();
                                    },
                                    child: const Text('Retry'),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Dismiss notification',
                            constraints: const BoxConstraints(
                              minWidth: 48,
                              minHeight: 48,
                            ),
                            onPressed: widget.onClose,
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
