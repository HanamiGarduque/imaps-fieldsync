import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/insight_theme.dart';
import 'app_feedback.dart';

/// Assignment reads only. This never represents inspection-submit delivery.
enum TaskRefreshPhase {
  checking,
  fresh,
  saved,
  offline,
  failed,
  cacheUnavailable,
  ownerChanged,
}

/// A view of the owning screen's real refresh; it performs no IO of its own.
class TaskSyncIndicator extends StatefulWidget {
  const TaskSyncIndicator({
    super.key,
    required this.phase,
    required this.hasSavedTasks,
    this.lastChecked,
    this.onRetry,
  });

  final TaskRefreshPhase phase;
  final bool hasSavedTasks;
  final DateTime? lastChecked;
  final VoidCallback? onRetry;

  @override
  State<TaskSyncIndicator> createState() => _TaskSyncIndicatorState();
}

class _TaskSyncIndicatorState extends State<TaskSyncIndicator>
    with SingleTickerProviderStateMixin {
  VoidCallback? _dismissFeedback;
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  // Fresh without a verified time is never treated as confirmation.
  TaskRefreshPhase get _phase =>
      widget.phase == TaskRefreshPhase.fresh && widget.lastChecked == null
      ? TaskRefreshPhase.saved
      : widget.phase;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(TaskSyncIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase != widget.phase ||
        oldWidget.lastChecked != widget.lastChecked ||
        oldWidget.hasSavedTasks != widget.hasSavedTasks) {
      _dismissFeedback?.call();
    }
    _syncMotion();
  }

  void _syncMotion() {
    if (_phase == TaskRefreshPhase.checking &&
        !MediaQuery.disableAnimationsOf(context)) {
      if (!_motion.isAnimating) _motion.repeat();
    } else {
      _motion.stop();
    }
  }

  @override
  void dispose() {
    _dismissFeedback?.call();
    _motion.dispose();
    super.dispose();
  }

  String get _label => switch (_phase) {
    TaskRefreshPhase.checking => 'checking for updates',
    TaskRefreshPhase.fresh => 'up to date',
    TaskRefreshPhase.offline =>
      widget.hasSavedTasks ? 'offline, saved tasks' : 'no saved tasks',
    TaskRefreshPhase.saved =>
      widget.hasSavedTasks ? 'saved tasks, not verified' : 'no saved tasks',
    TaskRefreshPhase.failed => 'could not check for updates',
    TaskRefreshPhase.cacheUnavailable => 'saved tasks unavailable',
    TaskRefreshPhase.ownerChanged => 'inspector session changed',
  };

  String get _message {
    final saved = widget.hasSavedTasks;
    switch (_phase) {
      case TaskRefreshPhase.checking:
        return saved
            ? 'Checking for task updates… Your saved tasks are still available.'
            : 'Checking for task updates… An internet connection is needed to load your assignments.';
      case TaskRefreshPhase.fresh:
        final time = widget.lastChecked!
            .toLocal()
            .toIso8601String()
            .split('.')
            .first
            .replaceFirst('T', ' ');
        return 'Task data is up to date. Last checked: $time (local time).';
      case TaskRefreshPhase.offline:
      case TaskRefreshPhase.saved:
        return saved
            ? 'Showing saved task data. Connect and refresh to check for updates.'
            : 'No saved tasks are available on this device. Connect to load your assignments.';
      case TaskRefreshPhase.failed:
        return saved
            ? "Couldn't check for updates. Your saved tasks are still available. Tap Retry to try again."
            : "Couldn't check for updates. No saved tasks are available on this device. Connect and retry to load your assignments.";
      case TaskRefreshPhase.cacheUnavailable:
        return 'Could not read saved tasks on this device. Retry to load your assignments.';
      case TaskRefreshPhase.ownerChanged:
        return 'Inspector session changed. Reopen this screen from your current account.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final phase = _phase;
    final canRetry =
        phase != TaskRefreshPhase.checking &&
        phase != TaskRefreshPhase.fresh &&
        phase != TaskRefreshPhase.ownerChanged &&
        widget.onRetry != null;
    final color = switch (phase) {
      TaskRefreshPhase.checking ||
      TaskRefreshPhase.fresh => InsightTheme.blueInk,
      TaskRefreshPhase.failed ||
      TaskRefreshPhase.cacheUnavailable ||
      TaskRefreshPhase.ownerChanged => InsightTheme.amberInk,
      _ => InsightTheme.ink3,
    };
    final tooltip = 'Task data: $_label';
    return IconButton(
      tooltip: tooltip,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      padding: const EdgeInsets.all(12),
      onPressed: () {
        _dismissFeedback = AppFeedback.show(
          context,
          message: _message,
          color: color,
          icon: phase == TaskRefreshPhase.fresh
              ? Icons.cloud_done_outlined
              : Icons.info_outline_rounded,
          onRetry: canRetry ? widget.onRetry : null,
          dismissOnNavigation: true,
        );
      },
      icon: CustomPaint(
        size: const Size.square(24),
        painter: _TaskCloudPainter(phase, color, _motion),
      ),
    );
  }
}

/// Native counterpart of assets/icon/task_cloud_*.svg. Same 24-unit paths;
/// keeps the SVG artwork crisp without adding a runtime SVG dependency.
class _TaskCloudPainter extends CustomPainter {
  _TaskCloudPainter(this.phase, this.color, this.motion)
    : super(repaint: motion);
  final TaskRefreshPhase phase;
  final Color color;
  final Animation<double> motion;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final cloud = Path()
      ..moveTo(6.5, 18)
      ..cubicTo(3.7, 18, 2, 16.2, 2, 13.8)
      ..cubicTo(2, 11.5, 3.6, 9.7, 5.8, 9.4)
      ..cubicTo(6.5, 6.2, 9.2, 4, 12.4, 4)
      ..cubicTo(16, 4, 18.8, 6.6, 19.1, 10.1)
      ..cubicTo(20.9, 10.6, 22, 12.1, 22, 14)
      ..cubicTo(22, 16.2, 20.2, 18, 18, 18)
      ..close();
    canvas.drawPath(cloud, Paint()..color = color.withValues(alpha: 0.08));
    canvas.drawPath(cloud, stroke);
    if (phase == TaskRefreshPhase.offline || phase == TaskRefreshPhase.saved) {
      canvas.drawLine(
        const Offset(3, 3),
        const Offset(21, 21),
        Paint()
          ..color = InsightTheme.surface
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(const Offset(3, 3), const Offset(21, 21), stroke);
      return;
    }
    const center = Offset(17.5, 17.5);
    canvas.drawCircle(center, 5.5, Paint()..color = InsightTheme.surface);
    if (phase == TaskRefreshPhase.checking) {
      canvas.drawCircle(
        center,
        3.7,
        Paint()
          ..color = color.withValues(alpha: 0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.7,
      );
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: 3.7),
        -math.pi / 2 + motion.value * math.pi * 2,
        math.pi * 1.4,
        false,
        stroke,
      );
    } else if (phase == TaskRefreshPhase.fresh) {
      canvas.drawCircle(center, 4.5, Paint()..color = color);
      canvas.drawPath(
        Path()
          ..moveTo(15.2, 17.5)
          ..lineTo(16.8, 19.1)
          ..lineTo(19.8, 16),
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    } else {
      canvas.drawCircle(center, 4.5, stroke);
      canvas.drawLine(
        const Offset(17.5, 15.3),
        const Offset(17.5, 17.8),
        stroke,
      );
      canvas.drawCircle(const Offset(17.5, 19.7), 0.8, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_TaskCloudPainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.color != color;
}
