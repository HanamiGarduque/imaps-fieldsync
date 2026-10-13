import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/theme/insight_theme.dart';
import 'package:imaps_fieldsync/core/widgets/quick_actions_sheet.dart';
import 'package:imaps_fieldsync/modules/inspection/providers/inspection_provider.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/compass_preview_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/gps_verification_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/site_map_preview_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/notifications_screen.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

import 'support/site_map_http_fixture.dart';

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
  final captureKey = GlobalKey();
  final provider = InspectionProvider();
  final task = TaskItem(id: 'approved-ui-demo', parcelId: 'demo-parcel', name: 'Demonstration only',
    location: 'Rosario, Batangas — demonstration site', parcels: '1 parcel',
    status: 'assigned', inspectionNo: 'DEMO-001');
  late Database db;
  late SiteMapHttpFixture mapFixture;
  HttpOverrides? originalHttp;
  var online = true;
  var distance = 22.0;
  String? clipboard;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    originalHttp = HttpOverrides.current;
    HttpOverrides.global = mapFixture = SiteMapHttpFixture(tileDirectory: Platform.environment['IMAPS_MAP_TILE_DIR']);
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    for (final match in RegExp(r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)')
      .allMatches(File('lib/core/services/db_helper.dart').readAsStringSync())) {
      await db.execute(match.group(0)!);
    }
    DBHelper.useDatabaseForTesting(db);
    DBHelper.inspectorIdForTesting = 'approved-ui-inspector';
    GoogleFonts.config.allowRuntimeFetching = false;
    final manifest = <String, Object>{};
    for (final family in ['Inter', 'Urbanist']) {
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
        final asset = '$family-$weight.ttf';
        manifest[asset] = [{'asset': asset}];
      }
    }
    final sdk = Directory('${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts');
    final fallback = sdk.listSync().whereType<File>().firstWhere((file) => file.path.endsWith('.ttf')).readAsBytesSync();
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      final asset = const StringCodec().decodeMessage(message)!;
      if (asset == 'AssetManifest.bin') return const StandardMessageCodec().encodeMessage(manifest);
      if (asset.startsWith('assets/')) return ByteData.sublistView(File(asset).readAsBytesSync());
      if (!asset.endsWith('.ttf')) return null;
      final fonts = Platform.environment['IMAPS_LAYOUT_FONT_DIR'];
      return ByteData.sublistView(fonts == null ? fallback : File('$fonts/${asset.split('-').first}.ttf').readAsBytesSync());
    });
    for (final weight in [FontWeight.w400, FontWeight.w500, FontWeight.w600, FontWeight.w700, FontWeight.w800]) {
      GoogleFonts.inter(fontWeight: weight);
      GoogleFonts.urbanist(fontWeight: weight);
    }
    await GoogleFonts.pendingFonts();
    await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(
      File('${sdk.path}/MaterialIcons-Regular.otf').readAsBytesSync())))).load();
    for (final channel in ['screen_protector', 'flutter.baseflow.com/geolocator_updates',
      'hemanthraj/flutter_compass', 'dev.fluttercommunity.plus/connectivity_status']) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), (_) async => null);
    }
    messenger.setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (_) async => [online ? 'wifi' : 'none']);
    messenger.setMockMethodCallHandler(const MethodChannel('flutter.baseflow.com/geolocator'), (call) async {
      if (call.method == 'isLocationServiceEnabled') return true;
      if (call.method == 'checkPermission') return 3;
      if (call.method == 'getCurrentPosition') {
        return {
          'latitude': 13.8425, 'longitude': 121.1765, 'accuracy': 5.0, 'timestamp': 0,
          'altitude': 0.0, 'heading': 0.0, 'speed': 0.0, 'speed_accuracy': 0.0,
        };
      }
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    await Supabase.initialize(url: 'https://approved-ui.test', publishableKey: 'isolated-fixture-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false,
        detectSessionInUri: false, localStorage: EmptyLocalStorage()),
      httpClient: MockClient((request) async {
        if (request.url.host != 'approved-ui.test') throw StateError('Unexpected request host');
        if (request.method != 'GET' && request.url.path != '/rest/v1/rpc/distance_to_parcel_boundary') {
          throw StateError('UI fixtures must not submit an inspection');
        }
        Object response = [];
        if (request.url.path.contains('/rpc/')) response = distance;
        if (request.url.path.endsWith('/supabase_parcels')) response = {'latitude': 13.84265, 'longitude': 121.1766};
        return http.Response(jsonEncode(response), 200, request: request,
          headers: {'content-type': 'application/json'});
      }));
    await Supabase.instance.client.auth.setInitialSession(jsonEncode({
      'access_token': 'isolated-demo-token', 'refresh_token': 'isolated-demo-refresh',
      'token_type': 'bearer', 'expires_in': 3600,
      'user': {'id': 'approved-ui-inspector', 'app_metadata': {}, 'user_metadata': {},
        'aud': 'authenticated', 'created_at': '2026-01-01T00:00:00Z'},
    }));
  });

  setUp(() { online = true; distance = 22; clipboard = null; });
  tearDownAll(() async {
    final output = Platform.environment['IMAPS_UI_CAPTURE_DIR'];
    if (output != null) {
      final requests = mapFixture.requestedTiles.toList()..sort();
      File('$output/map-tile-requests.json').writeAsStringSync(jsonEncode(requests));
    }
    await Supabase.instance.dispose();
    DBHelper.useDatabaseForTesting(null);
    DBHelper.inspectorIdForTesting = null;
    await db.close();
    provider.dispose();
    HttpOverrides.global = originalHttp;
    messenger.setMockMessageHandler('flutter/assets', null);
  });

  Future<void> pumpSurface(WidgetTester tester, Widget screen, {
    Size size = const Size(390, 844), TextScaler scaler = TextScaler.noScaling,
    FakeViewPadding padding = const FakeViewPadding(top: 24, bottom: 24),
    bool sensor = true, ValueNotifier<TextScaler>? scalerController,
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 4));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.padding = padding;
    tester.view.viewPadding = padding;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: provider, child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorScheme: const ColorScheme.light(primary: InsightTheme.blue1)),
      builder: (context, child) {
        Widget content(TextScaler scale) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: scale),
          child: RepaintBoundary(key: captureKey, child: child!));
        return scalerController == null ? content(scaler) : ValueListenableBuilder<TextScaler>(
          valueListenable: scalerController, builder: (_, scale, _) => content(scale));
      },
      home: screen,
    )));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 150));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    }
    if (sensor) {
      messenger.handlePlatformMessage('hemanthraj/flutter_compass',
        const StandardMethodCodec().encodeSuccessEnvelope([123.0, 0.0, 4.0]), (_) {});
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(tester.takeException(), isNull);
  }

  Future<Uint8List> image(WidgetTester tester, {String? name, Rect? crop, Finder? target}) async {
    final boundary = target == null ? captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary
      : tester.renderObject<RenderRepaintBoundary>(target);
    return (await tester.runAsync(() async {
      final full = await boundary.toImage(pixelRatio: 1);
      ui.Image selected = full;
      if (crop != null) {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawImageRect(full, crop, Rect.fromLTWH(0, 0, crop.width, crop.height), Paint());
        final picture = recorder.endRecording();
        selected = await picture.toImage(crop.width.ceil(), crop.height.ceil());
        picture.dispose();
      }
      final output = Platform.environment['IMAPS_UI_CAPTURE_DIR'];
      if (output != null && name != null) {
        final png = await selected.toByteData(format: ui.ImageByteFormat.png);
        final file = File('$output/$name.png')..parent.createSync(recursive: true);
        file.writeAsBytesSync(png!.buffer.asUint8List());
      }
      final raw = await selected.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (selected != full) selected.dispose();
      full.dispose();
      return raw!.buffer.asUint8List();
    }))!;
  }

  final screens = <String, Widget Function()>{
    'compass': () => const StandaloneCompassScreen(),
    'gps': () => GpsVerificationScreen(task: task),
  };
  for (final screen in screens.entries) {
    for (final viewport in <String, Size>{'small': const Size(320, 568), 'portrait': const Size(390, 844),
      'landscape': const Size(844, 390), 'tablet': const Size(1280, 800)}.entries) {
      for (final scale in <String, TextScaler>{'normal': TextScaler.noScaling, '130': const TextScaler.linear(1.3),
        '200': const TextScaler.linear(2), 'android200': const _Android200TextScaler()}.entries) {
        testWidgets('Actual ${screen.key} retains readable populated details at ${viewport.key}/${scale.key}', (tester) async {
          await pumpSurface(tester, screen.value(), size: viewport.value, scaler: scale.value);
          final card = find.byKey(ValueKey('${screen.key}-details'));
          expect(card, findsOneWidget);
          final labels = screen.key == 'gps'
            ? ['Distance to site', 'GPS accuracy', 'Required ≤ 30 m', task.location]
            : ['Heading', 'Cardinal', 'Accuracy', 'Sensor · Live Device Magnetometer'];
          await image(tester, name: '${screen.key}-${viewport.key}-${scale.key}');
          for (final label in labels) {
            final text = find.descendant(of: card, matching: find.text(label));
            await tester.ensureVisible(text);
            await tester.pump(const Duration(milliseconds: 200));
            expect(text.hitTestable(), findsOneWidget, reason: '$label must not be clipped in a metric tile.');
          }
          if (screen.key == 'gps') {
            final button = find.widgetWithText(ElevatedButton, 'Confirm GPS');
            await tester.ensureVisible(button);
            expect(tester.widget<ElevatedButton>(button).onPressed, isNotNull);
            expect(tester.getSize(button).height, greaterThanOrEqualTo(52));
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('Protected face pixels are invariant while accessible readouts scale', (tester) async {
    final semantics = tester.ensureSemantics();
    for (final screen in screens.entries) {
      final scalerController = ValueNotifier<TextScaler>(TextScaler.noScaling);
      await pumpSurface(tester, screen.value(), size: const Size(1280, 800), scalerController: scalerController);
      Uint8List? original;
      for (final scale in [TextScaler.noScaling, const TextScaler.linear(2), const _Android200TextScaler()]) {
        // This SDK compares MediaQueryData via the legacy factor. Reset before
        // two different curves with the same factor, keeping fake time still.
        scalerController.value = TextScaler.noScaling;
        await tester.pump();
        scalerController.value = scale;
        await tester.pump(); // Same animation phase and sensor sample on both sides.
        final pixels = await image(tester, name: '${screen.key}-protected-face-${original == null ? 'normal' : '200'}',
          target: find.byKey(ValueKey('${screen.key}-face')));
        if (original != null) expect(pixels, original, reason: 'Scaling must not redesign protected face artwork.');
        original = pixels;
        expect(find.bySemanticsLabel(RegExp(r'Heading 123 degrees, ESE')), findsOneWidget);
        if (screen.key == 'gps') {
          expect(find.bySemanticsLabel(RegExp(r'Target bearing \d+ degrees')), findsOneWidget);
          expect(find.bySemanticsLabel(RegExp(r'^ESE$')), findsNothing,
            reason: 'The complete heading announcement already contains the cardinal direction.');
        }
        final card = find.byKey(ValueKey('${screen.key}-details'));
        final reading = find.descendant(of: card, matching: find.text('123°'));
        expect(tester.widget<Text>(reading).textScaler ?? MediaQuery.textScalerOf(tester.element(reading)), scale);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      scalerController.dispose();
    }
    semantics.dispose();
  });

  testWidgets('Missing readings remain unknown and GPS keeps the inclusive 30m boundary', (tester) async {
    await pumpSurface(tester, const StandaloneCompassScreen(), sensor: false);
    expect(find.text('Waiting'), findsOneWidget);
    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('High'), findsNothing);
    await image(tester, name: 'compass-waiting');
    for (final (meters, valid) in [(22.0, true), (30.0, true), (30.01, false), (124.0, false)]) {
      distance = meters;
      await pumpSurface(tester, GpsVerificationScreen(task: task));
      final confirm = find.widgetWithText(ElevatedButton, 'Confirm GPS');
      expect(tester.widget<ElevatedButton>(confirm).onPressed != null, valid);
      await image(tester, name: 'gps-distance-$meters');
    }
    online = false;
    await tester.runAsync(() => DBHelper.cacheJobs([{'id': task.id, 'status': 'assigned',
      'supabase_parcels': {'latitude': 13.84265, 'longitude': 121.1766}}]));
    await pumpSurface(tester, GpsVerificationScreen(task: task));
    expect(tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Confirm GPS')).onPressed, isNotNull);
    expect(find.text('Offline · Distance to cached site point'), findsOneWidget);
    await image(tester, name: 'gps-offline');
    await tester.tap(find.byTooltip('Copy device coordinates'));
    await tester.pump();
    expect(clipboard, '13°50\'33"N   121°10\'35"E');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('Standalone location panel disclosure and recenter remain clear and functional', (tester) async {
    for (final size in [const Size(390, 844), const Size(320, 568), const Size(844, 390), const Size(640, 360)]) {
      for (final scale in [TextScaler.noScaling, const TextScaler.linear(2), const _Android200TextScaler()]) {
        await pumpSurface(tester, const SiteMapPreviewScreen(), size: size, scaler: scale);
        final panel = find.byType(MapDetailPanel);
        final recenter = find.byTooltip('Recenter on your location');
        final hide = find.byTooltip('Hide location details');
        expect(panel, findsOneWidget);
        expect(hide.hitTestable(), findsOneWidget);
        expect(tester.getSize(recenter).height, greaterThanOrEqualTo(48));
        expect(tester.getRect(panel).overlaps(tester.getRect(recenter)), isFalse);
        final attribution = find.byKey(const ValueKey('quick-map-attribution'));
        expect(tester.getRect(panel).overlaps(tester.getRect(attribution)), isFalse);
        await image(tester, name: 'quick-map-${size.width.toInt()}-${scale is _Android200TextScaler ? 'android200' : scale.scale(10).round()}');
        await tester.tap(hide);
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('13.842500'), findsNothing);
        await tester.tap(find.byTooltip('Show location details'));
        await tester.pump(const Duration(milliseconds: 400));
        for (final value in ['13.842500', '121.176500', '± 5 m', '123°']) {
          await tester.ensureVisible(find.text(value));
          await tester.pump(const Duration(milliseconds: 200));
          expect(find.text(value).hitTestable(), findsOneWidget);
        }
        await tester.tap(recenter);
        await tester.pump();
        final beacon = find.byWidgetPredicate((widget) => widget.runtimeType.toString() == '_PulsingLocationBeacon');
        final marker = tester.getRect(beacon);
        for (final overlay in [panel, recenter, attribution, find.byTooltip('Back')]) {
          expect(marker.overlaps(tester.getRect(overlay)), isFalse,
            reason: 'Recenter at $size/${scale.runtimeType}: marker $marker overlaps '
              '$overlay ${tester.getRect(overlay)}.');
        }
        expect(marker.left, greaterThanOrEqualTo(0));
        expect(marker.right, lessThanOrEqualTo(size.width));
        expect(marker.top, greaterThanOrEqualTo(24));
        expect(marker.bottom, lessThanOrEqualTo(size.height - 24));
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('Notifications title and named Back share an axis at small enlarged text', (tester) async {
    for (final (size, scale) in [(const Size(390, 844), TextScaler.noScaling),
      (const Size(320, 568), const TextScaler.linear(2)), (const Size(844, 390), const TextScaler.linear(2))]) {
      await pumpSurface(tester, const NotificationsScreen(), size: size, scaler: scale);
      expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
      expect(tester.getSize(find.byTooltip('Back')).height, greaterThanOrEqualTo(48));
      await image(tester, name: 'notifications-${size.width.toInt()}-${scale.scale(10).round()}');
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Map details and recenter clear horizontal safe-area insets', (tester) async {
    for (final size in [const Size(844, 390), const Size(640, 360)]) {
      for (final padding in [const FakeViewPadding(left: 32, right: 48, top: 24, bottom: 24),
        const FakeViewPadding(left: 48, right: 32, top: 24, bottom: 24)]) {
        for (final scale in [TextScaler.noScaling, const TextScaler.linear(2), const _Android200TextScaler()]) {
          await pumpSurface(tester, const SiteMapPreviewScreen(), size: size, padding: padding, scaler: scale);
          final panel = find.byType(MapDetailPanel);
          final attribution = find.byKey(const ValueKey('quick-map-attribution'));
          for (final overlay in [panel, attribution, find.byTooltip('Hide location details')]) {
            final rect = tester.getRect(overlay);
            expect(rect.left, greaterThanOrEqualTo(padding.left), reason: '$size: $overlay $rect');
            expect(rect.right, lessThanOrEqualTo(size.width - padding.right), reason: '$size: $overlay $rect');
          }
          await tester.tap(find.byTooltip('Hide location details'));
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.text('13.842500'), findsNothing);
          await tester.tap(find.byTooltip('Show location details'));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.ensureVisible(find.text('121.176500'));
          await tester.pump();
          expect(find.text('121.176500').hitTestable(), findsOneWidget);
          await tester.tap(find.byTooltip('Recenter on your location'));
          await tester.pump();
          final beacon = tester.getRect(find.byWidgetPredicate((widget) => widget.runtimeType.toString() == '_PulsingLocationBeacon'));
          expect(beacon.left, greaterThanOrEqualTo(padding.left));
          expect(beacon.right, lessThanOrEqualTo(size.width - padding.right));
          for (final overlay in [panel, attribution, find.byTooltip('Back'), find.byTooltip('Recenter on your location')]) {
            expect(beacon.overlaps(tester.getRect(overlay)), isFalse,
              reason: '$size/${scale.runtimeType}: beacon $beacon overlaps $overlay ${tester.getRect(overlay)}');
          }
          expect(tester.takeException(), isNull);
          if (padding.right == 48 && scale is _Android200TextScaler) {
            await image(tester, name: 'quick-map-${size.width.toInt()}-notched-android200');
          }
        }
      }
    }
  });
}
