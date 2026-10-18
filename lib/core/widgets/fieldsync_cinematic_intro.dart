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

  /// Only the leftover search corridor yields earlier; approved ridges,
  /// arrival and entrance pulses retain their original dissolve window.
  static const double searchTailOutEndSeconds = 6.15;

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
  static const double edgeTurnSeconds = 11.00;
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

  /// Two rings in the approved arrival's visual language, with its gap and
  /// easing. Only the destination duration is shorter, so both rings finish
  /// before the complete brand group reveals. Page 1's pulse is unchanged.
  static const double loginPulseStartSeconds = 12.05;
  static const double loginPulseGapSeconds = pulseGapSeconds;
  static const double loginPulseDurationSeconds = 0.60;

  /// The re-entered route dissolves once it has arrived …
  static const double loginLineFadeStartSeconds = 12.15;
  static const double loginLineFadeEndSeconds = 12.75;

  /// … and the destination dot dissolves as the official logo takes its
  /// place.
  static const double loginDotFadeStartSeconds = 12.45;
  static const double loginDotFadeEndSeconds = 12.78;

  /// The destination's complete brand group fades in (opacity only) after the
  /// pulse, with the artwork at the same measured anchor the route reached.
  static const double brandRevealStartSeconds = 12.80;
  static const double brandRevealEndSeconds = 13.30;

  /// Interaction is allowed only once the reveal has finished; until then
  /// the barrier consumes taps (a tap is a skip request).
  static const double barrierReleaseSeconds = totalSeconds;

  /// The stroke settles on navy over light surfaces during the transition.
  /// App Lock retains white over blue; neither replaces the authored route.
  static const double loginStrokeColourEndSeconds = 11.45;
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
  static final Offset _establishCentre =
      _waypoints.first - const Offset(0, 500);
  // Small route-relative leads keep the traveller inside the actual channels.
  static const Offset _reframeA = Offset(-24, -8);
  static const Offset _reframeB = Offset(8, 0);
  static const double _enterBlendStart = 0.55;
  static const double _arrivalHoldSeconds =
      FieldSyncCinematicTimeline.arrowStartSeconds;
  static const double _lookAhead = 14; // SVG units, independent of route length

  // ── authored search corridor (viewBox units) ──────────────────────────────
  // User-drawn green direction: lower-right entrance -> inner loop -> lower
  // bends -> left channel -> official route -> red dot. Guide points were
  // centred in those same SVG gaps with the full stroke/glow envelope checked.
  // They shape one continuous spline, not separate animation stops. The final
  // position/tangent still come from the untouched official route metric.
  static const List<Offset> _waypoints = <Offset>[
    Offset(629.500, 974.500), Offset(649.885, 956.115), Offset(672.027, 941.973),
    Offset(694.755, 929.245), Offset(715.018, 911.982), Offset(720.500, 886.252),
    Offset(735.110, 864.890), Offset(754.374, 846.626), Offset(772.051, 825.949),
    Offset(785.500, 803.519), Offset(794.500, 779.833), Offset(797.500, 753.076),
    Offset(795.500, 728.147), Offset(786.058, 706.058), Offset(764.916, 689.500),
    Offset(743.644, 681.500), Offset(719.544, 679.500), Offset(692.786, 682.500),
    Offset(670.514, 691.500), Offset(650.500, 708.858), Offset(637.054, 728.946),
    Offset(633.500, 752.988), Offset(636.500, 779.746), Offset(645.500, 802.603),
    Offset(654.766, 826.766), Offset(656.500, 854.047), Offset(644.500, 871.319),
    Offset(623.728, 882.272), Offset(600.379, 893.500), Offset(576.107, 902.500),
    Offset(552.249, 912.500), Offset(529.302, 924.698), Offset(509.090, 943.500),
    Offset(486.889, 957.500), Offset(466.097, 974.903), Offset(439.855, 977.855),
    Offset(414.901, 970.500), Offset(406.287, 952.713), Offset(421.500, 931.014),
    Offset(435.500, 912.328), Offset(451.178, 890.822), Offset(470.489, 877.500),
    Offset(493.220, 864.780), Offset(516.534, 853.466), Offset(533.500, 834.837),
    Offset(553.500, 820.394), Offset(558.500, 794.465), Offset(558.576, 770.576),
    Offset(558.500, 745.920), Offset(560.500, 719.577), Offset(567.500, 694.477),
    Offset(572.413, 669.413), Offset(557.518, 650.500), Offset(536.418, 639.500),
    Offset(512.835, 650.165), Offset(501.643, 670.357), Offset(490.500, 693.741),
    Offset(487.965, 719.035), Offset(478.500, 743.114), Offset(471.702, 768.298),
    Offset(460.509, 790.491), Offset(444.610, 804.390), Offset(423.455, 819.500),
    Offset(399.861, 830.139), Offset(380.500, 847.190), Offset(356.538, 856.500),
    Offset(329.113, 855.113), Offset(318.506, 831.506), Offset(322.272, 806.728),
    Offset(332.879, 783.121), Offset(354.728, 768.272), Offset(374.406, 749.594),
    Offset(387.500, 727.018),
  ];

  // Preserve the existing join/arrival beats, without pausing at guide points.
  static const double _routeJoinSeconds = 4.72;

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
    }
    _searchPath = path;
    _searchMetric = path.computeMetrics().first;
    _searchLength = _searchMetric!.length;
    _graphLength = _searchLength + _routeLength;
  }

  static double _win(double t, double a, double b) =>
      ((t - a) / (b - a)).clamp(0.0, 1.0);

  static double _ease(Curve curve, double t, double a, double b) =>
      curve.transform(_win(t, a, b));

  /// One uninterrupted search traversal, then the official route's existing
  /// final ride. Guide-point density never creates pauses or changes duration.
  static double tipFractionAt(double t) {
    _prepare();
    if (t <= FieldSyncCinematicTimeline.settleEndSeconds) return 0;
    if (t < _routeJoinSeconds) {
      return _searchLength / _graphLength * _ease(Curves.easeInOutSine, t,
          FieldSyncCinematicTimeline.settleEndSeconds, _routeJoinSeconds);
    }
    return (_searchLength + _routeLength * _ease(Curves.easeInOutSine, t,
        _routeJoinSeconds, FieldSyncCinematicTimeline.arriveSeconds)) / _graphLength;
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
      math.min(1.0, tipFractionAt(t) + _lookAhead / _graphLength),
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
      // Two gentle reframes lead the channel bends without leaving the tip.
      final a = _ease(Curves.easeInOutSine, t, 1.95, 2.65);
      final b = _ease(Curves.easeInOutSine, t, 3.25, 3.95);
      return follow + Offset.lerp(_reframeA * a, _reframeB, b)!;
    }
    if (t < _arrivalHoldSeconds) {
      return Offset.lerp(
        follow + _reframeB,
        _siteDot,
        _ease(
          Curves.easeInOutSine,
          t,
          FieldSyncCinematicTimeline.puckOutStartSeconds,
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
        _paintSearchTail(canvas, 1 - _ease(
          Curves.easeInOutSine, t, FieldSyncCinematicTimeline.seamSeconds,
          FieldSyncCinematicTimeline.searchTailOutEndSeconds,
        ));
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
      _searchPath!,
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
  static const double _zoomOut = 1.0;

  /// The push ends here; the zoom-out owns the rest of the departure.
  static const double _pushEndSeconds = 10.20;
  static const double settleSeconds = 10.65;

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
              settleSeconds,
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
  static Matrix4 matrixAt(double t, Size boxSize, {Offset? followedTip}) {
    final k = zoomAt(t);
    if (k == 1) return Matrix4.identity();
    final tip = followedTip ?? tipLocalAt(t, boxSize);
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

/// One measured, single-contour journey from the official route's own end,
/// through a short off-screen turn, to either destination's real brand anchor.
/// Geometry and metrics are retained until the host's layout changes.
class FieldSyncJourneyPath {
  FieldSyncJourneyPath._(this.departureBox, this.brand, this.viewport, this.path,
      this.metric, this.exitDistance, this.returnDistance);

  final Rect departureBox;
  final Rect brand;
  final Size viewport;
  final Path path;
  final ui.PathMetric metric;
  final double exitDistance;
  final double returnDistance;

  factory FieldSyncJourneyPath({required Rect departureBox, required Rect brand,
      required Size viewport}) {
    final settled = FieldSyncDepartureCamera.settled;
    final anchor = FieldSyncEntranceCamera.screenAnchorOf(
      departureBox.size, settled.anchorT,
    );
    final q = FieldSyncEntranceCamera.viewportFit(departureBox.size) * settled.zoom;
    final mapping = Matrix4.identity()
      ..translateByDouble(departureBox.left + anchor.dx,
          departureBox.top + anchor.dy, 0, 1)
      ..scaleByDouble(q, q, 1, 1)
      ..translateByDouble(-settled.centre.dx, -settled.centre.dy, 0, 1);
    final tail = FieldSyncDepartureRoutePainter.tailPath
        .transform(mapping.storage).computeMetrics().first;
    final start = tail.getTangentForOffset(0)!.position;
    // Keep the approved departure's first bend and exact contact direction.
    final prefix = math.min(tail.length * 0.18,
        math.max(8.0, (viewport.width - start.dx) * 0.22));
    final path = tail.extractPath(0, prefix);
    final contact = tail.getTangentForOffset(prefix)!;
    final handle = ((viewport.width - contact.position.dx) / 3).clamp(8.0, 96.0);
    // Derive both crossings from the destination layout, not independent y
    // constants. The lock's white route stays inside its existing blue header.
    final inset = math.min(32.0, viewport.height / 2);
    final y = (brand.center.dy + 96).clamp(inset, viewport.height - inset);
    final exit = Offset(viewport.width, y);
    final c1 = contact.position + contact.vector * handle;
    path.cubicTo(c1.dx, c1.dy, exit.dx - handle, exit.dy, exit.dx, exit.dy);
    final exitDistance = path.computeMetrics().first.length;
    // A real, tangent-continuous turn, just 1.5 px outside the viewport. The
    // head's ring straddles the edge; no teleport, reset or long hidden travel.
    final returning = exit - const Offset(0, 2);
    path.cubicTo(exit.dx + 2, exit.dy, returning.dx + 2, returning.dy,
        returning.dx, returning.dy);
    final returnDistance = path.computeMetrics().first.length;
    final target = FieldSyncLoginRoutePainter.targetFor(brand);
    final incomingHandle = ((returning.dx - target.dx) / 3).clamp(8.0, 120.0);
    path.cubicTo(returning.dx - incomingHandle, returning.dy,
        target.dx + incomingHandle, target.dy + 64, target.dx, target.dy);
    return FieldSyncJourneyPath._(departureBox, brand, viewport, path,
        path.computeMetrics().first, exitDistance, returnDistance);
  }

  /// One monotonically advancing arc distance. The two Hermite spans share
  /// the same non-zero velocity at the turn; neither page owns a fresh clock.
  double distanceAt(double t) {
    const start = FieldSyncCinematicTimeline.departureStartSeconds;
    const turn = FieldSyncCinematicTimeline.edgeTurnSeconds;
    const end = FieldSyncCinematicTimeline.travelEndSeconds;
    if (t <= start) return 0;
    if (t >= end) return metric.length;
    final atTurn = (exitDistance + returnDistance) / 2;
    final velocity = 2 * math.min(atTurn / (turn - start),
        (metric.length - atTurn) / (end - turn));
    final first = t <= turn;
    final duration = first ? turn - start : end - turn;
    final u = (t - (first ? start : turn)) / duration;
    final u2 = u * u;
    final u3 = u2 * u;
    final blend = 3 * u2 - 2 * u3;
    return first
        ? blend * atTurn + (u3 - u2) * duration * velocity
        : atTurn + blend * (metric.length - atTurn) +
            (u3 - 2 * u2 + u) * duration * velocity;
  }

  double progressAt(double t) => distanceAt(t) / metric.length;
  Offset headAt(double t) => metric.getTangentForOffset(distanceAt(t))!.position;

  /// The back of the SAME trail advances off Page 2 as the new surface comes
  /// in. Once opaque, only the returning segment remains over the form/header.
  double trailStartAt(double t) => math.min(distanceAt(t), returnDistance *
      FieldSyncCinematicScenePainter._ease(Curves.easeInOutSine, t,
        FieldSyncCinematicTimeline.mountStartSeconds,
        FieldSyncCinematicTimeline.mountEndSeconds));
}

/// Page 3's route: the journey re-entering from the right edge of the login
/// page, the stroke easing from the pages' white to the official navy on the
/// light surface, arriving at the measured login logo, dropping the red
/// destination dot, and pulsing it like water before the logo takes its
/// place. Screen space: the login's layout is measured, never assumed.
class FieldSyncLoginRoutePainter extends CustomPainter {
  FieldSyncLoginRoutePainter({required this.time, this.brandRect,
    this.journeyFor, this.onBlue = false, this.splitSurface = false})
    : super(repaint: time);

  /// Global cinematic seconds.
  final Animation<double> time;

  /// The measured rect of the login logo (the brand mark's render box, which
  /// keeps its exact layout space while hidden). Null → nothing to aim at;
  /// the painter draws nothing.
  final Rect? Function()? brandRect;

  /// The host retains one layout-derived path across both pages. Null keeps
  /// the standalone destination painter's existing contract.
  final FieldSyncJourneyPath? Function(Size)? journeyFor;
  final bool onBlue;
  final bool splitSurface;

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
      FieldSyncCinematicTimeline.mountStartSeconds,
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
    final colour = onBlue ? Colors.white : strokeColourAt(t);
    // App Lock's existing wide layout is blue on the left, white on the
    // right. A hard shader boundary changes only ink contrast, not the path,
    // trail or head; there is still exactly one draw of each shape.
    Paint routeInk(double alpha) => onBlue && splitSurface
        ? (Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(size.width, 0),
            [Colors.white.withValues(alpha: alpha),
             strokeColourAt(t).withValues(alpha: alpha)], const [0.5, 0.5]))
        : (Paint()..color = colour.withValues(alpha: alpha));
    final journey = journeyFor?.call(size);
    if (journeyFor != null && journey == null) return;

    // The re-entered route: drawn to exactly the tip's own arc position,
    // dissolving once it has arrived.
    final p = journey?.progressAt(t) ?? progressAt(t);
    final lineAlpha =
        1 -
        FieldSyncCinematicScenePainter._ease(
          Curves.easeInOutSine,
          t,
          FieldSyncCinematicTimeline.loginLineFadeStartSeconds,
          FieldSyncCinematicTimeline.loginLineFadeEndSeconds,
        );
    if (p > 0 && lineAlpha > 0.004) {
      final metric = journey?.metric ?? pathFor(brand, size).computeMetrics().first;
      final at = p * metric.length;
      final q = journey == null ? 1.0 :
          FieldSyncEntranceCamera.viewportFit(journey.departureBox.size);
      final width = journey == null ? lineWidth :
          ui.lerpDouble(FieldSyncLogoGeometry.routeStrokeWidth * q, lineWidth, p)!;
      canvas.save();
      if (journey != null && t < FieldSyncDepartureCamera.settleSeconds) {
        final box = journey.departureBox;
        canvas.translate(box.left, box.top);
        canvas.transform(FieldSyncDepartureCamera.matrixAt(t, box.size,
          followedTip: journey.headAt(t) - box.topLeft).storage);
        canvas.translate(-box.left, -box.top);
      }
      canvas.drawPath(
        metric.extractPath(journey?.trailStartAt(t) ?? 0, at),
        routeInk(lineAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round,
      );
      // One head for the whole journey, yielding to the destination dot on
      // arrival. Its size/stroke evolve continuously, never a second puck.
      if (journey == null || t < FieldSyncCinematicTimeline.travelEndSeconds) {
        final head = metric.getTangentForOffset(at)!.position;
        final radius = journey == null ? 3.0 : ui.lerpDouble(2.9 * q, 3, p)!;
        final ring = journey == null ? 4.6 : ui.lerpDouble(4.4 * q, 4.6, p)!;
        canvas.drawCircle(head, radius,
          routeInk(lineAlpha));
        canvas.drawCircle(head, ring, routeInk(0.45 * lineAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = journey == null ? 1 : ui.lerpDouble(0.75 * q, 1, p)!);
        if (journey != null) {
          canvas.drawCircle(head, ui.lerpDouble(1.15 * q, 1, p)!,
            Paint()..color = _kitNavy.withValues(alpha: lineAlpha));
        }
      }
      canvas.restore();
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
      oldDelegate.time != time || oldDelegate.brandRect != brandRect ||
      oldDelegate.journeyFor != journeyFor || oldDelegate.onBlue != onBlue ||
      oldDelegate.splitSurface != splitSurface;
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
    this.journeyFor,
    this.onBlue = false,
    this.splitSurface = false,
  });

  /// Global cinematic seconds.
  final Animation<double> time;

  /// Key on the login logo (LoginScreen's `brandKey`), measured in this
  /// layer's own space.
  final GlobalKey? brandKey;
  final FieldSyncJourneyPath? Function(Size)? journeyFor;
  final bool onBlue;
  final bool splitSurface;

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
            journeyFor: widget.journeyFor,
            onBlue: widget.onBlue,
            splitSurface: widget.splitSurface,
          ),
        ),
      ),
    );
  }
}
