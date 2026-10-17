import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/insight_theme.dart';
import 'fieldsync_entrance_animation.dart';
import 'fieldsync_logo_geometry.dart';

/// Global timeline of the approved three-page startup cinematic (SPEC v3), in
/// absolute seconds from the first frame of the launch.
///
/// One clock drives all three pages. The approved entrance animation is fed
/// 1:1 from [painterStartSeconds], so its own timeline is this one shifted by
/// that offset, and every shared beat below is the approved painter's own
/// window plus the same offset. That identity is what makes the Page 1 → Page
/// 2 seam invisible: at [seamSeconds] this page shows exactly the frame
/// [FieldSyncEntrancePainter] frames at
/// [FieldSyncEntranceTimeline.handoffSeconds].
class FieldSyncCinematicTimeline {
  FieldSyncCinematicTimeline._();

  /// Nominal total, from the first frame to the moment the destination screen
  /// is settled and the cinematic barrier may release.
  static const double totalSeconds = 13.35;

  /// Global second the approved entrance painter starts on
  /// (global → entrance-local: `local = global − painterStartSeconds`). It is
  /// hidden until the seam; this page carries the frame up to it.
  static const double painterStartSeconds = 3.65;

  /// Page 1 → Page 2 seam. Derived from the frozen T3 API, never retyped:
  /// moving [FieldSyncEntranceTimeline.handoffSeconds] moves the seam.
  static const double seamSeconds =
      painterStartSeconds + FieldSyncEntranceTimeline.handoffSeconds;

  // ── Page 1: navigation search (implemented in this file) ──────────────────

  /// Terrain fade-in complete; the search line begins to draw in.
  static const double settleEndSeconds = 0.40;

  /// The line has entered through the bottom edge; the search proper begins.
  static const double enterEndSeconds = 1.30;

  /// The camera begins framing the discovered destination.
  static const double searchEndSeconds = 4.50;

  /// The search line reaches the site dot and the arrival begins. Mirrors the
  /// approved painter's own arrival at entrance-local 1.62.
  static const double arriveSeconds = 5.27;

  /// Red site dot pop complete (mirrors entrance-local 1.90).
  static const double dotPopEndSeconds = 5.55;

  /// Arrival-window mirrors of the approved painter's beats, all shifted by
  /// [painterStartSeconds] — the seam-congruence contract, pinned by tests.
  static const double bloomStartSeconds = 5.15; // entrance-local 1.50
  static const double bloomEndSeconds = 5.75; // entrance-local 2.10
  static const double arrowStartSeconds = 5.20; // entrance-local 1.55
  static const double arrowEndSeconds = 5.50; // entrance-local 1.85
  static const double puckOutStartSeconds = 5.10; // entrance-local 1.45
  static const double puckOutEndSeconds = 5.27; // entrance-local 1.62
  static const double pulseStartSeconds = 5.31; // entrance-local 1.66
  static const double pulseGapSeconds = 0.13;
  static const double pulseDurationSeconds = 0.95;

  /// The approved painter's own route-ghost dissolve window (entrance-local
  /// 2.15–2.90), mirrored so both layers agree in time as the seam
  /// cross-fade runs.
  static const double routeGhostOutStartSeconds = seamSeconds;
  static const double routeGhostOutEndSeconds = 6.55;

  // ── Page 2: the approved entrance (wired in T5; boundaries only here) ─────

  /// The approved formation has fully settled (entrance-local 5.15).
  static const double formationEndSeconds = 8.80;

  /// The approved entrance's hold is over — Page 2 departs. Equals the
  /// approved painter's own end of timeline (entrance-local
  /// [FieldSyncEntranceTimeline.total]).
  static const double holdEndSeconds =
      painterStartSeconds + FieldSyncEntranceTimeline.total;

  // ── Page 3: destination re-entry (wired in T5/T6; boundaries only here) ───

  static const double departureStartSeconds = holdEndSeconds;
  static const double departureEndSeconds = 11.05;
  static const double mountStartSeconds = 10.85;
  static const double mountEndSeconds = 11.15;
  static const double travelEndSeconds = 11.95;
  static const double revealEndSeconds = totalSeconds;
}

