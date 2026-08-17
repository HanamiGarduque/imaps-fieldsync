import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_compass/flutter_compass.dart';

import '../../../core/widgets/sensitive_screen.dart';

/// Local theme for this screen — identical values to the InsightTheme
/// class already defined inside gps_verification_screen.dart (and
/// standalone_site_map_screen.dart), kept as its own private copy here
/// rather than importing across screen files. Same reasoning as
/// standalone_site_map_screen.dart's doc comment: this mirrors the
/// already-established "map/compass UI" pattern in this app, distinct
/// from the app's main dark shell theme on purpose.
class _CompassUITheme {
  static const Color bg = Color(0xFFF2F4FB);
  static const Color surface = Colors.white;
  static const Color ink = Color(0xFF12141F);
  static const Color ink2 = Color(0xFF666C82);
  static const Color ink3 = Color(0xFFA2A7BC);
  static const Color blue1 = Color(0xFF3D6BFF);
  static const Color blue2 = Color(0xFF0B2FBF);

  static TextStyle poppins(double size, {FontWeight w = FontWeight.w600, Color? c, double? h, double? ls}) =>
      GoogleFonts.poppins(fontSize: size, fontWeight: w, color: c ?? ink, height: h ?? 1.2, letterSpacing: ls);
  static TextStyle inter(double size, {FontWeight w = FontWeight.w400, Color? c, double? h, double? ls}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: c ?? ink2, height: h ?? 1.5, letterSpacing: ls);
  static TextStyle jetBrains(double size, {FontWeight w = FontWeight.w500, Color? c, double? ls}) =>
      GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: w, color: c ?? ink3, letterSpacing: ls);
}

/// Standalone Compass — reached from the nav bar's Quick Actions sheet.
///
/// This is the same screen shell, background, header treatment, and
/// compass dial as Step 2 of the inspection flow
/// (gps_verification_screen.dart) — same sizing formula, same painters,
/// same glass background blobs. The only thing removed is everything that
/// depended on comparing the device's position against a parcel target:
/// no distance badge, no lat/long readout, no bearing-to-target arrow, no
/// verified/unverified threshold, no live-tracking position stream, no
/// submit button. What remains is exactly one piece of information — the
/// live heading shown inside the compass dial itself — with nothing to
/// verify against, because there's no task here.
class StandaloneCompassScreen extends StatefulWidget {
  const StandaloneCompassScreen({super.key});

  @override
  State<StandaloneCompassScreen> createState() => _StandaloneCompassScreenState();
}

class _StandaloneCompassScreenState extends State<StandaloneCompassScreen> {
  StreamSubscription<CompassEvent>? _compassSub;
  double? _heading;
  bool _compassUnavailable = false;

  static const _cardinals = [
    'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
    'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW',
  ];

  String get _headingCardinal {
    if (_heading == null) return '--';
    return _cardinals[(((_heading! + 11.25) ~/ 22.5) % 16)];
  }

  @override
  void initState() {
    super.initState();
    _startCompass();
  }

  @override
  void dispose() {
    _compassSub?.cancel();
    super.dispose();
  }

