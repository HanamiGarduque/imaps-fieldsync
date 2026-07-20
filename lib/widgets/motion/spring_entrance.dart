import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// ==================================================================
/// SPRING ENTRANCE
///
/// Replaces the earlier fade/curve-based entrance with a real
/// mass-spring-damper simulation per item: each section starts a beat
/// after the previous one, travels quickly, overshoots its resting spot,
/// then settles — instead of a linear/eased fade. The PAGE itself is
/// never animated (MainShellScreen's IndexedStack already shows it
/// instantly); only the content inside animates, and only after the
/// page is already on screen.
///
/// Tuning: damping ratio 0.55 on a 430 stiffness spring produces ~12-13%
/// overshoot past the resting position and settles to within tolerance
/// in roughly 300-380ms — inside the 250-450ms / "quick but clearly
/// noticeable, single overshoot, not bouncy" brief. Every item gets its
/// own controller (not a shared Interval), so each one genuinely
/// accelerates and decelerates on its own physics rather than being a
/// slice of one master timeline.
///
/// Why this only plays once per visit, not on every tab return: tab
/// screens in this app live inside MainShellScreen's IndexedStack, so
/// their State objects are created a single time and kept alive for as
/// long as the app runs — initState/field initializers fire exactly
/// once across the whole lifetime of that tab, and springFor() below
/// only ever launches a section's simulation the first time it's asked
/// for. There is no code path that resets or replays it on return, and
/// scroll offsets / section state are untouched either way. A screen
/// pushed the normal Navigator way (a new route, not a persisted tab)
/// gets a fresh State on every push, so it correctly animates again —
/// that's a genuinely new instance.
/// ==================================================================
class Spring {
  Spring._();

  static final SpringDescription physics = SpringDescription.withDampingRatio(
    mass: 1.0,
    stiffness: 430,
    ratio: 0.55,
  );

  /// Gap between one section/item starting and the next one starting.
  /// Kept inside the 40-70ms band from the brief.
  static const Duration step = Duration(milliseconds: 55);
}

/// Mix into a screen's State (alongside TickerProviderStateMixin) to get
/// per-item spring-driven entrance animations that:
///  - start only once per State lifetime (see the class doc above for
///    why that means "once per visit, never replayed on tab return")
///  - are staggered 40-70ms apart automatically by index
///  - overshoot then settle via real spring physics, not a curve fake
mixin SpringEntrance<T extends StatefulWidget> on State<T>, TickerProviderStateMixin<T> {
  final Map<Object, AnimationController> _springs = {};

  /// Unbounded animation (can exceed 1.0 during overshoot) for [key] —
  /// its own controller is created and its delayed launch scheduled only
  /// the first time this key is requested, then reused on every
  /// subsequent build. [delayIndex] sets how many [Spring.step]s to wait
  /// before this item's spring launches.
  ///
  /// Use a stable per-item identity (e.g. a task id) as [key] for list
  /// rows built lazily by a SliverList/ListView — that way a card that
  /// only scrolls into view later still gets its own independent spring
  /// (playing the moment it first appears) instead of colliding with a
  /// sibling that happens to land on the same stagger slot. For a fixed
  /// small set of named sections on a screen, the section index alone is
  /// a fine key (see [springFor]).
  Animation<double> springForKey(Object key, int delayIndex) {
    return _springs.putIfAbsent(key, () {
      final controller = AnimationController(vsync: this);
      Future.delayed(Spring.step * delayIndex, () {
        if (!mounted) return;
        controller.animateWith(SpringSimulation(Spring.physics, 0, 1, 0));
      });
      return controller;
    });
  }

  /// Convenience for a screen's fixed top-level sections, where the
  /// section's position in the layout and its stagger slot are the same
  /// number.
  Animation<double> springFor(int index) => springForKey(index, index);

  @mustCallSuper
  void disposeSpringEntrance() {
    for (final c in _springs.values) {
      c.dispose();
    }
  }
}

/// Slides [child] in from [beginOffset] (its starting displacement from
/// the resting position) using a spring [animation] from [SpringEntrance].
/// Because the underlying animation legitimately travels past 1.0, the
/// widget overshoots its final spot before settling — no clamping here,
/// that overshoot is the point.
class SpringSlide extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;
  final Offset beginOffset;
  final bool fade;

  const SpringSlide({
    super.key,
    required this.animation,
    required this.child,
    required this.beginOffset,
    this.fade = true,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final v = animation.value;
        final offset = beginOffset * (1 - v);
        Widget result = Transform.translate(offset: offset, child: child);
        if (fade) {
          // Opacity still needs a valid 0-1 range even though position
          // legitimately overshoots past 1 — fade finishes slightly
          // ahead of the settle so the overshoot itself is never seen
          // through a still-fading widget.
          result = Opacity(opacity: v.clamp(0.0, 1.0), child: result);
        }
        return result;
      },
      child: child,
    );
  }
}

/// Scale-in with spring overshoot (e.g. "pops" slightly past 100% before
/// settling) — used for the sync status card and similar single
/// emphasis elements rather than a directional slide.
class SpringScale extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;
  final double beginScale;
  final bool fade;

  const SpringScale({
    super.key,
    required this.animation,
    required this.child,
    this.beginScale = 0.9,
    this.fade = true,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final v = animation.value;
        final scale = beginScale + (1 - beginScale) * v;
        Widget result = Transform.scale(scale: scale, child: child);
        if (fade) {
          result = Opacity(opacity: v.clamp(0.0, 1.0), child: result);
        }
        return result;
      },
      child: child,
    );
  }
}