/// The driven, navigation-free Page 1 stage.
///
/// It paints exactly what its clock says and nothing else: no controller, no
/// timers, no navigation, no state. The host supplies global cinematic time
/// and decides when the seam frame may leave the screen; that orchestration
/// is deliberately not part of this widget.
class FieldSyncCinematicStage extends StatelessWidget {
  const FieldSyncCinematicStage({super.key, required this.time});

  /// Global cinematic seconds ([FieldSyncCinematicTimeline]). Values outside
  /// the timeline paint held boundary frames rather than extrapolating.
  final Animation<double> time;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        isComplex: true,
        size: Size.infinite,
        painter: FieldSyncCinematicScenePainter(time: time),
      ),
    );
  }
}

/// Paints Page 1 of the three-page cinematic — an inspector's navigation
/// search across the fingerprint terrain — for any position of [time].
///
/// Everything is deterministic in the clock ([cameraAt] and the element
/// windows are pure functions); the same timestamp always paints the same
/// frame. The page ends by construction on the exact camera the approved
/// entrance framed at [FieldSyncEntranceTimeline.handoffSeconds]: at
/// [FieldSyncCinematicTimeline.seamSeconds] and beyond, [cameraAt] returns
/// `FieldSyncEntrancePainter.cameraAt(handoffSeconds)` verbatim, so the
/// handoff cannot drift from the approved maths.
///
/// Element regularity follows the same rule: the terrain is the artwork's own
/// fingerprint paths, the line rides the artwork's own route into the site
/// dot at its official world coordinates, and every arrival beat (pop, rings,
/// bloom, arrowhead, puck fade) mirrors the approved painter's own window
/// shifted by [FieldSyncCinematicTimeline.painterStartSeconds]. The red dot
/// never moves in world space — discovery framing is camera only.
class FieldSyncCinematicScenePainter extends CustomPainter {
  FieldSyncCinematicScenePainter({required this.time}) : super(repaint: time);

  /// Global cinematic seconds.
  final Animation<double> time;

  static const Color _siteRed = Color(0xFFEF3B3B);
  static const Color _kitNavy = Color(0xFF102D50);

  // ── authored camera (Page 1) ──────────────────────────────────────────────
  static const double _zoomEstablish = 2.0;
  static const double _zoomEnter = 2.4;
  static const double _zoomArrival = 7.2;
  static const Offset _establishCentre = Offset(560, 700);
  static const Offset _reframeA = Offset(700, 800);
  static const Offset _reframeB = Offset(500, 700);
  static const double _enterBlendStart = 0.55;
  static const double _arrivalHoldSeconds = 5.05;
  static const double _lookAhead = 0.04;

  // ── authored search corridor (viewBox units) ──────────────────────────────
  // A serpentine crossing the fingerprint field with six deliberate turns —
  // left, right, left, right, left, right — then an exact C1 join onto the
  // artwork's own navigation route (the same route the approved entrance
  // rides), which carries the line to the site dot. The join point and the
  // join direction are read from the real route metric at prepare time, so
  // the join cannot drift from the official geometry.
  static const List<Offset> _waypoints = <Offset>[
    Offset(596, 1260), // below the visible bottom edge
    Offset(736, 1076),
    Offset(606, 946),
    Offset(806, 872),
    Offset(614, 762),
    Offset(764, 628),
    Offset(588, 682),
    Offset(368, 900),
  ];

  /// Global windows in which the tip traverses each leg: the eight search
  /// legs, then the artwork route itself. Speeds vary deliberately — slow in
  /// the tight turns, opening up on the long west sweep and the final ride
  /// home. The first window starts at
  /// [FieldSyncCinematicTimeline.settleEndSeconds].
  static const List<double> _legEndSeconds = <double>[
    0.95,
    1.42,
    2.00,
    2.55,
    3.05,
    3.55,
    4.20,
    4.72,
    FieldSyncCinematicTimeline.arriveSeconds,
  ];

  // ── arrival-mirror styles (kept in step with the approved painter) ────────
  static const double _ridgeTerrainAlpha = 0.10; // painter's ridge ghost level
  static const double _routeGhostAlpha = 0.16; // painter's route ghost level
  static const double _puckPopEnd = 0.68;
  static const double _puckIn = FieldSyncCinematicTimeline.settleEndSeconds;

