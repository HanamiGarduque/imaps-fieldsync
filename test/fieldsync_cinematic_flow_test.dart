import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/navigation/main_shell_screen.dart';
import 'package:imaps_fieldsync/core/services/app_bootstrap.dart';
import 'package:imaps_fieldsync/core/services/auth_service.dart';
import 'package:imaps_fieldsync/core/widgets/fieldsync_brand.dart';
import 'package:imaps_fieldsync/core/widgets/fieldsync_cinematic_intro.dart';
import 'package:imaps_fieldsync/core/widgets/fieldsync_entrance_animation.dart';
import 'package:imaps_fieldsync/core/widgets/fieldsync_logo_geometry.dart';
import 'package:imaps_fieldsync/modules/auth_startup/screens/app_resume_lock_screen.dart';
import 'package:imaps_fieldsync/modules/auth_startup/screens/splash_screen.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/biometric_service.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/secure_prefs_service.dart';

import 'support/offline_reliability_fixture.dart';

/// T5 flow coverage for the approved three-page launch cinematic: the one
/// clock and its beat map, the Page 1 → Page 2 seam splice onto the measured
/// logo box, single-route ownership after the seam, the departure's
/// follow-the-tip camera and its C1 continuation of the official route, the
/// Page 3 re-entry onto the login's measured brand rect, the stroke's
/// white → navy interpolation, the destination dot and its water-drop pulse,
/// the startup barrier, skip-with-and-without-a-destination, reduced motion,
/// and the preserved destination/layout guarantees.
void main() {
  final fixture = OfflineReliabilityFixture();
  setUpAll(fixture.initialize);

  // ── 1. beat map and the single clock ─────────────────────────────────────

  group('1 beat map and the single clock', () {
    test('the Page 3 beats are ordered and contained by the clock', () {
      const beats = <double>[
        FieldSyncCinematicTimeline.seamSeconds,
        FieldSyncCinematicTimeline.holdEndSeconds,
        FieldSyncCinematicTimeline.departureStartSeconds,
        FieldSyncCinematicTimeline.mountStartSeconds,
        FieldSyncCinematicTimeline.departureEndSeconds,
        FieldSyncCinematicTimeline.mountEndSeconds,
        FieldSyncCinematicTimeline.travelEndSeconds,
        FieldSyncCinematicTimeline.loginDotStartSeconds,
        FieldSyncCinematicTimeline.loginPulseStartSeconds,
        FieldSyncCinematicTimeline.loginLineFadeStartSeconds,
        FieldSyncCinematicTimeline.loginDotPopEndSeconds,
        FieldSyncCinematicTimeline.loginDotFadeStartSeconds,
        FieldSyncCinematicTimeline.loginLineFadeEndSeconds,
        FieldSyncCinematicTimeline.loginDotFadeEndSeconds,
        FieldSyncCinematicTimeline.brandRevealStartSeconds,
        FieldSyncCinematicTimeline.brandRevealEndSeconds,
        FieldSyncCinematicTimeline.barrierReleaseSeconds,
        FieldSyncCinematicTimeline.totalSeconds,
      ];
      for (var i = 0; i + 1 < beats.length; i++) {
        expect(
          beats[i],
          lessThanOrEqualTo(beats[i + 1]),
          reason: 'beat $i (${beats[i]}) must not follow beat ${i + 1} '
              '(${beats[i + 1]})',
        );
      }
      // The login mounts in-stack while the exit is still leaving the frame —
      // by design, so there is never a frame without either page.
      expect(
        FieldSyncCinematicTimeline.mountStartSeconds,
        lessThan(FieldSyncCinematicTimeline.departureEndSeconds),
      );
      // The reveal settles inside the clock; the clock releases the barrier
      // exactly when the logo is complete.
      expect(
        FieldSyncCinematicTimeline.brandRevealEndSeconds,
        lessThan(FieldSyncCinematicTimeline.totalSeconds),
      );
      expect(
        FieldSyncCinematicTimeline.barrierReleaseSeconds,
        FieldSyncCinematicTimeline.totalSeconds,
      );
      expect(FieldSyncCinematicTimeline.brandRevealEndSeconds,
          lessThanOrEqualTo(FieldSyncCinematicTimeline.barrierReleaseSeconds));
    });

    test('chrome steps in at the seam, never during page 1', () {
      expect(
        FieldSyncCinematicTimeline.chromeFadeStartSeconds,
        FieldSyncCinematicTimeline.seamSeconds,
      );
      expect(
        FieldSyncCinematicTimeline.chromeFadeEndSeconds,
        greaterThan(FieldSyncCinematicTimeline.chromeFadeStartSeconds),
      );
      expect(
        FieldSyncCinematicTimeline.chromeFadeEndSeconds,
        lessThan(FieldSyncCinematicTimeline.holdEndSeconds),
      );
    });
  });

  // ── 2. the seam splice lands on the measured box ─────────────────────────

  group('2 the seam splice lands exactly on the measured box', () {
    const canvas = Size(390, 844);
    const box = Rect.fromLTWH(54.6, 210, 280.8, 353.0);
    const seam = FieldSyncCinematicTimeline.seamSeconds;

    test('full canvas before the arrival hold, the box itself from the seam',
        () {
      expect(
        FieldSyncCinematicScenePainter.spliceRectAt(0, canvas, box),
        Offset.zero & canvas,
      );
      expect(
        FieldSyncCinematicScenePainter.spliceRectAt(
          FieldSyncCinematicTimeline.arriveSeconds,
          canvas,
          box,
        ),
        Offset.zero & canvas,
      );
      expect(
        FieldSyncCinematicScenePainter.spliceRectAt(seam, canvas, box),
        box,
      );
      expect(
        FieldSyncCinematicScenePainter.spliceRectAt(
          FieldSyncCinematicTimeline.totalSeconds,
          canvas,
          box,
        ),
        box,
      );
      // No measured box: the standalone full-screen behavior (T4) is intact.
      expect(
        FieldSyncCinematicScenePainter.spliceRectAt(
          FieldSyncCinematicTimeline.totalSeconds,
          canvas,
          null,
        ),
        Offset.zero & canvas,
      );
      // Strictly between the hold and the seam the rect genuinely travels.
      final mid = FieldSyncCinematicScenePainter.spliceRectAt(5.5, canvas, box);
      expect(mid.left, greaterThan(0));
      expect(mid.left, lessThan(box.left));
      expect(mid.width, lessThan(canvas.width));
    });

    test('at the seam the scene frames the box exactly as the entrance does',
        () {
      final splice = FieldSyncCinematicScenePainter.spliceRectAt(
        seam,
        canvas,
        box,
      );
      final scene = FieldSyncCinematicScenePainter.cameraAt(seam);
      final entrance = FieldSyncEntrancePainter.cameraAt(
        FieldSyncEntranceTimeline.handoffSeconds,
      );

      // The scene's own framing of the splice rect — viewport fit and screen
      // anchor, in canvas space …
      final qScene = FieldSyncEntranceCamera.viewportFit(splice.size);
      final aScene =
          splice.topLeft +
          FieldSyncEntranceCamera.screenAnchorOf(splice.size, scene.anchorT);
      // … and the approved entrance painter's framing of its own box.
      final qBox = FieldSyncEntranceCamera.viewportFit(box.size);
      final aBox = FieldSyncEntranceCamera.screenAnchorOf(
        box.size,
        entrance.anchorT,
      );

      expect(splice.size, box.size);
      expect(scene.zoom, closeTo(entrance.zoom, 1e-12));
      expect(scene.centre, entrance.centre);
      expect(qScene * scene.zoom, closeTo(qBox * entrance.zoom, 1e-12));
      // The entrance painter's canvas *is* the box, so its anchor is
      // box-local; the scene paints in canvas space and must place the same
      // point at the box's own top-left.
      expect(aScene, box.topLeft + aBox);
    });
  });

  // ── 3. ownership after the seam: one route, no doubles ───────────────────

  group('3 ownership after the seam: one route, no doubles', () {
    test('splice mode paints through every beat without exception', () {
      const canvas = Size(390, 844);
      const box = Rect.fromLTWH(54.6, 210, 280.8, 353.0);
      final boundary = <double>{
        0,
        FieldSyncCinematicTimeline.arriveSeconds,
        FieldSyncCinematicTimeline.seamSeconds,
        6.0,
        FieldSyncCinematicTimeline.routeGhostOutEndSeconds,
        7.5,
        FieldSyncCinematicTimeline.holdEndSeconds,
        FieldSyncCinematicTimeline.departureEndSeconds,
        FieldSyncCinematicTimeline.totalSeconds,
      };
      for (final t in boundary) {
        final recorder = ui.PictureRecorder();
        final pictureCanvas = Canvas(recorder);
        FieldSyncCinematicScenePainter(
          time: AlwaysStoppedAnimation<double>(t),
          boxRect: () => box,
        ).paint(pictureCanvas, canvas);
        // The default (no box) mode keeps T4's contract at the same beats.
        FieldSyncCinematicScenePainter(
          time: AlwaysStoppedAnimation<double>(t),
        ).paint(pictureCanvas, canvas);
        recorder.endRecording().dispose();
      }
    });

    test('the painter notices a changed measured box (splice rect source)', () {
      final a = FieldSyncCinematicScenePainter(
        time: const AlwaysStoppedAnimation<double>(0),
        boxRect: () => const Rect.fromLTWH(0, 0, 10, 10),
      );
      final b = FieldSyncCinematicScenePainter(
        time: const AlwaysStoppedAnimation<double>(0),
        boxRect: () => const Rect.fromLTWH(0, 0, 10, 10),
      );
      final c = FieldSyncCinematicScenePainter(
        time: const AlwaysStoppedAnimation<double>(0),
        boxRect: () => const Rect.fromLTWH(0, 0, 20, 20),
      );
      expect(a.boxRect, isNotNull);
      expect(
        FieldSyncCinematicScenePainter(
          time: const AlwaysStoppedAnimation<double>(0),
        ).boxRect,
        isNull,
      );
      expect(c.shouldRepaint(a), isTrue);
      // Closures are fresh per build, so a rebuilt painter repaints once —
      // the measured rect itself is read every paint, never cached.
      expect(b.shouldRepaint(a), isTrue);
    });
  });

  // ── 4. the departure camera follows the tip ──────────────────────────────

  group('4 the departure camera follows the tip and releases off the edge', () {
    const box = Size(280.8, 353.0);
    const start = FieldSyncCinematicTimeline.departureStartSeconds;
    const end = FieldSyncCinematicTimeline.departureEndSeconds;

    test('exactly identity at the hold end, then push, follow, zoom-out', () {
      expect(FieldSyncDepartureCamera.zoomAt(start), 1.0);
      expect(FieldSyncDepartureCamera.matrixAt(start, box), Matrix4.identity());
      expect(FieldSyncDepartureCamera.zoomAt(0), 1.0);
      expect(FieldSyncDepartureCamera.zoomAt(13.35), closeTo(1.0, 1e-12));

      var previous = 1.0;
      for (var t = start; t <= 10.20; t += 0.05) {
        final z = FieldSyncDepartureCamera.zoomAt(t);
        expect(z, greaterThanOrEqualTo(previous - 1e-12));
        previous = z;
      }
      expect(FieldSyncDepartureCamera.zoomAt(10.20), closeTo(1.28, 1e-9));

      previous = 1.28;
      for (var t = 10.25; t <= end; t += 0.05) {
        final z = FieldSyncDepartureCamera.zoomAt(t);
        expect(z, lessThanOrEqualTo(previous + 1e-12));
        previous = z;
      }
      expect(FieldSyncDepartureCamera.zoomAt(end), closeTo(1.0, 1e-9));
      expect(FieldSyncDepartureCamera.matrixAt(10.68, box), Matrix4.identity());
    });

    test('the tip is the one point the departure never moves', () {
      for (final t in <double>[9.90, 10.30, 10.55, 10.90, 11.05]) {
        final tip = FieldSyncDepartureCamera.tipLocalAt(t, box);
        final moved = MatrixUtils.transformPoint(
          FieldSyncDepartureCamera.matrixAt(t, box),
          tip,
        );
        expect(moved.dx, closeTo(tip.dx, 1e-9));
        expect(moved.dy, closeTo(tip.dy, 1e-9));
      }
    });
  });

  // ── 5. the departure tail continues the official route ───────────────────

  group('5 the departure tail continues the official route exactly', () {
    test('it starts at the route\'s own end point, with C1 contact', () {
      final route = FieldSyncLogoGeometry.route.computeMetrics().first;
      final routeEnd = route.getTangentForOffset(route.length)!.position;
      final before = route.getTangentForOffset(route.length - 0.5)!.position;
      final routeDir = math.atan2(
        routeEnd.dy - before.dy,
        routeEnd.dx - before.dx,
      );

      final tail = FieldSyncDepartureRoutePainter.tailPath.computeMetrics().first;
      final start = tail.getTangentForOffset(0)!.position;
      expect((start - routeEnd).distance, lessThan(0.01));

      final a = tail.getTangentForOffset(0)!.position;
      final b = tail.getTangentForOffset(0.5)!.position;
      final tailDir = math.atan2(b.dy - a.dy, b.dx - a.dx);
      // Tangent-continuous by construction; the tolerance absorbs the chord
      // baseline (0.5 units) across the route's own end curvature (~0.9°)
      // and PathMetric's flattening, so a real direction break would fail.
      expect(math.cos(tailDir - routeDir), greaterThan(0.9995));
    });

    test('the tail holds the site height while continuing right', () {
      final tail = FieldSyncDepartureRoutePainter.tailPath.computeMetrics().first;
      final start = tail.getTangentForOffset(0)!.position;
      var previousX = start.dx;
      for (var d = 8.0; d <= tail.length; d += 8) {
        final point = tail.getTangentForOffset(d)!.position;
        expect(point.dx, greaterThan(previousX));
        expect(point.dy, closeTo(start.dy, 2),
            reason: 'the green departure goes right, not up into a crest');
        previousX = point.dx;
      }
    });

    test('the tip is monotone and clamped to the authored window', () {
      expect(FieldSyncDepartureRoutePainter.progressAt(0), 0.0);
      expect(
        FieldSyncDepartureRoutePainter.progressAt(
          FieldSyncCinematicTimeline.holdEndSeconds,
        ),
        0.0,
      );
      expect(FieldSyncDepartureRoutePainter.progressAt(13.35), 1.0);
      expect(
        FieldSyncDepartureRoutePainter.progressAt(
          FieldSyncCinematicTimeline.departureEndSeconds,
        ),
        1.0,
      );

      final route = FieldSyncLogoGeometry.route.computeMetrics().first;
      final routeEnd = route.getTangentForOffset(route.length)!.position;
      final tipAtHold = FieldSyncDepartureRoutePainter.tipWorldAt(
        FieldSyncCinematicTimeline.holdEndSeconds,
      );
      expect((tipAtHold - routeEnd).distance, lessThan(0.01));

      var previous = -1.0;
      for (var t = 9.85; t <= 11.05; t += 0.02) {
        final p = FieldSyncDepartureRoutePainter.progressAt(t);
        expect(p, greaterThanOrEqualTo(previous - 1e-12));
        previous = p;
      }
    });

    testWidgets('the exit is really painted: tip in frame, tail off the edge',
        (tester) async {
      await tester.runAsync(() async {
        const screen = Size(390, 844);
        const box = Rect.fromLTWH(54.6, 210, 280.8, 353.0);

        Future<ByteData> frameAt(double t) async {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          canvas.drawRect(Offset.zero & screen, Paint()..color = Colors.black);
          canvas.save();
          canvas.translate(box.left, box.top);
          FieldSyncDepartureRoutePainter(
            time: AlwaysStoppedAnimation<double>(t),
          ).paint(canvas, box.size);
          canvas.restore();
          final image = await recorder.endRecording().toImage(
            screen.width.toInt(),
            screen.height.toInt(),
          );
          final data = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          image.dispose();
          return data;
        }

        bool whiteNear(ByteData data, Offset p, {int radius = 6}) {
          final w = screen.width.toInt();
          for (var y = (p.dy - radius).round();
              y <= (p.dy + radius).round();
              y++) {
            for (var x = (p.dx - radius).round();
                x <= (p.dx + radius).round();
                x++) {
              if (x < 0 || y < 0 || x >= w || y >= screen.height) continue;
              final i = 4 * (y * w + x);
              if (data.getUint8(i) > 200 &&
                  data.getUint8(i + 1) > 200 &&
                  data.getUint8(i + 2) > 200) {
                return true;
              }
            }
          }
          return false;
        }

        // Mid-flight: the puck rides the tip the camera follows — in the
        // frame the eye sees, not in viewBox coordinates far off it.
        const mid = 10.45;
        final midData = await frameAt(mid);
        expect(
          whiteNear(midData, box.topLeft + FieldSyncDepartureCamera.tipLocalAt(mid, box.size)),
          isTrue,
          reason: 'the departing puck must render on the followed tip',
        );

        // The last beat of the exit: the tail has crossed the right edge.
        final lateData = await frameAt(11.00);
        var crossed = false;
        final w = screen.width.toInt();
        for (var y = 0; y < screen.height.toInt() && !crossed; y++) {
          for (var x = w - 10; x < w; x++) {
            final i = 4 * (y * w + x);
            if (lateData.getUint8(i) > 200 &&
                lateData.getUint8(i + 1) > 200 &&
                lateData.getUint8(i + 2) > 200) {
              crossed = true;
              break;
            }
          }
        }
        expect(crossed, isTrue,
            reason: 'the route must leave through the right edge');
      });
    });
  });

  // ── 6. the re-entry arrives at the measured brand rect ───────────────────

  group('6 the re-entry arrives at the measured brand rect', () {
    const brand = Rect.fromLTWH(28, 100, 44.5, 56.0);
    const canvas = Size(390, 844);

    test('it starts off the right edge and ends exactly on the target', () {
      final metric = FieldSyncLoginRoutePainter.pathFor(
        brand,
        canvas,
      ).computeMetrics().first;
      expect(
        metric.getTangentForOffset(0)!.position.dx,
        greaterThan(canvas.width),
      );
      final end = metric.getTangentForOffset(metric.length)!.position;
      final target = FieldSyncLoginRoutePainter.targetFor(brand);
      expect((end - target).distance, lessThan(0.01));
      // And the tip is on screen before it arrives.
      final mid = metric.getTangentForOffset(metric.length * 0.5)!.position;
      expect(mid.dx, lessThan(canvas.width));
      expect(mid.dx, greaterThan(0));
    });

    test('the target is the artwork\'s own site-dot fraction, on both axes',
        () {
      final target = FieldSyncLoginRoutePainter.targetFor(brand);
      expect(
        target.dx,
        closeTo(
          brand.left +
              brand.width *
                  (FieldSyncLogoGeometry.siteDotX -
                      FieldSyncLogoGeometry.viewBoxLeft) /
                  FieldSyncLogoGeometry.viewBoxWidth,
          1e-9,
        ),
      );
      expect(
        target.dy,
        closeTo(
          brand.top +
              brand.height *
                  (FieldSyncLogoGeometry.siteDotY -
                      FieldSyncLogoGeometry.viewBoxTop) /
                  FieldSyncLogoGeometry.viewBoxHeight,
          1e-9,
        ),
      );
      // Inside the mark: the pulse dissolves onto the logo's own dot, never
      // beside it.
      expect(target.dx, greaterThan(brand.left));
      expect(target.dx, lessThan(brand.right));
      expect(target.dy, greaterThan(brand.top));
      expect(target.dy, lessThan(brand.bottom));
    });

    test('progress is zero before the mount completes, one at travel end', () {
      expect(FieldSyncLoginRoutePainter.progressAt(0), 0.0);
      expect(
        FieldSyncLoginRoutePainter.progressAt(
          FieldSyncCinematicTimeline.mountEndSeconds,
        ),
        0.0,
      );
      expect(
        FieldSyncLoginRoutePainter.progressAt(
          FieldSyncCinematicTimeline.travelEndSeconds,
        ),
        1.0,
      );
      expect(FieldSyncLoginRoutePainter.progressAt(13.35), 1.0);
    });

    testWidgets('the re-entry is really painted: navy stroke, one red dot',
        (tester) async {
      await tester.runAsync(() async {
        const canvas = Size(390, 844);
        const brand = Rect.fromLTWH(28, 36, 88, 56);
        final recorder = ui.PictureRecorder();
        final painted = Canvas(recorder);
        painted.drawRect(Offset.zero & canvas, Paint()..color = Colors.white);
        FieldSyncLoginRoutePainter(
          time: const AlwaysStoppedAnimation<double>(12.30),
          brandRect: () => brand,
        ).paint(painted, canvas);
        final image = await recorder.endRecording().toImage(
          canvas.width.toInt(),
          canvas.height.toInt(),
        );
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        image.dispose();

        bool anyNear(
          Offset p,
          bool Function(int r, int g, int b) test, {
          int radius = 4,
        }) {
          final w = canvas.width.toInt();
          for (var y = (p.dy - radius).round();
              y <= (p.dy + radius).round();
              y++) {
            for (var x = (p.dx - radius).round();
                x <= (p.dx + radius).round();
                x++) {
              if (x < 0 || y < 0 || x >= w || y >= canvas.height) continue;
              final i = 4 * (y * w + x);
              if (test(
                data.getUint8(i),
                data.getUint8(i + 1),
                data.getUint8(i + 2),
              )) {
                return true;
              }
            }
          }
          return false;
        }

        final target = FieldSyncLoginRoutePainter.targetFor(brand);
        expect(
          anyNear(target, (r, g, b) => r > 170 && g < 130 && b < 130),
          isTrue,
          reason: 'the single destination dot is red, on the target',
        );

        // Somewhere along the arrived line the official navy is on screen.
        final metric = FieldSyncLoginRoutePainter.pathFor(
          brand,
          canvas,
        ).computeMetrics().first;
        final navySamples = <Offset>[
          for (final f in const [0.35, 0.5, 0.65, 0.8])
            metric.getTangentForOffset(metric.length * f)!.position,
        ];
        expect(
          navySamples.any(
            (p) => anyNear(p, (r, g, b) => r < 110 && b > g && g < 140),
          ),
          isTrue,
          reason: 'the arrived route is the official navy on the light page',
        );
      });
    });
  });

  // ── 7. the stroke colour interpolates white → navy ───────────────────────

  group('7 the stroke colour interpolates white to navy on the light page', () {
    const navy = Color(0xFF102D50);

    test('white through the pages, navy once the re-entry lands', () {
      expect(FieldSyncLoginRoutePainter.strokeColourAt(0), Colors.white);
      expect(FieldSyncLoginRoutePainter.strokeColourAt(5.8), Colors.white);
      expect(
        FieldSyncLoginRoutePainter.strokeColourAt(
          FieldSyncCinematicTimeline.mountStartSeconds,
        ),
        Colors.white,
      );
      expect(
        FieldSyncLoginRoutePainter.strokeColourAt(
          FieldSyncCinematicTimeline.loginStrokeColourEndSeconds,
        ),
        navy,
      );
      expect(FieldSyncLoginRoutePainter.strokeColourAt(13.35), navy);
    });

    test('the interpolation is smooth: never a hard cut', () {
      var previous = FieldSyncLoginRoutePainter.strokeColourAt(11.0);
      var maxStep = 0.0;
      for (var t = 11.0; t <= 11.75; t += 0.005) {
        final c = FieldSyncLoginRoutePainter.strokeColourAt(t);
        // White (1,1,1) → navy: every channel only descends.
        expect(c.r, lessThanOrEqualTo(previous.r + 1e-9));
        expect(c.g, lessThanOrEqualTo(previous.g + 1e-9));
        expect(c.b, lessThanOrEqualTo(previous.b + 1e-9));
        maxStep = math.max(maxStep, (previous.r - c.r).abs());
        previous = c;
      }
      // One 5 ms step moves at most ~1.3% of a channel (the eased window is
      // 0.6 s wide): a dissolve, not a cut — a hard swap would jump ~94%.
      expect(maxStep, lessThan(0.02));
    });
  });

  // ── 8. one destination dot, shared pulse DNA ─────────────────────────────

  group('8 one destination dot and the shared pulse DNA', () {
    test('the pulse retains the approved rings but finishes before brand reveal', () {
      expect(
        FieldSyncCinematicTimeline.loginPulseGapSeconds,
        FieldSyncCinematicTimeline.pulseGapSeconds,
      );
      expect(FieldSyncCinematicTimeline.loginPulseDurationSeconds,
          allOf(greaterThan(0), lessThan(FieldSyncCinematicTimeline.pulseDurationSeconds)));
      expect(FieldSyncCinematicTimeline.loginPulseStartSeconds +
          FieldSyncCinematicTimeline.loginPulseGapSeconds +
          FieldSyncCinematicTimeline.loginPulseDurationSeconds,
          lessThanOrEqualTo(FieldSyncCinematicTimeline.brandRevealStartSeconds));
      // The dot pops only once the route has actually arrived …
      expect(
        FieldSyncCinematicTimeline.loginDotStartSeconds,
        FieldSyncCinematicTimeline.travelEndSeconds,
      );
      // … the ring leaves from the dot, and both dissolve exactly as the
      // official logo takes their place.
      expect(
        FieldSyncCinematicTimeline.loginPulseStartSeconds,
        greaterThanOrEqualTo(FieldSyncCinematicTimeline.loginDotStartSeconds),
      );
      expect(
        FieldSyncCinematicTimeline.loginDotFadeEndSeconds,
        lessThanOrEqualTo(FieldSyncCinematicTimeline.brandRevealEndSeconds),
      );
      // The login's own scale is a destination marker, not the artwork's dot.
      expect(FieldSyncLoginRoutePainter.dotRadius, lessThan(8.2));
      expect(FieldSyncLoginRoutePainter.rippleGrowth, greaterThan(0));
    });

    test('both route layers paint every boundary frame without exception', () {
      const brand = Rect.fromLTWH(28, 100, 44.5, 56.0);
      const canvas = Size(390, 844);
      final boundaries = <double>{
        0,
        FieldSyncCinematicTimeline.holdEndSeconds,
        9.90,
        10.55,
        FieldSyncCinematicTimeline.departureEndSeconds,
        FieldSyncCinematicTimeline.mountStartSeconds,
        FieldSyncCinematicTimeline.mountEndSeconds,
        FieldSyncCinematicTimeline.travelEndSeconds,
        FieldSyncCinematicTimeline.loginDotPopEndSeconds,
        FieldSyncCinematicTimeline.loginPulseStartSeconds,
        FieldSyncCinematicTimeline.loginLineFadeStartSeconds,
        FieldSyncCinematicTimeline.loginDotFadeStartSeconds,
        FieldSyncCinematicTimeline.brandRevealStartSeconds,
        FieldSyncCinematicTimeline.brandRevealEndSeconds,
        FieldSyncCinematicTimeline.totalSeconds,
      };
      for (final t in boundaries) {
        final recorder = ui.PictureRecorder();
        final pictureCanvas = Canvas(recorder);
        FieldSyncDepartureRoutePainter(
          time: AlwaysStoppedAnimation<double>(t),
        ).paint(pictureCanvas, canvas);
        FieldSyncLoginRoutePainter(
          time: AlwaysStoppedAnimation<double>(t),
          brandRect: () => brand,
        ).paint(pictureCanvas, canvas);
        // An unmeasurable logo rect draws nothing, never throws.
        FieldSyncLoginRoutePainter(
          time: AlwaysStoppedAnimation<double>(t),
          brandRect: () => null,
        ).paint(pictureCanvas, canvas);
        recorder.endRecording().dispose();
      }
    });
  });

  // ── widget-level coverage of the launch itself ───────────────────────────

  Future<void> advance(WidgetTester tester, Duration elapsed) async {
    await tester.pump(elapsed);
    await fixture.flush(tester);
  }

  Future<void> loggedOut() async {
    await SecurePrefsService.setSoftLoggedOut(true);
    await AuthService.loadSoftLogoutState();
  }

  double entranceDriver(WidgetTester tester) => tester
      .widget<FieldSyncEntranceAnimation>(
        find.byType(FieldSyncEntranceAnimation),
      )
      .driver!
      .value;

  void fixtureGroup(String name, void Function() body) {
    group(name, () {
      setUp(() {
        AppBootstrap.resetForTests();
      });
      setUp(fixture.reset);
      tearDown(() {
        AppBootstrap.resetForTests();
      });
      tearDown(fixture.closeCase);
      body();
    });
  }

  // ── 3 (widget side). the entrance is gated until the seam ────────────────

  fixtureGroup('3 ownership after the seam (host gating)', () {
    fixture.widgetTest(
        'the approved entrance stays invisible until the seam: one page at a time',
        (tester) async {
      await fixture.mount(tester, const SplashScreen());

      List<Opacity> entranceOpacities() => tester
          .widgetList<Opacity>(
            find.ancestor(
              of: find.byType(FieldSyncEntranceAnimation),
              matching: find.byType(Opacity),
            ),
          )
          .toList();

      await advance(tester, const Duration(seconds: 2));
      expect(
        entranceOpacities().any((o) => o.opacity == 0.0),
        isTrue,
        reason: 'Page 1 owns the frame before the seam',
      );

      await advance(tester, const Duration(seconds: 4));
      expect(
        entranceOpacities().any((o) => o.opacity == 0.0),
        isFalse,
        reason: 'Page 2 owns the frame from the seam',
      );
      expect(
        entranceOpacities().any((o) => o.opacity == 1.0),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });

    fixture.widgetTest(
        'the depicted journey leaves the right edge before it re-enters, at the measured box',
        (tester) async {
      await loggedOut();
      await fixture.mount(tester, const SplashScreen());
      await advance(tester, const Duration(seconds: 3));

      final box = tester.getRect(find.byType(FieldSyncEntranceAnimation));
      final screenWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      double tipScreenX(double t) =>
          box.left + FieldSyncDepartureCamera.tipLocalAt(t, box.size).dx;

      expect(
        tipScreenX(FieldSyncCinematicTimeline.holdEndSeconds),
        lessThan(screenWidth),
        reason: 'the route is still on the page when the hold ends',
      );
      expect(
        tipScreenX(FieldSyncCinematicTimeline.departureEndSeconds),
        greaterThan(screenWidth),
        reason: 'the exit completes off the edge as its own beat ends',
      );

      var crossing = FieldSyncCinematicTimeline.departureEndSeconds;
      for (var t = FieldSyncCinematicTimeline.holdEndSeconds;
          t <= FieldSyncCinematicTimeline.departureEndSeconds;
          t += 0.005) {
        if (tipScreenX(t) > screenWidth) {
          crossing = t;
          break;
        }
      }
      expect(
        crossing,
        lessThanOrEqualTo(FieldSyncCinematicTimeline.mountEndSeconds),
        reason: 'only an off-screen route may precede the re-entry',
      );

      // The logo box and the splash chrome do not move while the login mounts
      // above them: no layout shift.
      final cardBefore = tester.getRect(find.byKey(const ValueKey('splash-status')));
      final boxSizeBefore = tester.getSize(find.byType(FieldSyncEntranceAnimation));
      await advance(tester, const Duration(seconds: 9));
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(
        tester.getSize(find.byType(FieldSyncEntranceAnimation)),
        boxSizeBefore,
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('splash-status'))),
        cardBefore,
      );
      expect(tester.takeException(), isNull);
    });
  });

  // ── 9. the barrier consumes taps until the reveal completes ──────────────

  fixtureGroup('9 the startup barrier', () {
    fixture.widgetTest(
        'during the reveal a tap is a skip request, never a button press',
        (tester) async {
      await loggedOut();
      await fixture.mount(tester, const SplashScreen());
      await advance(tester, const Duration(seconds: 3));
      await advance(tester, const Duration(milliseconds: 8300)); // 11.3 s

      expect(find.byType(LoginScreen), findsOneWidget);
      final signIn = find.widgetWithText(ElevatedButton, 'Sign in');
      expect(signIn, findsOneWidget);
      expect(find.byKey(const ValueKey('splash-skip')), findsOneWidget);

      // Tap exactly on the sign-in button: the barrier is above it.
      await tester.tapAt(tester.getCenter(signIn));
      await fixture.flush(tester);

      // Consumed as the skip: the login never started signing in, the launch
      // finished on the spot and the barrier released with it.
      expect(find.text('Signing in…'), findsNothing);
      expect(find.byKey(const ValueKey('splash-skip')), findsNothing);
      expect(
        tester
            .widget<LoginScreen>(find.byType(LoginScreen))
            .brandReveal!
            .value,
        1.0,
      );
      expect(
        tester.widget<ElevatedButton>(signIn).onPressed,
        isNotNull,
        reason: 'once released the login is genuinely interactive',
      );
      expect(entranceDriver(tester), FieldSyncEntranceTimeline.total);
      expect(tester.takeException(), isNull);
    });
  });

  // ── 10. skip with a known destination ────────────────────────────────────

  fixtureGroup('10 skip with a known destination', () {
    fixture.widgetTest(
        'login: finishes on the spot — revealed logo, no replay, no doubt',
        (tester) async {
      await loggedOut();
      await fixture.mount(tester, const SplashScreen());
      await advance(tester, const Duration(seconds: 3, milliseconds: 200));

      await tester.tap(find.byKey(const ValueKey('splash-skip')));
      await fixture.flush(tester);

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(
        tester
            .widget<LoginScreen>(find.byType(LoginScreen))
            .brandReveal!
            .value,
        1.0,
      );
      expect(find.byKey(const ValueKey('splash-skip')), findsNothing);
      expect(find.byType(MainShellScreen), findsNothing);
      // The journey is at its settled end, not mid-flight.
      expect(entranceDriver(tester), FieldSyncEntranceTimeline.total);
      expect(tester.takeException(), isNull);
    });

    fixture.widgetTest(
        'home: hands over at once, with the login never built', (tester) async {
      await fixture.mount(tester, const SplashScreen());
      await advance(tester, const Duration(seconds: 3, milliseconds: 200));

      await tester.tap(find.byKey(const ValueKey('splash-skip')));
      await fixture.flush(tester);

      expect(find.byType(MainShellScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  // ── 11. skip with a pending destination ──────────────────────────────────

  fixtureGroup('11 skip with a pending destination', () {
    fixture.widgetTest(
        'parks on the settled page 2, then goes directly to the real destination',
        (tester) async {
      final gate = Completer<void>();
      AppBootstrap.initialize(steps: [
        (name: 'held-open', run: () => gate.future),
      ]);

      await fixture.mount(tester, const SplashScreen());
      await advance(tester, const Duration(seconds: 2, milliseconds: 500));
      await tester.tap(find.byKey(const ValueKey('splash-skip')));
      await fixture.flush(tester);

      // The settled Page 2 composition: the completed logo, exactly where the
      // approved timeline would hold it — nothing mid-flight. (The parked
      // clock is normalized, so compare within a hair of the exact beat.)
      expect(
        entranceDriver(tester),
        closeTo(FieldSyncEntranceTimeline.total, 1e-6),
      );
      expect(find.byType(MainShellScreen), findsNothing);
      expect(find.byType(LoginScreen), findsNothing);

      // Waiting cannot move it: the gate is not skippable.
      await advance(tester, const Duration(seconds: 4));
      expect(
        entranceDriver(tester),
        closeTo(FieldSyncEntranceTimeline.total, 1e-6),
      );
      expect(find.byType(MainShellScreen), findsNothing);
      expect(find.byType(LoginScreen), findsNothing);

      // The real decision lands: straight to the destination, no replay.
      gate.complete();
      await fixture.flush(tester);
      expect(find.byType(MainShellScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  // ── 12. reduced motion ───────────────────────────────────────────────────

  fixtureGroup('12 reduced motion', () {
    fixture.widgetTest(
        'settled composition from the first frame, then the real destination',
        (tester) async {
      await loggedOut();
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      await fixture.mount(tester, const SplashScreen());
      await advance(tester, const Duration(milliseconds: 500));

      // Already the settled Page 2 frame — no route, no search, no replay.
      expect(
        entranceDriver(tester),
        closeTo(FieldSyncEntranceTimeline.total, 1e-6),
      );
      // The decision is not in yet, so the destination is not invented.
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.byType(MainShellScreen), findsNothing);

      await advance(tester, const Duration(seconds: 3));
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(
        tester
            .widget<LoginScreen>(find.byType(LoginScreen))
            .brandReveal!
            .value,
        1.0,
      );
      expect(find.byKey(const ValueKey('splash-skip')), findsNothing);
      expect(
        entranceDriver(tester),
        closeTo(FieldSyncEntranceTimeline.total, 1e-6),
      );
      expect(tester.takeException(), isNull);
    });
  });

  // ── 13. destinations and layout safety are preserved ─────────────────────

  fixtureGroup('13 destinations and layout safety', () {
    fixture.widgetTest(
        'failed init stays terminal — never login — and a skip cannot bypass it',
        (tester) async {
      AppBootstrap.initialize(steps: [
        (name: 'boom',
            run: () async => throw Exception('isolated bootstrap failure')),
      ]);

      await fixture.mount(tester, const SplashScreen());
      await advance(tester, const Duration(seconds: 3, milliseconds: 500));
      expect(
        find.textContaining('Unable to initialize FieldSync.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('splash-skip')));
      await fixture.flush(tester);
      await advance(tester, const Duration(milliseconds: 500));

      expect(find.byType(SplashScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.byType(MainShellScreen), findsNothing);
      expect(
        find.textContaining('Unable to initialize FieldSync.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    fixture.widgetTest(
        'the hidden brand keeps its exact layout space: the form never moves',
        (tester) async {
      await fixture.mount(tester, const LoginScreen());
      final brandSize = tester.getSize(find.byType(FieldSyncBrand));
      final fieldRect = tester.getRect(find.byType(TextFormField).first);
      expect(
        tester
            .widgetList<Opacity>(
              find.ancestor(
                of: find.byType(FieldSyncBrand),
                matching: find.byType(Opacity),
              ),
            )
            .any((o) => o.opacity == 0.0),
        isFalse,
        reason: 'without a reveal the mark is simply visible',
      );

      await fixture.mount(
        tester,
        const LoginScreen(
          brandReveal: AlwaysStoppedAnimation<double>(0),
        ),
      );
      expect(tester.getSize(find.byType(FieldSyncBrand)), brandSize);
      expect(tester.getRect(find.byType(TextFormField).first), fieldRect);
      expect(
        tester
            .widgetList<Opacity>(
              find.ancestor(
                of: find.byType(FieldSyncBrand),
                matching: find.byType(Opacity),
              ),
            )
            .any((o) => o.opacity == 0.0),
        isTrue,
        reason: 'the reveal hides the mark, reserving its space',
      );
      expect(tester.takeException(), isNull);
    });

    fixture.widgetTest(
        'biometric-on-open still lands on the resume lock, never the shell directly',
        (tester) async {
      fixture.online = true;
      fixture.mode = 'success';
      await BiometricService.enroll();
      await SecurePrefsService.setBioConfirmed(true);
      fixture.online = false;
      fixture.mode = 'transport';
      fixture.requests.clear();

      await fixture.mount(tester, const SplashScreen());
      await advance(tester, const Duration(seconds: 3));
      await advance(tester, const Duration(milliseconds: 6900));

      expect(find.byType(AppResumeLockScreen), findsOneWidget);
      expect(find.byType(MainShellScreen), findsNothing);
      expect(find.byType(LoginScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