  void _startCompass() {
    final events = FlutterCompass.events;
    if (events == null) {
      setState(() => _compassUnavailable = true);
      return;
    }
    _compassSub = events.listen((event) {
      if (!mounted || event.heading == null) return;
      setState(() => _heading = event.heading);
    });
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    return SensitiveScreen(
      child: Scaffold(
        backgroundColor: _CompassUITheme.bg,
        body: Stack(
          children: [
            Positioned(
              top: -60,
              right: -60,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _CompassUITheme.blue1.withValues(alpha: 0.20),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -80,
              left: -80,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _CompassUITheme.blue1.withValues(alpha: 0.10),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      children: [
                        _GlassBackButton(onTap: () => Navigator.pop(context)),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Compass', style: _CompassUITheme.poppins(17, w: FontWeight.w700)),
                              Text(
                                'Live heading',
                                style: _CompassUITheme.inter(12, c: _CompassUITheme.ink2),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Deliberately no step progress bar here (see
                  // gps_verification_screen.dart's "STEP 2 OF 6" block) —
                  // this screen isn't part of the 6-step inspection flow.
                  Expanded(
                    child: _compassUnavailable
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.explore_off_rounded, size: 40, color: _CompassUITheme.ink3),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Compass sensor is not available on this device.',
                                    textAlign: TextAlign.center,
                                    style: _CompassUITheme.inter(13, c: _CompassUITheme.ink2),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              // Exact same sizing formula as gps_verification_screen.dart's
                              // _Compass usage — smaller of width/height so it stays a true
                              // circle and never forces content off-screen.
                              final compassSize = math.min(
                                constraints.maxWidth * 0.72,
                                math.min(constraints.maxHeight * 0.62, 268.0),
                              ).clamp(160.0, 268.0).toDouble();

                              return Center(
                                child: _Compass(
                                  size: compassSize,
                                  heading: _heading,
                                  headingCardinal: _headingCardinal,
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The circular compass ring + heading readout — same dial, same
/// proportions, same painters as gps_verification_screen.dart's _Compass.
/// Removed: the [bearingToParcel] parameter and its target arrow (nothing
/// to point to without a parcel), and the [verified] threshold that used
/// to switch the ring/marker between blue ("searching") and amber/green
/// accents. Standalone mode has no verification concept, so it's always
/// rendered in the one consistent accent color.
class _Compass extends StatelessWidget {
  final double size;
  final double? heading;
  final String headingCardinal;

  const _Compass({
    required this.size,
    required this.heading,
    required this.headingCardinal,
  });

  @override
  Widget build(BuildContext context) {
    final ringSize = size * (250 / 268);
    final innerSize = size * (148 / 268);
    final headingFontSize = (size / 268) * 34;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: ringSize,
            height: ringSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: _CompassUITheme.blue1.withValues(alpha: 0.22), blurRadius: 46, spreadRadius: 4),
              ],
            ),
          ),
          AnimatedRotation(
            turns: heading != null ? -(heading! / 360) : 0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.linear,
            child: CustomPaint(size: Size(ringSize, ringSize), painter: _CompassRingPainter()),
          ),
          Positioned(
            top: size * (2 / 268),
            child: CustomPaint(size: Size(18 * size / 268, 14 * size / 268), painter: _ForwardMarkerPainter()),
          ),
          Container(
            width: innerSize,
            height: innerSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [_CompassUITheme.blue1, _CompassUITheme.blue2],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(color: _CompassUITheme.blue2.withValues(alpha: 0.35), blurRadius: 26, offset: const Offset(0, 12)),
              ],
              border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2),
            ),
            // Fixed-length content only ("N"/"NNW", "0°"-"360°"), same as
            // the original — font size already scales with [size].
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  headingCardinal,
                  style: _CompassUITheme.poppins(
                    math.max(12.0, headingFontSize * 15 / 34),
                    w: FontWeight.w700,
                    c: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  heading != null ? '${heading!.round()}°' : '--°',
                  style: _CompassUITheme.poppins(headingFontSize, w: FontWeight.w800, c: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompassRingPainter extends CustomPainter {
  static const _cardinalAt = {0: 'N', 90: 'E', 180: 'S', 270: 'W'};

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const accent = _CompassUITheme.blue1;

    final ringPaint = Paint()
      ..shader = SweepGradient(
        colors: [accent.withValues(alpha: 0.05), accent.withValues(alpha: 0.35), accent.withValues(alpha: 0.05)],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, radius - 4, ringPaint);

    for (int deg = 0; deg < 360; deg += 10) {
      final isMajor = deg % 30 == 0;
      final isCardinal = _cardinalAt.containsKey(deg);
      final angle = (deg - 90) * math.pi / 180.0;
      final tickLen = isCardinal ? 16.0 : (isMajor ? 11.0 : 6.0);
      final outer = Offset(center.dx + (radius - 6) * math.cos(angle), center.dy + (radius - 6) * math.sin(angle));
      final inner = Offset(center.dx + (radius - 6 - tickLen) * math.cos(angle), center.dy + (radius - 6 - tickLen) * math.sin(angle));
      canvas.drawLine(
        inner,
        outer,
        Paint()
          ..color = isCardinal ? accent : _CompassUITheme.ink3.withValues(alpha: isMajor ? 0.55 : 0.3)
          ..strokeWidth = isCardinal ? 3 : (isMajor ? 2 : 1.2)
          ..strokeCap = StrokeCap.round,
      );

      if (isMajor) {
        final label = _cardinalAt[deg] ?? '$deg';
        final labelRadius = radius - 30;
        final pos = Offset(center.dx + labelRadius * math.cos(angle), center.dy + labelRadius * math.sin(angle));
        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: isCardinal
                ? _CompassUITheme.poppins(15, w: FontWeight.w800, c: accent)
                : _CompassUITheme.jetBrains(10, w: FontWeight.w600, c: _CompassUITheme.ink3),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CompassRingPainter oldDelegate) => false;
}

class _ForwardMarkerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const color = _CompassUITheme.blue1;
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(0, size.height)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.2), 2, false);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _ForwardMarkerPainter oldDelegate) => false;
}

class _GlassBackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _GlassBackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.65)),
          boxShadow: const [BoxShadow(color: Color(0x0F141628), blurRadius: 10, offset: Offset(0, 4))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: _CompassUITheme.ink),
              ),
            ),
          ),
        ),
      ),
    );
  }
}