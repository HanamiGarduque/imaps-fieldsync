import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/profile_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://policy-menu.test.invalid',
      publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });

  tearDownAll(() async => Supabase.instance.dispose());

  testWidgets('Profile exposes all three separate updated policy entries', (
    tester,
  ) async {
    final profile = UserProfile.fromMap({
      'id': 'policy-menu-fixture',
      'full_name': 'Policy Menu Fixture',
      'role': 'inspector',
    });
    await tester.pumpWidget(MaterialApp(home: ProfileScreen(profile: profile)));
    await tester.pumpAndSettle();
    // Profile uses lazy slivers; mount the legal menu before inspecting it.
    await tester.scrollUntilVisible(
      find.text('Privacy Policy'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    for (final label in [
      'Terms & Conditions',
      'Privacy Policy',
      'Cookie & Storage Policy',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
