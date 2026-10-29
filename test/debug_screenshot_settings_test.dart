import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:imaps_fieldsync/core/services/app_bootstrap.dart';
import 'package:imaps_fieldsync/core/widgets/sensitive_screen.dart';
import 'package:imaps_fieldsync/main.dart';
import 'package:imaps_fieldsync/modules/auth_startup/screens/security_settings_screen.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/screen_protection_service.dart';

import 'support/offline_reliability_fixture.dart';

void main() {
  const demoPin =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
  final fixture = OfflineReliabilityFixture();
  final protection = ScreenProtectionService.instance;
  setUpAll(fixture.initialize);
  setUp(() async {
    AppBootstrap.resetForTests();
    await fixture.reset();
  });
  tearDown(() async {
    AppBootstrap.resetForTests();
    // The singleton carries static capture flags; never leak a grant.
    protection.revokeQaDocumentation();
    await fixture.closeCase();
  });

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

  fixture.widgetTest('a verified demo identity that is not runtime-ready '
      'stays denied and protected', (tester) async {
    // Identity granted, but the live attestation (device/package/signature)
    // is unavailable in this environment, so activation must stay closed.
    expect(
      await protection.grantQaDocumentation(
        debugMode: true,
        onAndroid: true,
        qaPreview: true,
        flavor: 'demo',
        pin: demoPin,
        packageName: ScreenProtectionService.demoPackageName,
        buildSignature: demoPin,
      ),
      isTrue,
    );
    await fixture.mount(tester, ScreenProtectionHost(
      child: SecuritySettingsScreen(profile: UserProfile.fromMap(offlineProfile)),
    ));
    await fixture.flush(tester);
    final control = find.byKey(const ValueKey('demo-screenshot-switch'));
    expect(control, findsOneWidget);
    await tester.ensureVisible(control);
    await tester.tap(control);
    await tester.pumpAndSettle();
    final enable = find.widgetWithText(FilledButton, 'Enable demo screenshots');
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(enable);
    await tester.pumpAndSettle();
    // Fail-closed: no capture session, native protection still on.
    expect(protection.isDocumentationActive, isFalse);
    expect(protection.appliedProtection, isTrue);
    expect(await protection.beginDocumentation(), isFalse);
    expect(tester.takeException(), isNull);
  });

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
