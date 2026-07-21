import 'package:flutter/material.dart';

/// ==================================================================
/// LINKED LIST MOTION ANIMATION
///
/// Animates list items sequentially as a linked chain (Node 0 -> Node 1 -> Node 2...).
/// Each item enters with a combined:
///  1. Fade-in (0.0 -> 1.0)
///  2. Subtle Scale-up with gentle spring overshoot (0.93 -> 1.0)
///  3. Chained Slide transition (Offset begin -> Offset.zero)
/// ==================================================================
class LinkedListSlide extends StatefulWidget {
  final int index;
  final Widget child;
  final Duration duration;
  final Duration itemDelay;
  final Offset beginOffset;

  const LinkedListSlide({
    super.key,
    required this.index,
    required this.child,
    this.duration = const Duration(milliseconds: 420),
    this.itemDelay = const Duration(milliseconds: 65),
    this.beginOffset = const Offset(0.06, 0.0),
  });

  @override
  State<LinkedListSlide> createState() => _LinkedListSlideState();
}

class _LinkedListSlideState extends State<LinkedListSlide> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);

    final curved = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
    _scaleAnimation = Tween<double>(begin: 0.93, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _slideAnimation = Tween<Offset>(begin: widget.beginOffset, end: Offset.zero).animate(curved);

    final delay = widget.itemDelay * (widget.index.clamp(0, 10));
    Future.delayed(delay, () {
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
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: widget.child,
        ),
      ),
    );
  }
}
