import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final text = File('lib/modules/auth_startup/screens/splash_screen.dart').readAsStringSync();
  test('login screen has no Terms checkbox or its state/gating', () {
    expect(text, isNot(contains('Checkbox(')));
    expect(text, isNot(contains('_acceptedTerms')));
    expect(text, isNot(contains('_needsLegalAcceptance')));
    expect(text, isNot(contains('Please acknowledge that you have read')));
  });
  test('Terms notice, links and acknowledgement persistence remain', () {
    expect(text, contains('By signing in, you agree to the '));
    expect(text, contains("'Terms of Use'"));
    expect(text, contains("'Privacy Policy'"));
    expect(text, contains('PolicyDocumentScreen('));
    expect(text, contains('termsAndConditionsDocument'));
    expect(text, contains('privacyNoticeDocument'));
    expect(text, contains('setAcceptedLegalVersion('));
  });
}