  /// The site marker's official world position — the same point the approved
  /// painter pops, never moved.
  static const Offset _siteDot = Offset(
    FieldSyncLogoGeometry.siteDotX,
    FieldSyncLogoGeometry.siteDotY,
  );

  // ── prepared once (pure geometry) ─────────────────────────────────────────
  static Path? _searchPath;
  static ui.PathMetric? _searchMetric;
  static ui.PathMetric? _routeMetric;
  static double _searchLength = 0;
  static double _routeLength = 0;
  static double _graphLength = 0;
  static final List<double> _legLengths = <double>[];
  static final List<double> _legStarts = <double>[];

  /// The approved painter's seam state, resolved once — the single source of
  /// truth this page lands on.
  static final FieldSyncEntranceCamera _seamCamera =
      FieldSyncEntrancePainter.cameraAt(
        FieldSyncEntranceTimeline.handoffSeconds,
      );

  /// The authored search corridor, exposed for the shape invariants (turn
  /// count, C1 join). Built once from official route geometry.
  static Path get searchPath {
    _prepare();
    return _searchPath!;
  }

  static void _prepare() {
    if (_searchPath != null) return;
    final route = FieldSyncLogoGeometry.route.computeMetrics().first;
    _routeMetric = route;
    _routeLength = route.length;
    final join = route.getTangentForOffset(0)!.position;
    final joinAhead = route.getTangentForOffset(0.5)!.position;
    final joinVector = joinAhead - join;
    final joinDirection = joinVector / joinVector.distance;

    final points = <Offset>[..._waypoints, join];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    _legLengths.clear();
    _legStarts.clear();
    var traversed = 0.0;
    for (var i = 0; i < points.length - 1; i++) {
      final from = points[i];
      final to = points[i + 1];
      final previous = i == 0 ? points[0] : points[i - 1];
      final next = i + 2 < points.length ? points[i + 2] : null;
      final control1 = from + (to - previous) / 6;
      // The final leg's end tangent is the route's own start direction,
      // verbatim — the C1 join onto the official route.
      final control2 = next != null
          ? to - (next - from) / 6
          : to - joinDirection * ((to - from).distance / 6);
      path.cubicTo(
        control1.dx,
        control1.dy,
        control2.dx,
        control2.dy,
        to.dx,
        to.dy,
      );
      final leg = Path()
        ..moveTo(from.dx, from.dy)
        ..cubicTo(
          control1.dx,
          control1.dy,
          control2.dx,
          control2.dy,
          to.dx,
          to.dy,
        );
      final length = leg.computeMetrics().first.length;
      _legStarts.add(traversed);
      _legLengths.add(length);
      traversed += length;
    }
    _searchLength = traversed;
    _legStarts.add(_searchLength);
    _legLengths.add(_routeLength);
    _graphLength = _searchLength + _routeLength;
    _searchPath = path;
    _searchMetric = path.computeMetrics().first;
  }

  static double _win(double t, double a, double b) =>
      ((t - a) / (b - a)).clamp(0.0, 1.0);

  static double _ease(Curve curve, double t, double a, double b) =>
      curve.transform(_win(t, a, b));

  /// Fraction (0..1) of the whole authored graph — search legs, then the
  /// artwork route — that the tip has traversed at global second [t]. Each
  /// leg eases in and out of its turn; the schedule is monotone and clamped.
  static double tipFractionAt(double t) {
    _prepare();
    if (t <= FieldSyncCinematicTimeline.settleEndSeconds) return 0;
    var legStart = FieldSyncCinematicTimeline.settleEndSeconds;
    for (var i = 0; i < _legEndSeconds.length; i++) {
      final legEnd = _legEndSeconds[i];
      if (t < legEnd) {
        final e = Curves.easeInOutSine.transform(
          ((t - legStart) / (legEnd - legStart)).clamp(0.0, 1.0),
        );
        return (_legStarts[i] + _legLengths[i] * e) / _graphLength;
      }
      legStart = legEnd;
    }
    return 1.0;
  }

  static Offset _graphPointAt(double fraction) {
    _prepare();
    final distance = (fraction * _graphLength).clamp(0.0, _graphLength);
    if (distance <= _searchLength) {
      return _searchMetric!.getTangentForOffset(distance)!.position;
    }
    return _routeMetric!
        .getTangentForOffset(distance - _searchLength)!
        .position;
  }

