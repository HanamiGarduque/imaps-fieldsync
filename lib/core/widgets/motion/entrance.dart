import 'package:flutter/material.dart';

/// ==================================================================
/// MOTION TOKENS
///
/// Small shared duration/curve set for widgets that animate an IN-PLACE
/// content change (a row's data updated, a number ticked up) — distinct
/// from the one-time per-visit spring entrance system in
/// spring_entrance.dart, which is for whole sections appearing the first
/// time a screen is visited, not for values changing on an already-
/// visible widget.
///
/// Used by UpdatingTile (cross-fade + rise when a row's signature
/// changes) and CountUpText (number tween) in updating_tile.dart.
/// ==================================================================
class Motion {
  Motion._();

  /// Standard transition duration for an in-place content swap — in the
  /// same ~300ms neighborhood as Spring's ~300-380ms settle time
  /// (spring_entrance.dart) so the two motion systems feel consistent
  /// even though they're built differently.
  static const Duration base = Duration(milliseconds: 300);

  /// Incoming content — quick start, eases into its resting state.
  static const Curve enter = Curves.easeOutCubic;

  /// Default easing for anything without a distinct enter/exit shape —
  /// outgoing content in UpdatingTile, and CountUpText's number tween.
  static const Curve standard = Curves.easeInOutCubic;
}
