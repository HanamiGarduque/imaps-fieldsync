import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/navigation/main_shell_screen.dart';
import 'package:imaps_fieldsync/core/services/app_bootstrap.dart';
import 'package:imaps_fieldsync/core/services/auth_service.dart';
import 'package:imaps_fieldsync/core/theme/insight_theme.dart';
import 'package:imaps_fieldsync/core/widgets/fieldsync_brand.dart';
import 'package:imaps_fieldsync/core/widgets/fieldsync_cinematic_intro.dart';
import 'package:imaps_fieldsync/modules/auth_startup/screens/app_resume_lock_screen.dart';
import 'package:imaps_fieldsync/modules/auth_startup/screens/splash_screen.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/biometric_service.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/secure_prefs_service.dart';

import 'support/offline_reliability_fixture.dart';

double effectiveOpacity(WidgetTester tester, Finder finder) {
  expect(
    finder,
    findsOneWidget,
    reason: 'measure one destination element, not covered splash text',
  );
  return tester
      .widgetList<Opacity>(
        find.ancestor(of: finder, matching: find.byType(Opacity)),
      )
      .fold(1.0, (value, widget) => value * widget.opacity);
}

void main() {
  final fixture = OfflineReliabilityFixture();
  var authenticationCalls = 0;
  late Completer<bool> authentication;
  setUpAll(fixture.initialize);
  setUp(() async {
    AppBootstrap.resetForTests();
    await fixture.reset();
    authenticationCalls = 0;
    authentication = Completer<bool>();
    fixture.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/local_auth'),
      (call) async {
        if (call.method == 'getAvailableBiometrics') return ['fingerprint'];
        if (call.method == 'authenticate') {
          authenticationCalls++;
          return authentication.future;
        }
        return true;
      },
    );
  });
  tearDown(() async {
    if (!authentication.isCompleted) authentication.complete(false);
    AppBootstrap.resetForTests();
    await fixture.closeCase();
  });

  Future<void> advance(WidgetTester tester, double seconds) async {
    // Geometry checks use authored beats; real-time pacing has separate tests.
    await tester.pump(Duration(microseconds: (seconds *
        FieldSyncCinematicTimeline.playbackDuration.inMicroseconds /
        FieldSyncCinematicTimeline.totalSeconds).round()));
    await fixture.flush(tester);
  }

  Future<void> eligibleLock() async {
    fixture.online = true;
    fixture.mode = 'success';
    await BiometricService.enroll();
    await SecurePrefsService.setBioConfirmed(true);
    fixture.online = false;
    fixture.mode = 'transport';
    fixture.requests.clear();
  }

  fixture.widgetTest('zoomed official logo has no rectangular internal cutoff',
      (tester) async {
    await SecurePrefsService.setSoftLoggedOut(true);
    await AuthService.loadSoftLogoutState();
    await fixture.mount(tester, const SplashScreen());
    await advance(tester, 3);
    await advance(tester, 3.1);
    await fixture.capture(tester, 'logo-unclipped');
    final box = tester.getRect(find.byType(AspectRatio).first);
    expect(box.width / box.height, closeTo(887 / 1115, 0.0001));
    Future<ByteData> pixels() async => (await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(fixture.captureKey),
      );
      final image = await boundary.toImage(pixelRatio: 1);
      final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      image.dispose();
      return data;
    }))!;
    final zoomed = await pixels();
    final left = box.right.floor() - 2;
    final right = box.right.ceil() + 2;
    var alignedCut = 0;
    for (var y = box.top.ceil() + 16; y < box.bottom.floor() - 16; y++) {
      final a = 4 * (y * 390 + left);
      final b = 4 * (y * 390 + right);
      if (zoomed.getUint8(a) - zoomed.getUint8(b) > 8) alignedCut++;
    }
    expect(alignedCut, lessThan(24),
        reason: 'ribbons must not share the straight right edge of the logo box');
    await advance(tester, 3.5);
    final settled = await pixels();
    var white = 0;
    for (var y = box.top.ceil(); y < box.bottom.floor(); y++) {
      for (var x = box.left.ceil(); x < box.right.floor(); x++) {
        final i = 4 * (y * 390 + x);
        if (settled.getUint8(i) > 210 && settled.getUint8(i + 1) > 210) white++;
      }
    }
    expect(white, greaterThan(2000),
        reason: 'fix the paint bounds, do not hide the complete official artwork');
  });

  fixture.widgetTest('the longer search remains skippable after six real seconds',
      (tester) async {
    await SecurePrefsService.setSoftLoggedOut(true);
    await AuthService.loadSoftLogoutState();
    await fixture.mount(tester, const SplashScreen());
    await tester.pump(const Duration(seconds: 3));
    await fixture.flush(tester);
    await tester.pump(const Duration(seconds: 3));
    await fixture.flush(tester);
    final scene = tester.widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((widget) => widget.painter)
        .whereType<FieldSyncCinematicScenePainter>().single;
    expect(FieldSyncCinematicScenePainter.redDotAlphaAt(scene.time.value), 0,
        reason: 'give the search real travel time, not a hurry then a long hold');
    await tester.tap(find.byKey(const ValueKey('splash-skip')));
    await fixture.flush(tester);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('splash-skip')), findsNothing);
  });

  fixture.widgetTest('the return journey is still travelling at nineteen real seconds',
      (tester) async {
    await SecurePrefsService.setSoftLoggedOut(true);
    await AuthService.loadSoftLogoutState();
    await fixture.mount(tester, const SplashScreen());
    await tester.pump(const Duration(seconds: 3));
    await fixture.flush(tester);
    await tester.pump(const Duration(milliseconds: 16300));
    await fixture.flush(tester);
    FieldSyncLoginRoutePainter route() {
      final routes = tester.widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((widget) => widget.painter)
          .whereType<FieldSyncLoginRoutePainter>().toList();
      expect(routes, hasLength(1), reason: 'the return must still be travelling');
      return routes.single;
    }
    final painter = route();
    final journey = painter.journeyFor!(
      tester.getSize(find.byType(FieldSyncLoginRouteOverlay)),
    )!;
    final before = journey.headAt(painter.time.value);
    await tester.pump(const Duration(milliseconds: 800));
    await fixture.flush(tester);
    expect((journey.headAt(route().time.value) - before).distance, greaterThan(10));
    expect(route().time.value, lessThan(FieldSyncCinematicTimeline.travelEndSeconds));
    await tester.pump(const Duration(milliseconds: 3000));
    await fixture.flush(tester);
    expect(find.byKey(const ValueKey('splash-skip')), findsNothing);
  });

  fixture.widgetTest(
    'whole login branding is hidden without moving form or status',
    (tester) async {
      await fixture.mount(tester, const LoginScreen());
      await fixture.flush(tester);
      final field = tester.getRect(find.byType(TextFormField).first);
      final mark = tester.getRect(find.byType(FieldSyncBrand));
      final status = tester.getRect(find.text('Offline'));
      expect(effectiveOpacity(tester, find.text('iMAPS')), 1);
      expect(effectiveOpacity(tester, find.text('FieldSync')), 1);

      await fixture.mount(
        tester,
        const LoginScreen(brandReveal: AlwaysStoppedAnimation<double>(0)),
      );
      await fixture.flush(tester);
      expect(tester.getRect(find.byType(TextFormField).first), field);
      expect(tester.getRect(find.byType(FieldSyncBrand)), mark);
      expect(tester.getRect(find.text('Offline')), status);
      expect(effectiveOpacity(tester, find.text('Offline')), 1);
      expect(effectiveOpacity(tester, find.byType(FieldSyncBrand)), 0);
      expect(effectiveOpacity(tester, find.text('iMAPS')), 0);
      expect(effectiveOpacity(tester, find.text('FieldSync')), 0);
    },
  );

  fixture.widgetTest(
    'cold-start lock waits for the completed cinematic, never Login',
    (tester) async {
      await eligibleLock();
      await fixture.mount(tester, const SplashScreen());
      await advance(tester, 3);
      await advance(
        tester,
        7.2,
      ); // 10.20: lock may measure, but never authenticate.
      expect(find.byType(AppResumeLockScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.byType(MainShellScreen), findsNothing);
      expect(
        authenticationCalls,
        0,
        reason: 'native authentication must not obscure the departure/reveal',
      );
      await advance(
        tester,
        3.14,
      ); // 13.34: final presentation frame not reached.
      expect(authenticationCalls, 0);
      await advance(tester, 0.02);
      expect(authenticationCalls, 1);
      expect(find.byKey(const ValueKey('splash-skip')), findsNothing);
      expect(find.byType(MainShellScreen), findsNothing);
      authentication.complete(true);
      await fixture.flush(tester);
      await tester.pumpAndSettle();
      expect(find.byType(AppResumeLockScreen), findsNothing);
      expect(find.byType(MainShellScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    },
  );

  fixture.widgetTest(
    'App Lock presentation reserves the whole header and stays inert',
    (tester) async {
      final ready = ValueNotifier(false);
      final reveal = AnimationController(vsync: tester)..value = 0;
      addTearDown(ready.dispose);
      addTearDown(reveal.dispose);
      await fixture.mount(
        tester,
        AppResumeLockScreen(cinematicReady: ready, brandReveal: reveal),
      );
      await fixture.flush(tester);
      final mark = tester.getRect(find.byType(FieldSyncBrand));
      final unlock = tester.getRect(find.byType(ElevatedButton));
      final header = find.text('Your work.\nKept private.');
      expect(effectiveOpacity(tester, find.text('iMAPS')), 0);
      expect(effectiveOpacity(tester, find.text('FieldSync')), 0);
      expect(effectiveOpacity(tester, header), 1);
      expect(
        tester.widget<Text>(find.text('Unlock with Fingerprint')).style!.color,
        InsightTheme.ink3,
        reason: 'the deferred control must remain readable',
      );
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
      expect(authenticationCalls, 0);
      reveal.value = 1;
      await fixture.flush(tester);
      expect(tester.getRect(find.byType(FieldSyncBrand)), mark);
      expect(tester.getRect(find.byType(ElevatedButton)), unlock);
      expect(effectiveOpacity(tester, find.text('iMAPS')), 1);
      expect(effectiveOpacity(tester, find.text('FieldSync')), 1);
      expect(
        authenticationCalls,
        0,
        reason: 'brand visibility alone is not prompt readiness',
      );
      ready.value = true;
      await fixture.flush(tester);
      expect(authenticationCalls, 1);
    },
  );

  fixture.widgetTest(
    'App Lock cancellation stays locked; resume does not duplicate; retry and logout work',
    (tester) async {
      final ready = ValueNotifier(false);
      addTearDown(ready.dispose);
      await fixture.mount(tester, AppResumeLockScreen(cinematicReady: ready));
      await fixture.flush(tester);
      ready.value = true;
      await fixture.flush(tester);
      expect(authenticationCalls, 1);
      authentication.complete(false);
      await fixture.flush(tester);
      expect(
        find.text("That didn't match. Try again with Fingerprint."),
        findsOneWidget,
      );
      expect(find.byType(MainShellScreen), findsNothing);
      expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
      fixture.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.inactive,
      );
      fixture.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await fixture.flush(tester);
      expect(authenticationCalls, 1);
      await tester.tap(find.byType(ElevatedButton));
      await fixture.flush(tester);
      expect(authenticationCalls, 2);
      fixture.mode = 'success';
      await tester.tap(find.widgetWithText(TextButton, 'Log Out'));
      await fixture.flush(tester);
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(AppResumeLockScreen), findsNothing);
      expect(find.byType(MainShellScreen), findsNothing);
      expect(AuthService.isLoggedIn, isFalse);
    },
  );

  fixture.widgetTest(
    'App Lock readiness in background waits for foreground exactly once',
    (tester) async {
      final ready = ValueNotifier(false);
      addTearDown(ready.dispose);
      addTearDown(
        () => fixture.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      await fixture.mount(tester, AppResumeLockScreen(cinematicReady: ready));
      fixture.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.inactive,
      );
      fixture.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      fixture.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      ready.value = true;
      await fixture.flush(tester);
      expect(authenticationCalls, 0);
      fixture.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      fixture.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.inactive,
      );
      fixture.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await fixture.flush(tester);
      expect(authenticationCalls, 1);
      fixture.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await fixture.flush(tester);
      expect(authenticationCalls, 1);
    },
  );

  fixture.widgetTest('disposed App Lock cancels its queued automatic attempt', (
    tester,
  ) async {
    final ready = ValueNotifier(false);
    addTearDown(ready.dispose);
    await fixture.mount(tester, AppResumeLockScreen(cinematicReady: ready));
    await fixture.flush(tester);
    ready.value = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await fixture.flush(tester);
    expect(authenticationCalls, 0);
    expect(tester.takeException(), isNull);
  });

  for (final reduced in [false, true]) {
    for (final pending in [false, true]) {
      fixture.widgetTest(
        'lock cannot be bypassed: reduced=$reduced pending=$pending',
        (tester) async {
          await eligibleLock();
          final gate = Completer<void>();
          if (pending) {
            AppBootstrap.initialize(
              steps: [(name: 'T6 held bootstrap', run: () => gate.future)],
            );
          }
          if (reduced) {
            tester.platformDispatcher.accessibilityFeaturesTestValue =
                const FakeAccessibilityFeatures(disableAnimations: true);
            addTearDown(
              tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
            );
          }
          await fixture.mount(tester, const SplashScreen());
          await advance(tester, 3.2);
          if (!reduced) {
            await tester.tap(find.byKey(const ValueKey('splash-skip')));
            await fixture.flush(tester);
          }
          if (pending) {
            await advance(tester, 4);
            expect(find.byType(AppResumeLockScreen), findsNothing);
            expect(find.byType(LoginScreen), findsNothing);
            expect(find.byType(MainShellScreen), findsNothing);
            expect(authenticationCalls, 0);
            gate.complete();
            await fixture.flush(tester);
          }
          expect(find.byType(AppResumeLockScreen), findsOneWidget);
          expect(find.byType(LoginScreen), findsNothing);
          expect(find.byType(MainShellScreen), findsNothing);
          final lock = find.byType(AppResumeLockScreen);
          expect(
            effectiveOpacity(
              tester,
              find.descendant(of: lock, matching: find.text('iMAPS')),
            ),
            1,
          );
          expect(
            effectiveOpacity(
              tester,
              find.descendant(of: lock, matching: find.text('FieldSync')),
            ),
            1,
          );
          expect(find.byKey(const ValueKey('splash-skip')), findsNothing);
          expect(authenticationCalls, 1);
        },
      );
    }
  }

  for (final missing in ['require-on-open', 'enrolled', 'confirmed']) {
    fixture.widgetTest('authenticated without $missing retains direct Home', (
      tester,
    ) async {
      await eligibleLock();
      if (missing == 'require-on-open') {
        await SecurePrefsService.setBioRequireOnOpen(false);
      }
      if (missing == 'enrolled') fixture.secure['sp_bio_enrolled'] = 'false';
      if (missing == 'confirmed') {
        await SecurePrefsService.setBioConfirmed(false);
      }
      await fixture.mount(tester, const SplashScreen());
      await advance(tester, 3);
      await advance(tester, 6.9);
      expect(find.byType(MainShellScreen), findsOneWidget);
      expect(find.byType(AppResumeLockScreen), findsNothing);
      expect(find.byType(LoginScreen), findsNothing);
      expect(authenticationCalls, 0);
    });
  }

  fixture.widgetTest(
    'late authenticated decision settles on lock without replay or premature mount',
    (tester) async {
      await eligibleLock();
      final decision = Completer<String?>();
      fixture.storageReplies['sp_bio_require_on_open'] = decision;
      await fixture.mount(tester, const SplashScreen());
      await advance(tester, 3);
      await advance(tester, 8);
      expect(find.byType(AppResumeLockScreen), findsNothing);
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.byType(MainShellScreen), findsNothing);
      expect(authenticationCalls, 0);
      decision.complete('true');
      await fixture.flush(tester);
      expect(find.byType(AppResumeLockScreen), findsOneWidget);
      expect(effectiveOpacity(tester, find.text('FieldSync')), 1);
      expect(find.byKey(const ValueKey('splash-skip')), findsNothing);
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.byType(MainShellScreen), findsNothing);
      expect(authenticationCalls, 1);
    },
  );

  fixture.widgetTest(
    'failed bootstrap never mounts an eligible App Lock or prompts',
    (tester) async {
      await eligibleLock();
      AppBootstrap.initialize(
        steps: [
          (
            name: 'T6 isolated failure',
            run: () async => throw StateError('fixture failure'),
          ),
        ],
      );
      await fixture.mount(tester, const SplashScreen());
      await advance(tester, 3.2);
      await tester.tap(find.byKey(const ValueKey('splash-skip')));
      await fixture.flush(tester);
      expect(
        find.textContaining('Unable to initialize FieldSync.'),
        findsOneWidget,
      );
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.byType(AppResumeLockScreen), findsNothing);
      expect(find.byType(MainShellScreen), findsNothing);
      expect(authenticationCalls, 0);
    },
  );

  fixture.widgetTest(
    'screen uses exactly one journey painter and retains measured metrics across ticks',
    (tester) async {
      await eligibleLock();
      await fixture.mount(tester, const SplashScreen());
      await advance(tester, 3);
      await advance(tester, 7.8);
      FieldSyncLoginRoutePainter route() {
        final painters = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((widget) => widget.painter)
            .whereType<FieldSyncLoginRoutePainter>()
            .toList();
        expect(painters, hasLength(1));
        expect(
          tester
              .widgetList<CustomPaint>(find.byType(CustomPaint))
              .map((widget) => widget.painter)
              .whereType<FieldSyncDepartureRoutePainter>(),
          isEmpty,
        );
        return painters.single;
      }

      final size = tester.getSize(find.byType(FieldSyncLoginRouteOverlay));
      final before = route().journeyFor!(size)!;
      final head = before.headAt(10.8);
      await advance(tester, 1 / 60);
      final after = route().journeyFor!(size)!;
      expect(
        identical(before, after),
        isTrue,
        reason: 'no per-frame path/metric rebuilding',
      );
      expect((after.headAt(10.8 + 1 / 60) - head).distance, greaterThan(0.1));
      expect(route().onBlue, isTrue);
      tester.view.physicalSize = const Size(844, 390);
      await fixture.flush(tester);
      final resized = route().journeyFor!(
        tester.getSize(find.byType(FieldSyncLoginRouteOverlay)),
      )!;
      expect(identical(resized, before), isFalse);
      expect(resized.viewport.width, 844);
      expect(authenticationCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in const [Size(844, 390), Size(1280, 800)]) {
    fixture.widgetTest(
      'App Lock workspace occludes the route and traveller $size',
      (tester) async {
        await eligibleLock();
        await fixture.mount(tester, const SplashScreen(), size: size);
        await advance(tester, 3);
        await advance(tester, 8.2);
        final route = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((widget) => widget.painter)
            .whereType<FieldSyncLoginRoutePainter>()
            .single;
        final journey = route.journeyFor!(
          tester.getSize(find.byType(FieldSyncLoginRouteOverlay)),
        )!;
        final head = journey.headAt(11.2) + const Offset(0, 24);
        expect(
          head.dx,
          greaterThan(size.width / 2),
          reason: 'head is on the light workspace',
        );
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(fixture.captureKey),
        );
        Future<ByteData> pixels() async => (await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          image.dispose();
          return bytes;
        }))!;
        final before = await pixels();
        await advance(tester, 0.42); // 11.62: the head is back on the blue side.
        final blueHead = journey.headAt(11.62) + const Offset(0, 24);
        expect(blueHead.dx, lessThan(size.width / 2));
        final blueBefore = await pixels();
        await advance(tester, 1 / 60);
        final blueAfter = await pixels();
        var moving = 0;
        for (var x = blueHead.dx.floor() - 16; x <= blueHead.dx.ceil() + 16; x++) {
          for (var y = blueHead.dy.floor() - 16; y <= blueHead.dy.ceil() + 16; y++) {
            final i = 4 * (y * size.width.toInt() + x);
            if ((blueBefore.getUint8(i) - blueAfter.getUint8(i)).abs() > 8) moving++;
          }
        }
        expect(moving, greaterThan(8),
            reason: 'occlusion must not hide the journey on the blue background');
        await advance(
          tester,
          13.30 - 11.62 - 1 / 60,
        ); // 13.30: same workspace, route gone, no auth yet.
        final background = await pixels();
        var changed = 0;
        // The opaque workspace must cover both the trail and the head. Compare
        // with its real, unchanged UI after the route has dissipated.
        for (var x = head.dx.floor() - 8; x <= head.dx.ceil() + 24; x++) {
          for (var y = head.dy.floor() - 8; y <= head.dy.ceil() + 8; y++) {
            final i = 4 * (y * size.width.toInt() + x);
            for (var c = 0; c < 3; c++) {
              if ((background.getUint8(i + c) - before.getUint8(i + c)).abs() > 8) {
                changed++;
                break;
              }
            }
          }
        }
        expect(
          changed,
          0,
          reason: 'the route and moving dot belong behind the opaque workspace',
        );
        expect(authenticationCalls, 0);
      },
    );
  }

  for (final lock in [false, true]) {
    fixture.widgetTest('offline cinematic animates through to ${lock ? 'App Lock' : 'Login'}',
        (tester) async {
      if (lock) {
        await eligibleLock();
      } else {
        fixture.online = false;
        fixture.mode = 'transport';
        await SecurePrefsService.setSoftLoggedOut(true);
        await AuthService.loadSoftLogoutState();
      }
      expect(fixture.online, isFalse);
      await fixture.mount(tester, const SplashScreen());
      await advance(tester, 3);
      FieldSyncCinematicScenePainter scene() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((widget) => widget.painter)
          .whereType<FieldSyncCinematicScenePainter>().single;
      final searchTime = scene().time.value;
      await advance(tester, 1 / 60);
      expect(scene().time.value, greaterThan(searchTime),
          reason: 'offline startup must not freeze the local animation clock');
      await advance(tester, 7.8 - 1 / 60); // 10.80: the departure is running.
      final route = tester.widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((widget) => widget.painter)
          .whereType<FieldSyncLoginRoutePainter>().single;
      final journey = route.journeyFor!(
          tester.getSize(find.byType(FieldSyncLoginRouteOverlay)))!;
      final time = route.time.value;
      final head = journey.headAt(time);
      await advance(tester, 1 / 60);
      expect((journey.headAt(route.time.value) - head).distance, greaterThan(0.1));
      expect(authenticationCalls, 0);
      await advance(tester, 2.55); // 13.3667: presentation has completed.
      final destination = find.byType(lock ? AppResumeLockScreen : LoginScreen);
      expect(destination, findsOneWidget);
      expect(find.byType(lock ? LoginScreen : AppResumeLockScreen), findsNothing);
      expect(find.byKey(const ValueKey('splash-skip')), findsNothing);
      expect(effectiveOpacity(tester,
          find.descendant(of: destination, matching: find.text('FieldSync'))), 1);
      expect(fixture.online, isFalse);
      expect(authenticationCalls, lock ? 1 : 0,
          reason: 'offline animation never bypasses the App Lock readiness gate');
      if (!lock) {
        expect(find.text('Offline'), findsOneWidget);
        expect(find.byType(TextFormField), findsNWidgets(2));
      }
      expect(tester.takeException(), isNull);
    });
  }

  fixture.widgetTest(
    'embedded Login leaves system icons with the cinematic surface',
    (tester) async {
      final styles = <Map<dynamic, dynamic>>[];
      fixture.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemChrome.setSystemUIOverlayStyle') {
            styles.add(Map<dynamic, dynamic>.from(call.arguments as Map));
          }
          return null;
        },
      );
      addTearDown(
        () => fixture.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
      await fixture.flush(tester);
      await SecurePrefsService.setSoftLoggedOut(true);
      await AuthService.loadSoftLogoutState();
      await fixture.mount(tester, const SplashScreen());
      await advance(tester, 3);
      await advance(tester, 7.2);
      expect(
        find.byType(LoginScreen),
        findsOneWidget,
        reason: 'the destination is laid out invisibly',
      );
      expect(styles.last['statusBarIconBrightness'], 'Brightness.light');
      await advance(tester, 0.79);
      expect(styles.last['statusBarIconBrightness'], 'Brightness.light');
      await advance(tester, 0.02);
      expect(styles.last['statusBarIconBrightness'], 'Brightness.dark');
      SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
      await fixture.flush(tester);
      await fixture.mount(tester, const LoginScreen());
      await fixture.flush(tester);
      expect(
        styles.last['statusBarIconBrightness'],
        'Brightness.dark',
        reason: 'ordinary Login still owns its normal dark icon style',
      );
    },
  );

  test(
    'departure keeps its close-up but frames the full logo again by 10.68',
    () {
      expect(FieldSyncDepartureCamera.zoomAt(10.20), greaterThan(1.15));
      expect(FieldSyncDepartureCamera.zoomAt(10.68), lessThanOrEqualTo(1.001));
    },
  );

  test('destination rings dissipate before the full brand reveal starts', () {
    final lastRingEnd =
        FieldSyncCinematicTimeline.loginPulseStartSeconds +
        FieldSyncCinematicTimeline.loginPulseGapSeconds +
        FieldSyncCinematicTimeline.loginPulseDurationSeconds;
    expect(
      lastRingEnd,
      lessThanOrEqualTo(FieldSyncCinematicTimeline.brandRevealStartSeconds),
    );
    expect(
      FieldSyncCinematicTimeline.loginDotFadeEndSeconds,
      lessThanOrEqualTo(FieldSyncCinematicTimeline.brandRevealStartSeconds),
    );
  });

  test(
    'shared journey has one contour, level exit and hidden C1 turn',
    () {
      final journey = FieldSyncJourneyPath(
        departureBox: const Rect.fromLTWH(32, 136, 280.8, 353),
        brand: const Rect.fromLTWH(59.2, 16, 44.55, 56),
        viewport: const Size(390, 796),
      );
      expect(journey.path.computeMetrics().length, 1);
      final exit = journey.metric.getTangentForOffset(journey.exitDistance)!;
      final returning = journey.metric.getTangentForOffset(
        journey.returnDistance,
      )!;
      expect(exit.position.dx, closeTo(390, 0.1));
      expect(returning.position.dx, closeTo(390, 0.1));
      final start = journey.metric.getTangentForOffset(0)!.position;
      for (var d = 0.0; d <= journey.exitDistance; d += 2) {
        expect(journey.metric.getTangentForOffset(d)!.position.dy,
            closeTo(start.dy, 1),
            reason: 'the outbound follows the green line at the site height');
      }
      expect(exit.position.dy, closeTo(start.dy, 1));
      expect(
        (exit.position.dy - returning.position.dy).abs(),
        greaterThan(24),
        reason: 'separate the exit and entry rather than a visible hairpin',
      );
      expect(journey.headAt(FieldSyncCinematicTimeline.edgeTurnSeconds).dx,
          greaterThan(journey.viewport.width + 10),
          reason: 'the complete head ring must be off-screen during reversal');
      expect(exit.vector.dx, greaterThan(0.99));
      expect(returning.vector.dx, lessThan(-0.99));
      for (final join in [journey.exitDistance, journey.returnDistance]) {
        final before = journey.metric.getTangentForOffset(join - 0.001)!.vector;
        final after = journey.metric.getTangentForOffset(join + 0.001)!.vector;
        expect(before.dx * after.dx + before.dy * after.dy, greaterThan(0.99));
      }
      final target = FieldSyncLoginRoutePainter.targetFor(journey.brand);
      expect((journey.headAt(11.95) - target).distance, lessThan(0.01));
    },
  );

  test(
    'shared arc distance never resets or stalls and crossing speed is continuous',
    () {
      for (final size in const [
        Size(320, 520),
        Size(390, 796),
        Size(844, 342),
        Size(1280, 752),
      ]) {
        final journey = FieldSyncJourneyPath(
          departureBox: Rect.fromLTWH(
            32,
            96,
            size.width < 500 ? size.width * 0.72 : 280.8,
            353,
          ),
          brand: const Rect.fromLTWH(28, 24, 35, 44),
          viewport: size,
        );
        var before = journey.distanceAt(9.85);
        for (var frame = 1; frame < 126; frame++) {
          final distance = journey.distanceAt(9.85 + frame / 60);
          expect(distance, greaterThan(before));
          before = distance;
        }
        final v1 =
            (journey.distanceAt(11) - journey.distanceAt(10.999)) / 0.001;
        final v2 =
            (journey.distanceAt(11.001) - journey.distanceAt(11)) / 0.001;
        expect((v1 - v2).abs() / v1, lessThan(0.01));
        double timeAt(double distance) {
          var lo = 9.85;
          var hi = 11.95;
          for (var i = 0; i < 40; i++) {
            final mid = (lo + hi) / 2;
            if (journey.distanceAt(mid) < distance) {
              lo = mid;
            } else {
              hi = mid;
            }
          }
          return (lo + hi) / 2;
        }

        final hiddenSeconds =
            timeAt(journey.returnDistance) - timeAt(journey.exitDistance);
        expect(hiddenSeconds, greaterThan(1 / 60),
            reason: 'the head exits before returning; no one-frame ricochet');
        expect(hiddenSeconds, lessThan(0.35),
            reason: 'the off-screen trip stays brief, not a stalled reveal');
        expect(
          journey.trailStartAt(11.2),
          closeTo(journey.returnDistance, 1e-6),
        );
      }
    },
  );

  fixture.widgetTest(
    'returning route is visibly advancing immediately after the page fade',
    (tester) async {
      await SecurePrefsService.setSoftLoggedOut(true);
      await AuthService.loadSoftLogoutState();
      await fixture.mount(tester, const SplashScreen());
      await advance(tester, 3);
      await advance(tester, 8.2);
      Future<ByteData> pixels() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(fixture.captureKey),
        );
        return (await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final data = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          image.dispose();
          return data;
        }))!;
      }

      final before = await pixels();
      await advance(tester, 1 / 60);
      final after = await pixels();
      var changed = 0;
      for (var y = 80; y < 400; y++) {
        for (var x = 0; x < 390; x++) {
          final i = 4 * (y * 390 + x);
          if ((before.getUint8(i) - after.getUint8(i)).abs() > 10 ||
              (before.getUint8(i + 1) - after.getUint8(i + 1)).abs() > 10) {
            changed++;
          }
        }
      }
      expect(
        changed,
        greaterThan(8),
        reason:
            'the re-entry must not hold an identical, route-free login frame',
      );
    },
  );

  fixture.widgetTest(
    'finished Login does not keep the covered startup spinner ticking',
    (tester) async {
      await SecurePrefsService.setSoftLoggedOut(true);
      await AuthService.loadSoftLogoutState();
      await fixture.mount(tester, const SplashScreen());
      await advance(tester, 3);
      await advance(tester, 10.4);
      expect(find.byType(LoginScreen), findsOneWidget);
      await tester.pumpAndSettle(
        const Duration(milliseconds: 16),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 1),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
