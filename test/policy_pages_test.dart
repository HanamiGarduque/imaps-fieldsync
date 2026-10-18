import 'dart:convert' show LineSplitter;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:imaps_fieldsync/core/widgets/fieldsync_brand.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/secure_prefs_service.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/policy_document_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/policy_documents.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/profile_screen.dart';

/// Guards the three separately navigable policy pages supplied as DRAFT v0.9
/// (prepared October 18, 2026). The bundled markdown assets are the source of
/// truth; these tests verify routing, completeness, and that opening a policy
/// never records legal acceptance.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final secureValues = <String, String>{};

  setUp(() {
    secureValues.clear();
    rootBundle.clear();
  });

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final key = args['key'] as String?;
        switch (call.method) {
          case 'read':
            return secureValues[key];
          case 'write':
            secureValues[key!] = args['value'] as String;
            return null;
          case 'delete':
            secureValues.remove(key);
            return null;
          case 'deleteAll':
            secureValues.clear();
            return null;
          case 'readAll':
            return Map<String, String>.of(secureValues);
        }
        return null;
      },
    );
    await Supabase.initialize(
      url: 'https://policy-pages-test.invalid',
      publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });

  tearDownAll(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
    await Supabase.instance.dispose();
  });

  final profile = UserProfile.fromMap({
    'id': 'policy-pages-test',
    'full_name': 'Policy Pages Fixture',
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

  Future<void> scrollTo(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  const termsSections = [
    '1. Purpose and Scope',
    '2. Authorized Users and Access',
    '3. Responsible Use of Records',
    '4. FieldSync Inspections',
    '5. Security and Prohibited Conduct',
    '6. Availability and Connectivity',
    '7. Third-Party Services',
    '8. Privacy and Record Retention',
    '9. Ownership and Permitted Use',
    '10. Updates, Suspension, and Governing Law',
    '11. Contact and Acknowledgment',
  ];
  const privacySections = [
    '1. Who This Notice Covers',
    '2. Responsible Office and Privacy Contact',
    '3. Categories of Personal and Operational Data',
    '4. Why the Information Is Processed',
    '5. Lawful Basis and Fair Processing',
    '6. When FieldSync Uses Camera and Location',
    '7. Offline Records and Data Synchronization',
    '8. Authorized Access and Data Sharing',
    '9. Public Status Information',
    '10. Security and Incident Handling',
    '11. Retention and Disposal',
    '12. Rights of Data Subjects',
    '13. Policy Changes and Contact',
  ];
  const cookieSections = [
    '1. Scope: Web Cookies and Mobile Storage',
    '2. Essential Web Session and Security Storage',
    '3. Web Preferences, Caches, and Reports',
    '4. FieldSync Offline Storage',
    '5. Authentication and Other Device Data',
    '6. Maps and External Resources',
    '7. Analytics, Advertising, and Optional Tracking',
    '8. How Users Can Manage Storage',
    '9. Data Retention and Updates',
    '10. Contact and Version',
  ];

  test('Bundled policy assets keep all numbered sections and draft metadata', () {
    const expectedSections = {
      'assets/policies/terms_and_conditions.md': termsSections,
      'assets/policies/privacy_notice.md': privacySections,
      'assets/policies/cookie_and_storage_policy.md': cookieSections,
    };
    for (final entry in expectedSections.entries) {
      final text = File(entry.key).readAsStringSync();
      final lines = const LineSplitter().convert(text);
      final headings = lines.where((line) => line.startsWith('## ')).toList();
      expect(
        headings,
        [for (final section in entry.value) '## $section'],
        reason: '${entry.key} must keep every numbered section in order.',
      );
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].startsWith('## ')) {
          expect(
            lines
                .sublist(i + 1)
                .firstWhere((line) => line.trim().isNotEmpty, orElse: () => ''),
            isNotEmpty,
            reason: '${entry.key}: ${lines[i]} must keep its body text.',
          );
        }
      }
      // Draft identification and the legacy-vs-pending date distinction.
      expect(text, contains('DRAFT v0.9'), reason: entry.key);
      expect(text, contains('Prepared:** October 18, 2026'), reason: entry.key);
      expect(
        text,
        contains('(legacy reference only):** September 7, 2026'),
        reason: entry.key,
      );
      expect(
        text,
        contains('New policy effective date:** Pending official approval'),
        reason: entry.key,
      );
      expect(text, contains('FOR REVIEW ONLY'), reason: entry.key);
      // Verified office identification and unconfirmed contacts stay blank.
      expect(
        text,
        contains(
          'Municipal Planning and Development Office (MPDO), Municipality of Rosario, Batangas',
        ),
        reason: entry.key,
      );
      expect(text, contains('__________'), reason: entry.key);
      expect(
        text,
        contains('intentionally blank until verified'),
        reason: entry.key,
      );
    }
  });

  testWidgets('Renderer retains every word of all numbered policy sections', (
    tester,
  ) async {
    String normalized(String value) =>
        value.replaceAll(RegExp(r'\s+'), ' ').trim();

    for (final document in [
      termsAndConditionsDocument,
      privacyNoticeDocument,
      cookieStoragePolicyDocument,
    ]) {
      final source = File(document.assetPath).readAsStringSync();
      final sections = source.substring(
        source.indexOf('## '),
        source.lastIndexOf('\n---'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(children: buildPolicyDocumentBody(sections)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final rendered = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data ?? text.textSpan!.toPlainText())
          .join(' ');
      final expected = sections
          .replaceAll(RegExp(r'^## ', multiLine: true), '')
          .replaceAll('**', '');
      expect(
        normalized(rendered),
        normalized(expected),
        reason: '${document.menuLabel} must not drop or rewrite body text.',
      );
      expect(tester.takeException(), isNull);
    }
  });

  Future<void> expectDocument(
    WidgetTester tester, {
    required PolicyDocument document,
    required String tileLabel,
    required String formalTitle,
    required int formalTitleCount,
    required List<String> sections,
    required String foreignSection,
  }) async {
    await openTile(tester, tileLabel);
    final screen = tester.widget<PolicyDocumentScreen>(
      find.byType(PolicyDocumentScreen),
    );
    expect(screen.document, same(document));
    final brand = find.descendant(
      of: find.byType(PolicyDocumentScreen),
      matching: find.byType(FieldSyncBrand),
    );
    expect(brand, findsOneWidget);
    expect(
      tester.widget<FieldSyncBrand>(brand).variant,
      FieldSyncBrandVariant.navy,
    );
    expect(find.text(formalTitle), findsNWidgets(formalTitleCount));
    expect(find.text(foreignSection), findsNothing);
    // The draft banner sits above the sections and renders on entry.
    expect(find.textContaining('FOR REVIEW ONLY'), findsOneWidget);
    // Draft/version/date metadata stays visible and distinct.
    expect(
      find.text('DRAFT v0.9 — MPDO/DPO review required; not yet effective'),
      findsOneWidget,
    );
    expect(find.text('October 18, 2026'), findsOneWidget);
    expect(find.text('September 7, 2026'), findsOneWidget);
    expect(find.text('Pending official approval'), findsOneWidget);
    // Every numbered section is present and reachable.
    for (final section in sections) {
      await scrollTo(tester, find.text(section));
      expect(
        find.text(section).hitTestable(),
        findsOneWidget,
        reason: '$tileLabel: $section must stay reachable.',
      );
    }
    // Closing notice and footer remain reachable at the very end.
    final closing = find.textContaining('intentionally blank until verified');
    await scrollTo(tester, closing);
    expect(closing.hitTestable(), findsOneWidget);
    final footer = find.text(
      'iMAPS FieldSync · Municipal Planning and Development Office, '
      'Rosario, Batangas',
    );
    await scrollTo(tester, footer);
    expect(footer.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  }

  testWidgets('Terms & Conditions row opens the complete terms document', (
    tester,
  ) async {
    await expectDocument(
      tester,
      document: termsAndConditionsDocument,
      tileLabel: 'Terms & Conditions',
      formalTitle: 'Terms and Conditions',
      formalTitleCount: 1,
      sections: termsSections,
      foreignSection: '1. Who This Notice Covers',
    );
  });

  testWidgets('Privacy Policy row opens the Privacy Notice document', (
    tester,
  ) async {
    await expectDocument(
      tester,
      document: privacyNoticeDocument,
      tileLabel: 'Privacy Policy',
      formalTitle: 'Privacy Notice',
      formalTitleCount: 1,
      sections: privacySections,
      foreignSection: '1. Purpose and Scope',
    );
  });

  testWidgets(
    'Cookie & Storage Policy row opens the complete cookie document',
    (tester) async {
      await expectDocument(
        tester,
        document: cookieStoragePolicyDocument,
        tileLabel: 'Cookie & Storage Policy',
        formalTitle: 'Cookie & Storage Policy',
        // Header label and document title share the same wording.
        formalTitleCount: 2,
        sections: cookieSections,
        foreignSection: '1. Who This Notice Covers',
      );
    },
  );

  testWidgets('Opening policy pages never records legal acceptance', (
    tester,
  ) async {
    for (final acceptedVersion in <int?>[null, 1]) {
      if (acceptedVersion != null) {
        await SecurePrefsService.setAcceptedLegalVersion(acceptedVersion);
      }
      for (final document in [
        termsAndConditionsDocument,
        privacyNoticeDocument,
        cookieStoragePolicyDocument,
      ]) {
        await openTile(tester, document.menuLabel);
        expect(find.byType(PolicyDocumentScreen), findsOneWidget);
        expect(
          await SecurePrefsService.getAcceptedLegalVersion(),
          acceptedVersion,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(ProfileScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    }
  });
}
