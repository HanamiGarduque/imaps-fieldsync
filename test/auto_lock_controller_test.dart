import 'dart:ui' show AppLifecycleState;

import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/auto_lock_controller.dart';

import 'support/auto_lock_test_support.dart';

void main() {
  group('AutoLockController', () {
    late FakeAutoLockClock clock;
    late AutoLockController controller;
    late LockGate gate;

    setUp(() {
      clock = FakeAutoLockClock();
      controller = AutoLockController(
        now: () => clock.current,
        timerFactory: clock.create,
      );
      gate = LockGate();
    });

    tearDown(() => controller.stop());

    void start({
      int minutes = 1,
      bool requireOnOpen = false,
      bool biometricReady = true,
    }) {
      controller.start(
        policy: AutoLockPolicy(
          requireOnOpen: requireOnOpen,
          minutes: minutes,
          biometricReady: biometricReady,
        ),
        onLockRequested: gate.request,
      );
    }

    test('locks after exactly one minute of foreground inactivity', () {
      start(minutes: 1);

      clock.advance(const Duration(seconds: 59));
      expect(gate.count, 0);

      clock.advance(const Duration(seconds: 1));
      expect(gate.count, 1);
      expect(controller.isLocked, isTrue);
    });

    test('regular activity keeps postponing the lock', () {
      start(minutes: 1);

      clock.advance(const Duration(seconds: 50));
      controller.recordActivity();

      clock.advance(const Duration(seconds: 50));
      expect(gate.count, 0);

      clock.advance(const Duration(seconds: 10));
      expect(gate.count, 1);
    });

    test('30 seconds in background at one minute does not lock', () {
      start(minutes: 1);

      controller.handleLifecycle(AppLifecycleState.paused);
      clock.advance(const Duration(seconds: 30));
      controller.handleLifecycle(AppLifecycleState.resumed);
      expect(gate.count, 0);

      clock.advance(const Duration(seconds: 29));
      expect(gate.count, 0);

      clock.advance(const Duration(seconds: 1));
      expect(gate.count, 1);
    });

    test('61 seconds in background locks on resume', () {
      start(minutes: 1);

      controller.handleLifecycle(AppLifecycleState.paused);
      clock.advance(const Duration(seconds: 61));
      controller.handleLifecycle(AppLifecycleState.resumed);

      expect(gate.count, 1);
    });

    test('foreground and background inactivity accumulate at ten minutes', () {
      start(minutes: 10);

      clock.advance(const Duration(minutes: 9));
      expect(gate.count, 0);

      controller.handleLifecycle(AppLifecycleState.paused);
      clock.advance(const Duration(minutes: 2));
      controller.handleLifecycle(AppLifecycleState.resumed);

      expect(gate.count, 1);
    });

    test('successful unlock rearms a full idle period', () async {
      start(minutes: 1);
      clock.advance(const Duration(minutes: 1));
      expect(gate.count, 1);

      await gate.release();
      expect(controller.isLocked, isFalse);

      clock.advance(const Duration(seconds: 59));
      expect(gate.count, 1);

      clock.advance(const Duration(seconds: 1));
      expect(gate.count, 2);
    });

    test(
      'slow authentication cannot permanently disable future locks',
      () async {
        start(minutes: 1);
        clock.advance(const Duration(minutes: 1));
        expect(gate.count, 1);

        clock.advance(const Duration(minutes: 15));
        expect(gate.count, 1);

        await gate.release();
        clock.advance(const Duration(seconds: 59));
        expect(gate.count, 1);

        clock.advance(const Duration(seconds: 1));
        expect(gate.count, 2);
      },
    );

    test(
      'require-on-open off still idles but does not lock on short resume',
      () {
        start(minutes: 5, requireOnOpen: false);

        clock.advance(const Duration(seconds: 30));
        controller.handleLifecycle(AppLifecycleState.paused);
        clock.advance(const Duration(seconds: 30));
        controller.handleLifecycle(AppLifecycleState.resumed);
        expect(gate.count, 0);

        clock.advance(const Duration(minutes: 4));
        expect(gate.count, 1);
      },
    );

    test('require-on-open on locks on any background resume', () {
      start(minutes: 10, requireOnOpen: true);

      controller.handleLifecycle(AppLifecycleState.paused);
      clock.advance(const Duration(seconds: 1));
      controller.handleLifecycle(AppLifecycleState.resumed);

      expect(gate.count, 1);
    });

    test('never disables idle lock but keeps opening lock', () {
      start(minutes: 0, requireOnOpen: true);

      clock.advance(const Duration(hours: 1));
      expect(gate.count, 0);

      controller.handleLifecycle(AppLifecycleState.paused);
      controller.handleLifecycle(AppLifecycleState.resumed);
      expect(gate.count, 1);
    });

    test('never with opening lock off does not lock at all', () {
      start(minutes: 0, requireOnOpen: false);

      clock.advance(const Duration(days: 1));
      controller.handleLifecycle(AppLifecycleState.paused);
      controller.handleLifecycle(AppLifecycleState.resumed);

      expect(gate.count, 0);
    });

    test('immediately locks on resume, never on a foreground timer', () {
      start(minutes: -1);

      clock.advance(const Duration(hours: 5));
      expect(gate.count, 0);

      controller.handleLifecycle(AppLifecycleState.paused);
      controller.handleLifecycle(AppLifecycleState.resumed);
      expect(gate.count, 1);
    });

    test('exact thresholds lock at one, five and ten minutes', () {
      for (final minutes in <int>[1, 5, 10]) {
        final localClock = FakeAutoLockClock();
        final localController = AutoLockController(
          now: () => localClock.current,
          timerFactory: localClock.create,
        );
        final localGate = LockGate();
        addTearDown(localController.stop);
        localController.start(
          policy: AutoLockPolicy(
            requireOnOpen: false,
            minutes: minutes,
            biometricReady: true,
          ),
          onLockRequested: localGate.request,
        );

        localClock.advance(
          Duration(minutes: minutes) - const Duration(milliseconds: 1),
        );
        expect(
          localGate.count,
          0,
          reason: '$minutes minute threshold fired early',
        );

        localClock.advance(const Duration(milliseconds: 1));
        expect(
          localGate.count,
          1,
          reason: '$minutes minute threshold did not fire',
        );
      }
    });

    test('stop cancels the timer and clears the session timestamp', () {
      start(minutes: 1);
      clock.advance(const Duration(seconds: 30));

      controller.stop();
      expect(controller.isActive, isFalse);
      expect(controller.lastActivityAt, isNull);

      clock.advance(const Duration(hours: 1));
      expect(gate.count, 0);

      start(minutes: 1);
      clock.advance(const Duration(minutes: 1));
      expect(gate.count, 1);
    });

    test('does not request overlapping locks', () {
      start(minutes: 1);
      clock.advance(const Duration(minutes: 1));
      expect(gate.count, 1);

      clock.advance(const Duration(minutes: 5));
      expect(gate.count, 1);

      controller.handleLifecycle(AppLifecycleState.paused);
      controller.handleLifecycle(AppLifecycleState.resumed);
      expect(gate.count, 1);
    });

    test('inactive lifecycle is not treated as a background event', () {
      start(minutes: 1);

      clock.advance(const Duration(seconds: 30));
      controller.handleLifecycle(AppLifecycleState.inactive);
      clock.advance(const Duration(seconds: 30));

      expect(gate.count, 1);
    });

    test('inactive does not trigger an opening lock', () {
      start(minutes: 0, requireOnOpen: true);

      controller.handleLifecycle(AppLifecycleState.inactive);
      controller.handleLifecycle(AppLifecycleState.resumed);

      expect(gate.count, 0);
    });

    test('activity while locked is ignored', () async {
      start(minutes: 1);
      clock.advance(const Duration(minutes: 1));
      final before = controller.lastActivityAt;

      controller.recordActivity();
      expect(controller.lastActivityAt, before);

      await gate.release();
      expect(controller.isLocked, isFalse);
    });

    test('activity during a pause transition does not erase background time', () {
      start(minutes: 1);
      clock.advance(const Duration(seconds: 30));
      controller.handleLifecycle(AppLifecycleState.paused);

      controller.recordActivity();
      clock.advance(const Duration(seconds: 31));
      controller.handleLifecycle(AppLifecycleState.resumed);

      expect(gate.count, 1);
    });

    test('policy changes are applied without rereading secure storage', () {
      start(minutes: 1);
      clock.advance(const Duration(seconds: 30));

      controller.updatePolicy(
        const AutoLockPolicy(
          requireOnOpen: false,
          minutes: 5,
          biometricReady: true,
        ),
      );
      clock.advance(const Duration(seconds: 30));
      expect(gate.count, 0);

      clock.advance(const Duration(minutes: 4));
      expect(gate.count, 1);
    });

    test('turning idle lock off cancels the pending timer', () {
      start(minutes: 1);
      clock.advance(const Duration(seconds: 30));

      controller.updatePolicy(
        const AutoLockPolicy(
          requireOnOpen: false,
          minutes: 0,
          biometricReady: true,
        ),
      );
      clock.advance(const Duration(hours: 1));

      expect(gate.count, 0);
    });

    test('system image-picker pause/resume locks when opening protection is on', () {
      start(minutes: 1, requireOnOpen: true);
      controller.handleLifecycle(AppLifecycleState.paused);
      clock.advance(const Duration(seconds: 2));
      controller.handleLifecycle(AppLifecycleState.resumed);

      expect(gate.count, 1);
    });

    test('system image-picker pause/resume does not idle-lock on a quick return', () {
      start(minutes: 1);
      controller.handleLifecycle(AppLifecycleState.paused);
      clock.advance(const Duration(seconds: 2));
      controller.handleLifecycle(AppLifecycleState.resumed);

      expect(gate.count, 0);
    });

    test('secure fallback keeps opening and idle locks enabled', () async {
      const fallback = AutoLockPolicy.secureFallback();
      expect(fallback.requireOnOpen, isTrue);
      expect(fallback.minutes, 1);
      expect(fallback.biometricReady, isTrue);
      expect(fallback.canLock, isTrue);
      expect(fallback.locksOnResume, isTrue);

      controller.start(policy: fallback, onLockRequested: gate.request);
      clock.advance(const Duration(seconds: 59));
      expect(gate.count, 0);
      clock.advance(const Duration(seconds: 1));
      expect(gate.count, 1);
      await gate.release();
    });

    test('policy load read failure uses the secure fallback', () async {
      final policy = await AutoLockPolicy.loadWith(
        () async => throw StateError('secure storage unavailable'),
      );

      expect(policy.requireOnOpen, isTrue);
      expect(policy.minutes, 1);
      expect(policy.biometricReady, isTrue);
      expect(policy.canLock, isTrue);
    });

    test('does not lock when no biometric unlock is available', () {
      start(minutes: 1, biometricReady: false);

      clock.advance(const Duration(hours: 1));
      controller.handleLifecycle(AppLifecycleState.paused);
      controller.handleLifecycle(AppLifecycleState.resumed);

      expect(gate.count, 0);
    });
  });
}
