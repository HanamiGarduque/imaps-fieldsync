import 'package:flutter/material.dart';
import 'entrance.dart';

/// ==================================================================
/// UpdatingTile
///
/// Wraps ONE row/card in a list so that a data refresh only animates
/// that row when its own visible content actually changed — every
/// sibling row that didn't change keeps the exact same child identity
/// and is never touched by an animation, per the "never refresh the
/// whole screen" requirement.
///
/// Usage: give each item a stable [itemKey] (its id) and a [signature]
/// built from whatever fields are rendered on screen (status, title,
/// timestamp, etc). Recompute both on every build from the latest data:
///
///   UpdatingTile(
///     itemKey: task.id,
///     signature: Object.hash(task.status, task.scheduledDate),
///     child: TaskCard(task),
///   )
///
/// - Same itemKey + same signature  -> child key unchanged -> no
///   animation, tile just renders (this is the common case on every
///   normal rebuild, e.g. scrolling, sibling state changes).
/// - Same itemKey + different signature -> that field changed on the
///   server/locally -> tile cross-fades + gently rises to its new
///   content.
/// - New itemKey not seen before -> brand new row -> plays the same
///   fade + rise, reading as "this one just arrived".
///
/// For rows that can also be *removed* (not just changed), drive the
/// surrounding list with AnimatedList/SliverAnimatedList instead so the
/// removal itself animates; UpdatingTile only covers in-place changes
/// and additions, which covers most dashboard/metric refresh cases with
/// far less rework than migrating a screen to AnimatedList.
/// ==================================================================
class UpdatingTile extends StatelessWidget {
  final Object itemKey;
  final Object signature;
  final Widget child;

  const UpdatingTile({
    super.key,
    required this.itemKey,
    required this.signature,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Motion.base,
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.standard,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(animation),
          child: child,
        ),
      ),
      // Stack (not the default Column) so the outgoing frame of the
      // previous content doesn't briefly reflow the list underneath it.
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topCenter,
        children: [...previousChildren, ?currentChild],
      ),
      child: KeyedSubtree(key: ValueKey('$itemKey::$signature'), child: child),
    );
  }
}

/// Animates a metric/count smoothly from its previous value to [value]
/// whenever [value] changes, instead of the label just jumping. Safe to
/// rebuild on every parent build — TweenAnimationBuilder only re-animates
/// when the target actually differs from what it last settled on.
class CountUpText extends StatelessWidget {
  final num value;
  final TextStyle? style;
  final String Function(num value) format;
  final Duration duration;
  final TextAlign? textAlign;

  const CountUpText({
    super.key,
    required this.value,
    this.style,
    this.textAlign,
    this.duration = const Duration(milliseconds: 500),
    this.format = _defaultFormat,
  });

  static String _defaultFormat(num v) => v.round().toString();

  @override
  Widget build(BuildContext context) {
    // begin is only consulted on the very first build of this widget;
    // TweenAnimationBuilder itself swaps the effective start to whatever
    // value is currently on screen for every later change, so passing a
    // fixed begin here does not cause a reset-to-zero on refresh.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: Motion.standard,
      builder: (context, v, _) => Text(format(v), style: style, textAlign: textAlign),
    );
  }
}
