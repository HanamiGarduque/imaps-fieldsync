import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/navigation/main_shell_screen.dart';
import 'package:imaps_fieldsync/core/services/app_bootstrap.dart';
import 'package:imaps_fieldsync/core/services/auth_failure.dart';
import 'package:imaps_fieldsync/core/services/auth_service.dart';
import 'package:imaps_fieldsync/core/services/supabase_service.dart';
import 'package:imaps_fieldsync/modules/auth_startup/screens/splash_screen.dart';

import 'support/offline_reliability_fixture.dart';

/// T2/T3.5 gate coverage: the splash session decision waits for the actual
/// bootstrap result. The eight-second boundary is a status threshold only —
/// it never releases the gate — and interactive login mounts only when the
/// Supabase foundation is genuinely usable: the client exists, and after a
/// FAILED bootstrap the Supabase step itself completed.
void main() {
  final fixture = OfflineReliabilityFixture();
  setUpAll(fixture.initialize);
  setUp(() {
    AppBootstrap.resetForTests();
    SupabaseService.debugClientAvailableOverride = null;
  });
  setUp(fixture.reset);
  tearDown(() {
    AppBootstrap.resetForTests();
    SupabaseService.debugClientAvailableOverride = null;
  });
  tearDown(fixture.closeCase);

  Future<void> advance(WidgetTester tester, Duration elapsed) async {
    await tester.pump(elapsed);
    await fixture.flush(tester);
  }

  // These tests measure bootstrap/session safety, not optional film duration.
  // A skip only removes presentation and must never release the real gate.
  Future<void> mountStartup(WidgetTester tester) async {
    await fixture.mount(tester, const SplashScreen());
    await tester.tap(find.byKey(const ValueKey('splash-skip')));
    await fixture.flush(tester);
  }

  BootstrapStep stubSupabaseStep({Future<void> Function()? run}) =>
      (name: AppBootstrap.supabaseStep, run: run ?? () async {});

  // ── Scenario 1: normal completion before the eight-second boundary ──────

  fixture.widgetTest(
      'a still-running bootstrap holds the session decision past the three-second minimum',
      (tester) async {
    // The fixture starts with a retained owner session: without the gate,
    // the offline startup path would deliver its destination as soon as the
    // three-second minimum elapsed.
    final bootstrapGate = Completer<void>();
    AppBootstrap.initialize(steps: [
      (name: 'held-open', run: () => bootstrapGate.future),
    ]);

    await mountStartup(tester);
    await advance(tester, const Duration(seconds: 4));
    expect(find.byType(MainShellScreen), findsNothing);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.textContaining('Still starting up'), findsNothing);

    bootstrapGate.complete();
    await fixture.flush(tester);
    // Once the real gate opens, queued navigation must stay stable.
    await advance(tester, const Duration(milliseconds: 6000));
    expect(find.byType(MainShellScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  fixture.widgetTest(
      'a bootstrap finishing before the eight-second boundary never shows the slow status',
      (tester) async {
    AppBootstrap.initialize(steps: [stubSupabaseStep()]);

    await mountStartup(tester);
    await advance(tester, const Duration(seconds: 2, milliseconds: 500));
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.textContaining('Still starting up'), findsNothing);

    await advance(tester, const Duration(seconds: 1));
    // A completed bootstrap must not later raise the slow-start status.
    await advance(tester, const Duration(milliseconds: 6400));
    expect(find.byType(MainShellScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ── Failure classification matches the auth foundation state ────────────

  fixture.widgetTest(
      'a failed bootstrap after the Supabase step routes to login with the classified message, even with a retained session',
      (tester) async {
    AppBootstrap.initialize(steps: [
      stubSupabaseStep(),
      (name: 'boom',
          run: () async => throw Exception('isolated bootstrap failure')),
    ]);

    await mountStartup(tester);
    await advance(tester, const Duration(seconds: 3));
    // The classified failure remains attached to the real Login destination.
    await advance(tester, const Duration(milliseconds: 8000));
    expect(find.byType(MainShellScreen), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text(AuthFailure.sessionRestoreFailed.message), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  fixture.widgetTest(
      'a failed bootstrap before the Supabase step holds the terminal startup state instead of mounting login',
      (tester) async {
    AppBootstrap.initialize(steps: [
      (name: 'boom',
          run: () async => throw Exception('isolated bootstrap failure')),
    ]);

    await mountStartup(tester);
    await advance(tester, const Duration(seconds: 3));
    await advance(tester, const Duration(milliseconds: 3400));
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(MainShellScreen), findsNothing);
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(
        find.textContaining('Unable to initialize FieldSync.'), findsOneWidget);
    expect(find.textContaining('Please close and reopen the app.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ── Scenario 2: beyond the boundary, no premature navigation ────────────

  fixture.widgetTest(
      'an unfinished bootstrap holds the splash past the eight-second boundary with an honest status, then routes on the real result',
      (tester) async {
    final never = Completer<void>();
    AppBootstrap.initialize(steps: [
      (name: 'hung', run: () => never.future),
    ]);

    await mountStartup(tester);
    await advance(tester, const Duration(seconds: 3));
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(MainShellScreen), findsNothing);
    expect(AppBootstrap.settled, isFalse);
    expect(find.textContaining('Still starting up'), findsNothing);

    // The eight-second boundary is a status threshold only (3 s + 5.5 s):
    // the splash announces the wait and keeps awaiting the real result.
    await advance(tester, const Duration(seconds: 5, milliseconds: 500));
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.textContaining('Still starting up'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(MainShellScreen), findsNothing);

    never.complete();
    await fixture.flush(tester);
    await advance(tester, const Duration(milliseconds: 3400));
    expect(find.byType(MainShellScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ── Scenario 3: finishing after the boundary still decides correctly ────

  fixture.widgetTest(
      'an initialization finishing at nine seconds still selects the real destination',
      (tester) async {
    final gate = Completer<void>();
    AppBootstrap.initialize(steps: [stubSupabaseStep(run: () => gate.future)]);

    await mountStartup(tester);
    await advance(tester, const Duration(seconds: 9));
    expect(find.textContaining('Still starting up'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(MainShellScreen), findsNothing);

    gate.complete();
    await fixture.flush(tester);
    await advance(tester, const Duration(milliseconds: 3400));
    expect(find.byType(MainShellScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ── Scenario 4: failures after the boundary follow classification ───────

  fixture.widgetTest(
      'a failure after the eight-second boundary without the Supabase step follows the classified terminal path',
      (tester) async {
    final gate = Completer<void>();
    AppBootstrap.initialize(steps: [
      (name: 'hung', run: () => gate.future),
      (name: 'boom',
          run: () async => throw Exception('isolated late failure')),
    ]);

    await mountStartup(tester);
    await advance(tester, const Duration(seconds: 9));
    expect(find.textContaining('Still starting up'), findsOneWidget);

    gate.complete();
    await fixture.flush(tester);
    await advance(tester, const Duration(milliseconds: 3400));
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(MainShellScreen), findsNothing);
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(
        find.textContaining('Unable to initialize FieldSync.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  fixture.widgetTest(
      'a late failure after the Supabase step still lands on the classified login',
      (tester) async {
    final gate = Completer<void>();
    AppBootstrap.initialize(steps: [
      stubSupabaseStep(),
      (name: 'hung', run: () => gate.future),
      (name: 'boom',
          run: () async => throw Exception('isolated late failure')),
    ]);

    await mountStartup(tester);
    await advance(tester, const Duration(seconds: 9));
    expect(find.textContaining('Still starting up'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);

    gate.complete();
    await fixture.flush(tester);
    await advance(tester, const Duration(milliseconds: 3400));
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text(AuthFailure.sessionRestoreFailed.message), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ── Scenario 5: no Supabase client — no LoginScreen build exception ─────

  fixture.widgetTest(
      'no Supabase client: the auth getters stay exception-free and login is never built',
      (tester) async {
    SupabaseService.debugClientAvailableOverride = false;
    AppBootstrap.initialize(steps: [
      (name: 'boom',
          run: () async => throw Exception('isolated bootstrap failure')),
    ]);

    // The exact shape LoginScreen's build reads: with no client these must
    // answer false, never trip the client assert (debug) or hit
    // LateInitializationError (release).
    expect(() => AuthService.hasLiveUnderlyingSession, returnsNormally);
    expect(AuthService.hasLiveUnderlyingSession, isFalse);
    expect(() => AuthService.isLoggedIn, returnsNormally);
    expect(AuthService.isLoggedIn, isFalse);

    await mountStartup(tester);
    await advance(tester, const Duration(seconds: 3));
    await advance(tester, const Duration(milliseconds: 3400));
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(
        find.textContaining('Unable to initialize FieldSync.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ── Scenario 6: never-started bootstrap stays safe ──────────────────────

  fixture.widgetTest(
      'a bootstrap that was never started in the isolated test default still routes without hanging',
      (tester) async {
    await mountStartup(tester);
    await advance(tester, const Duration(seconds: 3));
    await advance(tester, const Duration(milliseconds: 7000));
    expect(find.byType(MainShellScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ── Scenario 7: settled bootstrap, unusable auth foundation ─────────────

  fixture.widgetTest(
      'a settled bootstrap whose auth foundation is unusable holds the terminal state, never interactive login',
      (tester) async {
    SupabaseService.debugClientAvailableOverride = false;
    AppBootstrap.initialize(steps: [stubSupabaseStep()]);

    await mountStartup(tester);
    await advance(tester, const Duration(seconds: 3));
    await advance(tester, const Duration(milliseconds: 3400));
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(MainShellScreen), findsNothing);
    expect(
        find.textContaining('Unable to initialize FieldSync.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ── Scenario 8: disposal during pending initialization ──────────────────

  fixture.widgetTest(
      'disposing during a pending initialization leaves no timer or navigation behind',
      (tester) async {
    final never = Completer<void>();
    AppBootstrap.initialize(steps: [
      (name: 'hung', run: () => never.future),
    ]);

    await mountStartup(tester);
    await advance(tester, const Duration(seconds: 4));
    await tester.pumpWidget(const SizedBox.shrink());
    never.complete();
    await fixture.flush(tester);
    // Cross the old boundary: the cancelled status timer must stay silent.
    await advance(tester, const Duration(seconds: 6));
    expect(find.byType(SplashScreen), findsNothing);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(MainShellScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  fixture.widgetTest(
      'disposing right after the status boundary leaves no timer or navigation behind',
      (tester) async {
    final never = Completer<void>();
    AppBootstrap.initialize(steps: [
      (name: 'hung', run: () => never.future),
    ]);

    await mountStartup(tester);
    await advance(tester, const Duration(seconds: 8, milliseconds: 500));
    expect(find.textContaining('Still starting up'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    never.complete();
    await fixture.flush(tester);
    await advance(tester, const Duration(seconds: 2));
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(MainShellScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // ── Client probe units ──────────────────────────────────────────────────

  test('hasClient reports the fixture client once Supabase is initialized', () {
    expect(SupabaseService.hasClient, isTrue);
  });

  test('hasClient honours the isolated test override', () {
    SupabaseService.debugClientAvailableOverride = false;
    expect(SupabaseService.hasClient, isFalse);
  });
}
