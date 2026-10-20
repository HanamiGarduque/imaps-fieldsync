import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:imaps_fieldsync/core/widgets/fieldsync_brand.dart';
import 'package:imaps_fieldsync/modules/profile_settings/models/faq_data.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/about_insight_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/help_faq_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/policy_document_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/policy_documents.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => rootBundle.clear());

  setUpAll(() {
    // Use supplied real fonts for acceptance, or the offline SDK fixture.
    GoogleFonts.config.allowRuntimeFetching = false;
    final directory = Directory(
      '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts',
    );
    final font = ByteData.sublistView(
      directory
          .listSync()
          .whereType<File>()
          .firstWhere((file) => file.path.endsWith('.ttf'))
          .readAsBytesSync(),
    );
    final manifest = <String, Object>{};
    for (final family in ['Inter', 'Urbanist']) {
      for (final weight in [
        'Regular',
        'Medium',
        'SemiBold',
        'Bold',
        'ExtraBold',
      ]) {
        final asset = '$family-$weight.ttf';
        manifest[asset] = [
          {'asset': asset},
        ];
      }
    }
    final brand = ByteData.sublistView(
      File('assets/branding/fieldsync-logo.svg').readAsBytesSync(),
    );
    binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (
      message,
    ) async {
      final asset = const StringCodec().decodeMessage(message)!;
      if (asset == 'AssetManifest.bin') {
        return const StandardMessageCodec().encodeMessage(manifest);
      }
      if (asset == 'assets/branding/fieldsync-logo.svg') return brand;
      if (asset.startsWith('assets/policies/')) {
        return ByteData.sublistView(File(asset).readAsBytesSync());
      }
      if (!asset.endsWith('.ttf')) return null;
      final folder = Platform.environment['IMAPS_LAYOUT_FONT_DIR'];
      return folder == null ? font : ByteData.sublistView(
          File('$folder/${asset.split('-').first}.ttf').readAsBytesSync());
    });
  });
  tearDownAll(
    () => binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      null,
    ),
  );

  Future<void> pump(
    WidgetTester tester,
    Widget page,
    Size size,
    double scale,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => page),
              ),
              child: const Text('Open page'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open page'));
    await tester.pumpAndSettle();
  }

  for (final size in [
    const Size(320, 568),
    const Size(640, 240),
    const Size(1280, 800),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'Support pages are readable and navigable at $size / $scale',
        (tester) async {
          for (final page in [
            const HelpFaqScreen(),
            const PolicyDocumentScreen(document: termsAndConditionsDocument),
            const PolicyDocumentScreen(document: privacyNoticeDocument),
            const PolicyDocumentScreen(document: cookieStoragePolicyDocument),
            const AboutInsightScreen(),
          ]) {
            await pump(tester, page, size, scale);
            expect(tester.takeException(), isNull);
            final back = find.byTooltip('Back');
            expect(back, findsOneWidget);
            final backTarget = find.ancestor(
              of: back,
              matching: find.byType(IconButton),
            );
            expect(
              tester.getSize(backTarget).shortestSide,
              greaterThanOrEqualTo(48),
            );
            if (page is HelpFaqScreen) {
              final question = find.text('Why is my task blue?');
              await tester.scrollUntilVisible(
                question,
                240,
                scrollable: find.byType(Scrollable).first,
              );
              await tester.pumpAndSettle();
              await tester.tap(question);
              await tester.pumpAndSettle();
              expect(
                find.text(FaqData.categories.first.items.first.answerEn),
                findsOneWidget,
              );
            } else if (page is PolicyDocumentScreen) {
              const lastSectionsByAsset = {
                'assets/policies/terms_and_conditions.md':
                    '11. Contact and Acknowledgment',
                'assets/policies/privacy_notice.md':
                    '13. Policy Changes and Contact',
                'assets/policies/cookie_and_storage_policy.md':
                    '10. Contact and Version',
              };
              final lastSection = find.text(
                lastSectionsByAsset[page.document.assetPath]!,
              );
              final scrollable = find.byType(Scrollable).first;
              // A fixed 400px drag can skip a heading in a 120px viewport.
              final step = tester.getSize(scrollable).height / 2;
              await tester.scrollUntilVisible(
                lastSection,
                step,
                scrollable: scrollable,
                maxScrolls: 300,
              );
              await tester.pumpAndSettle();
              expect(lastSection.hitTestable(), findsOneWidget);
              final footer = find.text(
                'iMAPS FieldSync · Municipal Planning and Development Office, '
                'Rosario, Batangas',
              );
              await tester.scrollUntilVisible(
                footer,
                step,
                scrollable: scrollable,
                maxScrolls: 300,
              );
              await tester.pumpAndSettle();
              expect(footer.hitTestable(), findsOneWidget);
            } else {
              final appIcon = find.byType(FieldSyncBrand);
              expect(appIcon, findsOneWidget);
              expect(
                tester.widget<FieldSyncBrand>(appIcon).variant,
                FieldSyncBrandVariant.navy,
              );
              expect(appIcon.hitTestable(), findsOneWidget);
              expect(find.text('iMAPS:FieldSync'), findsOneWidget);
              final attribution = find.text('Rosario, Batangas');
              await tester.scrollUntilVisible(
                attribution,
                240,
                scrollable: find.byType(Scrollable).first,
              );
              await tester.pumpAndSettle();
              expect(attribution.hitTestable(), findsOneWidget);
            }
            expect(tester.takeException(), isNull);
            await tester.tap(back);
            await tester.pumpAndSettle();
            expect(find.text('Open page'), findsOneWidget);
          }
        },
      );
    }
  }

  testWidgets(
    'FAQ preserves bilingual search, category filtering and clearing',
    (tester) async {
      await pump(tester, const HelpFaqScreen(), const Size(390, 844), 1);
      final languageTarget = find.ancestor(of: find.text('English'),
          matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.button == true)).first;
      expect(tester.getSize(languageTarget).height, greaterThanOrEqualTo(48));
      await tester.enterText(find.byType(TextField), 'red pin');
      await tester.pumpAndSettle();
      expect(find.text('What is the red pin?'), findsOneWidget);
      expect(find.text('Why is my task blue?'), findsNothing);
      await tester.tap(find.text('What is the red pin?'));
      await tester.pumpAndSettle();
      expect(find.textContaining('target parcel'), findsOneWidget);
      await tester.tap(find.text('Tagalog'));
      await tester.pumpAndSettle();
      expect(find.text('Ano ang red pin?'), findsOneWidget);
      await tester.tap(find.text('Ano ang red pin?'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('lokasyon ng inspection site'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Mga Task at Kulay').first);
      await tester.tap(find.text('Mga Task at Kulay').first);
      await tester.pumpAndSettle();
      expect(find.text('Bakit kulay blue ang task ko?'), findsOneWidget);
      expect(find.text('Ano ang red pin?'), findsNothing);
      await tester.scrollUntilVisible(
        find.byType(TextField),
        -240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.byType(TextField), 'no-such-topic-123');
      await tester.pumpAndSettle();
      expect(find.text('Walang nahanap na katanungan'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Policy pages open as independent documents', (tester) async {
    for (final (document, firstSection) in [
      (termsAndConditionsDocument, '1. Purpose and Scope'),
      (privacyNoticeDocument, '1. Who This Notice Covers'),
      (cookieStoragePolicyDocument, '1. Scope: Web Cookies and Mobile Storage'),
    ]) {
      await pump(
        tester,
        PolicyDocumentScreen(document: document),
        const Size(390, 844),
        1,
      );
      expect(find.byType(PolicyDocumentScreen), findsOneWidget);
      final section = find.text(firstSection);
      await tester.scrollUntilVisible(
        section,
        320,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(section.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Open page'), findsOneWidget);
    }
  });
}
