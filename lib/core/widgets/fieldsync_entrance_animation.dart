import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'fieldsync_logo_geometry.dart';

/// The approved FieldSync splash entrance: an inspector navigating to the
/// assigned site, rendered natively from the official artwork's own geometry.
///
/// Choreography is authored against the approved reference
/// `FieldSync_Inspector_Entrance_v2.mp4` (480x800, 6.0 s):
///
/// 1. The camera pushes in along the lockup's own navigation route — a wide
///    establishing view tightening during the ride — while the route draws
///    toward the red site marker, traveller puck at the head.
/// 2. Arrival: gentle push-in, the red site dot pops in with a pulse.
/// 3. Cinematic zoom-out while the fingerprint ribbons assemble along their
///    own curved trajectories (staggered, soft head glow, ghost trails), then
///    the pin eye and the custom curved lettering.
/// 4. The complete official lockup settles and holds, then [onCompleted] fires
///    exactly once so navigation can continue.
///
/// All geometry comes verbatim from [FieldSyncLogoGeometry] (generated from the
/// kit's `fieldsync-logo-white.svg`), so the settled frame is the official
/// artwork — nothing is redrawn, simplified or substituted. Colors follow the
/// existing splash: white artwork, `#EF3B3B` site dot, on the splash's own
/// background. Reduced motion (`MediaQuery.disableAnimations`) skips the
/// journey and lands directly on the final artwork.
class FieldSyncEntranceAnimation extends StatefulWidget {
  const FieldSyncEntranceAnimation({
    super.key,
    this.width,
    required this.onCompleted,
    this.driver,
    this.startSeconds = 0,
  });

  /// Stage width; the height follows the lockup's 887:1115 ratio.
  final double? width;

  /// Called exactly once when the entrance has settled (immediately for
  /// reduced motion). Navigation should wait on this.
  final VoidCallback onCompleted;

  /// External clock, in entrance-local seconds (0 → the end of the timeline),
  /// clamped at both ends. When supplied, the widget creates no controller of
  /// its own and time advances only when the host ticks this animation —
  /// mounting at the current entrance second continues from exactly there,
  /// with no restart. Supply one stable instance for the widget's lifetime.
  final Animation<double>? driver;

  /// Entrance-local second to begin from when [driver] is null: the internal
  /// controller plays exactly the remaining span at the original pace — used
  /// to mount the entrance mid-timeline, e.g. at the
  /// [FieldSyncEntranceTimeline.handoffSeconds] seam. Ignored when [driver]
  /// is set. Defaults to 0 (the full entrance from the top).
  final double startSeconds;

  static const double aspectRatio =
      FieldSyncLogoGeometry.viewBoxWidth / FieldSyncLogoGeometry.viewBoxHeight;

  @override
  State<FieldSyncEntranceAnimation> createState() =>
      _FieldSyncEntranceAnimationState();
}

/// Single source of truth for the entrance timing (seconds), shared by the
/// animation, the splash gate and the tests.
class FieldSyncEntranceTimeline {
  FieldSyncEntranceTimeline._();

  /// Total entrance duration including the final hold.
  static const Duration duration = Duration(milliseconds: 6200);
  static const double total = 6.2;

  /// The three-page cinematic's handoff seam: the entrance-local second the
  /// pre-roll lands on before this entrance owns the frame (it is also where
  /// the route's ghost begins to dissolve).
  static const double handoffSeconds = 2.15;
}

