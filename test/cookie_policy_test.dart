import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/profile_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/terms_privacy_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://cookie-policy-test.invalid',
      publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });

  tearDownAll(() async => Supabase.instance.dispose());

  final profile = UserProfile.fromMap({
    'id': 'cookie-policy-test',
    'full_name': 'Cookie Policy Fixture',
    'role': 'inspector',
  });

  Future<void> openTile(WidgetTester tester, String title) async {
    await tester.pumpWidget(MaterialApp(home: ProfileScreen(profile: profile)));
    await tester.pumpAndSettle();
    final tile = find.text(title);
    await tester.scrollUntilVisible(
      tile,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
  }

  testWidgets('Profile Cookie Policy tile opens the cookie document', (
    tester,
  ) async {
    await openTile(tester, 'Cookie Policy');
    expect(find.byType(TermsPrivacyScreen), findsOneWidget);
    expect(find.text('1. What Cookies Are'), findsOneWidget);
    expect(
      find.textContaining('does not store browser cookies'),
      findsOneWidget,
      reason: 'The mobile app must not claim to set browser cookies.',
    );
    expect(find.text('1. Authorized Use & Municipal Purpose'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('5. Questions & Inquiries'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('5. Questions & Inquiries').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Profile Privacy Policy tile opens the privacy document', (
    tester,
  ) async {
    await openTile(tester, 'Privacy Policy');
    expect(find.text('1. Information We Collect & Process'), findsOneWidget);
    expect(find.text('1. Authorized Use & Municipal Purpose'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legal segments switch across terms, privacy and cookies', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: TermsPrivacyScreen()));
    await tester.pumpAndSettle();
    expect(find.text('1. Authorized Use & Municipal Purpose'), findsOneWidget);

    await tester.tap(find.text('Cookie Policy').first);
    await tester.pumpAndSettle();
    expect(find.text('1. What Cookies Are'), findsOneWidget);
    expect(find.text('1. Authorized Use & Municipal Purpose'), findsNothing);

    await tester.tap(find.text('Privacy Policy').first);
    await tester.pumpAndSettle();
    expect(find.text('1. Information We Collect & Process'), findsOneWidget);
    expect(find.text('1. What Cookies Are'), findsNothing);

    await tester.tap(find.text('Terms of Use').first);
    await tester.pumpAndSettle();
    expect(find.text('1. Authorized Use & Municipal Purpose'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
