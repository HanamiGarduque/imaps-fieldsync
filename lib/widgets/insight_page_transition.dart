import 'package:flutter/material.dart';

/// Fade-through transition for switching between the 4 main tabs (Home,
/// Tasks, Updates, Profile) via the bottom nav — replaces the abrupt
/// default MaterialPageRoute cut. Outgoing page fades+drops out slightly,
/// incoming page fades+rises in; no directional slide, since bottom-nav
/// taps aren't a forward/back stack move.
Route<T> insightTabRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: Transform.translate(
          offset: Offset(0, (1 - curved.value) * 12),
          child: child,
        ),
      );
    },
  );
}