class _FieldSyncEntranceAnimationState extends State<FieldSyncEntranceAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: FieldSyncEntranceTimeline.duration,
  );

  /// What the painter reads: the internal controller, or the host's clock
  /// mapped onto this entrance's own timeline.
  late final Animation<double> _progress = widget.driver == null
      ? _controller
      : _SecondsProgress(widget.driver!);
  bool _decided = false;
  bool _reducedMotion = false;
  bool _reported = false;

  @override
  void initState() {
    super.initState();
    if (widget.driver == null) {
      _controller.addStatusListener((status) {
        if (status == AnimationStatus.completed) _finish();
      });
    } else {
      _progress.addListener(_onDriverTick);
    }
  }

  /// In driven mode the host owns time; completion is the moment its clock
  /// reaches the end of the entrance. Fires at most once (see [_reported]).
  void _onDriverTick() {
    if (!_reported && _progress.value >= 1.0) _finish();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (_reducedMotion) {
      // Accessibility: no journey — land on the finished artwork and release
      // navigation immediately. Undriven, completing the controller paints
      // it; driven, the host's clock is irrelevant (see [build]).
      if (widget.driver == null) {
        _controller.value = 1.0;
      } else {
        _finish();
      }
      return;
    }
    if (widget.driver == null) {
      _controller.forward(
        from: (widget.startSeconds / FieldSyncEntranceTimeline.total).clamp(
          0.0,
          1.0,
        ),
      );
    }
    // Driven: nothing to start — time only moves when the host moves it.
  }

  void _finish() {
    if (_reported) return;
    _reported = true;
    widget.onCompleted();
  }

  @override
  void dispose() {
    if (widget.driver == null) {
      // In driven mode the controller is never created; the widget owns no
      // time — only the listener on the host's clock.
      _controller.dispose();
    } else {
      _progress.removeListener(_onDriverTick);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: widget.width,
        child: AspectRatio(
          aspectRatio: FieldSyncEntranceAnimation.aspectRatio,
          child: CustomPaint(
            isComplex: true,
            painter: FieldSyncEntrancePainter(
              // Reduced motion shows the finished artwork whatever the host
              // clock says; undriven the controller already sits at 1.0.
              animation: _reducedMotion && widget.driver != null
                  ? const AlwaysStoppedAnimation<double>(1.0)
                  : _progress,
            ),
          ),
        ),
      ),
    );
  }
}

/// Maps an external seconds-based clock onto the painter's normalized 0..1
/// progress, holding both ends so an over- or under-run clock still paints a
/// valid frame instead of extrapolating past the artwork's timeline.
class _SecondsProgress extends Animation<double>
    with AnimationWithParentMixin<double> {
  _SecondsProgress(this.parent);

  @override
  final Animation<double> parent;

  @override
  double get value =>
      (parent.value / FieldSyncEntranceTimeline.total).clamp(0.0, 1.0);
}

/// One revealable artwork element (a ribbon, a glyph, a label path) drawn as
/// fills; each subpath gets its own "track" whose spine follows the element's
/// own curve, so reveals slide along the artwork's real trajectory.
class _Element {
  _Element(this.path, {required this.reverse})
    : tracks = [
        for (final metric in path.computeMetrics())
          _Track(metric, metric.length, reverse),
      ];

  final Path path;
  final List<_Track> tracks;
  final bool reverse;
}

class _Track {
  _Track(this.metric, this.length, this.reverse);

  final ui.PathMetric metric;
  final double length;
  final bool reverse;

  final List<Offset> _spine = <Offset>[];
  final List<Offset> _normals = <Offset>[];
  final List<double> _halfWidth = <double>[];
  final List<Offset> _tangents = <Offset>[];

  void prepare() {
    if (_spine.isNotEmpty) return;
    const samples = 40;
    final inset = math.min(0.4, length * 0.02);
    for (var i = 0; i < samples; i++) {
      final s = inset + (length - 2 * inset) * i / (samples - 1);
      final a = metric.getTangentForOffset(s);
      final b = metric.getTangentForOffset(length - s);
      if (a == null || b == null) continue;
      _spine.add((a.position + b.position) / 2);
      _halfWidth.add(math.max(0.05, (a.position - b.position).distance / 2));
      _tangents.add(a.vector);
    }
    for (var i = 0; i < _spine.length; i++) {
      final prev = _spine[math.max(0, i - 1)];
      final next = _spine[math.min(_spine.length - 1, i + 1)];
      final dir = next - prev;
      final len = dir.distance;
      _normals.add(
        len < 0.001 ? const Offset(0, -1) : Offset(-dir.dy / len, dir.dx / len),
      );
    }
    if (reverse) {
      final spine = _spine.reversed.toList();
      _spine
        ..clear()
        ..addAll(spine);
      final normals = _normals.reversed.toList();
      _normals
        ..clear()
        ..addAll(normals);
      final widths = _halfWidth.reversed.toList();
      _halfWidth
        ..clear()
        ..addAll(widths);
      final tangents = _tangents.reversed.toList();
      _tangents
        ..clear()
        ..addAll(tangents);
    }
  }

