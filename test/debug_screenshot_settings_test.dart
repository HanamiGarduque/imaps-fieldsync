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
  final fixture = OfflineReliabilityFixture();
  final protection = ScreenProtectionService.instance;
  setUpAll(fixture.initialize);
  setUp(() async {
    AppBootstrap.resetForTests();
    await fixture.reset();
  });
  tearDown(() async {
    AppBootstrap.resetForTests();
    await fixture.closeCase();
  });

  fixture.widgetTest('Security has a manual demo switch without a time limit',
      (tester) async {
    await fixture.mount(tester, ScreenProtectionHost(
      child: SecuritySettingsScreen(profile: UserProfile.fromMap(offlineProfile)),
    ));
    await fixture.flush(tester);
    final control = find.byKey(const ValueKey('demo-screenshot-switch'));
    expect(control, findsOneWidget);
    await tester.ensureVisible(control);
    await fixture.capture(tester, 'demo-settings-off');
    await tester.tap(control);
    await tester.pumpAndSettle();
    final enable = find.widgetWithText(FilledButton, 'Enable demo screenshots');
    expect(tester.widget<FilledButton>(enable).onPressed, isNull,
        reason: 'fictional/redacted-data confirmation is still required');
    await fixture.capture(tester, 'demo-settings-confirm');
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(enable);
    await tester.pumpAndSettle();
    expect(protection.isDocumentationActive, isTrue);
    expect(protection.appliedProtection, isFalse);
    await tester.pump(const Duration(seconds: 60));
    expect(protection.isDocumentationActive, isTrue,
        reason: 'manual capture must not expire at twenty seconds');
    await fixture.capture(tester, 'demo-settings-on');
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(builder: (_) => const SensitiveScreen(
      child: Scaffold(body: Text('Fictional inspection page')),
    )));
    await tester.pumpAndSettle();
    expect(protection.isDocumentationActive, isTrue,
        reason: 'a settings switch must work after leaving settings');
    expect(find.byIcon(Icons.camera_alt_outlined), findsNothing);
    navigator.pop();
    await tester.pumpAndSettle();
    await tester.ensureVisible(control);
    expect(tester.widget<SwitchListTile>(control).value, isTrue);
    await tester.tap(control);
    await tester.pumpAndSettle();
    expect(protection.isDocumentationActive, isFalse);
    expect(protection.appliedProtection, isTrue);
    expect(tester.widget<SwitchListTile>(control).value, isFalse);
    await fixture.capture(tester, 'demo-settings-restored');
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