  /// The camera's exact state at global second [globalSeconds].
  ///
  /// For anything at or past [FieldSyncCinematicTimeline.seamSeconds] this is
  /// the approved painter's own [FieldSyncEntranceTimeline.handoffSeconds]
  /// state, returned verbatim; before the seam it is this page's authored
  /// search camera, easing onto that same state over the final reframe so the
  /// landing has no step.
  static FieldSyncEntranceCamera cameraAt(double globalSeconds) {
    final seam = FieldSyncCinematicTimeline.seamSeconds;
    if (globalSeconds >= seam) {
      return _seamCamera;
    }
    final t = globalSeconds.clamp(0.0, seam);
    return FieldSyncEntranceCamera(
      zoom: _zoomAt(t),
      centre: _centreAt(t),
      anchorT: _anchorAt(t),
    );
  }

  static double _zoomAt(double t) {
    if (t < FieldSyncCinematicTimeline.enterEndSeconds) {
      return _zoomEstablish +
          (_zoomEnter - _zoomEstablish) *
              _ease(
                Curves.easeInOutSine,
                t,
                0,
                FieldSyncCinematicTimeline.enterEndSeconds,
              );
    }
    if (t < FieldSyncCinematicTimeline.arriveSeconds) {
      return _zoomEnter +
          (_zoomArrival - _zoomEnter) *
              _ease(
                Curves.easeInSine,
                t,
                FieldSyncCinematicTimeline.enterEndSeconds,
                FieldSyncCinematicTimeline.arriveSeconds,
              );
    }
    return _zoomArrival +
        (_seamCamera.zoom - _zoomArrival) *
            _ease(
              Curves.easeInOutSine,
              t,
              FieldSyncCinematicTimeline.arriveSeconds,
              FieldSyncCinematicTimeline.seamSeconds,
            );
  }

  static Offset _centreAt(double t) {
    final follow = _graphPointAt(
      math.min(1.0, tipFractionAt(t) + _lookAhead),
    );
    if (t < _enterBlendStart) return _establishCentre;
    if (t < FieldSyncCinematicTimeline.enterEndSeconds) {
      return Offset.lerp(
        _establishCentre,
        follow,
        _ease(
          Curves.easeInOutSine,
          t,
          _enterBlendStart,
          FieldSyncCinematicTimeline.enterEndSeconds,
        ),
      )!;
    }
    if (t < FieldSyncCinematicTimeline.searchEndSeconds) {
      // The two gentle reframes: the frame leads the line into the east
      // corridor, then pre-views the west sweep and the join.
      final a = _ease(Curves.easeInOutSine, t, 1.95, 2.65);
      final b = _ease(Curves.easeInOutSine, t, 3.25, 3.95);
      return Offset.lerp(Offset.lerp(follow, _reframeA, a)!, _reframeB, b)!;
    }
    if (t < _arrivalHoldSeconds) {
      return Offset.lerp(
        _reframeB,
        _siteDot,
        _ease(
          Curves.easeInOutSine,
          t,
          FieldSyncCinematicTimeline.searchEndSeconds,
          _arrivalHoldSeconds,
        ),
      )!;
    }
    if (t < FieldSyncCinematicTimeline.arriveSeconds) return _siteDot;
    return Offset.lerp(
      _siteDot,
      _seamCamera.centre,
      _ease(
        Curves.easeInOutSine,
        t,
        FieldSyncCinematicTimeline.arriveSeconds,
        FieldSyncCinematicTimeline.seamSeconds,
      ),
    )!;
  }

  static double _anchorAt(double t) {
    if (t < FieldSyncCinematicTimeline.searchEndSeconds) return 0;
    if (t < FieldSyncCinematicTimeline.arriveSeconds) {
      return _ease(
        Curves.easeInOutSine,
        t,
        FieldSyncCinematicTimeline.searchEndSeconds,
        _arrivalHoldSeconds,
      );
    }
    return 1.0 +
        (_seamCamera.anchorT - 1.0) *
            _ease(
              Curves.easeInOutSine,
              t,
              FieldSyncCinematicTimeline.arriveSeconds,
              FieldSyncCinematicTimeline.seamSeconds,
            );
  }