  /// Region covered by the element once [u] of it has been revealed: a band
  /// along the spine with a rounded nose at the reveal front.
  Path revealRegion(double u) {
    final n = _spine.length;
    final k = (u * (n - 1)).round().clamp(0, n - 1);
    final pts = <Offset>[
      for (var i = 0; i <= k; i++) _spine[i] + _normals[i] * _halfWidth[i],
    ];
    final tangent = _tangents[k];
    final normalAngle = math.atan2(_normals[k].dy, _normals[k].dx);
    final tangentAngle = math.atan2(tangent.dy, tangent.dx);
    var delta = tangentAngle - normalAngle;
    while (delta > math.pi) {
      delta -= 2 * math.pi;
    }
    while (delta < -math.pi) {
      delta += 2 * math.pi;
    }
    final dir = delta >= 0 ? 1.0 : -1.0;
    const capSegments = 8;
    for (var j = 1; j < capSegments; j++) {
      final angle = normalAngle + dir * math.pi * j / capSegments;
      pts.add(
        _spine[k] + Offset(math.cos(angle), math.sin(angle)) * _halfWidth[k],
      );
    }
    for (var i = k; i >= 0; i--) {
      pts.add(_spine[i] - _normals[i] * _halfWidth[i]);
    }
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    path.close();
    return path;
  }

  Offset get head => _spine.isEmpty ? Offset.zero : _spine.last;
}

/// A reveal schedule entry in seconds.
class _Reveal {
  const _Reveal(this.start, this.duration, this.reverse);
  final double start;
  final double duration;
  final bool reverse;
}

/// The nine fingerprint ribbons, staggered; directions chosen to match the
/// reference's observed assembly directions.
const List<_Reveal> _ridgeSchedule = <_Reveal>[
  _Reveal(2.45, 0.75, false), // fingerprint-1 (top arc)
  _Reveal(2.52, 0.85, false), // fingerprint-2 (big middle band)
  _Reveal(2.62, 0.80, true), // fingerprint-3 (left/middle)
  _Reveal(2.80, 0.75, false), // fingerprint-4 (lower band)
  _Reveal(2.95, 0.62, false), // fingerprint-5 (small middle)
  _Reveal(2.68, 0.70, true), // fingerprint-9 (right C)
  _Reveal(2.90, 0.70, false), // fingerprint-13 (bottom right)
  _Reveal(3.05, 0.65, true), // fingerprint-14 (bottom left)
  _Reveal(3.20, 0.75, false), // fingerprint-15 (pin whorl)
];

/// The entrance camera's exact framing at one moment, in artwork viewBox
/// units. [FieldSyncEntrancePainter.cameraAt] performs no interpolation — it
/// returns the same values [FieldSyncEntrancePainter.paint] frames with — so
/// the three-page cinematic's pre-roll can land on a seam frame this painter
/// continues from with no visible jump.
@immutable
class FieldSyncEntranceCamera {
  const FieldSyncEntranceCamera({
    required this.zoom,
    required this.centre,
    required this.anchorT,
  });

  /// Effective artwork scale: the camera push/zoom-out including the settle.
  final double zoom;

  /// The viewBox point placed under the screen anchor.
  final Offset centre;

  /// 0 → the route-following frame; 1 → the lockup-centred frame.
  final double anchorT;

  /// The painter's viewport fit — viewBox width → stage width.
  static double viewportFit(Size size) =>
      size.width / FieldSyncLogoGeometry.viewBoxWidth;

  /// The stage point [centre] is placed under, exactly as the painter places
  /// it.
  static Offset screenAnchorOf(Size size, double anchorT) =>
      Offset(size.width * 0.5, size.height * (0.43 + 0.07 * anchorT));
}

/// Paints the approved entrance artwork for any position of [animation]; the
/// camera math behind it is public via [cameraAt].
class FieldSyncEntrancePainter extends CustomPainter {
  FieldSyncEntrancePainter({required this.animation})
    : super(repaint: animation);

