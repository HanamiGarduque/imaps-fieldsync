import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/auto_lock_controller.dart';
import 'package:imaps_fieldsync/modules/auth_startup/widgets/auto_lock_activity_host.dart';

import 'support/auto_lock_test_support.dart';

void main() {
  group('AutoLockActivityHost', () {
    late FakeAutoLockClock clock;
    late AutoLockController controller;
    late LockGate gate;

    setUp(() {
      clock = FakeAutoLockClock();
      gate = LockGate();
      controller = AutoLockController(
        now: () => clock.current,
        timerFactory: clock.create,
      );
      addTearDown(controller.stop);
    });

    void start({int minutes = 1, bool requireOnOpen = false}) {
      controller.start(
        policy: AutoLockPolicy(
          requireOnOpen: requireOnOpen,
          minutes: minutes,
          biometricReady: true,
        ),
        onLockRequested: gate.request,
      );
    }

    Future<void> pumpHost(WidgetTester tester, Widget home) {
      return tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => AutoLockActivityHost(
            controller: controller,
            child: child ?? const SizedBox.shrink(),
          ),
          home: home,
        ),
      );
    }

    testWidgets('taps on pushed inspection routes count as activity', (
      tester,
    ) async {
      start(minutes: 1);
      await pumpHost(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(
                      body: Center(child: Text('Inspection Step 1')),
                    ),
                  ),
                ),
                child: const Text('Open inspection'),
              ),
            ),
          ),
        ),
      );

      clock.advance(const Duration(seconds: 50));
      await tester.tap(find.text('Open inspection'));
      await tester.pumpAndSettle();
      expect(controller.lastActivityAt, const Duration(seconds: 50));

      clock.advance(const Duration(seconds: 50));
      expect(gate.count, 0);

      await tester.tap(find.text('Inspection Step 1'));
      await tester.pump();
      expect(controller.lastActivityAt, const Duration(seconds: 100));

      clock.advance(const Duration(seconds: 59));
      expect(gate.count, 0);

      clock.advance(const Duration(seconds: 1));
      expect(gate.count, 1);
    });

    testWidgets('typing in a pushed inspection field counts as activity', (
      tester,
    ) async {
      start(minutes: 1);
      await pumpHost(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(
                      body: Center(
                        child: TextField(
                          decoration: InputDecoration(hintText: 'Findings'),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('Open findings'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open findings'));
      await tester.pumpAndSettle();

      clock.advance(const Duration(seconds: 50));
      await tester.showKeyboard(find.byType(TextField));
      clock.advance(const Duration(seconds: 5));
      expect(controller.lastActivityAt, Duration.zero);

      await tester.enterText(find.byType(TextField), 'Cracked pavement');
      await tester.pump();
      expect(controller.lastActivityAt, const Duration(seconds: 55));

      clock.advance(const Duration(seconds: 59));
      expect(gate.count, 0);

      clock.advance(const Duration(seconds: 1));
      expect(gate.count, 1);
    });

    testWidgets('root activity listener does not consume taps', (tester) async {
      start(minutes: 1);
      var taps = 0;
      await pumpHost(
        tester,
        Scaffold(
          body: Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
              child: const SizedBox(
                width: 140,
                height: 64,
                child: Center(child: Text('Tap me')),
              ),
            ),
          ),
        ),
      );

      clock.advance(const Duration(seconds: 1));
      await tester.tap(find.text('Tap me'));

      expect(taps, 1);
      expect(controller.lastActivityAt, const Duration(seconds: 1));
      expect(controller.isLocked, isFalse);
    });

    testWidgets('host forwards paused/resumed lifecycle to the controller', (
      tester,
    ) async {
      start(minutes: 0, requireOnOpen: true);
      await pumpHost(tester, const Scaffold(body: Text('Home')));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(gate.count, 1);
    });
  });
}
