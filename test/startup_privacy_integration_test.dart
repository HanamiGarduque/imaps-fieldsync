import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/services/app_bootstrap.dart';
import 'package:imaps_fieldsync/core/services/supabase_service.dart';
import 'package:imaps_fieldsync/core/widgets/fieldsync_cinematic_intro.dart';
import 'package:imaps_fieldsync/core/widgets/sensitive_screen.dart';
import 'package:imaps_fieldsync/main.dart';
import 'package:imaps_fieldsync/modules/auth_startup/screens/splash_screen.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/screen_protection_service.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/secure_prefs_service.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/biometric_service.dart';
import 'package:imaps_fieldsync/core/services/auth_service.dart';

import 'support/offline_reliability_fixture.dart';

void main() {
  final fixture = OfflineReliabilityFixture();
  final protection = ScreenProtectionService.instance;
  setUpAll(fixture.initialize);
  setUp(() async {
    AppBootstrap.resetForTests();
    SupabaseService.debugClientAvailableOverride = null;
    await fixture.reset();
  });
  tearDown(() async {
    AppBootstrap.resetForTests();
    SupabaseService.debugClientAvailableOverride = null;
    await fixture.closeCase();
  });

  Future<void> localAuthEvent(WidgetTester tester) async {
    // The SDK restores a fictional local session and emits an event; no HTTP.
    await fixture.client.auth.setInitialSession(jsonEncode(fixture.session()));
    await fixture.flush(tester);
  }

  fixture.widgetTest('privacy auth observer waits for bootstrap then watches events',
      (tester) async {
    final ready = Completer<void>();
    AppBootstrap.initialize(steps: [
      (name: 'held isolated bootstrap', run: () => ready.future),
    ]);
    await fixture.mount(tester, const MyApp());
    await fixture.flush(tester);
    final beforeReady = protection.documentationGeneration;
    await localAuthEvent(tester);
    expect(protection.documentationGeneration, beforeReady,
        reason: 'do not observe an unfinished auth foundation');
    ready.complete();
    await fixture.flush(tester);
    final afterReady = protection.documentationGeneration;
    await localAuthEvent(tester);
    expect(protection.documentationGeneration, greaterThan(afterReady),
        reason: 'auth changes must still revoke documentation permission');
    expect(tester.takeException(), isNull);
  });

  fixture.widgetTest('failed client bootstrap keeps the terminal startup safe',
      (tester) async {
    SupabaseService.debugClientAvailableOverride = false;
    await AppBootstrap.initialize(steps: [
      (name: 'isolated failed client', run: () async => throw StateError('fixture')),
    ]);
    await fixture.mount(tester, const MyApp());
    await tester.pump(const Duration(seconds: 3));
    await fixture.flush(tester);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.textContaining('Unable to initialize FieldSync.'), findsOneWidget);
    final before = protection.documentationGeneration;
    await localAuthEvent(tester);
    expect(protection.documentationGeneration, before,
        reason: 'a missing client must not attach an auth observer');
    expect(tester.takeException(), isNull);
  });

  fixture.widgetTest('disposed startup never attaches a late auth observer',
      (tester) async {
    final ready = Completer<void>();
    AppBootstrap.initialize(steps: [
      (name: 'held isolated bootstrap', run: () => ready.future),
    ]);
    await fixture.mount(tester, const MyApp());
    await fixture.flush(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await fixture.flush(tester);
    final disposed = protection.documentationGeneration;
    ready.complete();
    await fixture.flush(tester);
    await localAuthEvent(tester);
    expect(protection.documentationGeneration, disposed);
    expect(tester.takeException(), isNull);
  });

  for (final skip in [false, true]) {
    fixture.widgetTest('pending native privacy keeps public startup visible: skip=$skip',
        (tester) async {
      await SecurePrefsService.setSoftLoggedOut(true);
      await AuthService.loadSoftLogoutState();
      final acknowledged = Completer<void>();
      final protection = ScreenProtectionService(
        applyProtection: (secure) => secure ? acknowledged.future : Future.value(),
      );
      addTearDown(protection.dispose);
      await fixture.mount(tester, ScreenProtectionHost(
        protection: protection, child: const SplashScreen(),
      ));
      await tester.pump(const Duration(seconds: 3));
      await fixture.flush(tester);
      if (skip) {
        await tester.tap(find.byKey(const ValueKey('splash-skip')));
      } else {
        await tester.pump(Duration(microseconds: (9.9 *
            FieldSyncCinematicTimeline.playbackDuration.inMicroseconds /
            FieldSyncCinematicTimeline.totalSeconds - 3e6).round()));
      }
      await fixture.flush(tester);
      expect(protection.mustObscure, isTrue,
          reason: 'the native security acknowledgment is still mandatory');
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Protected screen'), findsNothing,
          reason: 'a hidden Login must not replace the public animation');
      expect(find.byKey(const ValueKey('splash-skip')), findsOneWidget,
          reason: 'skip cannot release protected content before acknowledgment');
      await tester.pump(const Duration(milliseconds: 1800));
      await fixture.flush(tester);
      final scene = tester.widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((widget) => widget.painter)
          .whereType<FieldSyncCinematicScenePainter>().single;
      expect(scene.time.value,
          lessThanOrEqualTo(FieldSyncCinematicTimeline.mountStartSeconds),
          reason: 'hold the public composition, never show a blank private page');
      acknowledged.complete();
      await fixture.flush(tester);
      await tester.pump(const Duration(seconds: 5));
      await fixture.flush(tester);
      expect(protection.appliedProtection, isTrue);
      expect(find.byKey(const ValueKey('splash-skip')), findsNothing);
      expect(find.byKey(const ValueKey('privacy-curtain')), findsNothing);
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  }

  for (final outcome in ['success', 'cancel', 'error']) {
    fixture.widgetTest('biometric prompt does not flash a privacy page: $outcome',
        (tester) async {
      final prompt = Completer<bool>();
      fixture.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/local_auth'), (call) async {
          if (call.method == 'authenticate') return prompt.future;
          if (call.method == 'getAvailableBiometrics') return ['fingerprint'];
          return true;
        },
      );
      await fixture.mount(tester, const ScreenProtectionHost(
        child: SensitiveScreen(child: Scaffold(body: Text('Fictional secured form'))),
      ));
      await fixture.flush(tester);
      bool? authenticated;
      BiometricService.authenticate(reason: 'Isolated verification')
          .then((value) => authenticated = value);
      addTearDown(() {
        if (!prompt.isCompleted) prompt.complete(false);
        fixture.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      });
      await fixture.flush(tester);
      fixture.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await fixture.flush(tester);
      expect(protection.requiresProtection, isTrue);
      expect(protection.appliedProtection, isTrue,
          reason: 'a system prompt never disables native screenshot security');
      expect(protection.mustObscure, isFalse,
          reason: 'only the active OS prompt may account for inactive here');
      expect(find.byKey(const ValueKey('privacy-curtain')), findsNothing);
      for (final state in [AppLifecycleState.hidden, AppLifecycleState.paused]) {
        // The binding stops rendering in hidden/paused. Drive the same policy
        // callback directly so its prepared background cover can be inspected.
        protection.didChangeAppLifecycleState(state);
        await fixture.flush(tester);
        expect(protection.mustObscure, isTrue,
            reason: 'a real app switch remains private even during sticky auth');
        expect(find.byKey(const ValueKey('privacy-curtain')), findsOneWidget);
      }
      fixture.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await fixture.flush(tester);
      if (outcome == 'error') {
        prompt.completeError(PlatformException(code: 'fixture-cancelled'));
      } else {
        prompt.complete(outcome == 'success');
      }
      await fixture.flush(tester);
      expect(authenticated, outcome == 'success');
      fixture.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await fixture.flush(tester);
      expect(protection.mustObscure, isTrue,
          reason: 'success, cancel and errors must all clear the prompt exemption');
      fixture.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await fixture.flush(tester);
      expect(tester.takeException(), isNull);
    });
  }
}
