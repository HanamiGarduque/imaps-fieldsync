import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/services/auth_service.dart';
import 'package:imaps_fieldsync/core/widgets/fieldsync_cinematic_intro.dart';
import 'package:imaps_fieldsync/modules/auth_startup/screens/splash_screen.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/secure_prefs_service.dart';

import 'support/offline_reliability_fixture.dart';

/// Storyboard capture harness for the approved three-page launch cinematic.
///
/// Gated behind `IMAPS_CINEMATIC_CAPTURE_DIR`: with the variable unset the
/// suite registers a single documentation test and writes nothing, so normal
/// and CI runs stay clean. With it set, one mounted launch is stepped to the
/// timeline's own beats and each frame is written as a PNG straight from the
/// Flutter render tree (no screenshots of a device).
///
/// These are Flutter-rendered frames, not device video. The T5 brief asks for
/// eight storyboard captures; frames 8 and 9 together carry the brief's
/// "red pulse + final login logo reveal" frame at full fidelity.
void main() {
  final captureDir = Platform.environment['IMAPS_CINEMATIC_CAPTURE_DIR'];

  if (captureDir == null) {
    test('cinematic captures are gated behind IMAPS_CINEMATIC_CAPTURE_DIR',
        () {
      // Intentionally empty: the harness only runs when asked for evidence.
    });
    return;
  }

  final fixture = OfflineReliabilityFixture();
  setUpAll(fixture.initialize);
  setUp(() => fixture.reset());
  tearDown(() => fixture.closeCase());

  Future<void> advance(WidgetTester tester, Duration elapsed) async {
    await tester.pump(Duration(microseconds: (elapsed.inMicroseconds *
        FieldSyncCinematicTimeline.playbackDuration.inMicroseconds /
        (FieldSyncCinematicTimeline.totalSeconds * 1e6)).round()));
    await fixture.flush(tester);
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    final folder = Directory(captureDir);
    if (!folder.existsSync()) folder.createSync(recursive: true);
    await tester.pump();
    await tester.runAsync(() async {
      final boundary = tester
          .renderObject<RenderRepaintBoundary>(find.byKey(fixture.captureKey));
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('${folder.path}/$name.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  fixture.widgetTest('the storyboard frames of the approved journey',
      (tester) async {
    // The clean login destination: a local signed-out owner, no banner.
    await SecurePrefsService.setSoftLoggedOut(true);
    await AuthService.loadSoftLogoutState();
    await fixture.mount(tester, const SplashScreen());

    // 1. Page 1 — the route searching through the obstacles (search runs
    //    0.95–5.27 s).
    await advance(tester, const Duration(milliseconds: 2000));
    await shoot(tester, 'storyboard-1-search-through-obstacles');

    // 2. Page 1 — the red site dot discovered: the route's arrowhead reaches
    //    it and the water-drop rings answer (dot visible from 5.27 s).
    await advance(tester, const Duration(milliseconds: 3500));
    await shoot(tester, 'storyboard-2-red-dot-discovery');

    // 3. Page 1 → Page 2 — the splice onto the measured logo box, late in the
    //    morph (5.27–5.80 s).
    await advance(tester, const Duration(milliseconds: 180));
    await shoot(tester, 'storyboard-3-page1-page2-transition');

    // 4. Page 2 — the fingerprint ribbons assembling (formation 5.80–8.80 s).
    await advance(tester, const Duration(milliseconds: 1620));
    await shoot(tester, 'storyboard-4-fingerprint-formation');

    // 5. Page 2 — the complete official lockup at the hold (8.80–9.85 s).
    await advance(tester, const Duration(milliseconds: 2300));
    await shoot(tester, 'storyboard-5-complete-logo');

    // 6. Page 2 — the route leaving through the right edge, camera following
    //    (departure 9.85–11.05 s).
    await advance(tester, const Duration(milliseconds: 1080));
    await shoot(tester, 'storyboard-6-route-exiting-page2');

    // 7. Page 3 — the same route re-entering the login (mount 10.85–11.15 s,
    //    travel 11.15–11.95 s).
    await advance(tester, const Duration(milliseconds: 940));
    await shoot(tester, 'storyboard-7-route-entering-page3');

    // 8. Page 3 — the destination dot and its water-drop pulse
    //    (pop 11.95–12.20 s, rings 12.05–12.70 s).
    await advance(tester, const Duration(milliseconds: 680));
    await shoot(tester, 'storyboard-8-red-dot-pulse');

    // 9. Page 3 — the official logo revealed and the login settled
    //    (brand 12.55–13.15 s, barrier released at 13.15 s).
    await advance(tester, const Duration(milliseconds: 900));
    await shoot(tester, 'storyboard-9-final-logo-reveal-login');

    // 9. Page 3 — the official logo revealed and the login settled
    //    (brand 12.55–13.15 s, barrier released at 13.15 s).
    await advance(tester, const Duration(milliseconds: 900));
    await shoot(tester, 'storyboard-9-final-logo-reveal-login');

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
