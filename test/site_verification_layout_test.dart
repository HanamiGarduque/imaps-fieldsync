import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:imaps_fieldsync/modules/inspection/widgets/inspection_step_header.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';
import 'support/site_map_http_fixture.dart';

// Delay the real DB query result while preserving insert/query side effects.
class _DelayedRouteRead implements Database {
  _DelayedRouteRead(this.inner, this.release, {this.delayWrites = false});
  final Database inner;
  final Future<void> release;
  final bool delayWrites;

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final rows = await inner.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
    if (table == 'local_route_cache' && !delayWrites) await release;
    return rows;
  }

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    if (table == 'local_route_cache' && delayWrites) await release;
    return inner.insert(
      table,
      values,
      nullColumnHack: nullColumnHack,
      conflictAlgorithm: conflictAlgorithm,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected fixture DB call: ${invocation.memberName}',
  );
}

// AOSP FontScaleConverterFactory's 200% curve, with linear interpolation.
// https://github.com/aosp-mirror/platform_frameworks_base/blob/master/core/java/android/content/res/FontScaleConverterFactory.java
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
        return to[i - 1] +
            (to[i] - to[i - 1]) *
                (fontSize - from[i - 1]) /
                (from[i] - from[i - 1]);
      }
    }
    return fontSize;
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  late Database db;
  late HttpOverrides? originalHttp;
  late SiteMapHttpFixture httpFixture;
  final captureKey = GlobalKey();
  var online = false;
  var gps = true;
  var locationRequests = 0;
  var boundaryRequests = 0;
  var gpsAccuracy = 5.0;
  DateTime? gpsTimestamp;
  Future<List<String>> Function()? connectivityResponse;
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
  const device = LatLng(13.8425, 121.1765);
  const target = LatLng(13.8486, 121.19);
  var gpsPoint = device;

  Map<String, Object> positionEvent() => {
    'latitude': gpsPoint.latitude,
    'longitude': gpsPoint.longitude,
    'accuracy': gpsAccuracy,
    'timestamp': (gpsTimestamp ?? DateTime.now()).millisecondsSinceEpoch,
    'altitude': 0.0,
    'heading': 0.0,
    'speed': 0.0,
    'speed_accuracy': 0.0,
  };

  setUpAll(() async {
    originalHttp = HttpOverrides.current;
    HttpOverrides.global = httpFixture = SiteMapHttpFixture(
      tileDirectory: Platform.environment['IMAPS_MAP_FIXTURE_DIR'],
    );
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    for (final match in RegExp(
      r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)',
    ).allMatches(File('lib/core/services/db_helper.dart').readAsStringSync())) {
      await db.execute(match.group(0)!);
    }
    DBHelper.useDatabaseForTesting(db);
    DBHelper.inspectorIdForTesting = 'site-ui-inspector';
    GoogleFonts.config.allowRuntimeFetching = false;
    final fonts = Directory(
      '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts',
    );
    final fallback = fonts
        .listSync()
        .whereType<File>()
        .firstWhere((f) => f.path.endsWith('.ttf'))
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
        folder == null
            ? fallback
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
      url: 'https://site-layout.test',
      publishableKey: 'fixture-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        if (request.url.path.contains('distance_to_parcel')) {
          boundaryRequests++;
        }
        return http.Response(
          request.url.path.contains('/rpc/')
              ? '1600'
              : jsonEncode({
                  'latitude': target.latitude,
                  'longitude': target.longitude,
                }),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (call) async {
        switch (call.method) {
          case 'isLocationServiceEnabled':
            return gps;
          case 'checkPermission':
            return 3;
          case 'getCurrentPosition':
            locationRequests++;
            return positionEvent();
        }
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (_) async {
        final response = connectivityResponse;
        connectivityResponse = null;
        return response == null ? [online ? 'wifi' : 'none'] : await response();
      },
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
  });

  setUp(() async {
    httpFixture.routeJson = null;
    httpFixture.routeResponse = null;
    httpFixture.requestedRoutes.clear();
    httpFixture.streetTilesAvailable = true;
    online = false;
    gps = true;
    locationRequests = 0;
    boundaryRequests = 0;
    gpsPoint = device;
    gpsAccuracy = 5;
    gpsTimestamp = null;
    connectivityResponse = null;
    InspectionProgress.instance.reset();
    await db.delete('local_jobs');
    await db.delete('local_route_cache');
    await db.insert('local_jobs', {
      'id': task.id,
      'inspector_id': 'site-ui-inspector',
      'status': 'assigned',
      'parcel_lat': target.latitude,
      'parcel_lng': target.longitude,
    });
    await DBHelper.saveRouteCache(
      CachedRoute(
        jobId: task.id,
        points: const [device, LatLng(13.8358, 121.1818), target],
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
    // Build the route before yielding to real SQLite I/O. pumpAndSettle alone
    // advances fake time while the FFI isolate is still answering the query.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
    }
    await tester.pumpAndSettle();
    // The app-wide provider budget intentionally outlives a screen by at most
    // one second. Drain that finite timer before Flutter checks test invariants.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  Future<void> mount(
    WidgetTester tester,
    Size size, {
    double scale = 1,
    TextScaler? textScaler,
    bool rework = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final provider = InspectionProvider();
    if (rework) provider.hydrateForRework(task);
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

  List<Polyline> routeLines(WidgetTester tester) => tester
      .widgetList<PolylineLayer>(find.byType(PolylineLayer))
      .expand((layer) => layer.polylines)
      .toList();

  Future<void> sendPosition(WidgetTester tester) async {
    await messenger.handlePlatformMessage(
      'flutter.baseflow.com/geolocator_updates',
      const StandardMethodCodec().encodeSuccessEnvelope(positionEvent()),
      (_) {},
    );
    await tester.pump();
  }

  Future<void> captureGuidance(WidgetTester tester, String name) async {
    final output = Platform.environment['IMAPS_GUIDANCE_VISUAL_DIR'];
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

  String roadResponse(List<LatLng> points) => jsonEncode({
    'code': 'Ok',
    'routes': [
      {
        'distance': 3372,
        'duration': 462.7,
        'geometry': {
          'coordinates': points.map((p) => [p.longitude, p.latitude]).toList(),
        },
      },
    ],
  });

  Future<void> saveRoad(List<LatLng> points) => DBHelper.saveRouteCache(
    CachedRoute(
      jobId: task.id,
      points: points,
      originLat: device.latitude,
      originLng: device.longitude,
      distanceMeters: 3372,
      durationSeconds: 462.7,
      fetchedAt: DateTime.utc(2026, 10, 9),
    ),
  );

  const offsetStart = LatLng(13.8425, 121.1775);
  const offsetEnd = LatLng(13.8486, 121.189);
  for (final scenario in [
    (name: 'user off-route', points: [offsetStart, target], links: 1),
    (name: 'target off-route', points: [device, offsetEnd], links: 1),
    (
      name: 'both offset',
      points: [
        LatLng(13.8445, 121.18),
        LatLng(13.8452, 121.186),
        LatLng(13.8478, 121.186),
      ],
      links: 2,
    ),
    (
      name: 'tiny gaps',
      points: [LatLng(13.8425, 121.17651), LatLng(13.8486, 121.18999)],
      links: 0,
    ),
  ]) {
    testWidgets(
      'guidance: ${scenario.name} keeps real roads and unsnapped GPS',
      (tester) async {
        await tester.runAsync(() => saveRoad(scenario.points));
        await mount(tester, const Size(390, 844));
        await captureGuidance(tester, scenario.name.replaceAll(' ', '-'));
        final lines = routeLines(tester);
        final road = lines.where(
          (p) => p.pattern == const StrokePattern.solid(),
        );
        final direct = lines
            .where((p) => p.pattern.spacingFactor != null)
            .toList();
        expect(road, hasLength(1));
        expect(road.single.points, scenario.points);
        expect(direct, hasLength(scenario.links));
        final markers = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
        expect(markers.markers.last.point, device);
        expect(markers.markers.first.point, target);
        if (scenario.links > 0) {
          expect(
            find.text('··· Unverified links'),
            findsOneWidget,
            reason: 'Schematic links must be identified without scrolling',
          );
          expect(
            find.text('··· Unverified links').hitTestable(),
            findsOneWidget,
          );
          expect(find.textContaining('not verified roads'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'guidance: road contrast adapts to zoom without hiding controls',
    (tester) async {
      await tester.runAsync(() => saveRoad([offsetStart, offsetEnd]));
      await mount(tester, const Size(390, 844));
      final controller = tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .mapController!;
      final widths = <double>[];
      for (final zoom in [13.0, 16.0, 18.0]) {
        controller.move(const LatLng(13.846, 121.183), zoom);
        await settle(tester);
        final road = routeLines(
          tester,
        ).singleWhere((p) => p.pattern == const StrokePattern.solid());
        expect(road.strokeWidth, inInclusiveRange(6, 8));
        widths.add(road.strokeWidth);
        expect(road.borderStrokeWidth, greaterThanOrEqualTo(2));
        expect(
          find.byTooltip('Fit both markers').hitTestable(),
          findsOneWidget,
        );
        expect(find.byTooltip('Full map').hitTestable(), findsOneWidget);
        await captureGuidance(tester, 'both-offset-zoom-${zoom.round()}');
      }
      expect(
        widths[1],
        greaterThan(widths.first),
        reason: 'Street-level guidance must be stronger than the overview',
      );
      tester.view.physicalSize = const Size(360, 800);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await settle(tester);
      await tester.ensureVisible(find.text('Proceed to Location'));
      await settle(tester);
      await captureGuidance(tester, 'both-offset-small-text-2x');
      expect(find.text('Proceed to Location').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final coordinates in [
    <List<double>>[],
    [
      [121.1765, 13.8425],
    ],
    [
      [121.1765, 13.8425],
      [181.0, 13.8486],
    ],
    [
      [121.1765, 13.8425],
      [121.1765, 13.8425],
    ],
  ]) {
    testWidgets(
      'guidance: unusable provider geometry $coordinates draws no road',
      (tester) async {
        online = true;
        httpFixture.routeJson = jsonEncode({
          'code': 'Ok',
          'routes': [
            {
              'distance': 123.0,
              'duration': 45.0,
              'geometry': {'coordinates': coordinates},
            },
          ],
        });
        await tester.runAsync(() => db.delete('local_route_cache'));
        await mount(tester, const Size(390, 844));
        expect(routeLines(tester), isEmpty);
        expect(find.text('Road route unavailable'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'guidance: live direct distance uses the mapped point without RPC',
    (tester) async {
      online = true;
      gpsPoint = const LatLng(13.848, 121.19); // ~67 m south of mapped point.
      await mount(tester, const Size(390, 844));
      expect(find.text('67 m'), findsOneWidget);
      expect(boundaryRequests, 0);
      gpsPoint = const LatLng(13.8484, 121.19); // ~22 m south.
      await sendPosition(tester);
      await settle(tester);
      expect(find.text('22 m'), findsOneWidget);
      expect(boundaryRequests, 0);
      expect(
        routeLines(tester).where((p) => p.pattern.spacingFactor == null),
        hasLength(1),
      ); // Near-site guidance never discards the saved road.
      expect(InspectionProgress.instance.highestCompleted, 0);
    },
  );

  testWidgets('guidance: 100m advisory has hysteresis and expires with GPS', (
    tester,
  ) async {
    gpsPoint = const LatLng(13.8476, 121.19); // ~111 m.
    await mount(tester, const Size(390, 844));
    final notice = find.textContaining('Near the mapped site');
    expect(notice, findsNothing);
    for (final latitude in [13.8478, 13.84765, 13.8478, 13.84765]) {
      gpsPoint = LatLng(latitude, 121.19); // ~89 m / ~106 m.
      await sendPosition(tester);
      await settle(tester);
      expect(notice, findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(GpsVerificationScreen), findsNothing);
    }
    await captureGuidance(tester, 'near-100m-advisory');
    gpsPoint = const LatLng(13.8473, 121.19); // ~145 m: leaves episode.
    await sendPosition(tester);
    await settle(tester);
    expect(notice, findsNothing);
    gpsPoint = const LatLng(13.84765, 121.19); // Outside entry zone.
    await sendPosition(tester);
    await settle(tester);
    expect(notice, findsNothing);
    gpsPoint = const LatLng(13.8478, 121.19);
    await sendPosition(tester);
    await settle(tester);
    expect(notice, findsOneWidget);
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(notice, findsNothing);
    expect(find.text('Proceed to Location').hitTestable(), findsOneWidget);
  });

  testWidgets('guidance: approach notice leaves the direct distance visible', (
    tester,
  ) async {
    gpsPoint = const LatLng(13.848, 121.19);
    await mount(tester, const Size(390, 844));
    for (final size in [
      const Size(390, 844),
      const Size(375, 812),
      const Size(360, 800),
    ]) {
      tester.view.physicalSize = size;
      await sendPosition(tester);
      await settle(tester);
      final distance = find.text('67 m');
      final viewport = tester.getRect(
        find
            .ancestor(
              of: distance,
              matching: find.byType(SingleChildScrollView),
            )
            .first,
      );
      expect(
        tester.getRect(distance).bottom,
        lessThanOrEqualTo(viewport.bottom),
        reason: '$size distance ${tester.getRect(distance)} / $viewport',
      );
      expect(tester.getRect(distance).top, greaterThanOrEqualTo(viewport.top));
      expect(find.text('Proceed to Location').hitTestable(), findsOneWidget);
    }
  });

  for (final quality in [
    (name: 'inaccurate', accuracy: 60.0, age: const Duration()),
    (name: 'old', accuracy: 5.0, age: const Duration(seconds: 40)),
    (name: 'unknown accuracy', accuracy: 0.0, age: const Duration()),
    (name: 'future', accuracy: 5.0, age: const Duration(seconds: -60)),
  ]) {
    testWidgets('guidance: ${quality.name} GPS never announces approach', (
      tester,
    ) async {
      gpsPoint = const LatLng(13.848, 121.19);
      gpsAccuracy = quality.accuracy;
      gpsTimestamp = DateTime.now().subtract(quality.age);
      await mount(tester, const Size(390, 844));
      expect(find.textContaining('Near the mapped site'), findsNothing);
      expect(find.textContaining('GPS old or imprecise'), findsOneWidget);
      final markers = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
      expect(markers.markers.last.point, gpsPoint);
      expect(find.text('Proceed to Location').hitTestable(), findsOneWidget);
    });
  }

  for (final location in [
    (name: 'above 100m', point: device, available: true),
    (name: 'around 100m', point: LatLng(13.8477, 121.19), available: true),
    (name: 'under 30m', point: LatLng(13.8484, 121.19), available: true),
    (name: 'missing route and GPS', point: device, available: false),
  ]) {
    testWidgets('guidance: ${location.name} can enter Step 2 but not Step 3', (
      tester,
    ) async {
      gpsPoint = location.point;
      gps = location.available;
      await tester.runAsync(() => db.delete('local_route_cache'));
      InspectionProgress.instance.ensureActiveInspection(
        task.id,
        initialStep: 0,
      );
      await mount(tester, const Size(390, 844));
      expect(InspectionProgress.instance.highestCompleted, 0);
      expect(InspectionProgress.instance.isLocked(3), isTrue);
      await tester.ensureVisible(find.text('Proceed to Location'));
      await tester.tap(find.text('Proceed to Location'));
      await settle(tester);
      expect(find.byType(GpsVerificationScreen), findsOneWidget);
      expect(InspectionProgress.instance.highestCompleted, 1);
      expect(InspectionProgress.instance.isLocked(3), isTrue);
      final confirmFinder = find.ancestor(
        of: find.text('Confirm GPS'),
        matching: find.byType(ElevatedButton),
      );
      if (location.available) {
        final confirm = tester.widget<ElevatedButton>(confirmFinder);
        expect(confirm.onPressed == null, location.name != 'under 30m');
      } else {
        expect(confirmFinder, findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'lifecycle: fresh drive estimates are qualified and motion hides them',
    (tester) async {
      online = true;
      httpFixture.routeJson = roadResponse([device, target]);
      await tester.runAsync(() => db.delete('local_route_cache'));
      await mount(tester, const Size(390, 844));
      expect(find.text('ESTIMATED drive · ~8 min'), findsOneWidget);
      expect(find.textContaining('not traffic-aware'), findsOneWidget);
      gpsPoint = const LatLng(13.84285, 121.1765); // ~39 m movement.
      await sendPosition(tester);
      await settle(tester);
      expect(httpFixture.requestedRoutes, hasLength(1));
      expect(find.text('ESTIMATED drive · ~8 min'), findsNothing);
      expect(find.text('Estimate out of date'), findsOneWidget);
      expect(routeLines(tester).first.points, [device, target]);
    },
  );

  testWidgets(
    'lifecycle: movement reroutes after 15s, never on every GPS tick',
    (tester) async {
      online = true;
      httpFixture.routeJson = roadResponse([device, target]);
      await tester.runAsync(() => db.delete('local_route_cache'));
      await mount(tester, const Size(390, 844));
      expect(httpFixture.requestedRoutes, hasLength(1));
      gpsPoint = const LatLng(13.84285, 121.1765);
      for (var i = 0; i < 10; i++) {
        await sendPosition(tester);
        await tester.pump(const Duration(seconds: 1));
        expect(httpFixture.requestedRoutes, hasLength(1));
      }
      await tester.pump(const Duration(seconds: 6));
      await sendPosition(tester);
      await settle(tester);
      expect(httpFixture.requestedRoutes, hasLength(2));
      expect(
        httpFixture.requestedRoutes.last.path,
        contains('121.1765,13.84285;'),
      );
      for (var i = 0; i < 10; i++) {
        await sendPosition(tester);
        await tester.pump();
      }
      expect(httpFixture.requestedRoutes, hasLength(2));
      expect(boundaryRequests, 0);
    },
  );

  testWidgets(
    'review: connectivity latency cannot shorten actual request spacing',
    (tester) async {
      online = true;
      final dispatches = <DateTime>[];
      httpFixture.routeResponse = (_) async {
        dispatches.add(tester.binding.clock.now());
        return roadResponse([gpsPoint, target]);
      };
      await mount(tester, const Size(390, 844));
      await tester.pump(const Duration(seconds: 16));
      final gate = Completer<List<String>>();
      connectivityResponse = () => gate.future;
      addTearDown(() {
        if (!gate.isCompleted) gate.complete(['none']);
      });
      gpsPoint = const LatLng(13.84285, 121.1765);
      await sendPosition(tester);
      await tester.pump(const Duration(seconds: 12));
      gate.complete(['wifi']);
      await settle(tester);
      expect(dispatches, hasLength(2));
      gpsPoint = const LatLng(13.8432, 121.1765); // Another ~39m.
      await sendPosition(tester);
      await tester.pump(const Duration(seconds: 4));
      await settle(tester);
      expect(
        dispatches,
        hasLength(2),
        reason: 'connectivity time cannot spend the provider request budget',
      );
      for (var i = 0; i < 10; i++) {
        await sendPosition(tester);
        await tester.pump(const Duration(seconds: 1));
      }
      await settle(tester);
      expect(dispatches, hasLength(3));
      expect(
        dispatches.last.difference(dispatches[1]),
        greaterThanOrEqualTo(const Duration(seconds: 15)),
      );
    },
  );

  testWidgets('review: obsolete failures still escalate 30/60/120s backoff', (
    tester,
  ) async {
    online = true;
    final replies = <Completer<String?>>[];
    httpFixture.routeResponse = (_) {
      final reply = Completer<String?>();
      replies.add(reply);
      return reply.future;
    };
    addTearDown(() async {
      for (final reply in replies) {
        if (!reply.isCompleted) reply.complete(null);
      }
      await settle(tester);
    });
    await mount(tester, const Size(390, 844));
    final saved = routeLines(tester).first.points;
    for (final stage in [
      (delay: 30, count: 1),
      (delay: 60, count: 2),
      (delay: 120, count: 3),
    ]) {
      expect(replies, hasLength(stage.count));
      gpsPoint = LatLng(
        gpsPoint.latitude + 0.0006,
        gpsPoint.longitude,
      ); // ~67m.
      await sendPosition(tester);
      final failedAt = tester.binding.clock.now();
      replies.last.complete(null);
      await settle(tester);
      final deadline = failedAt.add(Duration(seconds: stage.delay));
      while (tester.binding.clock.now().isBefore(
        deadline.subtract(const Duration(seconds: 1)),
      )) {
        await sendPosition(tester);
        await tester.pump(const Duration(seconds: 1));
        expect(
          httpFixture.requestedRoutes,
          hasLength(stage.count),
          reason: 'obsolete failure must retain ${stage.delay}s backoff',
        );
      }
      await tester.pump(const Duration(seconds: 2));
      await sendPosition(tester);
      await settle(tester);
      expect(httpFixture.requestedRoutes, hasLength(stage.count + 1));
      expect(
        httpFixture.requestedRoutes.last.path,
        contains('${gpsPoint.longitude},${gpsPoint.latitude};'),
      );
      expect(routeLines(tester).first.points, saved);
      final cached = await tester.runAsync(
        () => DBHelper.getRouteCache(task.id),
      );
      expect(cached!.points, saved);
    }
    replies.last.complete(null);
    await settle(tester);
  });

  testWidgets('review: failure after GPS expiry still starts 30s backoff', (
    tester,
  ) async {
    online = true;
    gpsTimestamp = DateTime.now().subtract(const Duration(seconds: 10));
    final replies = <Completer<String?>>[];
    httpFixture.routeResponse = (_) {
      final reply = Completer<String?>();
      replies.add(reply);
      return reply.future;
    };
    addTearDown(() async {
      for (final reply in replies) {
        if (!reply.isCompleted) reply.complete(null);
      }
      await settle(tester);
    });
    await mount(tester, const Size(390, 844));
    final saved = routeLines(tester).first.points;
    await tester.pump(const Duration(seconds: 5));
    expect(find.textContaining('GPS old or imprecise'), findsOneWidget);
    final failedAt = tester.binding.clock.now();
    replies.single.complete(null);
    await settle(tester);
    gpsTimestamp = null;
    final deadline = failedAt.add(const Duration(seconds: 30));
    while (tester.binding.clock.now().isBefore(
      deadline.subtract(const Duration(seconds: 1)),
    )) {
      await sendPosition(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(
        httpFixture.requestedRoutes,
        hasLength(1),
        reason: 'expiry cannot waive a provider failure',
      );
    }
    await tester.pump(const Duration(seconds: 2));
    await sendPosition(tester);
    await settle(tester);
    expect(httpFixture.requestedRoutes, hasLength(2));
    expect(routeLines(tester).first.points, saved);
    final cached = await tester.runAsync(() => DBHelper.getRouteCache(task.id));
    expect(cached!.points, saved);
    replies.last.complete(null);
    await settle(tester);
  });

  testWidgets(
    'lifecycle: meaningful lateral deviation responds below movement threshold',
    (tester) async {
      online = true;
      httpFixture.routeJson = roadResponse([
        device,
        const LatLng(13.85, 121.1765),
      ]);
      await tester.runAsync(() => db.delete('local_route_cache'));
      await mount(tester, const Size(390, 844));
      gpsPoint = const LatLng(13.8425, 121.1763); // ~22 m lateral deviation.
      await sendPosition(tester);
      await tester.pump(const Duration(seconds: 16));
      await sendPosition(tester);
      await settle(tester);
      expect(httpFixture.requestedRoutes, hasLength(2));
      for (var i = 0; i < 6; i++) {
        await sendPosition(tester);
        await tester.pump(const Duration(seconds: 3));
      }
      await settle(tester);
      expect(
        httpFixture.requestedRoutes,
        hasLength(2),
        reason:
            'a stable snapped-road offset must not cause repeated rerouting',
      );
    },
  );

  testWidgets(
    'lifecycle: failure backoff retains real cached roads while offline',
    (tester) async {
      online = true;
      await mount(tester, const Size(390, 844));
      final saved = routeLines(tester).first.points;
      expect(httpFixture.requestedRoutes, hasLength(1));
      for (var i = 0; i < 5; i++) {
        await sendPosition(tester);
        await tester.pump(const Duration(seconds: 4));
      }
      expect(httpFixture.requestedRoutes, hasLength(1));
      await tester.pump(const Duration(seconds: 11));
      await sendPosition(tester);
      await settle(tester);
      expect(httpFixture.requestedRoutes, hasLength(2));
      await tester.pump(const Duration(seconds: 40));
      await sendPosition(tester);
      await settle(tester);
      expect(httpFixture.requestedRoutes, hasLength(2));
      await tester.pump(const Duration(seconds: 21));
      await sendPosition(tester);
      await settle(tester);
      expect(httpFixture.requestedRoutes, hasLength(3));
      online = false;
      await tester.pump(const Duration(seconds: 121));
      await sendPosition(tester);
      await settle(tester);
      expect(httpFixture.requestedRoutes, hasLength(3));
      expect(routeLines(tester).first.points, saved);
      expect(find.text('Saved road route'), findsOneWidget);
      expect(find.text('ESTIMATED drive · ~8 min'), findsNothing);
    },
  );

  testWidgets(
    'lifecycle: obsolete response cannot replace current geometry or cache',
    (tester) async {
      online = true;
      final reply = Completer<String?>();
      httpFixture.routeResponse = (_) => reply.future;
      addTearDown(() async {
        if (!reply.isCompleted) reply.complete(null);
        await settle(tester);
      });
      await mount(tester, const Size(390, 844));
      final saved = routeLines(tester).first.points;
      gpsPoint = const LatLng(
        13.844,
        121.1765,
      ); // ~167 m beyond request origin.
      await sendPosition(tester);
      reply.complete(
        roadResponse([device, const LatLng(13.84, 121.183), target]),
      );
      await settle(tester);
      expect(routeLines(tester).first.points, saved);
      final cache = await tester.runAsync(
        () => DBHelper.getRouteCache(task.id),
      );
      expect(cache!.points, saved);
      httpFixture.routeResponse = (_) async => roadResponse([gpsPoint, target]);
      await tester.pump(const Duration(seconds: 16));
      await sendPosition(tester);
      await settle(tester);
      expect(httpFixture.requestedRoutes, hasLength(2));
      expect(routeLines(tester).first.points, [gpsPoint, target]);
      expect(
        tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers.last.point,
        gpsPoint,
      );
    },
  );

  testWidgets(
    'lifecycle: response after screen disposal cannot mutate route cache',
    (tester) async {
      online = true;
      final reply = Completer<String?>();
      httpFixture.routeResponse = (_) => reply.future;
      addTearDown(() async {
        if (!reply.isCompleted) reply.complete(null);
        await settle(tester);
      });
      await mount(tester, const Size(390, 844));
      final saved = routeLines(tester).first.points;
      await tester.pumpWidget(const SizedBox.shrink());
      reply.complete(
        roadResponse([device, const LatLng(13.84, 121.183), target]),
      );
      await settle(tester);
      final cache = await tester.runAsync(
        () => DBHelper.getRouteCache(task.id),
      );
      expect(cache!.points, saved);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'lifecycle: late cache read cannot overwrite a newer live route',
    (tester) async {
      online = true;
      final release = Completer<void>();
      DBHelper.useDatabaseForTesting(_DelayedRouteRead(db, release.future));
      addTearDown(() async {
        if (!release.isCompleted) release.complete();
        DBHelper.useDatabaseForTesting(db);
        await settle(tester);
      });
      final fresh = [device, const LatLng(13.84, 121.183), target];
      httpFixture.routeJson = roadResponse(fresh);
      await mount(tester, const Size(390, 844));
      expect(routeLines(tester).first.points, fresh);
      release.complete();
      await settle(tester);
      expect(routeLines(tester).first.points, fresh);
      expect(find.text('Saved road route'), findsNothing);
    },
  );

  testWidgets('lifecycle: reconnects share the same request budget', (
    tester,
  ) async {
    await mount(tester, const Size(390, 844));
    expect(httpFixture.requestedRoutes, isEmpty);
    httpFixture.routeJson = roadResponse([device, target]);
    Future<void> connectivity(bool connected) async {
      online = connected;
      await messenger.handlePlatformMessage(
        'dev.fluttercommunity.plus/connectivity_status',
        const StandardMethodCodec().encodeSuccessEnvelope([
          connected ? 'wifi' : 'none',
        ]),
        (_) {},
      );
      await settle(tester);
    }

    await connectivity(true);
    await connectivity(true);
    expect(httpFixture.requestedRoutes, hasLength(1));
    await connectivity(false);
    await connectivity(true);
    expect(httpFixture.requestedRoutes, hasLength(1));
    await tester.pump(const Duration(seconds: 16));
    await sendPosition(tester);
    await settle(tester);
    expect(httpFixture.requestedRoutes, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'lifecycle: slow cache persistence drains the queued current route',
    (tester) async {
      online = true;
      final release = Completer<void>();
      DBHelper.useDatabaseForTesting(
        _DelayedRouteRead(db, release.future, delayWrites: true),
      );
      httpFixture.routeResponse = (_) async => roadResponse([gpsPoint, target]);
      addTearDown(() async {
        if (!release.isCompleted) release.complete();
        DBHelper.useDatabaseForTesting(db);
        await settle(tester);
      });
      await mount(tester, const Size(390, 844));
      await tester.pump(const Duration(seconds: 16));
      gpsPoint = const LatLng(13.844, 121.1765);
      await sendPosition(tester);
      release.complete();
      await settle(tester); // No additional GPS tick after cache completion.
      expect(httpFixture.requestedRoutes, hasLength(2));
      expect(routeLines(tester).first.points, [gpsPoint, target]);
    },
  );

  testWidgets(
    'lifecycle: simultaneous Step 1 instances share the provider budget',
    (tester) async {
      online = true;
      httpFixture.routeJson = roadResponse([device, target]);
      final provider = InspectionProvider();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(780, 844);
      addTearDown(tester.view.reset);
      addTearDown(provider.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp(
            home: Row(
              children: [
                Expanded(child: SiteMapScreen(task: task)),
                Expanded(child: SiteMapScreen(task: task)),
              ],
            ),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 25));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
      }
      expect(httpFixture.requestedRoutes, hasLength(1));
      await tester.pump(const Duration(milliseconds: 1100));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 25));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
      }
      expect(httpFixture.requestedRoutes, hasLength(2));
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'lifecycle: future timestamp does not trap subsequent healthy GPS',
    (tester) async {
      gpsPoint = const LatLng(13.848, 121.19);
      gpsTimestamp = DateTime.now().add(const Duration(minutes: 1));
      await mount(tester, const Size(390, 844));
      expect(find.textContaining('Near the mapped site'), findsNothing);
      gpsTimestamp = null;
      await sendPosition(tester);
      await settle(tester);
      expect(find.textContaining('Near the mapped site'), findsOneWidget);
    },
  );

  testWidgets('lifecycle: old GPS event cannot move the blue dot backwards', (
    tester,
  ) async {
    await mount(tester, const Size(390, 844));
    gpsPoint = const LatLng(13.8478, 121.19);
    await sendPosition(tester);
    await settle(tester);
    gpsTimestamp = DateTime.now().subtract(const Duration(minutes: 1));
    gpsPoint = device;
    await sendPosition(tester);
    await settle(tester);
    expect(
      tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers.last.point,
      const LatLng(13.8478, 121.19),
    );
    expect(find.textContaining('Near the mapped site'), findsOneWidget);
  });

  testWidgets('lifecycle: aged geometry survives but its ETA expires', (
    tester,
  ) async {
    online = true;
    httpFixture.routeJson = roadResponse([device, target]);
    await tester.runAsync(() => db.delete('local_route_cache'));
    await mount(tester, const Size(390, 844));
    expect(find.text('ESTIMATED drive · ~8 min'), findsOneWidget);
    await tester.pump(const Duration(seconds: 121));
    await sendPosition(tester);
    await settle(tester);
    expect(find.text('ESTIMATED drive · ~8 min'), findsNothing);
    expect(find.text('Estimate out of date'), findsOneWidget);
    expect(routeLines(tester).first.points, [device, target]);
    expect(
      httpFixture.requestedRoutes,
      hasLength(1),
      reason: 'a stationary device must not poll the route provider',
    );
  });

  // Synthetic reproduction of absent guidance; not a diagnosis of phone GPS.
  testWidgets(
    'visibility: no road and coarse GPS keep markers and explain guidance',
    (tester) async {
      await tester.runAsync(() => db.delete('local_route_cache'));
      gpsAccuracy = 40;
      await mount(tester, const Size(390, 844));
      await captureGuidance(tester, 'no-road-coarse-gps');
      expect(routeLines(tester), isEmpty, reason: 'no fabricated road');
      expect(find.text('Road route unavailable'), findsOneWidget);
      expect(find.textContaining('GPS old or imprecise'), findsOneWidget);
      final markers = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
      expect(markers.markers.map((m) => m.point), [target, device]);
      expect(find.textContaining('Near the mapped site'), findsNothing);
      expect(find.text('Proceed to Location').hitTestable(), findsOneWidget);
      expect(
        find.textContaining('GPS-to-road link and ~100 m notice'),
        findsOneWidget,
        reason: 'explain which guidance needs a fresh precise fix',
      );
      final guidance = find.textContaining(
        'GPS-to-road link and ~100 m notice',
      );
      for (final scale in [1.0, 2.0]) {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        for (final width in [360.0, 375.0, 414.0]) {
          tester.view.physicalSize = Size(width, 844);
          await settle(tester);
          await tester.tap(find.byTooltip('Fit both markers'));
          await settle(tester);
          // At 200%, the paragraph can exceed the scroll viewport. Bring its
          // centre into view while the independent primary action stays pinned.
          await Scrollable.ensureVisible(
            tester.element(guidance),
            alignment: 0.5,
          );
          await settle(tester);
          expect(
            guidance.hitTestable(),
            findsOneWidget,
            reason: '$width/$scale',
          );
          expect(
            find.text('Proceed to Location').hitTestable(),
            findsOneWidget,
          );
          expect(routeLines(tester), isEmpty);
          await captureGuidance(
            tester,
            'no-road-guidance-${width.toInt()}-${scale.toInt()}x',
          );
          final targetLabel = tester.getRect(
            find
                .ancestor(
                  of: find.text('Target site'),
                  matching: find.byType(Container),
                )
                .first,
          );
          for (final tooltip in ['Full map', 'Fit both markers']) {
            final control = tester.getRect(find.byTooltip(tooltip));
            expect(
              targetLabel.overlaps(control),
              isFalse,
              reason:
                  '$width/$scale: target $targetLabel overlaps $tooltip $control',
            );
          }
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets('visibility: coarse GPS retains the road and target link only', (
    tester,
  ) async {
    await tester.runAsync(() => saveRoad([offsetStart, offsetEnd]));
    gpsAccuracy = 40;
    await mount(tester, const Size(390, 844));
    await captureGuidance(tester, 'cached-road-coarse-gps');
    final lines = routeLines(tester);
    expect(lines.first.points, [offsetStart, offsetEnd]);
    expect(lines, hasLength(2));
    expect(lines.last.points, [offsetEnd, target]);
    expect(find.textContaining('Near the mapped site'), findsNothing);
    expect(
      find.textContaining('GPS-to-road link and ~100 m notice'),
      findsOneWidget,
      reason: 'poor GPS does not suppress the route-to-target link',
    );
    await tester.ensureVisible(
      find.textContaining('GPS-to-road link and ~100 m notice'),
    );
    await settle(tester);
    await captureGuidance(tester, 'cached-road-gps-explanation');
    gpsAccuracy = 5;
    await sendPosition(tester);
    await settle(tester);
    expect(routeLines(tester), hasLength(3));
    expect(routeLines(tester)[1].points.first, device);
    expect(
      find.textContaining('GPS-to-road link and ~100 m notice'),
      findsNothing,
    );
    await captureGuidance(tester, 'cached-road-both-links-restored');
  });

  testWidgets('visibility: small gaps explain the absence of dotted links', (
    tester,
  ) async {
    await tester.runAsync(() => saveRoad([device, target]));
    await mount(tester, const Size(390, 844));
    await captureGuidance(tester, 'road-small-gaps');
    expect(routeLines(tester), hasLength(1));
    expect(
      find.textContaining('Small gaps or GPS uncertainty'),
      findsOneWidget,
    );
    expect(find.text('··· Unverified links'), findsNothing);
    expect(find.text('Proceed to Location').hitTestable(), findsOneWidget);
    await tester.ensureVisible(
      find.textContaining('Small gaps or GPS uncertainty'),
    );
    await settle(tester);
    await captureGuidance(tester, 'road-small-gap-explanation');
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('guidance: links and advisory keep controls usable at $scale', (
      tester,
    ) async {
      gpsPoint = const LatLng(13.848, 121.19);
      await tester.runAsync(
        () => saveRoad([offsetStart, const LatLng(13.8478, 121.186)]),
      );
      await mount(tester, const Size(390, 844), scale: scale);
      final semantics = tester.ensureSemantics();
      try {
        for (final size in [
          const Size(390, 844),
          const Size(320, 568),
          const Size(640, 360),
          const Size(844, 390),
        ]) {
          tester.view.physicalSize = size;
          await sendPosition(tester);
          await settle(tester);
          final fit = tester.getRect(find.byTooltip('Fit both markers'));
          final full = tester.getRect(find.byTooltip('Full map'));
          final attribution = tester.getRect(
            find
                .ancestor(
                  of: find.text('© OpenStreetMap contributors'),
                  matching: find.byType(Container),
                )
                .first,
          );
          expect(fit.size, const Size(48, 48));
          expect(full.size, const Size(48, 48));
          expect(
            fit.overlaps(attribution),
            isFalse,
            reason: '$size / $scale fit $fit attribution $attribution',
          );
          expect(
            full.overlaps(attribution),
            isFalse,
            reason: '$size / $scale full $full attribution $attribution',
          );
          expect(
            find.byTooltip('Fit both markers').hitTestable(),
            findsOneWidget,
          );
          expect(find.byTooltip('Full map').hitTestable(), findsOneWidget);
          await tester.ensureVisible(find.text('Proceed to Location'));
          await settle(tester);
          expect(
            find.text('Proceed to Location').hitTestable(),
            findsOneWidget,
          );
          await captureGuidance(
            tester,
            'near-${size.width.toInt()}-${size.height.toInt()}-${scale.toInt()}x',
          );
          await tester.tap(find.byTooltip('Full map'));
          await settle(tester);
          expect(
            find.byTooltip('Fit both markers').hitTestable(),
            findsOneWidget,
          );
          expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
          await captureGuidance(
            tester,
            'full-${size.width.toInt()}-${scale.toInt()}x',
          );
          await tester.tap(find.byTooltip('Exit full map'));
          await settle(tester);
          expect(tester.takeException(), isNull, reason: '$size / $scale');
        }
      } finally {
        semantics.dispose();
      }
    });
  }

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets(
      'portrait controls and split landscape remain reachable at $scale',
      (tester) async {
        await mount(tester, const Size(390, 844), scale: scale);
        final semantics = tester.ensureSemantics();
        try {
          for (final size in [
            const Size(390, 844),
            const Size(320, 568),
            const Size(844, 390),
            const Size(640, 360),
            const Size(740, 320),
            const Size(1280, 800),
          ]) {
            tester.view.physicalSize = size;
            await settle(tester);
            expect(find.text('Site details'), findsOneWidget);
            expect(find.text('Site Verification'), findsOneWidget);
            expect(
              find.text('STEP 1 OF 6 — LOCATE TARGET', findRichText: true),
              findsOneWidget,
            );
            final full = find.byTooltip('Full map');
            final fit = find.byTooltip('Fit both markers');
            final headerBounds = tester.getRect(
              find.ancestor(
                of: find.byType(InspectionStepHeader),
                matching: find.byType(SingleChildScrollView),
              ),
            );
            final attributionBounds = tester.getRect(
              find
                  .ancestor(
                    of: find.text('© OpenStreetMap contributors'),
                    matching: find.byType(Container),
                  )
                  .first,
            );
            final detailsBounds = tester.getRect(
              find
                  .ancestor(
                    of: find.text('Site details'),
                    matching: find.byType(Container),
                  )
                  .first,
            );
            expect(
              tester.getSemantics(full).tooltip,
              'Full map',
              reason: tester.getSemantics(full).toStringDeep(),
            );
            expect(
              tester.getSemantics(fit).tooltip,
              'Fit both markers',
              reason: tester.getSemantics(fit).toStringDeep(),
            );
            for (final control in [full, fit]) {
              final bounds = tester.getRect(control);
              expect(control, findsOneWidget);
              expect(tester.getSize(control).width, greaterThanOrEqualTo(48));
              expect(tester.getSize(control).height, greaterThanOrEqualTo(48));
              expect(
                control.hitTestable(),
                findsOneWidget,
                reason: '$size at $scale: ${tester.getRect(control)}',
              );
              for (final overlay in [
                headerBounds,
                attributionBounds,
                detailsBounds,
              ]) {
                expect(
                  bounds.overlaps(overlay),
                  isFalse,
                  reason: '$size at $scale: target $bounds, overlay $overlay',
                );
              }
              expect(bounds.top, greaterThanOrEqualTo(24));
              expect(bounds.bottom, lessThanOrEqualTo(size.height - 24));
            }
            if (size.width < size.height) {
              final fullBounds = tester.getRect(full);
              final fitBounds = tester.getRect(fit);
              expect(
                (fullBounds.center.dx - fitBounds.center.dx).abs() < 1 &&
                        fullBounds.bottom <= fitBounds.top ||
                    (fullBounds.center.dy - fitBounds.center.dy).abs() < 1 &&
                        fullBounds.right <= fitBounds.left,
                isTrue,
                reason:
                    'Complete targets form a non-overlapping row or column '
                    'at $size / $scale: $fullBounds and $fitBounds',
              );
            } else {
              expect(
                tester.getRect(find.byType(FlutterMap)).right,
                size.width,
                reason:
                    'the map remains visible beneath the content-sized side pane',
              );
              expect(headerBounds.right, lessThanOrEqualTo(detailsBounds.left));
              expect(
                attributionBounds.right,
                lessThanOrEqualTo(detailsBounds.left),
              );
            }
            await tester.ensureVisible(find.text('Proceed to Location'));
            await settle(tester);
            expect(
              find.text('Proceed to Location').hitTestable(),
              findsOneWidget,
              reason:
                  '$size at $scale: details $detailsBounds, header '
                  '$headerBounds, attribution $attributionBounds, action '
                  '${tester.getRect(find.text('Proceed to Location'))}',
            );
            expect(
              find.byTooltip('Hide site details').hitTestable(),
              findsOneWidget,
              reason:
                  'disclosure must stay reachable after details scroll at $size/$scale',
            );
            expect(tester.takeException(), isNull, reason: '$size at $scale');
          }
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  testWidgets(
    'normal phone details group related metrics without dominating the map',
    (tester) async {
      await mount(tester, const Size(360, 800));
      final site = tester.getRect(find.text('Direct to mapped site'));
      final road = tester.getRect(find.text('Saved road route'));
      expect((site.top - road.top).abs(), lessThan(4));
      expect(site.right, lessThan(road.left));
      final panel = tester.getRect(
        find
            .ancestor(
              of: find.text('Site details'),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        panel.height,
        lessThanOrEqualTo(272),
        reason: 'even the saved-route warning must remain proportionate',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Android nonlinear 200% text keeps the complete action visible', (
    tester,
  ) async {
    await mount(
      tester,
      const Size(320, 568),
      textScaler: const _Android200TextScaler(),
    );
    await tester.ensureVisible(find.text('Proceed to Location'));
    await settle(tester);
    final action = find.ancestor(
      of: find.text('Proceed to Location'),
      matching: find.byType(ElevatedButton),
    );
    final viewport = tester.getRect(
      find
          .ancestor(
            of: find.text('Site details'),
            matching: find.byType(Container),
          )
          .first,
    );
    final button = tester.getRect(action);
    final label = tester.getRect(find.text('Proceed to Location'));
    expect(button.height, greaterThanOrEqualTo(52));
    expect(
      button.top,
      greaterThanOrEqualTo(viewport.top),
      reason: 'button $button, label $label, viewport $viewport',
    );
    expect(button.bottom, lessThanOrEqualTo(viewport.bottom));
    expect(label.top, greaterThanOrEqualTo(viewport.top));
    expect(label.bottom, lessThanOrEqualTo(viewport.bottom));
    await tester.ensureVisible(find.text('Saved road route'));
    await settle(tester);
    expect(
      tester.getRect(find.text('Saved road route')).top,
      greaterThan(tester.getRect(find.text('Direct to mapped site')).bottom),
      reason: 'the actual enlarged caption size requires stacked metrics',
    );
    final backControl = find
        .ancestor(of: find.byTooltip('Back'), matching: find.byType(IconButton))
        .first;
    await tester.ensureVisible(backControl);
    await settle(tester);
    final headerViewport = tester.getRect(
      find.ancestor(
        of: find.byType(InspectionStepHeader),
        matching: find.byType(SingleChildScrollView),
      ),
    );
    final back = tester.getRect(backControl);
    expect(back.height, greaterThanOrEqualTo(48));
    expect(back.top, greaterThanOrEqualTo(headerViewport.top));
    expect(back.bottom, lessThanOrEqualTo(headerViewport.bottom));
    expect(tester.takeException(), isNull);
  });

  for (final close in [false, true]) {
    testWidgets(
      'Map labels remain readable ${close ? 'near-coincident' : 'far'} at normal and enlarged text',
      (tester) async {
        if (close) {
          await tester.runAsync(() async {
            await db.delete('local_route_cache');
            await db.update('local_jobs', {
              'parcel_lat': 13.84251,
              'parcel_lng': 121.17651,
            });
          });
        }
        for (final (size, scale) in [
          (const Size(390, 844), 1.0),
          (const Size(844, 390), 2.0),
        ]) {
          await tester.pumpWidget(const SizedBox.shrink());
          await mount(tester, size, scale: scale);
          await tester.tap(find.byTooltip('Fit both markers'));
          await settle(tester);
          final targetLabel = tester.getRect(
            find
                .ancestor(
                  of: find.text('Target site'),
                  matching: find.byType(Container),
                )
                .first,
          );
          final deviceLabel = tester.getRect(
            find
                .ancestor(
                  of: find.text('You'),
                  matching: find.byType(Container),
                )
                .first,
          );
          final header = find
              .ancestor(
                of: find.byType(InspectionStepHeader),
                matching: find.byType(SingleChildScrollView),
              )
              .first;
          final panel = find
              .ancestor(
                of: find.text('Site details'),
                matching: find.byType(Container),
              )
              .first;
          final attribution = find
              .ancestor(
                of: find.text('© OpenStreetMap contributors'),
                matching: find.byType(Container),
              )
              .first;
          for (final label in [targetLabel, deviceLabel]) {
            expect(
              label.left,
              greaterThanOrEqualTo(0),
              reason: '$size/$scale: $label',
            );
            expect(
              label.right,
              lessThanOrEqualTo(size.width),
              reason: '$size/$scale: $label',
            );
            expect(label.top, greaterThanOrEqualTo(24));
            expect(label.bottom, lessThanOrEqualTo(size.height - 24));
            for (final overlay in [
              header,
              panel,
              attribution,
              find.byTooltip('Full map'),
              find.byTooltip('Fit both markers'),
            ]) {
              expect(
                label.overlaps(tester.getRect(overlay)),
                isFalse,
                reason:
                    '$size/$scale: label $label overlaps $overlay ${tester.getRect(overlay)}',
              );
            }
          }
          expect(
            targetLabel.overlaps(deviceLabel),
            isFalse,
            reason:
                'Both identities must remain legible even when their coordinates are close.',
          );
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  testWidgets('fresh small-phone open fits after enlarged overlays settle', (
    tester,
  ) async {
    await mount(tester, const Size(320, 568), scale: 2);
    final controller = tester
        .widget<FlutterMap>(find.byType(FlutterMap))
        .mapController!;
    expect(
      controller.camera.zoom,
      greaterThan(10),
      reason:
          'fresh open must frame the site, not the world, without a fit tap',
    );
    final header = tester.getRect(
      find.ancestor(
        of: find.byType(InspectionStepHeader),
        matching: find.byType(SingleChildScrollView),
      ),
    );
    final attribution = tester.getRect(
      find
          .ancestor(
            of: find.text('© OpenStreetMap contributors'),
            matching: find.byType(Container),
          )
          .first,
    );
    for (final point in [device, target]) {
      final projected = controller.camera.latLngToScreenPoint(point);
      expect(projected.y, greaterThan(header.bottom + 16));
      expect(projected.y, lessThan(attribution.top - 16));
    }
    controller.move(const LatLng(14, 121), 16);
    await tester.tap(find.byTooltip('Hide site details'));
    await settle(tester);
    tester.view.physicalSize = const Size(844, 390);
    await settle(tester);
    expect(controller.camera.center, const LatLng(14, 121));
    expect(controller.camera.zoom, 16);
    expect(tester.takeException(), isNull);
  });

  testWidgets('enlarged attribution leaves the complete fit target tappable', (
    tester,
  ) async {
    await mount(tester, const Size(390, 844), scale: 2);
    final attribution = tester.getRect(
      find
          .ancestor(
            of: find.text('© OpenStreetMap contributors'),
            matching: find.byType(Container),
          )
          .first,
    );
    final fit = tester.getRect(find.byTooltip('Fit both markers'));
    expect(
      attribution.overlaps(fit),
      isFalse,
      reason:
          'attribution $attribution must not cover any of the 48dp target $fit',
    );
    final controller = tester
        .widget<FlutterMap>(find.byType(FlutterMap))
        .mapController!;
    controller.move(const LatLng(14, 121), 17);
    await settle(tester);
    await tester.tapAt(fit.bottomLeft + const Offset(1, -1));
    await settle(tester);
    expect(controller.camera.visibleBounds.contains(target), isTrue);
    expect(controller.camera.visibleBounds.contains(device), isTrue);
    expect(controller.camera.zoom, lessThan(17));
    expect(tester.takeException(), isNull);
  });

  testWidgets('online road metrics and Flutter visual acceptance', (
    tester,
  ) async {
    online = true;
    final fixtureDir = Platform.environment['IMAPS_MAP_FIXTURE_DIR'];
    httpFixture.routeJson = fixtureDir == null
        ? jsonEncode({
            'code': 'Ok',
            'routes': [
              {
                'distance': 3372,
                'duration': 462.7,
                'geometry': {
                  'coordinates': [
                    [121.1765, 13.8425],
                    [121.1818, 13.8358],
                    [121.19, 13.8486],
                  ],
                },
              },
            ],
          })
        : File('$fixtureDir/public-demo-route.json').readAsStringSync();
    final onlineRoute = httpFixture.routeJson;
    // First online fetch: cached replay is exercised separately above. This
    // avoids the pre-existing late-cache/fast-network race in the data owner.
    await tester.runAsync(() => db.delete('local_route_cache'));
    await mount(tester, const Size(390, 844));
    expect(
      find.text('Road route'),
      findsOneWidget,
      reason:
          'requests: ${httpFixture.requestedRoutes}, '
          'cached label: ${find.text('Saved road route').evaluate().length}',
    );
    expect(find.text('Saved road route'), findsNothing);
    expect(find.text('3.4 km'), findsOneWidget);
    expect(find.text('ESTIMATED drive · ~8 min'), findsOneWidget);
    expect(find.textContaining('not traffic-aware'), findsOneWidget);
    final output = Platform.environment['IMAPS_SITE_VISUAL_DIR'];
    final measurements = <String, Object>{};
    Future<void> capture(String name) async {
      if (output == null) return;
      final panel = tester.getSize(
        find
            .ancestor(
              of: find.text('Site details'),
              matching: find.byType(Container),
            )
            .first,
      );
      measurements[name] = {
        'screenDp': [
          tester.view.physicalSize.width,
          tester.view.physicalSize.height,
        ],
        'panelDp': [panel.width, panel.height],
        'cameraZoom': tester
            .widget<FlutterMap>(find.byType(FlutterMap))
            .mapController!
            .camera
            .zoom,
      };
      final boundary =
          captureKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory(output).createSync(recursive: true);
        File('$output/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await tester.tap(find.byTooltip('Fit both markers'));
    await settle(tester);
    await capture('site-verification-portrait');
    tester.view.physicalSize = const Size(360, 800);
    await settle(tester);
    await tester.tap(find.byTooltip('Fit both markers'));
    await settle(tester);
    final smallPanel = tester.getRect(
      find
          .ancestor(
            of: find.text('Site details'),
            matching: find.byType(Container),
          )
          .first,
    );
    final action = tester.getRect(
      find.ancestor(
        of: find.text('Proceed to Location'),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(smallPanel.height, lessThanOrEqualTo(216));
    expect(action.height, greaterThanOrEqualTo(52));
    expect(action.bottom, lessThanOrEqualTo(smallPanel.bottom - 12));
    expect(find.text('Proceed to Location').hitTestable(), findsOneWidget);
    await capture('site-verification-portrait-small');
    tester.view.physicalSize = const Size(390, 844);
    await settle(tester);
    await tester.tap(find.byTooltip('Hide site details'));
    await settle(tester);
    await capture('site-verification-collapsed');
    await tester.tap(find.byTooltip('Show site details'));
    await settle(tester);
    tester.view.physicalSize = const Size(844, 390);
    tester.view.padding = const FakeViewPadding(left: 24, bottom: 24);
    await settle(tester);
    await tester.tap(find.byTooltip('Fit both markers'));
    await settle(tester);
    await capture('site-verification-landscape');
    expect(
      find.text('Proceed to Location').hitTestable(),
      findsOneWidget,
      reason: 'the normal landscape action should be visible without a scroll',
    );
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    await settle(tester);
    await capture('site-verification-landscape-text-2x');
    await tester.ensureVisible(find.text('Proceed to Location'));
    await settle(tester);
    await capture('site-verification-landscape-text-2x-action');
    tester.view.physicalSize = const Size(390, 844);
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    await settle(tester);
    await tester.tap(find.byTooltip('Fit both markers'));
    await settle(tester);
    await capture('site-verification-portrait-text-2x');
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
    online = false;
    httpFixture.routeJson = null;
    httpFixture.streetTilesAvailable = false;
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await mount(tester, const Size(390, 844));
    expect(find.text('Saved road route'), findsOneWidget);
    expect(
      find.textContaining('Offline rerouting is unavailable'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Fit both markers'));
    await settle(tester);
    await capture('site-verification-offline');
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
    online = true;
    httpFixture.routeJson = onlineRoute;
    httpFixture.streetTilesAvailable = true;
    await tester.runAsync(() => db.delete('local_route_cache'));
    await mount(tester, const Size(320, 568), scale: 2);
    expect(
      tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .mapController!
          .camera
          .zoom,
      greaterThan(10),
    );
    await capture('site-verification-small-phone-text-2x');
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
    await tester.runAsync(() => db.delete('local_route_cache'));
    await mount(
      tester,
      const Size(320, 568),
      textScaler: const _Android200TextScaler(),
    );
    await capture('site-verification-android-nonlinear-200');
    await tester.ensureVisible(find.text('Proceed to Location'));
    await settle(tester);
    await capture('site-verification-android-nonlinear-200-action');
    if (output != null) {
      File('$output/composition-metrics.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(measurements),
      );
      File('$output/requested-tiles.json').writeAsStringSync(
        jsonEncode(httpFixture.requestedTiles.toList()..sort()),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('fit keeps real route geometry clear of header and details', (
    tester,
  ) async {
    await mount(tester, const Size(390, 844));
    await tester.tap(find.byTooltip('Fit both markers'));
    await settle(tester);
    final camera = tester
        .widget<FlutterMap>(find.byType(FlutterMap))
        .mapController!
        .camera;
    final route = tester
        .widget<PolylineLayer>(find.byType(PolylineLayer))
        .polylines
        .single
        .points;
    expect(route, const [device, LatLng(13.8358, 121.1818), target]);
    final top = tester.getRect(find.byType(InspectionStepHeader)).bottom + 8;
    final bottom =
        tester.getRect(find.text('© OpenStreetMap contributors')).top - 28;
    for (final point in route) {
      final screenPoint = camera.latLngToScreenPoint(point);
      expect(screenPoint.y, inInclusiveRange(top, bottom));
    }
    final targetLabel = tester.getRect(find.text('Target site'));
    expect(
      targetLabel.right,
      lessThanOrEqualTo(374),
      reason: 'the full marker label must fit',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'saved geometry without metrics never fabricates a driving estimate',
    (tester) async {
      await tester.runAsync(
        () => DBHelper.saveRouteCache(
          CachedRoute(
            jobId: task.id,
            points: const [device, LatLng(13.8358, 121.1818), target],
            originLat: device.latitude,
            originLng: device.longitude,
            fetchedAt: DateTime.utc(2026, 10, 9),
          ),
        ),
      );
      await mount(tester, const Size(390, 844));
      expect(find.text('Saved road route'), findsOneWidget);
      expect(find.byType(PolylineLayer), findsOneWidget);
      expect(find.text('Estimate unavailable'), findsOneWidget);
      expect(find.textContaining('less than a minute'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'collapse/fullscreen/rotation keep the map and restore disclosure state',
    (tester) async {
      await mount(tester, const Size(390, 844));
      final mapState = tester.state(find.byType(FlutterMap));
      await tester.tap(find.byTooltip('Hide site details'));
      await settle(tester);
      expect(find.text('Direct to mapped site'), findsNothing);
      expect(find.byTooltip('Show site details'), findsOneWidget);
      final collapsedFit = tester.getCenter(find.byTooltip('Fit both markers'));
      await tester.tap(find.byTooltip('Full map'));
      await settle(tester);
      expect(find.text('Site Verification'), findsNothing);
      expect(find.text('Site details'), findsNothing);
      expect(find.byTooltip('Exit full map'), findsOneWidget);
      tester.view.physicalSize = const Size(844, 390);
      await settle(tester);
      await tester.tap(find.byTooltip('Exit full map'));
      await settle(tester);
      expect(find.byTooltip('Show site details'), findsOneWidget);
      expect(tester.state(find.byType(FlutterMap)), same(mapState));
      tester.view.physicalSize = const Size(390, 844);
      await settle(tester);
      await tester.tap(find.byTooltip('Show site details'));
      await settle(tester);
      expect(find.text('Direct to mapped site'), findsOneWidget);
      expect(
        tester.getCenter(find.byTooltip('Fit both markers')).dy,
        lessThan(collapsedFit.dy),
      );
      await tester.tap(find.byTooltip('Fit both markers'));
      await settle(tester);
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(map.mapController!.camera.visibleBounds.contains(target), isTrue);
      expect(map.mapController!.camera.visibleBounds.contains(device), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cached route is truthful online; absent route and GPS never block Step 2',
    (tester) async {
      online = true;
      await mount(tester, const Size(390, 844));
      expect(find.text('Saved road route'), findsOneWidget);
      expect(
        find.textContaining('· Offline'),
        findsNothing,
        reason: 'cache provenance does not establish connectivity',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      await tester.runAsync(() => db.delete('local_route_cache'));
      gps = false;
      await mount(tester, const Size(390, 844));
      expect(find.text('Location unavailable'), findsOneWidget);
      expect(find.text('Road route unavailable'), findsOneWidget);
      expect(find.byType(PolylineLayer), findsNothing);
      gps = true;
      await tester.ensureVisible(find.text('Retry location'));
      await tester.tap(find.text('Retry location'));
      await settle(tester);
      expect(locationRequests, greaterThan(0));
      expect(find.text('Location unavailable'), findsNothing);
      await tester.ensureVisible(find.text('Proceed to Location'));
      await tester.tap(find.text('Proceed to Location'));
      await settle(tester);
      expect(find.byType(GpsVerificationScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'missing GPS and road route still complete Step 1 and open verification',
    (tester) async {
      gps = false;
      await tester.runAsync(() => db.delete('local_route_cache'));
      InspectionProgress.instance.ensureActiveInspection(
        task.id,
        initialStep: 0,
      );
      await mount(tester, const Size(390, 844));
      expect(find.text('Location unavailable'), findsOneWidget);
      expect(find.byType(PolylineLayer), findsNothing);
      await tester.ensureVisible(find.text('Proceed to Location'));
      await tester.tap(find.text('Proceed to Location'));
      await settle(tester);
      expect(find.byType(GpsVerificationScreen), findsOneWidget);
      expect(InspectionProgress.instance.highestCompleted, 1);
      final saved = await tester.runAsync(
        () => db.query(
          'local_inspections',
          columns: ['current_step'],
          where: 'id = ?',
          whereArgs: [task.id],
        ),
      );
      expect(saved!.single['current_step'], 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'rework Save returns to its caller without entering the GPS wizard',
    (tester) async {
      await mount(tester, const Size(844, 390), rework: true);
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(find.byType(SiteMapScreen), findsNothing);
      expect(find.byType(GpsVerificationScreen), findsNothing);
      expect(find.text('Open demonstration'), findsOneWidget);
      expect(InspectionProgress.instance.highestCompleted, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
