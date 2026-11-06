import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:imaps_fieldsync/core/navigation/main_shell_screen.dart';
import 'package:imaps_fieldsync/modules/auth_startup/screens/app_resume_lock_screen.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/auto_lock_controller.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/biometric_service.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/secure_prefs_service.dart';
import 'package:imaps_fieldsync/modules/auth_startup/widgets/auto_lock_activity_host.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_coordinator.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_host.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_preferences.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_script.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/offline_reliability_fixture.dart';

void main() {
  final fixture = OfflineReliabilityFixture();
  late Completer<bool> prompt;
  var promptError = false;
  void pause() {
    fixture.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    fixture.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    fixture.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  }

  void resume() {
    if (fixture.binding.lifecycleState == AppLifecycleState.paused) {
      fixture.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    }
    if (fixture.binding.lifecycleState == AppLifecycleState.hidden) {
      fixture.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.inactive,
      );
    }
    fixture.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  setUpAll(fixture.initialize);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await fixture.reset();
    fixture.mode = 'success';
    prompt = Completer<bool>();
    promptError = false;
    fixture.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/local_auth'),
      (call) async {
        if (call.method == 'authenticate') {
          final result = await prompt.future;
          // Throw at the platform boundary, not across setUp's error zone.
          if (promptError) throw PlatformException(code: 'fixture-cancelled');
          return result;
        }
        if (call.method == 'getAvailableBiometrics') return ['fingerprint'];
        return true;
      },
    );
    await BiometricService.enroll();
    await SecurePrefsService.setBioConfirmed(true);
    await SecurePrefsService.setBioAutoLockMins(0);
  });
  tearDown(() async {
    if (!prompt.isCompleted) prompt.complete(false);
    resume();
    await fixture.closeCase();
  });
  tearDownAll(fixture.dispose);

  Future<void> settle(WidgetTester tester) async {
    await fixture.flush(tester);
    await tester.pump(const Duration(seconds: 2));
    await fixture.flush(tester);
    await tester.pumpAndSettle();
    // A replaced cold-start route can become eligible at the final frame;
    // drain its asynchronous metadata write before checking the invitation.
    await fixture.flush(tester);
    await tester.pumpAndSettle();
  }

  Future<GuideCoordinator> openSample(WidgetTester tester) async {
    await fixture.mount(
      tester,
      AutoLockActivityHost(
        child: MainShellScreen(
          profile: UserProfile.fromMap(offlineProfile),
          offlineSession: true,
        ),
      ),
    );
    await settle(tester);
    final guide = tester.widget<GuideHost>(find.byType(GuideHost)).coordinator;
    expect(guide.phase, GuidePhase.invitation);
    await guide.start(GuideLanguage.english);
    while (guide.stopIndex <
        guideStops.indexWhere((stop) => stop.id == 'G16')) {
      guide.next();
    }
    await tester.pumpAndSettle();
    return guide;
  }

  for (final outcome in ['cancel', 'error', 'unconfirmed-pop']) {
    fixture.widgetTest(
      'guide does not resume after $outcome of a required lock',
      (tester) async {
        final guide = await openSample(tester);
        pause();
        resume();
        await fixture.flush(tester);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
        expect(find.byType(AppResumeLockScreen), findsOneWidget);
        expect(guide.phase, GuidePhase.suspended);
        expect(
          find.byKey(const ValueKey('guide-active-page'), skipOffstage: false),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('guide-coach'), skipOffstage: false),
          findsNothing,
        );
        promptError = outcome == 'error';
        prompt.complete(false);
        await fixture.flush(tester);
        if (outcome == 'unconfirmed-pop') {
          Navigator.of(tester.element(find.byType(AppResumeLockScreen))).pop();
          await tester.pumpAndSettle();
          expect(find.byType(AppResumeLockScreen), findsNothing);
        } else {
          expect(find.byType(AppResumeLockScreen), findsOneWidget);
        }
        expect(guide.phase, GuidePhase.suspended);
        expect(guideStops[guide.stopIndex].id, 'G16');
      },
    );
  }

  fixture.widgetTest(
    'same-owner successful unlock resumes only after the lock controller finishes',
    (tester) async {
      final guide = await openSample(tester);
      pause();
      expect(guide.phase, GuidePhase.suspended);
      resume();
      await fixture.flush(tester);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(AutoLockController.instance.isLocked, isTrue);
      prompt.complete(true);
      await settle(tester);
      expect(AutoLockController.instance.isLocked, isFalse);
      expect(find.byType(AppResumeLockScreen), findsNothing);
      expect(guide.phase, GuidePhase.active);
      expect(guideStops[guide.stopIndex].id, 'G16');
      expect(find.byKey(const ValueKey('guide-active-page')), findsOneWidget);
    },
  );

  fixture.widgetTest(
    'inactive hides examples without requesting an extra biometric lock',
    (tester) async {
      final guide = await openSample(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(guide.phase, GuidePhase.suspended);
      await tester.pump();
      expect(find.byKey(const ValueKey('guide-active-page')), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(guide.phase, GuidePhase.active);
      expect(find.byType(AppResumeLockScreen), findsNothing);
    },
  );

  fixture.widgetTest(
    'idle lock also removes the guide before showing App Locked',
    (tester) async {
      await SecurePrefsService.setBioAutoLockMins(1);
      final guide = await openSample(tester);
      await tester.pump(const Duration(minutes: 1));
      await fixture.flush(tester);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(guide.phase, GuidePhase.suspended);
      expect(find.byType(AppResumeLockScreen), findsOneWidget);
      expect(
        find.byKey(const ValueKey('guide-coach'), skipOffstage: false),
        findsNothing,
      );
      // Finish the native call inside this test's zone before unmounting;
      // otherwise its protection reconciliation leaks into the next case.
      prompt.complete(false);
      await fixture.flush(tester);
    },
  );

  fixture.widgetTest(
    'cold-start lock never constructs the shell until an actual successful unlock',
    (tester) async {
      await fixture.mount(
        tester,
        AppResumeLockScreen(
          nextScreenBuilder: (_) => MainShellScreen(
            profile: UserProfile.fromMap(offlineProfile),
            offlineSession: true,
          ),
        ),
      );
      await fixture.flush(tester);
      expect(find.byType(GuideHost, skipOffstage: false), findsNothing);
      expect(await GuidePreferences().read(offlineInspector), isNull);
      prompt.complete(false);
      await fixture.flush(tester);
      expect(find.byType(GuideHost, skipOffstage: false), findsNothing);
      prompt = Completer<bool>()..complete(true);
      await tester.tap(find.text('Unlock with Fingerprint'));
      await settle(tester);
      expect(
        tester.widget<GuideHost>(find.byType(GuideHost)).coordinator.phase,
        GuidePhase.invitation,
      );
    },
  );
}
