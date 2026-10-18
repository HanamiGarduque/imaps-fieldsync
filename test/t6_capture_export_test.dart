import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/layout/responsive_layout.dart';
import 'package:imaps_fieldsync/core/services/app_bootstrap.dart';
import 'package:imaps_fieldsync/core/services/auth_service.dart';
import 'package:imaps_fieldsync/core/widgets/fieldsync_cinematic_intro.dart';
import 'package:imaps_fieldsync/modules/auth_startup/screens/app_resume_lock_screen.dart';
import 'package:imaps_fieldsync/modules/auth_startup/screens/splash_screen.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/biometric_service.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/secure_prefs_service.dart';
import 'package:provider/provider.dart';

import 'support/offline_reliability_fixture.dart';

/// Actual Flutter render-tree evidence, never a device recording. No exports
/// unless T6_CAPTURE_DIR is explicitly set. Native auth is held at its mock
/// platform boundary; production verification and SensitiveScreen stay intact.
void main() {
  final destination = Platform.environment['T6_CAPTURE_DIR'];
  if (destination == null) {
    test('T6 review export is gated behind T6_CAPTURE_DIR', () {});
    return;
  }
  final fixture = OfflineReliabilityFixture();
  setUpAll(fixture.initialize);
  setUp(() async {
    AppBootstrap.resetForTests();
    await fixture.reset();
  });
  tearDown(() async {
    AppBootstrap.resetForTests();
    await fixture.closeCase();
  });

  for (final (variant, lock, viewport) in const [
    ('login', false, Size(390, 844)),
    ('app-lock', true, Size(390, 844)),
    ('app-lock-landscape', true, Size(844, 390)),
    ('app-lock-tablet', true, Size(1280, 800)),
  ]) {
    fixture.widgetTest('T6 Flutter-rendered $variant review', (tester) async {
      final root = Directory('$destination/$variant')
        ..createSync(recursive: true);
      final frames = Directory('${root.path}/frames')..createSync();
      final authentication = Completer<bool>();
      addTearDown(() {
        if (!authentication.isCompleted) authentication.complete(false);
      });
      var authCalls = 0;
      double? firstAuthenticationTime;
      double clockValue() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((widget) => widget.painter)
          .whereType<FieldSyncCinematicScenePainter>()
          .first
          .time
          .value;
      fixture.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/local_auth'),
        (call) async {
          if (call.method == 'getAvailableBiometrics') return ['fingerprint'];
          if (call.method == 'authenticate') {
            authCalls++;
            firstAuthenticationTime ??= clockValue();
            return authentication.future;
          }
          return true;
        },
      );
      if (lock) {
        fixture.online = true;
        fixture.mode = 'success';
        await BiometricService.enroll();
        await SecurePrefsService.setBioConfirmed(true);
        fixture.online = false;
        fixture.mode = 'transport';
      } else {
        await SecurePrefsService.setSoftLoggedOut(true);
        await AuthService.loadSoftLogoutState();
      }
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetPadding();
      });
      await tester.pumpWidget(
        RepaintBoundary(
          key: fixture.captureKey,
          child: ChangeNotifierProvider.value(
            value: fixture.provider,
            child: const MaterialApp(
              debugShowCheckedModeBanner: false,
              home: SplashScreen(),
            ),
          ),
        ),
      );

      // Use integer microseconds: labels report the painter's ACTUAL clock,
      // including the 1/60-second samples rather than rounded nominal labels.
      final shots = <int, (String, String)>{};
      void add(double seconds, String group, String scene) {
        shots[(seconds * 1e6).round()] = (group, scene);
      }

      for (final t in [
        5.60,
        5.65,
        5.70,
        5.75,
        5.79,
        5.799,
        5.8,
        5.801,
        5.85,
        5.9,
        6.0,
        6.1,
        6.15,
        6.2,
        6.4,
        6.6,
      ]) {
        add(t, 'p1p2', 'Page 1 -> Page 2 - seam and tail dissolve');
      }
      for (var i = 0; i <= 42; i++) {
        add(
          9.85 + i * 0.05,
          'departure',
          'Page 2 -> $variant - departure / return',
        );
      }
      for (var i = 0; i <= 24; i++) {
        add(
          10.80 + i / 60,
          'crossing-60fps',
          'Single route head - right-edge crossing',
        );
      }
      for (var i = 0; i <= 28; i++) {
        add(
          11.95 + i * 0.05,
          'reveal',
          '$variant - arrival, pulse, full-brand reveal',
        );
      }
      for (final t in [12.78, 12.799, 12.8, 13.2, 13.3, 13.34]) {
        add(t, 'reveal', '$variant - pulse/reveal/readiness boundary');
      }
      final storyboard = <double, String>{
        2.000: 'Page 1 - search through fingerprint obstacles',
        5.500: 'Page 1 - red-dot discovery',
        5.680: 'Page 1 -> Page 2 - measured seam splice',
        7.300: 'Page 2 - fingerprint snake formation',
        9.600: 'Page 2 - complete official logo',
        10.680: 'Page 2 - framed departure, close-up released',
        11.620: 'Destination - same route returning to brand',
        12.300: 'Destination - red-dot water-drop pulse',
        13.350: 'Destination - full brand revealed; presentation ready',
      };
      for (final beat in storyboard.entries) {
        add(beat.key, 'storyboard', beat.value);
      }
      for (final t in [
        0.90,
        1.12,
        1.75,
        2.38,
        2.75,
        3.15,
        3.40,
        3.66,
        3.79,
        4.18,
        4.32,
        4.46,
        4.60,
        4.72,
        4.90,
        5.10,
        5.30,
      ]) {
        add(t, 'search', 'Page 1 - user-green inner-channel sequence');
      }
      for (final t in [6.8, 7.0, 7.7, 8.2, 8.6, 9.1]) {
        add(t, 'formation', 'Page 2 - fingerprint formation');
      }
      // Page 1 is identical for both destinations. Export its entire 30 fps
      // sequence once, retaining the named review beats at matching times.
      if (variant == 'login') {
        for (var frame = 0; frame <= 168; frame++) {
          shots.putIfAbsent((frame * 1e6 / 30).round(),
              () => ('search-playback', 'Page 1 - continuous 30 fps sequence'));
        }
      }
      if (viewport.width > 390) {
        const wideSamples = {
          9600000,
          10680000,
          10983333,
          11000000,
          11016667,
          11150000,
          11200000,
          11620000,
          12300000,
          13300000,
          13340000,
          13350000,
        };
        shots.removeWhere((time, _) => !wideSamples.contains(time));
      }
      final manifest = StringBuffer(
        'file\tseconds\tgroup\tscene\tauthentication_calls\thead_x\thead_y\tdistance\n',
      );
      final requested = shots.keys.toList()..sort();
      var elapsed = 0;
      FieldSyncJourneyPath? graph;
      for (final micros in requested) {
        await tester.pump(Duration(microseconds: micros - elapsed));
        elapsed = micros;
        await fixture.flush(tester);
        final actual = clockValue();
        expect(actual, closeTo(micros / 1e6, 0.000002));
        final routes = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((widget) => widget.painter)
            .whereType<FieldSyncLoginRoutePainter>();
        if (routes.isNotEmpty) {
          graph = routes.single.journeyFor!(
            tester.getSize(find.byType(FieldSyncLoginRouteOverlay)),
          );
        }
        final stamp = actual.toStringAsFixed(6).padLeft(9, '0');
        final (group, scene) = shots[micros]!;
        final file = '$stamp-$group.png';
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(fixture.captureKey),
          );
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            '${frames.path}/$file',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
        final head = graph?.headAt(actual);
        manifest.writeln(
          '$file\t${actual.toStringAsFixed(6)}\t$group\t$scene\t$authCalls\t'
          '${head?.dx ?? ''}\t${head == null ? '' : head.dy + 24}\t${graph?.distanceAt(actual) ?? ''}',
        );
      }
      File('${root.path}/manifest.tsv').writeAsStringSync(manifest.toString());
      final journey = graph!;
      double timeAt(double distance) {
        var lo = 9.85;
        var hi = 11.95;
        for (var i = 0; i < 50; i++) {
          final mid = (lo + hi) / 2;
          if (journey.distanceAt(mid) < distance) {
            lo = mid;
          } else {
            hi = mid;
          }
        }
        return (lo + hi) / 2;
      }

      List<double> point(Offset p) => [p.dx, p.dy + 24];
      final paintCosts = <String, double>{};
      for (final t in [10.2, 10.68, 10.99, 11.0, 11.01, 11.2, 11.62, 12.3]) {
        final painter = FieldSyncLoginRoutePainter(
          time: AlwaysStoppedAnimation(t),
          brandRect: () => journey.brand,
          journeyFor: (_) => journey,
          onBlue: lock,
          splitSurface: lock && InsightBreakpoints(viewport).canSplitTwoPane,
        );
        final watch = Stopwatch()..start();
        for (var i = 0; i < 140; i++) {
          final recorder = ui.PictureRecorder();
          painter.paint(Canvas(recorder), journey.viewport);
          recorder.endRecording().dispose();
        }
        watch.stop();
        paintCosts[t.toString()] = watch.elapsedMicroseconds / 140;
      }
      final exitTime = timeAt(journey.exitDistance);
      final returnTime = timeAt(journey.returnDistance);
      File('${root.path}/measurements.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'variant': variant,
          'evidence':
              'Flutter render-tree and source-derived geometry; no REA MCP/device execution',
          'viewport_pixels': [viewport.width, viewport.height],
          'canvas_pixels': [journey.viewport.width, journey.viewport.height],
          'frame_count': requested.length,
          'route_contours': journey.path.computeMetrics().length,
          'exit_screen_xy': point(
            journey.metric.getTangentForOffset(journey.exitDistance)!.position,
          ),
          'return_screen_xy': point(
            journey.metric
                .getTangentForOffset(journey.returnDistance)!
                .position,
          ),
          'exit_time_seconds': exitTime,
          'return_time_seconds': returnTime,
          'head_center_offscreen_seconds': returnTime - exitTime,
          'velocity_before_turn_pixels_per_second':
              (journey.distanceAt(11) - journey.distanceAt(10.999)) / 0.001,
          'velocity_after_turn_pixels_per_second':
              (journey.distanceAt(11.001) - journey.distanceAt(11)) / 0.001,
          'paint_recording_microseconds': paintCosts,
          'paint_cost_excludes_raster_gpu_and_device_pacing': true,
          'authentication_calls': authCalls,
          'first_mock_native_authentication_time_seconds':
              firstAuthenticationTime,
        }),
      );
      expect(authCalls, lock ? 1 : 0);
      if (lock) expect(firstAuthenticationTime, greaterThanOrEqualTo(13.35));
      expect(
        find.byType(lock ? AppResumeLockScreen : LoginScreen),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
