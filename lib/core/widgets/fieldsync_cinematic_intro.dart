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

  /// Chrome (status card, wordmark texts) fades in right at the seam — the
  /// initialization page's own UI, stepped in as Page 2 takes the frame.
  static const double chromeFadeStartSeconds = seamSeconds;
  static const double chromeFadeEndSeconds = 6.20;

  /// Page 3 — the login reveal. The login page mounts during the departure
  /// tail ([mountStartSeconds]–[mountEndSeconds]); its logo stays hidden (its
  /// exact layout space reserved and measured) until the arrival completes.
  static const double loginDotStartSeconds = travelEndSeconds; // 11.95
  static const double loginDotPopEndSeconds = 12.20;

  /// The water-drop pulse: two rings in the approved arrival's own visual
  /// language — same gap, duration and easing as the site-dot rings, at the
  /// login's own scale.
  static const double loginPulseStartSeconds = 12.05;
  static const double loginPulseGapSeconds = pulseGapSeconds;
  static const double loginPulseDurationSeconds = pulseDurationSeconds;

  /// The re-entered route dissolves once it has arrived …
  static const double loginLineFadeStartSeconds = 12.15;
  static const double loginLineFadeEndSeconds = 12.75;

  /// … and the destination dot dissolves as the official logo takes its
  /// place.
  static const double loginDotFadeStartSeconds = 12.45;
  static const double loginDotFadeEndSeconds = 12.95;

  /// The login's real brand mark fades in (opacity/scale only) where the
  /// pulse was: the same measured rect the route was guided to.
  static const double brandRevealStartSeconds = 12.55;
  static const double brandRevealEndSeconds = 13.15;

  /// Interaction is allowed only once the reveal has finished; until then
  /// the barrier consumes taps (a tap is a skip request).
  static const double barrierReleaseSeconds = brandRevealEndSeconds;

  /// The re-entered stroke's colour has fully settled on the official navy by
  /// this second — well before the pipe crosses the right edge on screen.
  static const double loginStrokeColourEndSeconds = 11.65;
}

/// The driven, navigation-free Page 1 stage.
///
/// It paints exactly what its clock says and nothing else: no controller, no
/// timers, no navigation, no state. The host supplies global cinematic time
/// and decides when the seam frame may leave the screen; that orchestration
/// is deliberately not part of this widget.
class FieldSyncCinematicStage extends StatefulWidget {
  const FieldSyncCinematicStage({super.key, required this.time, this.boxKey});

  /// Global cinematic seconds ([FieldSyncCinematicTimeline]). Values outside
  /// the timeline paint held boundary frames rather than extrapolating.
  final Animation<double> time;

  /// When supplied, the stage splices onto the entrance's own box (see
  /// [FieldSyncCinematicScenePainter.boxRect]): it measures this key's render
  /// box in its own canvas space every paint, eases onto it so picture and
  /// box agree to the pixel at the seam, and hands route ownership over at
  /// [FieldSyncCinematicTimeline.seamSeconds]. Null keeps the standalone
  /// full-screen behavior.
  final GlobalKey? boxKey;

  @override
  State<FieldSyncCinematicStage> createState() => _FieldSyncCinematicStageState();
}

class _FieldSyncCinematicStageState extends State<FieldSyncCinematicStage> {
  final GlobalKey _stageKey = GlobalKey();