  final Animation<double> animation;

  // Kit navy (`#102D50`) for the traveller puck's centre, mirroring the
  // reference where the puck's dot is darker than its disc.
  static const Color _kitNavy = Color(0xFF102D50);
  static const Color _siteRed = Color(0xFFEF3B3B);

  // ── phase 1: navigation ----------------------------------------------------
  static const double _drawStart = 0.10;
  static const double _drawEnd = 1.62;
  static const double _zoomTravel = 7.1;
  static const double _zoomArrival = 8.0;
  // The video starts wide (the establishing view of the route) and pushes
  // the camera in during the ride itself — not a fixed close-up.
  static const double _zoomStart = 2.2;
  static const double _pushStart = 1.52;
  static const double _pushEnd = 2.02;
  static const double _lookAhead = 0.05;

  // ── phase 2: arrival -------------------------------------------------------
  static const double _dotPopStart = 1.62;
  static const double _dotPopEnd = 1.90;
  static const double _arrowStart = 1.55;
  static const double _arrowEnd = 1.85;
  static const double _pulseStart = 1.66;
  static const double _pulseGap = 0.13;
  static const double _pulseDuration = 0.95;
  static const double _bloomStart = 1.50;
  static const double _bloomEnd = 2.10;

  // ── phase 3: zoom-out and assembly -----------------------------------------
  static const double _zoomOutStart = 2.02;
  static const double _zoomOutEnd = 2.78;
  static const double _centreStart = 2.10;
  static const double _centreEnd = 2.95;
  static const double _dotOutStart = 2.55;
  static const double _dotOutEnd = 2.95;
  static const double _routeGhostOutStart = 2.15;
  static const double _routeGhostOutEnd = 2.90;
  static const double _pinEyeStart = 3.85;
  static const double _pinEyeEnd = 4.20;

  // ── phase 4: lettering, settle, hold ---------------------------------------
  static const double _glyphStart = 4.05;
  static const double _glyphGap = 0.055;
  static const double _glyphDuration = 0.55;
  static const double _dotBackStart = 4.45;
  static const double _dotBackEnd = 4.75;
  static const double _labelStart = 4.55;
  static const double _labelEnd = 4.85;
  static const double _settleStart = 4.90;
  static const double _settleEnd = 5.15;
  static const double _settleScale = 1.008;

  static const double _ridgeGhostAlpha = 0.10;
  static const double _glyphGhostAlpha = 0.08;
  static const double _routeGhostAlpha = 0.16;
  // The video only reveals the print and lettering as they assemble; their
  // static ghosts stay invisible until their own phase begins.
  static const double _ridgeGhostInStart = 2.20;
  static const double _ridgeGhostInEnd = 2.70;
  static const double _glyphGhostInStart = 3.85;
  static const double _glyphGhostInEnd = 4.10;

  // ── traveller puck ---------------------------------------------------------
  static const double _puckIn = 0.06;
  static const double _puckPopEnd = 0.34;
  static const double _puckOutStart = 1.45;
  static const double _puckOutEnd = 1.62;

  // ── prepared once ----------------------------------------------------------
  List<_Element>? _ridges;
  List<_Element>? _glyphs;
  List<_Element>? _label;

  // Route geometry is pure, so it is cached statically and can be prepared
  // without a painter instance — [cameraAt] needs it before the first frame.
  static ui.PathMetric? _routeMetric;
  static double _routeLength = 0;
  static Offset _lockupCentre = Offset.zero;

  double get _seconds => animation.value * FieldSyncEntranceTimeline.total;

  void _prepare() {
    if (_ridges != null) return;
    _ridges = [
      for (var i = 0; i < FieldSyncLogoGeometry.fingerprints.length; i++)
        _Element(
          FieldSyncLogoGeometry.fingerprints[i],
          reverse: _ridgeSchedule[i].reverse,
        ),
    ];
    _glyphs = [
      for (final p in FieldSyncLogoGeometry.wordmark)
        _Element(p, reverse: false),
    ];
    _label = [
      for (final p in FieldSyncLogoGeometry.siteLabel)
        _Element(p, reverse: false),
    ];
    _prepareRouteGeometry();
    for (final list in [_ridges!, _glyphs!, _label!]) {
      for (final element in list) {
        for (final track in element.tracks) {
          track.prepare();
        }
      }
    }
  }

