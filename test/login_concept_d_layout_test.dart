import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:imaps_fieldsync/core/theme/insight_theme.dart';
import 'package:imaps_fieldsync/core/services/app_info_service.dart';
import 'package:imaps_fieldsync/modules/auth_startup/screens/splash_screen.dart';
import 'package:imaps_fieldsync/modules/auth_startup/screens/app_resume_lock_screen.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/biometric_service.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/secure_prefs_service.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/policy_document_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/policy_documents.dart';

// Same AOSP 200% curve used by the existing Site/Home composition checks.
class _Android200TextScaler extends TextScaler {
  const _Android200TextScaler();
  @override
  double get textScaleFactor => 2;
  @override
  double scale(double fontSize) {
    const from = [8.0, 10.0, 12.0, 14.0, 18.0, 20.0, 24.0, 30.0, 100.0];
    const to = [16.0, 20.0, 24.0, 26.0, 30.0, 34.0, 36.0, 38.0, 100.0];
    if (fontSize <= from.first) return fontSize * 2;
    for (var i = 1; i < from.length; i++) {
      if (fontSize <= from[i]) {
        return to[i - 1] + (to[i] - to[i - 1]) *
            (fontSize - from[i - 1]) / (from[i] - from[i - 1]);
      }
    }
    return fontSize;
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  final secureValues = <String, String>{};
  final captureKey = GlobalKey();
  var online = true;
  var methods = <String>[];
  Completer<bool>? authentication;
  var mailOpened = false;
  var authenticationCalls = 0;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    // The package metadata fixture matches pubspec.yaml (1.0.0+1).
    PackageInfo.setMockInitialValues(appName: 'iMAPS FieldSync',
      packageName: 'com.imaps.fieldsync', version: '1.0.0', buildNumber: '1', buildSignature: '');
    await AppInfoService.initialize();
    GoogleFonts.config.allowRuntimeFetching = false;
    final fonts = Directory(
      '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts',
    );
    final fallback = fonts.listSync().whereType<File>()
        .firstWhere((file) => file.path.endsWith('.ttf')).readAsBytesSync();
    final manifest = <String, Object>{};
    for (final family in ['Inter', 'Urbanist']) {
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
        final asset = '$family-$weight.ttf';
        manifest[asset] = [{'asset': asset}];
      }
    }
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      final asset = const StringCodec().decodeMessage(message)!;
      if (asset == 'AssetManifest.bin') {
        return const StandardMessageCodec().encodeMessage(manifest);
      }
      if (asset.startsWith('assets/')) {
        return ByteData.sublistView(File(asset).readAsBytesSync());
      }
      if (!asset.endsWith('.ttf')) return null;
      final folder = Platform.environment['IMAPS_LAYOUT_FONT_DIR'];
      return ByteData.sublistView(folder == null ? fallback :
          File('$folder/${asset.split('-').first}.ttf').readAsBytesSync());
    });
    for (final weight in [FontWeight.w400, FontWeight.w500, FontWeight.w600,
      FontWeight.w700, FontWeight.w800]) {
      GoogleFonts.inter(fontWeight: weight);
      GoogleFonts.urbanist(fontWeight: weight);
    }
    await GoogleFonts.pendingFonts();
    await (FontLoader('MaterialIcons')..addFont(Future.value(
      ByteData.sublistView(File('${fonts.path}/MaterialIcons-Regular.otf').readAsBytesSync()),
    ))).load();
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final key = args['key'] as String?;
        switch (call.method) {
          case 'read': return secureValues[key];
          case 'write': secureValues[key!] = args['value'] as String; return null;
          case 'delete': secureValues.remove(key); return null;
          case 'deleteAll': secureValues.clear(); return null;
          case 'readAll': return Map<String, String>.of(secureValues);
        }
        throw StateError('Unexpected isolated secure-storage operation');
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/local_auth'), (call) async {
        if (call.method == 'getAvailableBiometrics') return methods;
        if (call.method == 'authenticate') {
          authenticationCalls++;
          return authentication?.future ?? false;
        }
        return true;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (_) async => [online ? 'wifi' : 'none'],
    );
    for (final channel in ['dev.fluttercommunity.plus/connectivity_status', 'screen_protector']) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), (_) async => null);
    }
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'), (call) async {
        if (call.method == 'launch') {
          mailOpened = (call.arguments as Map)['url'].toString().startsWith('mailto:');
        }
        return true;
      },
    );
    await Supabase.initialize(
      url: 'https://login-layout.test', publishableKey: 'isolated-test-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false,
        detectSessionInUri: false, localStorage: EmptyLocalStorage()),
      httpClient: MockClient((request) async {
        expect(request.url.host, 'login-layout.test');
        expect(request.url.path, anyOf('/auth/v1/logout',
          '/rest/v1/inspector_devices', '/rest/v1/rpc/log_security_event'));
        return http.Response('{}', 200, request: request,
          headers: {'content-type': 'application/json'});
      }),
    );
  });

  setUp(() async {
    secureValues.clear();
    online = true;
    methods = [];
    authentication = null;
    mailOpened = false;
    authenticationCalls = 0;
    await Supabase.instance.client.auth.setInitialSession(jsonEncode({
      'access_token': 'isolated-layout-token', 'refresh_token': 'isolated-layout-refresh',
      'token_type': 'bearer', 'expires_in': 3600,
      'user': {'id': 'login-layout-inspector', 'email': 'inspector@example.test',
        'app_metadata': {}, 'user_metadata': {}, 'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z'},
    }));
  });
  tearDownAll(() async {
    await Supabase.instance.dispose();
    messenger.setMockMessageHandler('flutter/assets', null);
  });

  final primary = find.widgetWithText(ElevatedButton, 'Sign in');
  final device = find.byType(OutlinedButton);
  Future<void> pumpAuth(WidgetTester tester, Widget screen, {
    Size size = const Size(390, 844), TextScaler scaler = TextScaler.noScaling,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true,
        colorScheme: const ColorScheme.light(primary: InsightTheme.blue1)),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: scaler, disableAnimations: true),
        child: RepaintBoundary(key: captureKey, child: child!),
      ),
      home: screen,
    ));
    await tester.pump(const Duration(milliseconds: 300));
    // The brand mark is an SVG (FieldSyncBrand) now. flutter_svg encodes
    // synchronously in debug/test builds, so the pumps below render it; the
    // old PNG precache went away with the app_icon.png branding images.
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
  }
  Future<void> pumpLogin(WidgetTester tester, {
    Size size = const Size(390, 844), TextScaler scaler = TextScaler.noScaling,
    double keyboard = 0, bool enrolled = true, bool confirmed = true,
  }) async {
    if (enrolled) {
      await BiometricService.enroll();
      await SecurePrefsService.setBioConfirmed(confirmed);
    }
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true,
        colorScheme: const ColorScheme.light(primary: InsightTheme.blue1)),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: scaler, disableAnimations: true),
        child: RepaintBoundary(key: captureKey, child: child!),
      ),
      home: const LoginScreen(),
    ));
    await tester.pumpAndSettle();
    // Brand mark is SVG (FieldSyncBrand) and paints during settle.
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final folder = Platform.environment['IMAPS_LOGIN_CAPTURE_DIR'];
    if (folder == null) return;
    final boundary = captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(folder).createSync(recursive: true);
      File('$folder/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('Concept D has a neutral heading and separate compact sign-in actions', (tester) async {
    await pumpLogin(tester);
    expect(find.text('Access your workspace'), findsOneWidget);
    expect(find.text('Welcome back.'), findsNothing);
    expect(primary, findsOneWidget);
    expect(find.descendant(of: primary, matching: find.byType(Icon)), findsNothing);
    expect(tester.getSize(primary).height, inInclusiveRange(48, 52));
    expect(tester.getRect(device).top, greaterThan(tester.getRect(primary).bottom));
    expect(tester.getRect(device).top - tester.getRect(primary).bottom, lessThanOrEqualTo(12));
    final brand = tester.getRect(find.text('FieldSync'));
    expect(tester.getRect(find.text('Online')).center.dy,
      inInclusiveRange(brand.top - 32, brand.bottom));
    final form = find.ancestor(of: primary, matching: find.byType(Container)).first;
    expect(find.descendant(of: form, matching: find.text('Authorized MPDO personnel only.')), findsOneWidget);
    await capture(tester, 'concept-d-portrait');
  });

  testWidgets('First-image Login stays compact and lower with a continuous legal sentence', (tester) async {
    await pumpLogin(tester);
    final form = find.ancestor(of: primary, matching: find.byType(Container)).first;
    final rect = tester.getRect(form);
    expect(rect.height, lessThanOrEqualTo(430), reason: 'Compact individual form/footer spacing.');
    expect(rect.top, greaterThanOrEqualTo(320));
    expect(844 - 24 - rect.bottom, lessThanOrEqualTo(48));
    expect(tester.widget<Text>(find.text('Sign in').first).style!.fontSize, lessThanOrEqualTo(30));
    final legal = find.byKey(const ValueKey('login-legal-sentence'));
    expect(legal, findsOneWidget);
    expect(tester.widget<Text>(legal).textSpan!.toPlainText(),
      startsWith('By signing in, you agree to the '));
    for (final label in ['Terms of Use', 'Privacy Policy']) {
      expect(find.descendant(of: legal, matching: find.text(label)), findsOneWidget);
    }
    final notice = tester.getRect(find.text('Authorized MPDO personnel only.'));
    expect(notice.top - tester.getRect(legal).bottom, inInclusiveRange(0, 6));
  });

  for (final viewport in <String, Size>{'small': const Size(320, 568),
    'portrait': const Size(390, 844), 'landscape': const Size(844, 390),
    'tablet': const Size(1280, 800)}.entries) {
    for (final scale in <String, TextScaler>{'normal': TextScaler.noScaling,
      'linear200': const TextScaler.linear(2), 'android200': const _Android200TextScaler()}.entries) {
      testWidgets('Login actions and legal links reachable at ${viewport.key}/${scale.key}', (tester) async {
        await pumpLogin(tester, size: viewport.value, scaler: scale.value);
        final brand = tester.renderObject<RenderParagraph>(find.text('FieldSync'));
        final brandLines = brand.getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: 9),
        ).map((box) => box.top).toSet();
        expect(brandLines, hasLength(1), reason: 'Reflow the identity, not the brand word.');
        await capture(tester, '${viewport.key}-${scale.key}');
        for (final target in [primary, device, find.widgetWithText(TextButton, 'Terms of Use'),
          find.widgetWithText(TextButton, 'Privacy Policy')]) {
          await tester.ensureVisible(target);
          await tester.pumpAndSettle();
          expect(target.hitTestable(), findsOneWidget);
          final rect = tester.getRect(target);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(viewport.value.width));
          expect(rect.height, greaterThanOrEqualTo(target == primary || target == device ? 48 : 24));
        }
        await capture(tester, '${viewport.key}-${scale.key}-actions');
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('Keyboard leaves passcode, sign-in and legal actions scrollable', (tester) async {
    await pumpLogin(tester, keyboard: 300);
    await tester.enterText(find.byType(TextFormField).last, 'synthetic-passcode');
    for (final target in [primary, device, find.text('Privacy Policy')]) {
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      expect(target.hitTestable(), findsOneWidget);
      expect(tester.getRect(target).bottom, lessThanOrEqualTo(844 - 300));
    }
    expect(tester.takeException(), isNull);
    await capture(tester, 'keyboard');
  });

  testWidgets('Legal inline links honor text scaling exactly once', (tester) async {
    for (final size in [const Size(320, 568), const Size(390, 844)]) {
      final normalHeights = <String, double>{};
      for (final scale in [TextScaler.noScaling, const TextScaler.linear(2), const _Android200TextScaler()]) {
        await pumpLogin(tester, size: size, scaler: scale);
        for (final label in ['Terms of Use', 'Privacy Policy']) {
          final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
          final painted = MatrixUtils.transformRect(paragraph.getTransformTo(null), Offset.zero & paragraph.size);
          if (scale == TextScaler.noScaling) {
            normalHeights[label] = painted.height;
          } else {
            // Both exercised 200% curves map this 12dp legal text to 24dp.
            expect(painted.height, closeTo(normalHeights[label]! * 2, 0.5),
              reason: '$label must grow once, like its sentence, at $size/${scale.runtimeType}.');
          }
          await tester.ensureVisible(find.widgetWithText(TextButton, label));
          await tester.pumpAndSettle();
          expect(find.widgetWithText(TextButton, label).hitTestable(), findsOneWidget);
        }
      }
    }
  });

  for (final eligibility in ['first-use', 'unconfirmed', 'no-session']) {
    testWidgets('Device sign-in is absent for $eligibility', (tester) async {
      if (eligibility == 'no-session') {
        await tester.runAsync(() => Supabase.instance.client.auth.signOut(scope: SignOutScope.local));
      }
      await pumpLogin(tester, enrolled: eligibility != 'first-use', confirmed: eligibility != 'unconfirmed');
      expect(device, findsNothing);
      expect(primary, findsOneWidget);
      await capture(tester, eligibility);
    });
  }

  for (final method in <String, List<String>>{'Device Credential': [],
    'Fingerprint': ['fingerprint'], 'Face Unlock': ['face'], 'Iris Scan': ['iris']}.entries) {
    testWidgets('Separate button retains the supported ${method.key} method', (tester) async {
      methods = method.value;
      await pumpLogin(tester);
      expect(find.text('Sign in with ${method.key}'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(device).onPressed, isNotNull);
      await capture(tester, method.key.toLowerCase().replaceAll(' ', '-'));
    });
  }

  testWidgets('Passcode cooldown retains eligible device sign-in', (tester) async {
    await SecurePrefsService.setLocalPasscodeCooldownUntil(DateTime.now().add(const Duration(seconds: 30)));
    await pumpLogin(tester);
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(device).onPressed, isNotNull);
    await capture(tester, 'cooldown');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Busy guards both methods and cancellation remains recoverable', (tester) async {
    authentication = Completer<bool>();
    await pumpLogin(tester);
    await tester.ensureVisible(device);
    await tester.tap(device);
    await tester.pump();
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(device).onPressed, isNull);
    final recovery = find.widgetWithText(TextButton, 'Forgot passcode?');
    expect(tester.widget<TextButton>(recovery).onPressed, isNull);
    await capture(tester, 'busy');
    authentication!.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('Biometric authentication canceled or failed.'), findsOneWidget);
    expect(tester.widget<ElevatedButton>(primary).onPressed, isNotNull);
    await capture(tester, 'device-cancelled');
  });

  testWidgets('Saved email, passcode visibility and inline validation still work', (tester) async {
    await SecurePrefsService.setSavedEmail('inspector@example.test');
    await pumpLogin(tester);
    expect(tester.widget<TextFormField>(find.byType(TextFormField).first).controller!.text, 'inspector@example.test');
    await tester.tap(find.byTooltip('Show passcode'));
    await tester.pump();
    expect(find.byTooltip('Hide passcode'), findsOneWidget);
    await tester.ensureVisible(primary);
    await tester.tap(primary);
    await tester.pumpAndSettle();
    expect(find.text('Enter your passcode.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'invalid');
    await tester.tap(primary);
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
  });

  testWidgets('Both grouped legal links retain their actual destinations', (tester) async {
    await pumpLogin(tester);
    for (final (link, document, formalTitle) in [
      ('Terms of Use', termsAndConditionsDocument, 'Terms and Conditions'),
      ('Privacy Policy', privacyNoticeDocument, 'Privacy Notice'),
    ]) {
      await tester.ensureVisible(find.text(link));
      await tester.tap(find.text(link));
      await tester.pumpAndSettle();
      final screen =
          tester.widget<PolicyDocumentScreen>(find.byType(PolicyDocumentScreen));
      expect(screen.document, same(document));
      expect(find.text(formalTitle), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Forgot passcode retains administrator-mediated recovery', (tester) async {
    await pumpLogin(tester);
    final recovery = find.text('Forgot passcode?');
    await tester.ensureVisible(recovery);
    await tester.tap(recovery);
    await tester.pumpAndSettle();
    expect(mailOpened, isTrue);
  });

  testWidgets('Offline state keeps the supported prior-login policy visible', (tester) async {
    online = false;
    await pumpLogin(tester);
    expect(find.text('Offline'), findsOneWidget);
    expect(find.textContaining('logged in before on this device'), findsOneWidget);
    expect(tester.widget<ElevatedButton>(primary).onPressed, isNotNull);
    expect(tester.widget<OutlinedButton>(device).onPressed, isNotNull);
    await capture(tester, 'offline');
  });

  testWidgets('Approved Splash separates the main identity from readable startup metadata', (tester) async {
    await pumpAuth(tester, const SplashScreen());
    expect(find.text('Initializing field unit…'), findsOneWidget);
    expect(find.text('Municipal Planning & Zoning Office'), findsOneWidget);
    final identity = tester.getRect(find.byKey(const ValueKey('splash-brand')));
    final metadata = tester.getRect(find.byKey(const ValueKey('splash-status')));
    expect(identity.overlaps(metadata), isFalse);
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor, InsightTheme.blue2);
    await capture(tester, 'splash-portrait');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 4));
  });

  for (final viewport in <String, Size>{'small': const Size(320, 568),
    'portrait': const Size(390, 844), 'landscape': const Size(844, 390),
    'tablet': const Size(1280, 800)}.entries) {
    for (final scale in <String, TextScaler>{'normal': TextScaler.noScaling,
      'linear200': const TextScaler.linear(2), 'android200': const _Android200TextScaler()}.entries) {
      testWidgets('Splash and locked controls remain readable at ${viewport.key}/${scale.key}', (tester) async {
        await pumpAuth(tester, const SplashScreen(), size: viewport.value, scaler: scale.value);
        await capture(tester, 'splash-${viewport.key}-${scale.key}');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 4));
        methods = ['fingerprint'];
        await pumpAuth(tester, const AppResumeLockScreen(), size: viewport.value, scaler: scale.value);
        for (final control in [find.byType(ElevatedButton), find.widgetWithText(TextButton, 'Log Out')]) {
          await tester.ensureVisible(control);
          await tester.pump(const Duration(milliseconds: 300));
          expect(control.hitTestable(), findsOneWidget);
          expect(tester.getSize(control).height, greaterThanOrEqualTo(48));
        }
        expect(tester.takeException(), isNull);
        await capture(tester, 'locked-${viewport.key}-${scale.key}');
      });
    }
  }

  testWidgets('Locked screen keeps automatic prompt, non-dismissible busy state and retry', (tester) async {
    methods = ['fingerprint'];
    authentication = Completer<bool>();
    await pumpAuth(tester, const AppResumeLockScreen());
    expect(authenticationCalls, 1);
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
    expect(find.text('Your work.\nKept private.'), findsOneWidget);
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNull);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Log Out')).onPressed, isNull);
    await capture(tester, 'locked-busy');
    authentication!.complete(false);
    await tester.pumpAndSettle();
    expect(find.text("That didn't match. Try again with Fingerprint."), findsOneWidget);
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNotNull);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    expect(authenticationCalls, 2);
    await capture(tester, 'locked-retry');
  });

  testWidgets('Locked success retains cold-start replacement and resume return', (tester) async {
    for (final cold in [true, false]) {
      authentication = Completer<bool>();
      await pumpAuth(tester, Builder(builder: (context) => Scaffold(body: TextButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => AppResumeLockScreen(
          nextScreenBuilder: cold ? (_) => const Scaffold(body: Text('Cold-start workspace')) : null,
        ))), child: const Text('Existing workspace'),
      ))));
      await tester.tap(find.text('Existing workspace'));
      await tester.pump(const Duration(milliseconds: 400));
      authentication!.complete(true);
      await tester.pumpAndSettle();
      expect(find.byType(AppResumeLockScreen), findsNothing);
      expect(find.text(cold ? 'Cold-start workspace' : 'Existing workspace'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
