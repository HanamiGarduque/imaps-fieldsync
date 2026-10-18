import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/services/app_bootstrap.dart';
import 'package:imaps_fieldsync/core/services/supabase_service.dart';
import 'package:imaps_fieldsync/main.dart';
import 'package:imaps_fieldsync/modules/auth_startup/screens/splash_screen.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/screen_protection_service.dart';

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
}