  /// Route geometry is pure and independent of any painter instance; cached
  /// once so [cameraAt] can answer before the first frame ever paints.
  static void _prepareRouteGeometry() {
    if (_routeMetric != null) return;
    _routeMetric = FieldSyncLogoGeometry.route.computeMetrics().first;
    _routeLength = _routeMetric!.length;
    _lockupCentre = Offset(
      FieldSyncLogoGeometry.viewBoxLeft +
          FieldSyncLogoGeometry.viewBoxWidth / 2,
      FieldSyncLogoGeometry.viewBoxTop +
          FieldSyncLogoGeometry.viewBoxHeight / 2,
    );
  }

  static double _win(double t, double a, double b) =>
      ((t - a) / (b - a)).clamp(0.0, 1.0);

  static double _ease(Curve curve, double t, double a, double b) =>
      curve.transform(_win(t, a, b));

  static double _routeProgress(double t) =>
      Curves.easeInOutSine.transform(_win(t, _drawStart, _drawEnd));

  static Offset _routePointAt(double fraction) {
    final tangent = _routeMetric!.getTangentForOffset(_routeLength * fraction);
    return tangent?.position ?? Offset.zero;
  }

  static double _cameraZoom(double t) {
    if (t < _pushStart) {
      return _zoomStart +
          (_zoomTravel - _zoomStart) *
              _ease(Curves.easeInOutSine, t, _drawStart, _pushStart);
    }
    if (t < _pushEnd) {
      return _zoomTravel +
          (_zoomArrival - _zoomTravel) *
              _ease(Curves.easeInOutSine, t, _pushStart, _pushEnd);
    }
    if (t < _zoomOutStart) return _zoomArrival;
    if (t < _zoomOutEnd) {
      return _zoomArrival +
          (1.0 - _zoomArrival) *
              _ease(Curves.easeInOutQuart, t, _zoomOutStart, _zoomOutEnd);
    }
    return 1.0;
  }

  static Offset _cameraCentre(double t) {
    final head = _routePointAt(math.min(1.0, _routeProgress(t) + _lookAhead));
    final w = _ease(Curves.easeInOutSine, t, _centreStart, _centreEnd);
    return Offset.lerp(head, _lockupCentre, w)!;
  }

  /// The camera's exact state at entrance-local [seconds] — the same values
  /// [paint] frames the artwork with, so the three-page cinematic's pre-roll
  /// can hand over at [FieldSyncEntranceTimeline.handoffSeconds] invisibly.
  /// Safe to call before any painter is built; out-of-range seconds are held
  /// at the timeline's own boundaries by the underlying windows.
  static FieldSyncEntranceCamera cameraAt(double seconds) {
    _prepareRouteGeometry();
    return FieldSyncEntranceCamera(
      zoom: _cameraZoom(seconds) * _settle(seconds),
      centre: _cameraCentre(seconds),
      anchorT: _ease(Curves.easeInOutSine, seconds, _centreStart, _centreEnd),
    );
  }

  double _siteDotAlpha(double t) {
    if (t < _dotPopStart) return 0;
    var a = _ease(Curves.easeOutCubic, t, _dotPopStart, _dotPopEnd);
    if (t > _dotOutStart) {
      a *= 1 - _ease(Curves.easeInOutSine, t, _dotOutStart, _dotOutEnd);
    }
    if (t > _dotBackStart) {
      a = math.max(
        a,
        _ease(Curves.easeOutCubic, t, _dotBackStart, _dotBackEnd),
      );
    }
    return a;
  }

  double _siteDotScale(double t) {
    if (t < _dotPopStart) return 0.55;
    final e = _ease(Curves.easeOutCubic, t, _dotPopStart, _dotPopEnd);
    return (0.55 + 0.45 * e) * (1 + 0.12 * math.sin(math.pi * e));
  }

  static double _settle(double t) {
    final e = _ease(Curves.easeInOutSine, t, _settleStart, _settleEnd);
    return _settleScale + (1 - _settleScale) * e;
  }