  Rect? _boxRect() {
    final box = widget.boxKey?.currentContext?.findRenderObject();
    final stage = _stageKey.currentContext?.findRenderObject();
    if (box is! RenderBox || stage is! RenderBox) return null;
    if (!box.attached || !stage.attached) return null;
    try {
      return box.localToGlobal(Offset.zero, ancestor: stage) & box.size;
    } catch (_) {
      // Different trees (e.g. the box unmounted mid-frame): fall back to the
      // full-screen frame; the splice simply holds until it is measurable.
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _stageKey,
      child: CustomPaint(
        isComplex: true,
        size: Size.infinite,
        painter: FieldSyncCinematicScenePainter(
          time: widget.time,
          boxRect: widget.boxKey == null ? null : _boxRect,
        ),
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
  FieldSyncCinematicScenePainter({required this.time, this.boxRect})
    : super(repaint: time);

  /// Global cinematic seconds.
  final Animation<double> time;

  /// The measured rect of the approved entrance's own box, in this canvas's
  /// space. When supplied, the scene *splices* onto it: the frame eases from
  /// the full-screen fit onto exactly that rect between the arrival hold and
  /// the seam, using the entrance painter's own [FieldSyncEntranceCamera]
  /// maths, so at [FieldSyncCinematicTimeline.seamSeconds] both layers frame
  /// the box to the pixel. Past the seam the layer dissolves its own remnants
  /// (terrain and search tail, over the approved ghost window) and stops
  /// painting what the approved painter now owns — route, dot, rings,
  /// arrowhead, puck. Null keeps the standalone full-screen behavior: held
  /// boundary frames, no splice.
  final Rect? Function()? boxRect;

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
    final splice = spliceRectAt(t, size, boxRect?.call());
    final q = FieldSyncEntranceCamera.viewportFit(splice.size);
    final anchor =
        splice.topLeft +
        FieldSyncEntranceCamera.screenAnchorOf(splice.size, camera.anchorT);

    // The field: full-bleed brand blue under everything.
    canvas.drawRect(Offset.zero & size, Paint()..color = InsightTheme.blue2);

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(anchor.dx, anchor.dy);
    canvas.scale(q * camera.zoom);
    canvas.translate(-camera.centre.dx, -camera.centre.dy);

    if (boxRect == null || t <= FieldSyncCinematicTimeline.seamSeconds) {
      _paintTerrain(canvas, t);
      _paintRouteGhost(canvas, t);
      _paintSearchLine(canvas, t);
      _paintArrival(canvas, t);
      _paintTraveller(canvas, t);
    } else {
      // Spliced, past the seam: the approved entrance painter owns the route,
      // dot, rings, arrowhead and puck from here — it frames them with this
      // exact transform, so this layer must not double them. What it keeps
      // drawing is only what the painter never draws: the terrain and the
      // search tail, dissolving over the approved ghost window.
      final fade =
          1 -
          _ease(
            Curves.easeInOutSine,
            t,
            FieldSyncCinematicTimeline.seamSeconds,
            FieldSyncCinematicTimeline.routeGhostOutEndSeconds,
          );
      if (fade > 0.004) {
        _paintTerrain(canvas, t, fade: fade);
        _paintSearchTail(canvas, fade);
      }
    }

    canvas.restore();
  }

  /// The frame rect the artwork is painted into at [t]: the full canvas until
  /// the arrival hold ends, easing onto [box] (when measured) by the seam.
  /// The rect drives both the viewport fit and the anchor, so at
  /// [FieldSyncCinematicTimeline.seamSeconds] it is exactly the entrance's
  /// own box — the two layers agree to the pixel inside it.
  static Rect spliceRectAt(double t, Size canvas, Rect? box) {
    final full = Offset.zero & canvas;
    if (box == null) return full;
    final b = _ease(
      Curves.easeInOutSine,
      t,
      FieldSyncCinematicTimeline.arriveSeconds,
      FieldSyncCinematicTimeline.seamSeconds,
    );
    if (b <= 0) return full;
    if (b >= 1) return box;
    return Rect.lerp(full, box, b)!;
  }

  /// The official fingerprint ribbons as abstract terrain: the artwork's own
  /// ridge paths, filled at the level the approved painter's ridge ghosts
  /// hold, ramped in during the settle. [fade] dissolves it after the seam
  /// where the painter's own ridge ghosts take over.
  void _paintTerrain(Canvas canvas, double t, {double fade = 1}) {
    final alpha =
        _ridgeTerrainAlpha *
        fade *
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

  /// The search corridor alone (no route portion), dissolving after the seam
  /// in splice mode — the part of the line the approved painter never draws.
  void _paintSearchTail(Canvas canvas, double fade) {
    final alpha = fade.clamp(0.0, 1.0);
    if (alpha <= 0.004) return;
    canvas.drawPath(
      _searchMetric!.extractPath(0, _searchLength),
      Paint()
        ..color = Colors.white.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = FieldSyncLogoGeometry.routeStrokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
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
      oldDelegate.time != time || oldDelegate.boxRect != boxRect;
}

/// Page 2's departure camera: the settled lockup holds until the hold ends,
/// then the frame pushes toward the leading tip, follows it as it leaves the
/// logo, and releases into a zoom-out as the route crosses the right screen
/// edge. A pure function of the clock and the stage's own box size; exactly
/// identity at [FieldSyncCinematicTimeline.departureStartSeconds], so the
/// held composition cannot jump.
class FieldSyncDepartureCamera {
  FieldSyncDepartureCamera._();

  /// The approved entrance painter's settled state (its own timeline's end) —
  /// the frame the hold leaves and the departure pushes in on.
  static final FieldSyncEntranceCamera settled =
      FieldSyncEntrancePainter.cameraAt(FieldSyncEntranceTimeline.total);

  /// The push apex: the camera tightens toward the tip before giving back.
  static const double _zoomIn = 1.28;

  /// The exit zoom, past 1.0 toward wide, releasing the route off the edge.
  static const double _zoomOut = 0.94;

  /// The push ends here; the zoom-out owns the rest of the departure.
  static const double _pushEndSeconds = 10.55;

  static double zoomAt(double t) {
    if (t <= FieldSyncCinematicTimeline.departureStartSeconds) return 1;
    if (t < _pushEndSeconds) {
      return 1 +
          (_zoomIn - 1) *
              FieldSyncCinematicScenePainter._ease(
                Curves.easeInOutSine,
                t,
                FieldSyncCinematicTimeline.departureStartSeconds,
                _pushEndSeconds,
              );
    }
    return _zoomIn +
        (_zoomOut - _zoomIn) *
            FieldSyncCinematicScenePainter._ease(
              Curves.easeInOutSine,
              t,
              _pushEndSeconds,
              FieldSyncCinematicTimeline.departureEndSeconds,
            );
  }

  /// The tip's box-local position at [t] under the settled camera — the point
  /// the departure scales about, so the tip is the one thing that never moves
  /// in the frame: the camera follows it by construction.
  static Offset tipLocalAt(double t, Size boxSize) {
    final world = FieldSyncDepartureRoutePainter.tipWorldAt(t);
    final anchor = FieldSyncEntranceCamera.screenAnchorOf(
      boxSize,
      settled.anchorT,
    );
    final q = FieldSyncEntranceCamera.viewportFit(boxSize);
    return anchor + (world - settled.centre) * (q * settled.zoom);
  }

  /// The departure transform for the box subtree at [t]: identity through the
  /// hold, then a scale about the moving tip. Exactly [Matrix4.identity] at
  /// [FieldSyncCinematicTimeline.departureStartSeconds] — no translation jump.
  static Matrix4 matrixAt(double t, Size boxSize) {
    final k = zoomAt(t);
    if (k == 1) return Matrix4.identity();
    final tip = tipLocalAt(t, boxSize);
    return Matrix4.identity()
      ..translateByDouble(tip.dx, tip.dy, 0, 1)
      ..scaleByDouble(k, k, 1, 1)
      ..translateByDouble(-tip.dx, -tip.dy, 0, 1);
  }
}

/// The journey resuming: the official route extended off the right edge with
/// an authored tail — the same C1 construction as the search's own join onto
/// the route, mirrored — drawn from the route's own end so the exit cannot
/// detach from the artwork. Pure box-local space: the host wraps it in the
/// same [FieldSyncDepartureCamera] transform as the entrance, so the logo and
/// the departing route can never separate.
class FieldSyncDepartureRoutePainter extends CustomPainter {
  FieldSyncDepartureRoutePainter({required this.time, this.active = true})
    : super(repaint: time);

  /// Global cinematic seconds.
  final Animation<double> time;

  /// Whether the journey is actually leaving for the login. The host clears
  /// this for launches heading to Home or a terminal state: the exit belongs
  /// to the login's own beat and must not play for journeys that never reach
  /// Page 3.
  final bool active;

  /// The authored external tail (viewBox units), continuing the route's end
  /// direction then sweeping down off the right edge. It overflies the
  /// screen edge of every supported portrait width at the departure's own
  /// end under the settled camera (pinned by the geometry tests).
  static const List<Offset> _tailWaypoints = <Offset>[
    Offset(770, 405),
    Offset(930, 385),
    Offset(1105, 448),
    Offset(1275, 610),
    Offset(1560, 900),
  ];

  static ui.Path? _tailPath;
  static ui.PathMetric? _metric;

  static ui.PathMetric _prepare() {
    if (_metric != null) return _metric!;
    final route = FieldSyncLogoGeometry.route.computeMetrics().first;
    final start = route.getTangentForOffset(route.length)!.position;
    final before = route.getTangentForOffset(route.length - 0.5)!.position;
    final delta = start - before;
    final heading = delta / delta.distance;

    final points = <Offset>[start, ..._tailWaypoints];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final from = points[i];
      final to = points[i + 1];
      final previous = i == 0 ? points[0] : points[i - 1];
      final next = i + 2 < points.length ? points[i + 2] : null;
      // The first leg leaves along the route's own end direction: the C1
      // continuation of the official geometry.
      final control1 = i == 0
          ? from + heading * ((to - from).distance / 6)
          : from + (to - previous) / 6;
      final control2 = next != null
          ? to - (next - from) / 6
          : to - (to - from) / 6;
      path.cubicTo(
        control1.dx,
        control1.dy,
        control2.dx,
        control2.dy,
        to.dx,
        to.dy,
      );
    }
    _tailPath = path;
    _metric = path.computeMetrics().first;
    return _metric!;
  }

  /// The extension path (route end → off the right edge), for the continuity
  /// checks.
  static Path get tailPath {
    _prepare();
    return _tailPath!;
  }

  /// The tip's own arc-length fraction of the tail at [t]: eased across
  /// [FieldSyncCinematicTimeline.departureStartSeconds] →
  /// [FieldSyncCinematicTimeline.departureEndSeconds].
  static double progressAt(double t) => FieldSyncCinematicScenePainter._ease(
    Curves.easeInOutSine,
    t,
    FieldSyncCinematicTimeline.departureStartSeconds,
    FieldSyncCinematicTimeline.departureEndSeconds,
  );

  /// The tip's world (viewBox) position at [t].
  static Offset tipWorldAt(double t) {
    final metric = _prepare();
    return metric.getTangentForOffset(progressAt(t) * metric.length)!.position;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (!active) return;
    if (size.width <= 0 || size.height <= 0) return;
    final p = progressAt(time.value);
    if (p <= 0) return;
    final metric = _prepare();
    final at = p * metric.length;

    // The tail is authored in the artwork's own (viewBox) coordinates, so it
    // is mapped into this box exactly as the approved painter maps the
    // artwork — the settled camera's own fit and anchor — which is also the
    // mapping [FieldSyncDepartureCamera.tipLocalAt] uses for the scale it
    // follows. Unlike the entrance, this layer deliberately does not clip to
    // the box: the route leaving the logo is the point of the exit.
    final settled = FieldSyncDepartureCamera.settled;
    final q = FieldSyncEntranceCamera.viewportFit(size);
    final anchor = FieldSyncEntranceCamera.screenAnchorOf(
      size,
      settled.anchorT,
    );
    canvas.save();
    canvas.translate(anchor.dx, anchor.dy);
    canvas.scale(q * settled.zoom);
    canvas.translate(-settled.centre.dx, -settled.centre.dy);

    canvas.drawPath(
      metric.extractPath(0, at),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = FieldSyncLogoGeometry.routeStrokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    // The leading tip: the approved traveller puck, back on the road.
    final head = metric.getTangentForOffset(at)!.position;
    canvas.drawCircle(
      head,
      4.4,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.92)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.75,
    );
    canvas.drawCircle(
      head,
      2.9,
      Paint()..color = Colors.white.withValues(alpha: 0.95),
    );
    canvas.drawCircle(
      head,
      1.15,
      Paint()..color = FieldSyncCinematicScenePainter._kitNavy,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant FieldSyncDepartureRoutePainter oldDelegate) =>
      oldDelegate.time != time || oldDelegate.active != active;
}

/// Page 3's route: the journey re-entering from the right edge of the login
/// page, the stroke easing from the pages' white to the official navy on the
/// light surface, arriving at the measured login logo, dropping the red
/// destination dot, and pulsing it like water before the logo takes its
/// place. Screen space: the login's layout is measured, never assumed.
class FieldSyncLoginRoutePainter extends CustomPainter {
  FieldSyncLoginRoutePainter({required this.time, this.brandRect})
    : super(repaint: time);

  /// Global cinematic seconds.
  final Animation<double> time;

  /// The measured rect of the login logo (the brand mark's render box, which
  /// keeps its exact layout space while hidden). Null → nothing to aim at;
  /// the painter draws nothing.
  final Rect? Function()? brandRect;

  static const Color _siteRed = FieldSyncCinematicScenePainter._siteRed;
  static const Color _kitNavy = FieldSyncCinematicScenePainter._kitNavy;

  /// The destination dot's radius at the login's own scale.
  static const double dotRadius = 7.0;

  /// The re-entry line's width at the login's own scale.
  static const double lineWidth = 2.4;

  /// The pulse's maximum growth: the approved water-drop rings, login scale.
  static const double rippleGrowth = 26.0;

  /// The arrival target inside the measured logo: the artwork's own site-dot
  /// position, in its viewBox fractions — so the pulse dissolves exactly
  /// where the revealed logo's own red dot appears.
  static Offset targetFor(Rect brand) => brand.topLeft +
      Offset(
        brand.width *
            (FieldSyncLogoGeometry.siteDotX - FieldSyncLogoGeometry.viewBoxLeft) /
            FieldSyncLogoGeometry.viewBoxWidth,
        brand.height *
            (FieldSyncLogoGeometry.siteDotY - FieldSyncLogoGeometry.viewBoxTop) /
            FieldSyncLogoGeometry.viewBoxHeight,
      );

  /// The re-entry: from off the right edge, curving up-left into the target.
  /// Exposed for the continuity checks.
  static Path pathFor(Rect brand, Size size) {
    final target = targetFor(brand);
    final start = Offset(size.width + 90, target.dy + 150);
    final c1 = Offset(size.width - 20, target.dy + 110);
    final c2 = Offset(target.dx + 150, target.dy + 80);
    return Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, target.dx, target.dy);
  }

  /// The tip's own arc-length fraction of the re-entry at [t].
  static double progressAt(double t) => FieldSyncCinematicScenePainter._ease(
    Curves.easeInOutSine,
    t,
    FieldSyncCinematicTimeline.mountEndSeconds,
    FieldSyncCinematicTimeline.travelEndSeconds,
  );

  /// The stroke's own colour at [t]: the pages' white, interpolating smoothly
  /// into the official navy as the line crosses onto the light login page.
  static Color strokeColourAt(double t) => Color.lerp(
    Colors.white,
    _kitNavy,
    FieldSyncCinematicScenePainter._ease(
      Curves.easeInOutSine,
      t,
      FieldSyncCinematicTimeline.departureEndSeconds,
      FieldSyncCinematicTimeline.loginStrokeColourEndSeconds,
    ),
  )!;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final brand = brandRect?.call();
    if (brand == null || brand.isEmpty) return;
    final t = time.value;
    final target = targetFor(brand);
    final colour = strokeColourAt(t);

    // The re-entered route: drawn to exactly the tip's own arc position,
    // dissolving once it has arrived.
    final p = progressAt(t);
    final lineAlpha =
        1 -
        FieldSyncCinematicScenePainter._ease(
          Curves.easeInOutSine,
          t,
          FieldSyncCinematicTimeline.loginLineFadeStartSeconds,
          FieldSyncCinematicTimeline.loginLineFadeEndSeconds,
        );
    if (p > 0 && lineAlpha > 0.004) {
      final metric = pathFor(brand, size).computeMetrics().first;
      final at = p * metric.length;
      canvas.drawPath(
        metric.extractPath(0, at),
        Paint()
          ..color = colour.withValues(alpha: lineAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = lineWidth
          ..strokeCap = StrokeCap.round,
      );
      final head = metric.getTangentForOffset(at)!.position;
      canvas.drawCircle(
        head,
        3.0,
        Paint()..color = colour.withValues(alpha: lineAlpha),
      );
      canvas.drawCircle(
        head,
        4.6,
        Paint()
          ..color = colour.withValues(alpha: 0.45 * lineAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    }

    // The red destination dot, popping on the approved site-dot shapes …
    final pop = FieldSyncCinematicScenePainter._ease(
      Curves.easeOutCubic,
      t,
      FieldSyncCinematicTimeline.loginDotStartSeconds,
      FieldSyncCinematicTimeline.loginDotPopEndSeconds,
    );
    final dotAlpha =
        pop *
        (1 -
            FieldSyncCinematicScenePainter._ease(
              Curves.easeInOutSine,
              t,
              FieldSyncCinematicTimeline.loginDotFadeStartSeconds,
              FieldSyncCinematicTimeline.loginDotFadeEndSeconds,
            ));
    if (dotAlpha > 0.004) {
      final scale =
          (0.55 + 0.45 * pop) * (1 + 0.12 * math.sin(math.pi * pop));
      canvas.save();
      canvas.translate(target.dx, target.dy);
      canvas.scale(scale);
      canvas.drawCircle(
        Offset.zero,
        dotRadius,
        Paint()..color = _siteRed.withValues(alpha: dotAlpha),
      );
      canvas.restore();
    }

    // … and its water-drop pulse: two rings, the approved arrival's own
    // shapes, at the login's scale.
    for (var k = 0; k < 2; k++) {
      final start =
          FieldSyncCinematicTimeline.loginPulseStartSeconds +
          k * FieldSyncCinematicTimeline.loginPulseGapSeconds;
      final w = FieldSyncCinematicScenePainter._win(
        t,
        start,
        start + FieldSyncCinematicTimeline.loginPulseDurationSeconds,
      );
      if (w <= 0 || w >= 1) continue;
      final e = Curves.easeOutCubic.transform(w);
      canvas.drawCircle(
        target,
        dotRadius + rippleGrowth * e,
        Paint()
          ..color = _siteRed.withValues(
            alpha: 0.55 * (1 - e) * math.min(1, w / 0.08),
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6 - 1.7 * e,
      );
    }
  }

  @override
  bool shouldRepaint(covariant FieldSyncLoginRoutePainter oldDelegate) =>
      oldDelegate.time != time || oldDelegate.brandRect != brandRect;
}

/// Page 3's route layer, above the login. Pointer-transparent by design: the
/// startup barrier owns input until the sequence completes. It measures the
/// login logo's own rect in its own canvas space every paint and draws
/// nothing while it is not measurable.
class FieldSyncLoginRouteOverlay extends StatefulWidget {
  const FieldSyncLoginRouteOverlay({
    super.key,
    required this.time,
    this.brandKey,
  });

  /// Global cinematic seconds.
  final Animation<double> time;

  /// Key on the login logo (LoginScreen's `brandKey`), measured in this
  /// layer's own space.
  final GlobalKey? brandKey;

  @override
  State<FieldSyncLoginRouteOverlay> createState() =>
      _FieldSyncLoginRouteOverlayState();
}

class _FieldSyncLoginRouteOverlayState
    extends State<FieldSyncLoginRouteOverlay> {
  final GlobalKey _stageKey = GlobalKey();

  Rect? _brandRect() {
    final brand = widget.brandKey?.currentContext?.findRenderObject();
    final stage = _stageKey.currentContext?.findRenderObject();
    if (brand is! RenderBox || stage is! RenderBox) return null;
    if (!brand.attached || !stage.attached) return null;
    try {
      return brand.localToGlobal(Offset.zero, ancestor: stage) & brand.size;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        key: _stageKey,
        child: CustomPaint(
          isComplex: true,
          size: Size.infinite,
          painter: FieldSyncLoginRoutePainter(
            time: widget.time,
            brandRect: widget.brandKey == null ? null : _brandRect,
          ),
        ),
      ),
    );
  }
}
