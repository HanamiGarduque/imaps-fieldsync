import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/profile_edit_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/profile_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://profile-test.invalid',
      publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });

  tearDownAll(() async => Supabase.instance.dispose());

  final profile = UserProfile.fromMap({
    'id': 'profile-test',
    'full_name': 'Gemini  Norawit Example',
    'role': 'inspector',
  });

  testWidgets('Profile Edit input preserves multi-word names and spaces', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: ProfileEditScreen(profile: profile)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('GN'), findsOneWidget);
    final nameField = find.byType(TextField).first;
    expect(
      tester.widget<TextField>(nameField).controller!.text,
      profile.fullName,
    );

    for (final name in [
      'Juan Miguel Dela Cruz',
      'Gemini Norawit Example',
      '  Gemini  Norawit Example  ',
    ]) {
      await tester.enterText(nameField, name);
      await tester.pump();
      final entered = tester.widget<TextField>(nameField).controller!.text;
      expect(entered, name);
      expect(validateProfileFullName(entered), isNull);
      expect(normalizeProfileFullName(entered), name.trim());
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Profile header Edit opens the existing ProfileEditScreen with the stored name',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ProfileScreen(profile: profile)),
      );
      await tester.pumpAndSettle();
      expect(find.text(profile.fullName), findsOneWidget);
      expect(find.text('GN'), findsOneWidget);
      await tester.tap(find.byKey(const Key('profile-edit-button')));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileEditScreen), findsOneWidget);
      expect(
        tester
            .widget<ProfileEditScreen>(find.byType(ProfileEditScreen))
            .profile,
        same(profile),
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        profile.fullName,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.text(profile.fullName), findsOneWidget);
    },
  );

  testWidgets(
    'identity stays visible through Log Out and restores on upward scroll',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(375, 667);
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: ProfileScreen(profile: profile)),
      );
      await tester.pumpAndSettle();
      final identity = find.byType(ProfileIdentityCard);
      final expandedHeight = tester.getSize(identity).height;
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(find.text(profile.fullName).hitTestable(), findsOneWidget);
      expect(tester.getSize(identity).height, lessThan(expandedHeight));
      await tester.scrollUntilVisible(
        find.text('Log Out'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Log Out').hitTestable(), findsOneWidget);
      expect(find.text(profile.fullName).hitTestable(), findsOneWidget);
      expect(find.text('No email found').hitTestable(), findsOneWidget);
      expect(
        find.byKey(const Key('profile-edit-button')).hitTestable(),
        findsOneWidget,
      );
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 140));
      await tester.pumpAndSettle();
      expect(tester.getSize(identity).height, closeTo(expandedHeight, 0.1));
      expect(tester.takeException(), isNull);
    },
  );
}
