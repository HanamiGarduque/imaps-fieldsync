// Flutter-rendered evidence for the three separate policy pages.
//
// PNGs are written only when IMAPS_POLICY_CAPTURE_DIR is set; without it the
// tests still run their layout assertions so the file stays CI-safe.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:imaps_fieldsync/core/theme/insight_theme.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/policy_document_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/policy_documents.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/profile_screen.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final captureKey = GlobalKey();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    final materialFonts = Directory(
      '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts',
    );
    final fallbackFont = materialFonts
        .listSync()
        .whereType<File>()
        .firstWhere((file) => file.path.endsWith('.ttf'))
        .readAsBytesSync();
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
    binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (
      message,
    ) async {
      final asset = const StringCodec().decodeMessage(message)!;
      if (asset == 'AssetManifest.bin') {
        return const StandardMessageCodec().encodeMessage(manifest);
      }
      if (asset.startsWith('assets/')) {
        return ByteData.sublistView(File(asset).readAsBytesSync());
      }
      if (!asset.endsWith('.ttf')) return null;
      final folder = Platform.environment['IMAPS_LAYOUT_FONT_DIR'];
      return ByteData.sublistView(
        folder == null
            ? fallbackFont
            : File('$folder/${asset.split('-').first}.ttf').readAsBytesSync(),
      );
    });
    for (final weight in [
      FontWeight.w400,
      FontWeight.w500,
      FontWeight.w600,
      FontWeight.w700,
      FontWeight.w800,
    ]) {
      GoogleFonts.inter(fontWeight: weight);
      GoogleFonts.urbanist(fontWeight: weight);
    }
    await GoogleFonts.pendingFonts();
    await (FontLoader('MaterialIcons')..addFont(
          Future.value(
            ByteData.sublistView(
              File(
                '${materialFonts.path}/MaterialIcons-Regular.otf',
              ).readAsBytesSync(),
            ),
          ),
        ))
        .load();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (_) async => null,
    );
    await Supabase.initialize(
      url: 'https://policy-capture.test.invalid',
      publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });

  setUp(() {
    // rootBundle caches asset loads as futures. A cached future created in an
    // earlier test's fake-async zone never completes in this test's zone, so
    // every test starts with a clean asset cache.
    rootBundle.clear();
  });

  tearDownAll(() async {
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
    await Supabase.instance.dispose();
  });

  Future<void> capture(WidgetTester tester, String name) async {
    final output = Platform.environment['IMAPS_POLICY_CAPTURE_DIR'];
    if (output == null) return;
    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final frame = await boundary.toImage(pixelRatio: 2);
      final bytes = await frame.toByteData(format: ui.ImageByteFormat.png);
      Directory(output).createSync(recursive: true);
      File('$output/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      frame.dispose();
    });
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    Widget home,
    Size size, {
    TextScaler? textScaler,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: const ColorScheme.light(
            primary: InsightTheme.blue1,
            secondary: InsightTheme.blue2,
            surface: InsightTheme.surface,
            error: InsightTheme.red,
          ),
          scaffoldBackgroundColor: InsightTheme.bg,
        ),
        builder: (context, child) {
          final rendered = RepaintBoundary(key: captureKey, child: child!);
          return textScaler == null
              ? rendered
              : MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                  child: rendered,
                );
        },
        home: home,
      ),
    );
    await tester.pumpAndSettle();
    // The policy markdown resolves through the asset channel; keep pumping
    // until the document body mounts so captures and scrolling see a loaded
    // page instead of the empty pre-load frame.
    for (var i = 0; i < 20 && find.byType(Scrollable).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
    }
    expect(find.byType(Scrollable), findsWidgets);
  }

  Future<void> scrollTo(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      320,
      scrollable: find.byType(Scrollable).first,
      // At 200% text the document is far taller than the default
      // 50 x 320px of dragging can cover.
      maxScrolls: 300,
    );
    await tester.pumpAndSettle();
  }

  const documents = [
    (termsAndConditionsDocument, 'terms', '6. Availability and Connectivity'),
    (
      privacyNoticeDocument,
      'privacy',
      '7. Offline Records and Data Synchronization',
    ),
    (
      cookieStoragePolicyDocument,
      'cookie',
      '5. Authentication and Other Device Data',
    ),
  ];

  for (final (document, slug, middleSection) in documents) {
    testWidgets('Policy captures: $slug beginning, middle and bottom', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        PolicyDocumentScreen(document: document),
        const Size(390, 844),
      );
      await capture(tester, '$slug-top-390x844');
      await scrollTo(tester, find.text(middleSection));
      await capture(tester, '$slug-middle-390x844');
      final closing = find.textContaining('intentionally blank until verified');
      await scrollTo(tester, closing);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
      await tester.pumpAndSettle();
      await capture(tester, '$slug-bottom-390x844');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Policy captures: terms on a small portrait phone', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      const PolicyDocumentScreen(document: termsAndConditionsDocument),
      const Size(320, 568),
    );
    await capture(tester, 'terms-top-320x568');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Policy captures: privacy at 200% text scaling', (tester) async {
    await pumpScreen(
      tester,
      const PolicyDocumentScreen(document: privacyNoticeDocument),
      const Size(390, 844),
      textScaler: const TextScaler.linear(2),
    );
    await capture(tester, 'privacy-top-text200-390x844');
    await scrollTo(
      tester,
      find.textContaining('intentionally blank until verified'),
    );
    await capture(tester, 'privacy-bottom-text200-390x844');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Policy captures: cookie in short landscape', (tester) async {
    await pumpScreen(
      tester,
      const PolicyDocumentScreen(document: cookieStoragePolicyDocument),
      const Size(844, 390),
    );
    await capture(tester, 'cookie-top-844x390');
    await scrollTo(
      tester,
      find.textContaining('intentionally blank until verified'),
    );
    await capture(tester, 'cookie-bottom-844x390');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Policy captures: revised profile legal menu', (tester) async {
    final profile = UserProfile.fromMap({
      'id': 'policy-capture',
      'full_name': 'Policy Capture Fixture',
      'role': 'inspector',
    });
    await pumpScreen(
      tester,
      ProfileScreen(profile: profile),
      const Size(390, 844),
    );
    await scrollTo(tester, find.text('Terms & Conditions'));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
    await tester.pumpAndSettle();
    await capture(tester, 'profile-legal-menu-390x844');
    expect(tester.takeException(), isNull);
  });
}