  /// Red-dot visibility at global [t]: invisible until the line arrives, then
  /// the approved pop. Settled (alpha 1) by the seam — exactly the state the
  /// approved painter shows at entrance-local 2.15.
  static double redDotAlphaAt(double t) {
    if (t < FieldSyncCinematicTimeline.arriveSeconds) return 0;
    return _ease(
      Curves.easeOutCubic,
      t,
      FieldSyncCinematicTimeline.arriveSeconds,
      FieldSyncCinematicTimeline.dotPopEndSeconds,
    );
  }

  /// Red-dot pop scale, mirroring the approved painter's own curve.
  static double redDotScaleAt(double t) {
    if (t < FieldSyncCinematicTimeline.arriveSeconds) return 0.55;
    final e = _ease(
      Curves.easeOutCubic,
      t,
      FieldSyncCinematicTimeline.arriveSeconds,
      FieldSyncCinematicTimeline.dotPopEndSeconds,
    );
    return (0.55 + 0.45 * e) * (1 + 0.12 * math.sin(math.pi * e));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    _prepare();
    final t = time.value;
    final camera = cameraAt(t);
    final q = FieldSyncEntranceCamera.viewportFit(size);
    final anchor = FieldSyncEntranceCamera.screenAnchorOf(
      size,
      camera.anchorT,
    );

    // The field: full-bleed brand blue under everything.
    canvas.drawRect(Offset.zero & size, Paint()..color = InsightTheme.blue2);

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(anchor.dx, anchor.dy);
    canvas.scale(q * camera.zoom);
    canvas.translate(-camera.centre.dx, -camera.centre.dy);

    _paintTerrain(canvas, t);
    _paintRouteGhost(canvas, t);
    _paintSearchLine(canvas, t);
    _paintArrival(canvas, t);
    _paintTraveller(canvas, t);

    canvas.restore();
  }

  /// The official fingerprint ribbons as abstract terrain: the artwork's own
  /// ridge paths, filled at the level the approved painter's ridge ghosts
  /// hold, ramped in during the settle.
  void _paintTerrain(Canvas canvas, double t) {
    final alpha = _ridgeTerrainAlpha *
        _ease(
          Curves.easeOutCubic,
          t,
          0,
          FieldSyncCinematicTimeline.settleEndSeconds,
        );
    if (alpha <= 0.004) return;
    final paint = Paint()..color = Colors.white.withValues(alpha: alpha);
    for (final ridge in FieldSyncLogoGeometry.fingerprints) {
      canvas.drawPath(ridge, paint);
    }
  }

