import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:imaps_fieldsync/core/services/app_bootstrap.dart';
import 'package:imaps_fieldsync/core/widgets/sensitive_screen.dart';
import 'package:imaps_fieldsync/main.dart';
import 'package:imaps_fieldsync/modules/auth_startup/screens/security_settings_screen.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/screen_protection_observer.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/screen_protection_service.dart';
import 'package:imaps_fieldsync/qa/demo_fixtures.dart';
import 'package:imaps_fieldsync/qa/demo_watermark.dart';

import 'support/offline_reliability_fixture.dart';

void main() {
  final fixture = OfflineReliabilityFixture();
  final protection = ScreenProtectionService.instance;
  late DemoFixtures demo;
  setUpAll(fixture.initialize);
  setUp(() async {
    AppBootstrap.resetForTests();
    await fixture.reset();
    await fixture.db.delete('local_jobs');
    await fixture.client.auth.setInitialSession(
      jsonEncode(DemoFixtures.session()),
    );
    // This verifies only the fictional source fixture, not native identity.
    demo = DemoFixtures.forTesting(verifyIdentity: () async => true);
  });
  tearDown(() async {
    AppBootstrap.resetForTests();
    // The singleton carries static capture flags; never leak a grant.
    protection.revokeQaDocumentation();
    await fixture.closeCase();
  });

  Future<void> mountDemoSettings(WidgetTester tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.runAsync(
      () => demo.initialize(documents: fixture.directory),
    );
    await tester.pumpWidget(
      ScreenProtectionScope(
        protection: protection,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: [ScreenProtectionObserver(protection)],
          builder: (context, child) => DemoWatermark(
            fixtures: demo,
            protection: protection,
            navigatorKey: navigatorKey,
            child: ScreenProtectionHost(
              protection: protection,
              child: child!,
            ),
          ),
          home: SecuritySettingsScreen(
            profile: UserProfile.fromMap(offlineProfile),
          ),
        ),
      ),
    );
    await fixture.flush(tester);
  }

  fixture.widgetTest('the demo switch stays hidden until demo identity is '
      'verified, and a regular call is denied', (tester) async {
    await fixture.mount(tester, ScreenProtectionHost(
      child: SecuritySettingsScreen(profile: UserProfile.fromMap(offlineProfile)),
    ));
    await fixture.flush(tester);
    // Regular app: no verified demo identity -> no capture control at all.
    expect(find.byKey(const ValueKey('demo-screenshot-switch')), findsNothing);
    expect(protection.documentationEnabled, isFalse);
    expect(await protection.beginDocumentation(), isFalse);
    expect(tester.takeException(), isNull);
  });

  fixture.widgetTest(
    'the isolated demo root stays OFF without native attestation',
    (tester) async {
      await mountDemoSettings(tester);
      expect(await tester.runAsync(() => demo.captureSourceReady), isTrue);
      final control = find.byKey(const ValueKey('demo-screenshot-switch'));
      expect(control, findsOneWidget);
      expect(
        find.text(
          'Off — capture protection is on. Enable only for fictional demo data.',
        ),
        findsOneWidget,
      );
      final toggle = tester.widget<SwitchListTile>(control);
      expect(toggle.value, isFalse);
      expect(toggle.onChanged, isNull);
      final scope = DemoCaptureScope.maybeOf(tester.element(control));
      expect(scope, isNotNull);
      expect(await scope!.beginDocumentation(), isFalse);
      expect(protection.documentationEnabled, isFalse);
      expect(protection.isDocumentationActive, isFalse);
      expect(protection.appliedProtection, isTrue);
      expect(await protection.beginDocumentation(), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  fixture.widgetTest('the real app has no global camera toggle on secured pages',
      (tester) async {
    await fixture.mount(tester, const MyApp());
    await tester.pump(const Duration(seconds: 3));
    await fixture.flush(tester);
    await tester.tap(find.byKey(const ValueKey('splash-skip')));
    await fixture.flush(tester);
    await tester.pumpAndSettle();
    expect(protection.requiresProtection, isTrue);
    expect(find.byIcon(Icons.camera_alt_outlined), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
