import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/models/user_profile.dart';

void main() {
  test('dashboard name contract preserves the complete configured value', () {
    expect(UserProfile.displayFullName('MyTofu'), 'MyTofu');
    expect(UserProfile.displayFullName('My Tofu'), 'My Tofu');
    expect(UserProfile.displayFullName('Juan Dela Cruz'), 'Juan Dela Cruz');
  });
  test('only outer whitespace is trimmed; no first-token extraction', () {
    expect(UserProfile.displayFullName('  My Tofu  '), 'My Tofu');
    expect(UserProfile.displayFullName('Juan  Dela\nCruz'), 'Juan  Dela\nCruz');
    expect(UserProfile.displayFullName('   '), 'there');
  });
  test('dashboard header uses the shared full-name helper, not whitespace split', () {
    final text = File(
      'lib/modules/analytics_dashboard/screens/home_dashboard_screen.dart',
    ).readAsStringSync();
    expect(text, contains('UserProfile.displayFullName('));
    // The removed truncation helper must stay gone; `_getInitials`'s
    // legitimate split for two-letter initials is not name display.
    expect(text, isNot(contains('_firstName(')));
    expect(text, isNot(contains("split(' ').first")));
  });
}