  /// The artwork's planned route as the pale path the search is converging
  /// on. It fades in as the arrival seals and then dissolves on exactly the
  /// approved painter's own ghost window, so both layers agree in time
  /// through the seam cross-fade.
  void _paintRouteGhost(Canvas canvas, double t) {
    var alpha = _routeGhostAlpha *
        _ease(
          Curves.easeInOutSine,
          t,
          FieldSyncCinematicTimeline.arriveSeconds,
          FieldSyncCinematicTimeline.seamSeconds,
        );
    if (t > FieldSyncCinematicTimeline.seamSeconds) {
      alpha *= 1 -
          _ease(
            Curves.easeInOutSine,
            t,
            FieldSyncCinematicTimeline.routeGhostOutStartSeconds,
            FieldSyncCinematicTimeline.routeGhostOutEndSeconds,
          );
    }
    if (alpha <= 0.004) return;
    canvas.drawPath(
      FieldSyncLogoGeometry.route,
      Paint()
        ..color = Colors.white.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = FieldSyncLogoGeometry.routeStrokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.1),
    );
  }

  /// The navigation line: the authored search corridor and, once the tip
  /// reaches it, the artwork's own route — drawn to exactly the tip's own
  /// arc-length position, so the line and the head never disagree.
  void _paintSearchLine(Canvas canvas, double t) {
    final u = tipFractionAt(t);
    if (u <= 0) return;
    final distance = u * _graphLength;
    final drawn = Path();
    drawn.addPath(
      _searchMetric!.extractPath(0, math.min(distance, _searchLength)),
      Offset.zero,
    );
    if (distance > _searchLength) {
      drawn.addPath(
        _routeMetric!.extractPath(
          0,
          (distance - _searchLength).clamp(0.0, _routeLength),
        ),
        Offset.zero,
      );
    }
    canvas.drawPath(
      drawn,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = FieldSyncLogoGeometry.routeStrokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  /// Arrival: bloom, arrowhead, pulse rings, red dot — the approved painter's
  /// own beats, mirrored.
  void _paintArrival(Canvas canvas, double t) {
    final bloomW = _win(
      t,
      FieldSyncCinematicTimeline.bloomStartSeconds,
      FieldSyncCinematicTimeline.bloomEndSeconds,
    );
    if (bloomW > 0 && bloomW < 1) {
      final radius = 3 + 26 * Curves.easeOutCubic.transform(bloomW);
      canvas.drawCircle(
        _siteDot,
        radius,
        Paint()
          ..shader = ui.Gradient.radial(_siteDot, radius, [
            Colors.white.withValues(alpha: 0.45 * (1 - bloomW)),
            Colors.white.withValues(alpha: 0),
          ]),
      );
    }

    final arrowA = _ease(
      Curves.easeOutCubic,
      t,
      FieldSyncCinematicTimeline.arrowStartSeconds,
      FieldSyncCinematicTimeline.arrowEndSeconds,
    );
    if (arrowA > 0.004) {
      const tip = Offset(686, 447);
      canvas.save();
      canvas.translate(tip.dx, tip.dy);
      canvas.scale(0.7 + 0.3 * arrowA);
      canvas.translate(-tip.dx, -tip.dy);
      canvas.drawPath(
        FieldSyncLogoGeometry.routeArrowhead,
        Paint()..color = Colors.white.withValues(alpha: arrowA),
      );
      canvas.restore();
    }

    // The approved rings, continuing across the seam with no phase reset:
    // this layer draws them up to the seam; the approved painter continues
    // the same rings from its own local 2.15 with identical phase.
    if (t <= FieldSyncCinematicTimeline.seamSeconds) {
      for (var k = 0; k < 2; k++) {
        final start = FieldSyncCinematicTimeline.pulseStartSeconds +
            k * FieldSyncCinematicTimeline.pulseGapSeconds;
        final w = _win(
          t,
          start,
          start + FieldSyncCinematicTimeline.pulseDurationSeconds,
        );
        if (w <= 0 || w >= 1) continue;
        final e = Curves.easeOutCubic.transform(w);
        canvas.drawCircle(
          _siteDot,
          FieldSyncLogoGeometry.siteDotR + 15.5 * e,
          Paint()
            ..color = _siteRed.withValues(
              alpha: 0.55 * (1 - e) * math.min(1, w / 0.08),
            )
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.6 - 1.7 * e,
        );
      }
    }

    final dotA = redDotAlphaAt(t);
    if (dotA > 0.004) {
      canvas.save();
      canvas.translate(_siteDot.dx, _siteDot.dy);
      canvas.scale(redDotScaleAt(t));
      canvas.drawCircle(
        Offset.zero,
        FieldSyncLogoGeometry.siteDotR,
        Paint()..color = _siteRed.withValues(alpha: dotA),
      );
      canvas.restore();
    }
  }

  /// The traveller puck riding the head of the line — the approved entrance's
  /// own disc, fading out as the tip reaches the site on the approved
  /// painter's own out window.
  void _paintTraveller(Canvas canvas, double t) {
    final u = tipFractionAt(t);
    if (u <= 0) return;
    final popW = _ease(Curves.easeOutCubic, t, _puckIn, _puckPopEnd);
    final alpha = popW *
        (1 -
            _ease(
              Curves.easeInOutSine,
              t,
              FieldSyncCinematicTimeline.puckOutStartSeconds,
              FieldSyncCinematicTimeline.puckOutEndSeconds,
            ));
    if (alpha <= 0.004) return;
    final head = _graphPointAt(u);
    canvas.save();
    canvas.translate(head.dx, head.dy);
    canvas.scale(0.6 + 0.4 * popW);
    canvas.drawCircle(
      Offset.zero,
      4.4,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.92 * alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.75,
    );
    canvas.drawCircle(
      Offset.zero,
      2.9,
      Paint()..color = Colors.white.withValues(alpha: 0.95 * alpha),
    );
    canvas.drawCircle(
      Offset.zero,
      1.15,
      Paint()..color = _kitNavy.withValues(alpha: alpha),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant FieldSyncCinematicScenePainter oldDelegate) =>
      oldDelegate.time != time;
}
