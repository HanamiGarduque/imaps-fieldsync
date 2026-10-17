import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/navigation/main_shell_screen.dart';
import 'package:imaps_fieldsync/core/services/app_bootstrap.dart';
import 'package:imaps_fieldsync/core/services/auth_failure.dart';
import 'package:imaps_fieldsync/modules/auth_startup/screens/splash_screen.dart';

import 'support/offline_reliability_fixture.dart';

/// T2 gate coverage: the splash session decision must wait for the moved
/// service bootstrap, and a bootstrap that fails or outlives the app's
/// eight-second startup recovery budget must route on with the existing
/// classified-failure behavior instead of holding the splash.
void main() {
  final fixture = OfflineReliabilityFixture();
  setUpAll(fixture.initialize);
  setUp(() {
    AppBootstrap.resetForTests();
  });
  setUp(fixture.reset);
  tearDown(() {
    AppBootstrap.resetForTests();
  });
  tearDown(fixture.closeCase);

  Future<void> advance(WidgetTester tester, Duration elapsed) async {
    await tester.pump(elapsed);
    await fixture.flush(tester);
  }

  fixture.widgetTest(
      'a still-running bootstrap holds the session decision past the three-second minimum',
      (tester) async {
    // The fixture starts with a retained owner session: without the gate,
    // the offline startup path would already be heading to Home at ~6.3 s.
    final bootstrapGate = Completer<void>();
    AppBootstrap.initialize(steps: [
      (name: 'held-open', run: () => bootstrapGate.future),
    ]);

    await fixture.mount(tester, const SplashScreen());
    await advance(tester, const Duration(seconds: 4));
    expect(find.byType(MainShellScreen), findsNothing);
    expect(find.byType(LoginScreen), findsNothing);

    bootstrapGate.complete();
    await fixture.flush(tester);
    await advance(tester, const Duration(milliseconds: 2900));
    expect(find.byType(MainShellScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  fixture.widgetTest(
      'a failed bootstrap routes to login with the classified message, even with a retained session',
      (tester) async {
    AppBootstrap.initialize(steps: [
      (name: 'boom',
          run: () async => throw Exception('isolated bootstrap failure')),
    ]);

    await fixture.mount(tester, const SplashScreen());
    await advance(tester, const Duration(seconds: 3));
    await advance(tester, const Duration(milliseconds: 3400));
    expect(find.byType(MainShellScreen), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text(AuthFailure.sessionRestoreFailed.message), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  fixture.widgetTest(
      'an unfinished bootstrap cannot hold the splash past the recovery budget',
      (tester) async {
    final never = Completer<void>();
    AppBootstrap.initialize(steps: [
      (name: 'hung', run: () => never.future),
    ]);

    await fixture.mount(tester, const SplashScreen());
    await advance(tester, const Duration(seconds: 3));
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(MainShellScreen), findsNothing);
    expect(AppBootstrap.settled, isFalse);

    // The eight-second recovery budget expires (3 s + 5 s since mount).
    await advance(tester, const Duration(seconds: 5));
    await advance(tester, const Duration(milliseconds: 3400));
    expect(find.byType(MainShellScreen), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text(AuthFailure.sessionRestoreFailed.message), findsOneWidget);
    expect(tester.takeException(), isNull);

    never.complete();
    await fixture.flush(tester);
  });
}
