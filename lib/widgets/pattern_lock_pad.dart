import 'package:flutter/material.dart';

/// A 3x3 Android-style pattern lock pad.
/// - Drag across dots (min 4) to draw a pattern.
/// - onComplete fires with the ordered dot indices (0-8) once the
///   finger lifts.
/// Deliberately large hit-targets so it still works with field gloves.
class PatternLockPad extends StatefulWidget {
  final ValueChanged<List<int>> onComplete;
  final Color dotColor;
  final Color activeColor;
  final Color errorColor;
  final bool showError;

  const PatternLockPad({
    super.key,
    required this.onComplete,
    this.dotColor = const Color(0xFFA2A7BC),
    this.activeColor = const Color(0xFF3D6BFF),
    this.errorColor = const Color(0xFFE23B4E),
    this.showError = false,
  });

  @override
  State<PatternLockPad> createState() => _PatternLockPadState();
}

class _PatternLockPadState extends State<PatternLockPad> {
  final List<int> _selected = [];
  final List<Offset> _dotPositions = List.filled(9, Offset.zero);
  Offset? _dragPosition;
  static const double _dotRadius = 14;
  static const double _hitRadius = 34;

  void _handleStart(Offset localPos) {
    setState(() {
      _selected.clear();
      _dragPosition = localPos;
      _tryAddDot(localPos);
    });
  }

  void _handleUpdate(Offset localPos) {
    setState(() {
      _dragPosition = localPos;
      _tryAddDot(localPos);
    });
  }

  void _handleEnd() {
    setState(() => _dragPosition = null);
    if (_selected.length >= 4) {
      widget.onComplete(List.from(_selected));
    }
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _selected.clear());
    });
  }

  void _tryAddDot(Offset pos) {
    for (int i = 0; i < 9; i++) {
      if (_selected.contains(i)) continue;
      if ((pos - _dotPositions[i]).distance <= _hitRadius) {
        _selected.add(i);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.maxWidth;
        final cell = size / 3;
        for (int row = 0; row < 3; row++) {
          for (int col = 0; col < 3; col++) {
            final idx = row * 3 + col;
            _dotPositions[idx] = Offset(cell * col + cell / 2, cell * row + cell / 2);
          }
        }

        return GestureDetector(
          onPanStart: (d) => _handleStart(d.localPosition),
          onPanUpdate: (d) => _handleUpdate(d.localPosition),
          onPanEnd: (_) => _handleEnd(),
          child: SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _PatternPainter(
                dotPositions: _dotPositions,
                selected: _selected,
                dragPosition: _dragPosition,
                dotColor: widget.showError ? widget.errorColor : widget.dotColor,
                activeColor: widget.showError ? widget.errorColor : widget.activeColor,
                dotRadius: _dotRadius,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PatternPainter extends CustomPainter {
  final List<Offset> dotPositions;
  final List<int> selected;
  final Offset? dragPosition;
  final Color dotColor;
  final Color activeColor;
  final double dotRadius;

  _PatternPainter({
    required this.dotPositions,
    required this.selected,
    required this.dragPosition,
    required this.dotColor,
    required this.activeColor,
    required this.dotRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = activeColor
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    if (selected.isNotEmpty) {
      final path = Path()..moveTo(dotPositions[selected.first].dx, dotPositions[selected.first].dy);
      for (int i = 1; i < selected.length; i++) {
        path.lineTo(dotPositions[selected[i]].dx, dotPositions[selected[i]].dy);
      }
      if (dragPosition != null) path.lineTo(dragPosition!.dx, dragPosition!.dy);
      canvas.drawPath(path, linePaint);
    }

    for (int i = 0; i < 9; i++) {
      final isActive = selected.contains(i);
      canvas.drawCircle(
        dotPositions[i],
        isActive ? dotRadius : dotRadius * 0.8,
        Paint()..color = isActive ? activeColor : dotColor.withValues(alpha: 0.35),
      );
      canvas.drawCircle(
        dotPositions[i],
        dotRadius * 0.32,
        Paint()..color = isActive ? Colors.white : dotColor.withValues(alpha: 0.6),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter oldDelegate) => true;
}
