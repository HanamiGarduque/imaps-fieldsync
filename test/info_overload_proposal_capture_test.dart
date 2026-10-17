// Proposal-only capture harness for the information-overload redesign of
// Site Verification (Step 1) and GPS Verification (Step 2).
//
// PNGs are written only when IMAPS_PROPOSAL_CAPTURE_DIR is set; the
// assertions run everywhere. No request reaches a tile server, routing
// server or application backend.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/route_service.dart';
import 'package:imaps_fieldsync/core/theme/insight_theme.dart';
import 'package:imaps_fieldsync/modules/inspection/providers/inspection_provider.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/gps_verification_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/inspection_progress.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/site_map_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/widgets/rosario_boundary_overlay.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

import 'support/site_map_http_fixture.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  final captureKey = GlobalKey();
  late Database db;
  late HttpOverrides? originalHttp;
  late SiteMapHttpFixture httpFixture;
  var rpcDistance = 1600.0;
  var online = false;
  var gpsPoint = const LatLng(13.8425, 121.1765);
  var gpsAccuracy = 5.0;
  String? copiedCoordinates;
  const device = LatLng(13.8425, 121.1765);
  const target = LatLng(13.8486, 121.19);
  const offsetEnd = LatLng(13.8486, 121.189);
  final task = TaskItem(
    id: 'site-ui-fixture',
    parcelId: 'fixture-parcel',
    name: 'Demonstration',
    location:
        'Rosario, Batangas — demonstration site with a long access-road address',
    parcels: '1 parcel',
    status: 'assigned',
    inspectionNo: 'DEMO-ONLY',
  );

  Map<String, Object> positionEvent() => {
    'latitude': gpsPoint.latitude,
    'longitude': gpsPoint.longitude,
    'accuracy': gpsAccuracy,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
    'altitude': 0.0,
    'heading': 0.0,
    'speed': 0.0,
    'speed_accuracy': 0.0,
  };

  setUpAll(() async {
    originalHttp = HttpOverrides.current;
    httpFixture = SiteMapHttpFixture(
      tileDirectory: Platform.environment['IMAPS_MAP_FIXTURE_DIR'],
    );
    HttpOverrides.global = httpFixture;
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    for (final match in RegExp(
      r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)',
    ).allMatches(File('lib/core/services/db_helper.dart').readAsStringSync())) {
      await db.execute(match.group(0)!);
    }
    DBHelper.useDatabaseForTesting(db);
    DBHelper.inspectorIdForTesting = 'proposal-inspector';
    GoogleFonts.config.allowRuntimeFetching = false;
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
    final fonts = Directory(
      '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts',
    );
    final fallback = fonts.listSync().whereType<File>()
        .firstWhere((file) => file.path.endsWith('.ttf')).readAsBytesSync();
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
      return ByteData.sublistView(
        folder == null ? fallback
            : File('$folder/${asset.split('-').first}.ttf').readAsBytesSync(),
      );
    });
    for (final weight in [
      FontWeight.w400,
      FontWeight.w500,
      FontWeight.w600,
      FontWeight.w700,
    ]) {
      GoogleFonts.inter(fontWeight: weight);
      GoogleFonts.urbanist(fontWeight: weight);
    }
    await GoogleFonts.pendingFonts();
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File('${fonts.path}/MaterialIcons-Regular.otf').readAsBytesSync(),
          ),
        ),
      );
    await icons.load();
    await RosarioBoundaryLoader.shared.load();
    await Supabase.initialize(
      url: 'https://proposal-capture.test',
      publishableKey: 'isolated-fixture-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        if (request.url.host != 'proposal-capture.test') {
          throw StateError('Unexpected request host: ${request.url}');
        }
        if (request.method != 'GET' &&
            request.url.path != '/rest/v1/rpc/distance_to_parcel_boundary') {
          throw StateError('Proposal fixtures must not submit an inspection');
        }
        final Object response = request.url.path.contains('/rpc/')
            ? rpcDistance
            : {'latitude': target.latitude, 'longitude': target.longitude};
        return http.Response(
          jsonEncode(response),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await Supabase.instance.client.auth.setInitialSession(
      jsonEncode({
        'access_token': 'isolated-demo-token',
        'refresh_token': 'isolated-demo-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': 'proposal-inspector',
          'app_metadata': <String, Object>{},
          'user_metadata': <String, Object>{},
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
        },
      }),
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (call) async {
        switch (call.method) {
          case 'isLocationServiceEnabled':
            return true;
          case 'checkPermission':
            return 3;
          case 'getCurrentPosition':
            return positionEvent();
        }
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (_) async => [online ? 'wifi' : 'none'],
    );
    for (final channel in [
      'flutter.baseflow.com/geolocator_updates',
      'dev.fluttercommunity.plus/connectivity_status',
      'screen_protector',
      'hemanthraj/flutter_compass',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(channel),
        (_) async => null,
      );
    }
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedCoordinates = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
  });

  setUp(() async {
    httpFixture.routeJson = null;
    httpFixture.routeResponse = null;
    httpFixture.requestedRoutes.clear();
    httpFixture.streetTilesAvailable = true;
    online = false;
    rpcDistance = 1600;
    gpsPoint = device;
    gpsAccuracy = 5;
    copiedCoordinates = null;
    InspectionProgress.instance.reset();
    await db.delete('local_jobs');
    await db.delete('local_route_cache');
    await db.insert('local_jobs', {
      'id': task.id,
      'inspector_id': 'proposal-inspector',
      'status': 'assigned',
      'parcel_lat': target.latitude,
      'parcel_lng': target.longitude,
    });
    // Seeded here (outside the fake-async test body): the cached road stops
    // short of the target, so the map draws a dotted direct link, and the
    // old timestamp keeps the route estimate stale.
    await DBHelper.saveRouteCache(
      CachedRoute(
        jobId: task.id,
        points: const [device, offsetEnd],
        originLat: device.latitude,
        originLng: device.longitude,
        distanceMeters: 3372,
        durationSeconds: 462.7,
        fetchedAt: DateTime.utc(2026, 10, 9),
      ),
    );
  });

  tearDownAll(() async {
    HttpOverrides.global = originalHttp;
    messenger.setMockMessageHandler('flutter/assets', null);
    await Supabase.instance.dispose();
    DBHelper.useDatabaseForTesting(null);
    DBHelper.inspectorIdForTesting = null;
    await db.close();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
    }
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final output = Platform.environment['IMAPS_PROPOSAL_CAPTURE_DIR'];
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

  Future<void> mountStep1(
    WidgetTester tester,
    Size size, {
    TextScaler? textScaler,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.reset);
    final provider = InspectionProvider();
    addTearDown(provider.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            primaryColor: InsightTheme.blue1,
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
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: textScaler),
                    child: rendered,
                  );
          },
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => SiteMapScreen(task: task)),
                ),
                child: const Text('Open demonstration'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open demonstration'));
    await settle(tester);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      await tester.pump(const Duration(seconds: 2));
    });
  }

  Future<void> sendPosition(WidgetTester tester) async {
    await messenger.handlePlatformMessage(
      'flutter.baseflow.com/geolocator_updates',
      const StandardMethodCodec().encodeSuccessEnvelope(positionEvent()),
      (_) {},
    );
    await tester.pump();
  }

  Future<void> pumpGps(
    WidgetTester tester, {
    required Size size,
    TextScaler scaler = TextScaler.noScaling,
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 4));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.reset);
    final provider = InspectionProvider();
    addTearDown(provider.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: const ColorScheme.light(
              primary: InsightTheme.blue1,
            ),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: scaler),
            child: RepaintBoundary(key: captureKey, child: child!),
          ),
          home: GpsVerificationScreen(task: task),
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 150));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
    }
    messenger.handlePlatformMessage(
      'hemanthraj/flutter_compass',
      const StandardMethodCodec().encodeSuccessEnvelope([123.0, 0.0, 4.0]),
      (_) {},
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
  }

  group('GPS Verification proposal renders', () {
    testWidgets('reference card keeps essential readouts and action in view', (tester) async {
      online = true;
      rpcDistance = 21000;
      gpsAccuracy = 8;
      await pumpGps(tester, size: const Size(411, 914));
      final card = find.byKey(const ValueKey('gps-details'));
      expect(tester.getSize(card).height, lessThanOrEqualTo(280));
      expect(find.text('More details'), findsNothing);
      for (final value in ['123°', '± 8 m', 'Too far', '21 km']) {
        expect(find.descendant(of: card, matching: find.text(value)).hitTestable(), findsOneWidget);
      }
      expect(find.byTooltip('Copy device coordinates').hitTestable(), findsOneWidget);
      final button = find.widgetWithText(ElevatedButton, 'Confirm GPS');
      expect(tester.widget<ElevatedButton>(button).onPressed, isNull);
      expect(tester.getRect(button).bottom, lessThanOrEqualTo(890));
      await capture(tester, 'gps-reference-411x914');
    });

    testWidgets('reference action stays pinned on short and enlarged phones', (tester) async {
      online = true;
      rpcDistance = 22;
      for (final (size, scaler) in [
        (const Size(320, 568), TextScaler.noScaling),
        (const Size(411, 914), const TextScaler.linear(2)),
      ]) {
        await pumpGps(tester, size: size, scaler: scaler);
        final button = find.widgetWithText(ElevatedButton, 'Confirm GPS');
        final rect = tester.getRect(button);
        expect(rect.top, greaterThanOrEqualTo(24));
        expect(rect.bottom, lessThanOrEqualTo(size.height - 24));
        expect(button.hitTestable(), findsOneWidget);
        expect(tester.widget<ElevatedButton>(button).onPressed, isNotNull);
        if (scaler == TextScaler.noScaling) {
          expect(find.text('22 m').hitTestable(), findsOneWidget,
            reason: 'Short phones must still show the distance above the pinned action.');
        }
        await capture(tester, 'gps-reference-action-${size.width.toInt()}-${scaler.scale(12)}');
      }
    });

    testWidgets('outside zone on a normal phone', (tester) async {
      online = true;
      rpcDistance = 21000;
      gpsAccuracy = 8;
      await pumpGps(tester, size: const Size(411, 914));
      expect(find.text('Outside zone'), findsOneWidget);
      expect(find.text('Required ≤ 30 m'), findsOneWidget);
      expect(find.text('More details'), findsNothing);
      expect(find.text('Confirm GPS'), findsOneWidget);
      // Technical readouts must not sit in the default view anymore.
      expect(find.textContaining('Target bearing'), findsNothing);
      expect(find.textContaining('Server distance validation'), findsNothing);
      await capture(tester, 'gps-outside-411x914');
      expect(find.text('Confirm GPS').hitTestable(), findsOneWidget);
    });

    testWidgets('outside zone on a small phone', (tester) async {
      online = true;
      rpcDistance = 21000;
      gpsAccuracy = 8;
      await pumpGps(tester, size: const Size(320, 568));
      expect(find.text('Outside zone'), findsOneWidget);
      await capture(tester, 'gps-outside-320x568');
    });

    testWidgets('outside zone in landscape', (tester) async {
      online = true;
      rpcDistance = 21000;
      gpsAccuracy = 8;
      await pumpGps(tester, size: const Size(844, 390));
      expect(find.text('Outside zone'), findsOneWidget);
      await capture(tester, 'gps-outside-844x390');
    });

    testWidgets('outside zone with enlarged text', (tester) async {
      online = true;
      rpcDistance = 21000;
      gpsAccuracy = 8;
      await pumpGps(
        tester,
        size: const Size(411, 914),
        scaler: const TextScaler.linear(2),
      );
      expect(find.text('Outside zone'), findsOneWidget);
      await capture(tester, 'gps-outside-text200');
    });

    testWidgets('ready to confirm on a normal phone', (tester) async {
      online = true;
      rpcDistance = 22;
      await pumpGps(tester, size: const Size(411, 914));
      expect(find.text('Ready to confirm'), findsOneWidget);
      expect(find.text('Move within 30 m of the site to confirm.'), findsNothing);
      await capture(tester, 'gps-ready-411x914');
      expect(find.text('Confirm GPS').hitTestable(), findsOneWidget);
    });

    testWidgets('reference coordinates are inline and copy the accepted fix', (tester) async {
      online = true;
      rpcDistance = 21000;
      gpsAccuracy = 8;
      await pumpGps(tester, size: const Size(411, 914));
      expect(find.textContaining('123°'), findsOneWidget);
      expect(find.textContaining('13°50'), findsOneWidget);
      await tester.tap(find.byTooltip('Copy device coordinates'));
      await tester.pump();
      expect(copiedCoordinates, '13°50\'33"N   121°10\'35"E');
      expect(find.byTooltip('Coordinates copied'), findsOneWidget);
      await capture(tester, 'gps-coordinates-copied-411x914');
    });
  });

  group('Site Verification proposal renders', () {
    Future<void> mountLinkedStale(
      WidgetTester tester,
      Size size, {
      TextScaler? textScaler,
    }) async {
      online = false;
      await mountStep1(tester, size, textScaler: textScaler);
      expect(find.text('Site details'), findsOneWidget);
      expect(find.text('Proceed to Location').hitTestable(), findsOneWidget);
    }

    testWidgets('reference rotation hides context without replacing the map', (tester) async {
      await mountLinkedStale(tester, const Size(411, 914));
      final map = tester.state(find.byType(FlutterMap));
      for (final size in [const Size(844, 390), const Size(568, 320), const Size(411, 914)]) {
        tester.view.physicalSize = size;
        await settle(tester);
        final portrait = size.height > size.width;
        expect(find.text('Site Verification'), portrait ? findsOneWidget : findsNothing);
        expect(find.text('STEP 1 OF 6 — LOCATE TARGET', findRichText: true),
          portrait ? findsOneWidget : findsNothing);
        if (!portrait) {
          expect(find.byTooltip('Exit inspection').hitTestable(), findsOneWidget,
            reason: '$size: back ${tester.getRect(find.byTooltip('Exit inspection'))}, '
              'action ${tester.getRect(find.text('Proceed to Location'))}');
        }
        expect(tester.state(find.byType(FlutterMap)), same(map));
        expect(find.byTooltip('Fit both markers').hitTestable(), findsOneWidget);
        expect(find.text('Proceed to Location').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('reference map footer separates small attribution from bare info', (tester) async {
      await mountLinkedStale(tester, const Size(411, 914));
      final attribution = find.text('© OpenStreetMap contributors');
      final info = find.text('Map info');
      expect(tester.getRect(attribution).right + 8, lessThanOrEqualTo(tester.getRect(info).left));
      final chip = find.ancestor(of: attribution, matching: find.byType(Container)).first;
      expect(tester.getSize(chip).height, lessThanOrEqualTo(28));
      final decoratedInfo = find.ancestor(of: info, matching: find.byWidgetPredicate(
        (widget) => widget is Container && widget.decoration != null));
      expect(decoratedInfo, findsNothing, reason: 'Map info has no painted container.');
      expect(info.hitTestable(), findsOneWidget);
      await tester.tap(info);
      await tester.pumpAndSettle();
      expect(find.text('Map information'), findsOneWidget);
      expect(find.textContaining('not verified roads or walkable access'), findsOneWidget);
    });

    testWidgets('compact panel on a normal phone', (tester) async {
      await mountLinkedStale(tester, const Size(411, 914));
      expect(find.text('Direct to mapped site'), findsOneWidget);
      expect(find.text('Saved road route'), findsOneWidget);
      expect(find.text('Estimate out of date'), findsOneWidget);
      expect(find.text('Rerouting needs a connection'), findsOneWidget);
      expect(find.text('Map info'), findsOneWidget);
      // Long-form explanations must not sit in the default panel anymore.
      expect(find.textContaining('not traffic-aware'), findsNothing);
      expect(find.textContaining('GPS-to-road link'), findsNothing);
      expect(find.textContaining('Unverified links'), findsNothing);
      await capture(tester, 'step1-overview-411x914');
      expect(tester.takeException(), isNull);
    });

    testWidgets('map information sheet on a normal phone', (tester) async {
      await mountLinkedStale(tester, const Size(411, 914));
      await tester.tap(find.text('Map info'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Map information'), findsOneWidget);
      expect(find.text('··· Unverified links'), findsOneWidget);
      expect(find.text('– –  Rosario boundary · MPDO Rosario'), findsOneWidget);
      expect(find.textContaining('not traffic-aware'), findsOneWidget);
      expect(find.textContaining('GPS-to-road link'), findsOneWidget);
      await capture(tester, 'step1-info-sheet-411x914');
      expect(tester.takeException(), isNull);
    });

    testWidgets('approach notice on a normal phone', (tester) async {
      online = false;
      gpsPoint = const LatLng(13.8476, 121.19); // ~111 m: outside entry zone.
      await mountStep1(tester, const Size(411, 914));
      expect(find.textContaining('Near the mapped site'), findsNothing);
      gpsPoint = const LatLng(13.848, 121.19); // ~67 m: advisory enters.
      await sendPosition(tester);
      await settle(tester);
      expect(find.textContaining('Near the mapped site'), findsOneWidget);
      expect(find.text('67 m'), findsOneWidget);
      await capture(tester, 'step1-approach-411x914');
      expect(tester.takeException(), isNull);
    });

    testWidgets('compact panel on a small phone', (tester) async {
      await mountLinkedStale(tester, const Size(320, 568));
      await capture(tester, 'step1-overview-320x568');
      expect(tester.takeException(), isNull);
    });

    testWidgets('compact panel in landscape', (tester) async {
      await mountLinkedStale(tester, const Size(844, 390));
      await capture(tester, 'step1-overview-844x390');
      expect(tester.takeException(), isNull);
    });

    testWidgets('compact panel with enlarged text', (tester) async {
      await mountLinkedStale(
        tester,
        const Size(411, 914),
        textScaler: const TextScaler.linear(2),
      );
      await capture(tester, 'step1-overview-text200');
      expect(tester.takeException(), isNull);
    });
  });
}
