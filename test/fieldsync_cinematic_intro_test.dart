import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/widgets/fieldsync_cinematic_intro.dart';
import 'package:imaps_fieldsync/core/widgets/fieldsync_entrance_animation.dart';
import 'package:imaps_fieldsync/core/widgets/fieldsync_logo_geometry.dart';

/// T4 — the three-page cinematic's timeline and Page 1 painter.
///
/// What these tests defend:
///  * the seam camera is the approved painter's own, not a look-alike;
///  * the authored search really turns (≥ 4 deliberate direction changes)
///    and really joins the artwork's own route (C1);
///  * discovery framing is camera-only — the dot never moves in world space;
///  * the stage is clock-driven and owns no time of its own.
void main() {
  const seam = FieldSyncCinematicTimeline.seamSeconds;
  final approvedSeam = FieldSyncEntrancePainter.cameraAt(
    FieldSyncEntranceTimeline.handoffSeconds,
  );

  double directionAt(ui.PathMetric metric, double from, double to) {
    final a = metric.getTangentForOffset(from.clamp(0, metric.length))!.position;
    final b = metric
        .getTangentForOffset(to.clamp(0, metric.length))!
        .position;
    return math.atan2(b.dy - a.dy, b.dx - a.dx);
  }

  Offset dotScreenPoint(double t, Size size) {
    final camera = FieldSyncCinematicScenePainter.cameraAt(t);
    const dot = Offset(
      FieldSyncLogoGeometry.siteDotX,
      FieldSyncLogoGeometry.siteDotY,
    );
    final q = FieldSyncEntranceCamera.viewportFit(size);
    return FieldSyncEntranceCamera.screenAnchorOf(size, camera.anchorT) +
        (dot - camera.centre) * (q * camera.zoom);
  }

  group('timeline', () {
    test('boundaries are ordered and the seam derives from the frozen API', () {
      expect(FieldSyncCinematicTimeline.totalSeconds, 13.35);
      expect(seam, closeTo(5.80, 1e-12));
      expect(
        seam,
        closeTo(
          FieldSyncCinematicTimeline.painterStartSeconds +
              FieldSyncEntranceTimeline.handoffSeconds,
          1e-12,
        ),
      );
      expect(
        FieldSyncCinematicTimeline.holdEndSeconds,
        closeTo(
          FieldSyncCinematicTimeline.painterStartSeconds +
              FieldSyncEntranceTimeline.total,
          1e-12,
        ),
      );
      expect(
        FieldSyncCinematicTimeline.departureStartSeconds,
        FieldSyncCinematicTimeline.holdEndSeconds,
      );

      const ordered = <double>[
        0.0,
        FieldSyncCinematicTimeline.settleEndSeconds,
        FieldSyncCinematicTimeline.enterEndSeconds,
        FieldSyncCinematicTimeline.searchEndSeconds,
        FieldSyncCinematicTimeline.arriveSeconds,
        FieldSyncCinematicTimeline.dotPopEndSeconds,
        seam,
        FieldSyncCinematicTimeline.formationEndSeconds,
        FieldSyncCinematicTimeline.holdEndSeconds,
        // The login starts mounting during the departure's tail — by design —
        // so it is ordered before the departure ends.
        FieldSyncCinematicTimeline.mountStartSeconds,
        FieldSyncCinematicTimeline.departureEndSeconds,
        FieldSyncCinematicTimeline.mountEndSeconds,
        FieldSyncCinematicTimeline.travelEndSeconds,
        FieldSyncCinematicTimeline.revealEndSeconds,
      ];
      for (var i = 0; i + 1 < ordered.length; i++) {
        expect(
          ordered[i],
          lessThan(ordered[i + 1]),
          reason: 'boundary $i is not ordered',
        );
      }
      expect(FieldSyncCinematicTimeline.revealEndSeconds, 13.35);
      expect(
        FieldSyncCinematicTimeline.mountStartSeconds,
        lessThan(FieldSyncCinematicTimeline.departureEndSeconds),
      );
    });

    test('arrival beats mirror the approved painter\'s windows (+3.65)', () {
      const shift = FieldSyncCinematicTimeline.painterStartSeconds;
      expect(FieldSyncCinematicTimeline.arriveSeconds - shift,
          closeTo(1.62, 1e-12));
      expect(FieldSyncCinematicTimeline.dotPopEndSeconds - shift,
          closeTo(1.90, 1e-12));
      expect(FieldSyncCinematicTimeline.bloomStartSeconds - shift,
          closeTo(1.50, 1e-12));
      expect(FieldSyncCinematicTimeline.bloomEndSeconds - shift,
          closeTo(2.10, 1e-12));
      expect(FieldSyncCinematicTimeline.arrowStartSeconds - shift,
          closeTo(1.55, 1e-12));
      expect(FieldSyncCinematicTimeline.arrowEndSeconds - shift,
          closeTo(1.85, 1e-12));
      expect(FieldSyncCinematicTimeline.puckOutStartSeconds - shift,
          closeTo(1.45, 1e-12));
      expect(FieldSyncCinematicTimeline.puckOutEndSeconds - shift,
          closeTo(1.62, 1e-12));
      expect(FieldSyncCinematicTimeline.pulseStartSeconds - shift,
          closeTo(1.66, 1e-12));
      expect(FieldSyncCinematicTimeline.pulseGapSeconds, 0.13);
      expect(FieldSyncCinematicTimeline.pulseDurationSeconds, 0.95);
      expect(
        FieldSyncCinematicTimeline.routeGhostOutEndSeconds - shift,
        closeTo(2.90, 1e-12),
      );

      // The pulse rings cross the seam with no phase reset: both layers' ring
      // windows describe the same phase at the handoff instant.
      for (final k in [0.0, 1.0]) {
        final boundsPhase =
            (seam - (FieldSyncCinematicTimeline.pulseStartSeconds + k * 0.13)) /
                FieldSyncCinematicTimeline.pulseDurationSeconds;
        final painterPhase =
            (FieldSyncEntranceTimeline.handoffSeconds - (1.66 + k * 0.13)) /
                0.95;
        expect(boundsPhase, closeTo(painterPhase, 1e-12));
      }
    });
  });

  group('camera seam', () {
    test('lands exactly on the approved painter\'s handoff camera', () {
      final at = FieldSyncCinematicScenePainter.cameraAt;
      final landed = at(seam);
      expect(landed.zoom, closeTo(approvedSeam.zoom, 1e-12));
      expect(landed.centre.dx, closeTo(approvedSeam.centre.dx, 1e-12));
      expect(landed.centre.dy, closeTo(approvedSeam.centre.dy, 1e-12));
      expect(landed.anchorT, closeTo(approvedSeam.anchorT, 1e-12));

      // The approved painter's runtime-exact seam state (single source of
      // truth — pinned by the T3 suite as well).
      expect(approvedSeam.zoom, closeTo(7.913361063033342, 1e-9));
      expect(approvedSeam.centre.dx, closeTo(679.7126147534698, 1e-9));
      expect(approvedSeam.centre.dy, closeTo(449.10553680621086, 1e-9));
      expect(approvedSeam.anchorT, closeTo(0.011730010062456131, 1e-9));
    });

    test('holds, never extrapolates: clamped at both ends of the clock', () {
      final at = FieldSyncCinematicScenePainter.cameraAt;
      for (final beyond in [seam, 9.0, FieldSyncCinematicTimeline.totalSeconds, 99.0]) {
        final camera = at(beyond);
        expect(camera.zoom, approvedSeam.zoom, reason: 't=$beyond');
        expect(camera.centre, approvedSeam.centre, reason: 't=$beyond');
        expect(camera.anchorT, approvedSeam.anchorT, reason: 't=$beyond');
      }
      final start = at(0);
      for (final before in [-8.0, -0.001, 0.0]) {
        expect(at(before).zoom, start.zoom, reason: 't=$before');
        expect(at(before).centre, start.centre, reason: 't=$before');
      }
      // Deterministic: a pure function of the clock.
      final a = at(4.2);
      final b = at(4.2);
      expect(a.zoom, b.zoom);
      expect(a.centre, b.centre);
      expect(a.anchorT, b.anchorT);
    });

    test('has no jump at the seam or at any internal beat', () {
      final at = FieldSyncCinematicScenePainter.cameraAt;
      final near = at(seam - 0.001);
      expect((near.zoom - approvedSeam.zoom).abs(), lessThan(0.01));
      expect((near.centre - approvedSeam.centre).distance, lessThan(0.5));
      expect((near.anchorT - approvedSeam.anchorT).abs(), lessThan(0.01));

      final half = at(seam - 0.05);
      expect((half.zoom - approvedSeam.zoom).abs(), lessThan(0.05));
      expect((half.centre - approvedSeam.centre).distance, lessThan(1.5));
      expect((half.anchorT - approvedSeam.anchorT).abs(), lessThan(0.05));

      // Dense sweep: no step anywhere is larger than plausible motion for a
      // 1/240 s frame, so no joint in the authored camera can pop.
      const dt = 1 / 240;
      var previous = at(0);
      for (var t = dt; t <= seam; t += dt) {
        final camera = at(t);
        expect(
          (camera.zoom - previous.zoom).abs(),
          lessThan(0.05),
          reason: 'zoom step at $t',
        );
        expect(
          (camera.centre - previous.centre).distance,
          lessThan(8.0),
          reason: 'centre step at $t',
        );
        expect(
          (camera.anchorT - previous.anchorT).abs(),
          lessThan(0.05),
          reason: 'anchor step at $t',
        );
        previous = camera;
      }
    });
  });

  group('search path', () {
    test('turns at least four times, then joins the route with C1 contact',
        () {
      final metric = FieldSyncCinematicScenePainter.searchPath
          .computeMetrics()
          .first;
      const samples = 240;
      var signChanges = 0;
      int? previousSign;
      var previousAngle = directionAt(metric, 0, 0.5);
      for (var i = 1; i <= samples; i++) {
        final offset = metric.length * i / samples;
        final angle = directionAt(metric, offset, offset + 0.5);
        var delta = angle - previousAngle;
        while (delta > math.pi) {
          delta -= 2 * math.pi;
        }
        while (delta < -math.pi) {
          delta += 2 * math.pi;
        }
        if (delta.abs() > 0.02) {
          final sign = delta > 0 ? 1 : -1;
          if (previousSign != null && sign != previousSign) signChanges++;
          previousSign = sign;
        }
        previousAngle = angle;
      }
      expect(
        signChanges,
        greaterThanOrEqualTo(4),
        reason: 'the search must contain at least four deliberate turns',
      );

      // C1 contact with the artwork's own route. The tolerance absorbs
      // PathMetric's arc-length sampling at its endpoint (~2e-4 viewBox
      // units here — four orders of magnitude below one pixel); the join is
      // exact by construction.
      final route = FieldSyncLogoGeometry.route.computeMetrics().first;
      final searchEnd = metric.getTangentForOffset(metric.length)!.position;
      final routeStart = route.getTangentForOffset(0)!.position;
      expect((searchEnd - routeStart).distance, lessThan(0.01));

      final searchHeading = directionAt(metric, metric.length - 0.5, metric.length);
      final routeHeading = directionAt(route, 0, 0.5);
      expect(
        math.cos(searchHeading - routeHeading),
        greaterThan(0.9999),
        reason: 'the join must be tangent-continuous with the route',
      );
      // Grounded sanity: the route leaves its start heading up-right toward
      // the site dot — the direction the search must therefore arrive on.
      expect(math.cos(routeHeading), greaterThan(0));
      expect(math.sin(routeHeading), lessThan(0));
    });

    test('the tip is monotone and clamped to the authored timeline', () {
      const tip = FieldSyncCinematicScenePainter.tipFractionAt;
      expect(tip(-2), 0);
      expect(tip(0), 0);
      expect(tip(FieldSyncCinematicTimeline.settleEndSeconds), 0);
      var previous = -1.0;
      for (var t = 0.0; t <= FieldSyncCinematicTimeline.totalSeconds; t += 0.05) {
        final u = tip(t);
        expect(u, greaterThanOrEqualTo(previous), reason: 'regressed at $t');
        expect(u, lessThanOrEqualTo(1.0), reason: 'ran past the graph at $t');
        previous = u;
      }
      expect(tip(FieldSyncCinematicTimeline.arriveSeconds), 1.0);
      expect(tip(FieldSyncCinematicTimeline.totalSeconds), 1.0);
    });
  });

  group('discovery framing', () {
    test('the camera — not the artwork — moves the dot to screen centre', () {
      for (final size in const [Size(390, 844), Size(360, 640)]) {
        final middle = Offset(size.width / 2, size.height / 2);

        // Early in the arrival the dot is still far outside the frame: the
        // search camera has not found it yet.
        expect(
          (dotScreenPoint(FieldSyncCinematicTimeline.searchEndSeconds, size) -
                  middle)
              .distance,
          greaterThan(200),
          reason: 'dot should still be off-frame at $size',
        );

        // Through the arrival hold it is framed dead centre.
        for (final t in [5.05, 5.16, 5.27]) {
          final screen = dotScreenPoint(t, size);
          expect((screen - middle).distance, lessThan(0.01), reason: 't=$t');
        }
      }

      // The dot's world position is the official geometry's, untouched.
      expect(FieldSyncLogoGeometry.siteDotX, 696);
      expect(FieldSyncLogoGeometry.siteDotY, 447);
    });

    test('the dot is settled at the seam — congruent with the painter', () {
      const alpha = FieldSyncCinematicScenePainter.redDotAlphaAt;
      const scale = FieldSyncCinematicScenePainter.redDotScaleAt;
      expect(alpha(5.27), 0);
      expect(alpha(seam), 1);
      expect(alpha(9.0), 1);
      expect(scale(seam), closeTo(1.0, 1e-12));
      expect(scale(FieldSyncCinematicTimeline.dotPopEndSeconds),
          closeTo(1.0, 1e-12));
    });
  });

  group('stage', () {
    test('paints valid frames at every boundary of the timeline', () {
      void paintAt(double t, Size size) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        FieldSyncCinematicScenePainter(
          time: AlwaysStoppedAnimation<double>(t),
        ).paint(canvas, size);
        recorder.endRecording().dispose();
      }

      for (final t in const [-5.0, 0.0, 0.4, 2.3, 4.5, 5.27, 5.8, 9.0, 13.35, 99.0]) {
        paintAt(t, const Size(390, 844));
        paintAt(t, const Size(360, 640));
      }
      // Degenerate canvases are a no-op, not a crash.
      paintAt(5.8, Size.zero);
      paintAt(0, const Size(0, 800));
    });

    testWidgets('owns no clock: host time only, nothing pending after unmount',
        (tester) async {
      final controller = AnimationController(
        vsync: tester,
        duration: const Duration(seconds: 6),
      );
      final clock = Tween<double>(
        begin: 0,
        end: FieldSyncCinematicTimeline.totalSeconds,
      ).animate(controller);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: FieldSyncCinematicStage(time: clock),
        ),
      );
      // Mounted but not started: the stage schedules nothing by itself.
      expect(tester.hasRunningAnimations, isFalse);
      expect(tester.binding.transientCallbackCount, 0);

      controller.forward();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('paints responsively across phone dimensions', (tester) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      for (final size in const [
        Size(320, 568),
        Size(360, 640),
        Size(390, 844),
        Size(430, 932),
        Size(844, 390),
      ]) {
        tester.view.physicalSize = size;
        for (final t in const [0.0, 2.35, 5.8, 13.35]) {
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: FieldSyncCinematicStage(
                time: AlwaysStoppedAnimation<double>(t),
              ),
            ),
          );
          expect(tester.takeException(), isNull, reason: '$size @ $t');
          expect(find.byType(FieldSyncCinematicStage), findsOneWidget);
        }
      }
    });
  });
}