  /// Ghost (pale reminder of the final position) + progressive reveal along the
  /// element's own curve with a soft glowing head.
  void _paintReveal(
    Canvas canvas,
    _Element element,
    double progress,
    double ghostAlpha,
  ) {
    if (progress <= 0) {
      if (ghostAlpha > 0) {
        canvas.drawPath(
          element.path,
          Paint()..color = Colors.white.withValues(alpha: ghostAlpha),
        );
      }
      return;
    }
    if (progress >= 1) {
      canvas.drawPath(element.path, Paint()..color = Colors.white);
      return;
    }
    final ghost = ghostAlpha * (1 - progress);
    if (ghost > 0.004) {
      canvas.drawPath(
        element.path,
        Paint()..color = Colors.white.withValues(alpha: ghost),
      );
    }
    final fill = Paint()..color = Colors.white;
    final glowFade = 1 - _win(progress, 0.72, 1.0);
    for (final track in element.tracks) {
      canvas.save();
      canvas.clipPath(track.revealRegion(progress));
      canvas.drawPath(element.path, fill);
      canvas.restore();
      if (glowFade > 0.01) {
        final head = track.head;
        final radius = track._halfWidth.isEmpty
            ? 3.0
            : track._halfWidth.last * 2.4 + 2;
        canvas.drawCircle(
          head,
          radius,
          Paint()
            ..shader = ui.Gradient.radial(head, radius, [
              Colors.white.withValues(alpha: 0.5 * glowFade),
              Colors.white.withValues(alpha: 0),
            ]),
        );
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    _prepare();
    final t = _seconds;

    final camera = cameraAt(t);
    final q = FieldSyncEntranceCamera.viewportFit(size);
    final screenAnchor = FieldSyncEntranceCamera.screenAnchorOf(
      size,
      camera.anchorT,
    );

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(screenAnchor.dx, screenAnchor.dy);
    canvas.scale(q * camera.zoom);
    canvas.translate(-camera.centre.dx, -camera.centre.dy);

    // 1. Route ghost (the pale planned path the camera is following).
    var routeGhost = _routeGhostAlpha;
    if (t > _routeGhostOutStart) {
      routeGhost *=
          1 -
          _ease(
            Curves.easeInOutSine,
            t,
            _routeGhostOutStart,
            _routeGhostOutEnd,
          );
    }
    if (routeGhost > 0.004) {
      canvas.drawPath(
        FieldSyncLogoGeometry.route,
        Paint()
          ..color = Colors.white.withValues(alpha: routeGhost)
          ..style = PaintingStyle.stroke
          ..strokeWidth = FieldSyncLogoGeometry.routeStrokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.1),
      );
    }

    // 2. Ridges: ghosts + snake reveals along their own curves.
    final ridgeGhostIn = _ease(
      Curves.easeOutCubic,
      t,
      _ridgeGhostInStart,
      _ridgeGhostInEnd,
    );
    for (var i = 0; i < _ridges!.length; i++) {
      final reveal = _ridgeSchedule[i];
      final u = _ease(
        Curves.easeInOutSine,
        t,
        reveal.start,
        reveal.start + reveal.duration,
      );
      _paintReveal(canvas, _ridges![i], u, _ridgeGhostAlpha * ridgeGhostIn);
    }

    // 3. Route drawing (solid) with the traveller puck at its head.
    final routeProgress = _routeProgress(t);
    if (routeProgress > 0) {
      final drawn = _routeMetric!.extractPath(0, _routeLength * routeProgress);
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

    // 4. Pin eye pop.
    final pinE = _ease(Curves.easeOutCubic, t, _pinEyeStart, _pinEyeEnd);
    if (pinE > 0) {
      canvas.save();
      canvas.translate(
        FieldSyncLogoGeometry.pinEyeX,
        FieldSyncLogoGeometry.pinEyeY,
      );
      canvas.scale(0.55 + 0.45 * pinE);
      canvas.drawCircle(
        Offset.zero,
        FieldSyncLogoGeometry.pinEyeR,
        Paint()..color = Colors.white.withValues(alpha: pinE),
      );
      canvas.restore();
    }

    // 5. Lettering: ghosts + left-to-right glyph wave.
    final glyphGhostIn = _ease(
      Curves.easeOutCubic,
      t,
      _glyphGhostInStart,
      _glyphGhostInEnd,
    );
    for (var i = 0; i < _glyphs!.length; i++) {
      final start = _glyphStart + i * _glyphGap;
      final u = _ease(Curves.easeInOutSine, t, start, start + _glyphDuration);
      _paintReveal(canvas, _glyphs![i], u, _glyphGhostAlpha * glyphGhostIn);
    }

    // 6. Site-label micro text (fades in with the final composition).
    final labelA = _ease(Curves.easeOutCubic, t, _labelStart, _labelEnd);
    if (labelA > 0.004) {
      final labelPaint = Paint()
        ..color = Colors.white.withValues(alpha: labelA);
      for (final element in _label!) {
        canvas.drawPath(element.path, labelPaint);
      }
    }

    // 7. Arrival: bloom, arrowhead, red dot, pulse rings.
    final bloomW = _win(t, _bloomStart, _bloomEnd);
    if (bloomW > 0 && bloomW < 1) {
      final dot = Offset(
        FieldSyncLogoGeometry.siteDotX,
        FieldSyncLogoGeometry.siteDotY,
      );
      final radius = 3 + 26 * Curves.easeOutCubic.transform(bloomW);
      canvas.drawCircle(
        dot,
        radius,
        Paint()
          ..shader = ui.Gradient.radial(dot, radius, [
            Colors.white.withValues(alpha: 0.45 * (1 - bloomW)),
            Colors.white.withValues(alpha: 0),
          ]),
      );
    }

    final arrowA = _ease(Curves.easeOutCubic, t, _arrowStart, _arrowEnd);
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

    for (var k = 0; k < 2; k++) {
      final start = _pulseStart + k * _pulseGap;
      final w = _win(t, start, start + _pulseDuration);
      if (w <= 0 || w >= 1) continue;
      final e = Curves.easeOutCubic.transform(w);
      canvas.drawCircle(
        Offset(FieldSyncLogoGeometry.siteDotX, FieldSyncLogoGeometry.siteDotY),
        FieldSyncLogoGeometry.siteDotR + 15.5 * e,
        Paint()
          ..color = _siteRed.withValues(
            alpha: 0.55 * (1 - e) * math.min(1, w / 0.08),
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6 - 1.7 * e,
      );
    }

    final dotA = _siteDotAlpha(t);
    if (dotA > 0.004) {
      canvas.save();
      canvas.translate(
        FieldSyncLogoGeometry.siteDotX,
        FieldSyncLogoGeometry.siteDotY,
      );
      canvas.scale(_siteDotScale(t));
      canvas.drawCircle(
        Offset.zero,
        FieldSyncLogoGeometry.siteDotR,
        Paint()..color = _siteRed.withValues(alpha: dotA),
      );
      canvas.restore();
    }

    // 8. Traveller puck on the route head.
    final puckW = _win(t, _puckIn, _puckOutEnd);
    if (t >= _puckIn && puckW < 1 && routeProgress > 0) {
      var puckA =
          _ease(Curves.easeOutCubic, t, _puckIn, _puckPopEnd) *
          (1 - _ease(Curves.easeInOutSine, t, _puckOutStart, _puckOutEnd));
      if (puckA > 0.004) {
        final head = _routePointAt(routeProgress);
        final scale =
            0.6 + 0.4 * _ease(Curves.easeOutCubic, t, _puckIn, _puckPopEnd);
        canvas.save();
        canvas.translate(head.dx, head.dy);
        canvas.scale(scale);
        canvas.drawCircle(
          Offset.zero,
          4.4,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.92 * puckA)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.75,
        );
        canvas.drawCircle(
          Offset.zero,
          2.9,
          Paint()..color = Colors.white.withValues(alpha: 0.95 * puckA),
        );
        canvas.drawCircle(
          Offset.zero,
          1.15,
          Paint()..color = _kitNavy.withValues(alpha: puckA),
        );
        canvas.restore();
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant FieldSyncEntrancePainter oldDelegate) =>
      oldDelegate.animation != animation;
}
