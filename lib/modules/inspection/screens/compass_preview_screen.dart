import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';

import '../../../core/layout/responsive_layout.dart';
import 'gps_verification_screen.dart' show fitCompassDiameter;

import '../../../core/widgets/sensitive_screen.dart';
import '../../../core/widgets/field_form_widgets.dart';
import '../../../core/theme/insight_theme.dart';

/// Standalone Compass — reached from the nav bar's Quick Actions sheet.
///
/// Shares the canonical compass dial face, painters, typography tokens,
/// and responsive proportions with Step 2 of the inspection flow
/// (`gps_verification_screen.dart`).
///
/// Removed from the standalone mode: task-bound target parcel metrics
/// (distance threshold, SITE relative needle, authoritative Haversine check,
/// and verification confirmation buttons) since there is no active inspection
/// task in standalone navigation.
class StandaloneCompassScreen extends StatefulWidget {
  const StandaloneCompassScreen({super.key});

  @override
  State<StandaloneCompassScreen> createState() =>
      _StandaloneCompassScreenState();
}

class _StandaloneCompassScreenState extends State<StandaloneCompassScreen> {
  StreamSubscription<CompassEvent>? _compassSub;
  double? _heading;
  double? _accuracy;
  bool _compassUnavailable = false;

  static const _cardinals = [
    'N',
    'NNE',
    'NE',
    'ENE',
    'E',
    'ESE',
    'SE',
    'SSE',
    'S',
    'SSW',
    'SW',
    'WSW',
    'W',
    'WNW',
    'NW',
    'NNW',
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
      if (!mounted) return;
      if (event.heading == null) {
        return;
      }
      setState(() {
        _heading = event.heading;
        _accuracy = event.accuracy;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    return SensitiveScreen(
      child: Scaffold(
        backgroundColor: InsightTheme.bg,
        body: Stack(
          children: [
            // Atmospheric background glow elements
            Positioned(
              top: -60,
              right: -60,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: InsightTheme.blue1.withValues(alpha: 0.12),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 120,
              left: -80,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: InsightTheme.blue2.withValues(alpha: 0.08),
                  ),
                ),
              ),
            ),

            SafeArea(
              // Portrait keeps the accepted stack: dial above the metrics card.
              // Landscape and tablet put the dial left as the primary pane and
              // the metrics beside it, so the dial stays large instead of being
              // squeezed to fit a portrait-shaped card.
              child: HeaderSplitBody(
                header: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FieldBackButton(
                            onPressed: () => Navigator.pop(context),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Compass',
                                  style: InsightTheme.poppins(
                                    18,
                                    w: FontWeight.w700,
                                    c: InsightTheme.ink,
                                  ),
                                ),
                                Text(
                                  'Live orientation',
                                  style: InsightTheme.inter(
                                    12,
                                    c: InsightTheme.ink2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: InsightTheme.blueTint,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: InsightTheme.blue1.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          'STANDALONE',
                          style: InsightTheme.jetBrains(
                            9,
                            w: FontWeight.w800,
                            c: InsightTheme.blueInk,
                            ls: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Center Compass Dial Area
                primary: _compassUnavailable
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: InsightTheme.surface,
                                  borderRadius: BorderRadius.circular(
                                    InsightTheme.radiusLg,
                                  ),
                                  border: Border.all(color: InsightTheme.line),
                          boxShadow: InsightTheme.cardShadow,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: InsightTheme.amberTint,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: InsightTheme.amber.withValues(
                                    alpha: 0.2,
                                  ),
                                ),
                              ),
                              child: const Icon(
                                Icons.explore_off_rounded,
                                size: 24,
                                color: InsightTheme.amber,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Compass sensor unavailable',
                              style: InsightTheme.poppins(
                                15,
                                w: FontWeight.w700,
                                c: InsightTheme.ink,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'A magnetometer sensor was not detected on this hardware. Orientation data cannot be provided.',
                              textAlign: TextAlign.center,
                              style: InsightTheme.inter(
                                12,
                                c: InsightTheme.ink2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          // Same fitting rule as GPS Verification: no minimum,
                          // so the dial can never demand more than the space it
                          // was given.
                          final compassSize = fitCompassDiameter(
                            availableWidth: constraints.maxWidth,
                            availableHeight: constraints.maxHeight,
                            ceiling: 270.0,
                          );

                          return Center(
                            child: RepaintBoundary(key: const ValueKey('compass-face'),
                              child: ExcludeSemantics(child: MediaQuery.withNoTextScaling(child: _StandaloneCompassDial(
                              size: compassSize,
                              heading: _heading,
                              headingCardinal: _headingCardinal,
                            )))),
                          );
                        },
                      ),
                // Orientation metrics: below the dial in portrait, beside it
                // once there is room.
                secondary: _compassUnavailable
                    ? null
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: _StandaloneOrientationCard(
                          heading: _heading,
                          headingCardinal: _headingCardinal,
                          accuracy: _accuracy,
                        ),
                      ),
                // Landscape reclaims the header's space for the dial and keeps
                // only this floating back control; portrait retains the header.
                landscapeBackButton: FieldBackButton(
                    onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Standalone Compass Dial component matching the canonical
/// `_Compass` visual design from `gps_verification_screen.dart`.
class _StandaloneCompassDial extends StatelessWidget {
  final double size;
  final double? heading;
  final String headingCardinal;

  const _StandaloneCompassDial({
    required this.size,
    required this.heading,
    required this.headingCardinal,
  });

  @override
  Widget build(BuildContext context) {
    // Grow the hub for enlarged text without enlarging the readout again.
    var hubSize = size * 0.47;
    final readoutSize = hubSize;
    final scaler = MediaQuery.textScalerOf(context);
    double lineHeight(double fontSize) {
      final painter = TextPainter(
        text: TextSpan(
          text: '0',
          style: InsightTheme.jetBrains(fontSize, w: FontWeight.w800),
        ),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      final measured = painter.height;
      painter.dispose();
      return measured;
    }

    final needed =
        lineHeight(hubSize * 0.085) +
        lineHeight(hubSize * 0.19) +
        lineHeight(hubSize * 0.066) +
        hubSize * 0.066;
    hubSize = math.min(size - 8, math.max(hubSize, needed / 0.78));

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Drop shadow behind the disc.
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: InsightTheme.blue2.withValues(alpha: 0.18),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
          ),

          // Rotating dial (face + ticks + cardinal letters via painter).
          AnimatedRotation(
            turns: heading != null ? -(heading! / 360) : 0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.linear,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: InsightTheme.surface,
                border: Border.all(color: InsightTheme.surface2, width: 4),
              ),
              child: CustomPaint(
                size: Size(size, size),
                painter: _DialPainter(verified: true),
              ),
            ),
          ),

          // Top forward pointer marking straight-ahead device orientation.
          Positioned(
            top: 0,
            child: CustomPaint(
              size: Size(16 * size / 268, 12 * size / 268),
              painter: _TopPointerPainter(color: InsightTheme.blue1),
            ),
          ),

          // Central Hub
          Container(
            width: hubSize,
            height: hubSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [InsightTheme.blue1, InsightTheme.blue2],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: InsightTheme.blue2.withValues(alpha: 0.35),
                  blurRadius: 26,
                  offset: const Offset(0, 12),
                ),
              ],
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.4),
                width: 2,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  headingCardinal,
                  style: InsightTheme.jetBrains(
                    readoutSize * 0.085,
                    w: FontWeight.w800,
                    ls: 1.5,
                    c: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      heading != null ? '${heading!.round()}' : '--',
                      style: InsightTheme.jetBrains(
                        readoutSize * 0.19,
                        w: FontWeight.w800,
                        c: Colors.white,
                      ),
                    ),
                    Text(
                      '°',
                      style: InsightTheme.jetBrains(
                        readoutSize * 0.115,
                        w: FontWeight.w700,
                        c: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: hubSize * 0.03),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: hubSize * 0.07,
                    vertical: hubSize * 0.018,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Text(
                    'LIVE',
                    style: InsightTheme.jetBrains(
                      readoutSize * 0.066,
                      w: FontWeight.w700,
                      ls: 1,
                      c: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints the canonical compass dial face: radial wash ending in the state tint,
/// outer accent ring, dashed inner circle, 10° ticks (30° majors) and cardinal letters
/// (N in red `#EF4444`, E/S/W in dark ink) + major degree labels.
class _DialPainter extends CustomPainter {
  final bool verified;
  _DialPainter({required this.verified});

  static const _cardinalAt = {0: 'N', 90: 'E', 180: 'S', 270: 'W'};

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final tint = verified ? InsightTheme.blueTint : InsightTheme.amberTint;
    final accent = verified ? InsightTheme.blue1 : InsightTheme.amber;

    // Face: subtle radial wash ending in the state tint at the rim.
    final face = Paint()
      ..shader = RadialGradient(
        colors: [Colors.white, const Color(0xFFF8FAFC), tint],
        stops: const [0.0, 0.82, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius - 4, face);

    // Outer accent ring.
    canvas.drawCircle(
      center,
      radius - 4,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = accent.withValues(alpha: 0.55),
    );

    // Dashed inner circle (2-on / 3-off segments).
    final dashPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = accent.withValues(alpha: 0.30);
    final dashCircle = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius * 0.72));
    for (final metric in dashCircle.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        canvas.drawPath(
          metric.extractPath(dist, math.min(dist + 2, metric.length)),
          dashPaint,
        );
        dist += 5;
      }
    }

    // Ticks + labels.
    for (int deg = 0; deg < 360; deg += 10) {
      final isMajor = deg % 30 == 0;
      final isCardinal = _cardinalAt.containsKey(deg);
      final angle = (deg - 90) * math.pi / 180.0;
      final tickLen = isMajor ? radius * 0.066 : radius * 0.033;
      final outer = Offset(
        center.dx + (radius - 9) * math.cos(angle),
        center.dy + (radius - 9) * math.sin(angle),
      );
      final inner = Offset(
        center.dx + (radius - 9 - tickLen) * math.cos(angle),
        center.dy + (radius - 9 - tickLen) * math.sin(angle),
      );
      canvas.drawLine(
        inner,
        outer,
        Paint()
          ..color = isMajor
              ? InsightTheme.ink2
              : InsightTheme.ink3.withValues(alpha: 0.45)
          ..strokeWidth = isMajor ? 2 : 1
          ..strokeCap = StrokeCap.round,
      );

      if (isMajor) {
        final isDegreeLabel = !isCardinal;
        final label = _cardinalAt[deg] ?? '$deg°';
        final labelRadius = radius * 0.60;
        final pos = Offset(
          center.dx + labelRadius * math.cos(angle),
          center.dy + labelRadius * math.sin(angle),
        );
        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: isCardinal
                ? InsightTheme.poppins(
                    size.width * 0.055,
                    w: FontWeight.w800,
                    c: deg == 0 ? InsightTheme.red : InsightTheme.ink2,
                  )
                : InsightTheme.jetBrains(
                    size.width * 0.036,
                    w: FontWeight.w600,
                    c: InsightTheme.ink3,
                  ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
        assert(isDegreeLabel || _cardinalAt.containsKey(deg));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DialPainter oldDelegate) =>
      oldDelegate.verified != verified;
}

/// Fixed pointer above the dial marking "straight ahead" (heading 0° relative to device).
class _TopPointerPainter extends CustomPainter {
  final Color color;
  _TopPointerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(0, size.height)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.2), 2, false);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _TopPointerPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Bottom Orientation Information Card for Standalone View
class _StandaloneOrientationCard extends StatelessWidget {
  final double? heading;
  final String headingCardinal;
  final double? accuracy;

  const _StandaloneOrientationCard({
    required this.heading,
    required this.headingCardinal,
    required this.accuracy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('compass-details'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: InsightTheme.surface,
        borderRadius: InsightTheme.roundedMd,
        border: Border.all(color: InsightTheme.line),
        boxShadow: InsightTheme.cardShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: Semantics(header: true,
              child: Text('Orientation details', style: InsightTheme.urbanist(14, w: FontWeight.w700)))),
            const SizedBox(width: 8),
            Flexible(child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: heading == null ? InsightTheme.surface2 : InsightTheme.greenTint,
                borderRadius: BorderRadius.circular(10)),
              child: Text(heading == null ? 'Waiting' : 'Active',
                style: InsightTheme.inter(12, w: FontWeight.w600,
                  c: heading == null ? InsightTheme.ink3 : InsightTheme.greenInk)))),
          ]),
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _MetricTile(
                label: 'Heading',
                value: heading != null ? '${heading!.round()}°' : '--',
                semanticsLabel: heading == null ? 'Heading unavailable' : 'Heading ${heading!.round()} degrees, $headingCardinal',
              ),
              _MetricTile(label: 'Cardinal', value: headingCardinal),
              _MetricTile(
                label: 'Accuracy',
                value: accuracy != null && accuracy! >= 0 ? '± ${accuracy!.round()}°' : 'Unavailable',
              ),
            ],
          ),
          const Divider(height: 24),
          Text('Sensor · Live Device Magnetometer', style: InsightTheme.inter(12)),
          const SizedBox(height: 12),
          Text('Rotate your device to observe real-time bearing in the field.',
            style: InsightTheme.inter(12, c: InsightTheme.blueInk)),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final String? semanticsLabel;
  const _MetricTile({required this.label, required this.value, this.semanticsLabel});

  @override
  Widget build(BuildContext context) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: InsightTheme.inter(12),
          ),
          const SizedBox(height: 2),
          Semantics(label: semanticsLabel, excludeSemantics: semanticsLabel != null, child: Text(
            value,
            style: InsightTheme.inter(16, w: FontWeight.w700, c: InsightTheme.ink),
          )),
        ],
    );
  }
}
