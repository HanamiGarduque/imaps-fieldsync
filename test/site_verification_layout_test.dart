import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
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
  late Database db;
  late HttpOverrides? originalHttp;
  var online = false;
  var gps = true;
  var locationRequests = 0;
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

  setUpAll(() async {
    originalHttp = HttpOverrides.current;
    HttpOverrides.global = SiteMapHttpFixture();
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
    await RosarioBoundaryLoader.shared.load();
    await Supabase.initialize(
      url: 'https://site-layout.test',
      publishableKey: 'fixture-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient(
        (request) async => http.Response(
          request.url.path.contains('/rpc/')
              ? '1600'
              : jsonEncode({
                  'latitude': target.latitude,
                  'longitude': target.longitude,
                }),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        ),
      ),
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
            return {
              'latitude': device.latitude,
              'longitude': device.longitude,
              'accuracy': 5.0,
              'timestamp': 0,
              'altitude': 0.0,
              'heading': 0.0,
              'speed': 0.0,
              'speed_accuracy': 0.0,
            };
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
  });

  setUp(() async {
    online = false;
    gps = true;
    locationRequests = 0;
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
  }

  Future<void> mount(
    WidgetTester tester,
    Size size, {
    double scale = 1,
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
    });
  }

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets(
      'portrait controls and split landscape remain reachable at $scale',
      (tester) async {
        await mount(tester, const Size(390, 844), scale: scale);
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
          for (final control in [full, fit]) {
            expect(control, findsOneWidget);
            expect(tester.getSize(control).width, greaterThanOrEqualTo(48));
            expect(tester.getSize(control).height, greaterThanOrEqualTo(48));
            expect(control.hitTestable(), findsOneWidget,
                reason: '$size at $scale: ${tester.getRect(control)}');
          }
          if (size.width < size.height) {
            expect(tester.getCenter(full).dx, tester.getCenter(fit).dx);
            expect(
              tester.getRect(full).bottom,
              lessThanOrEqualTo(tester.getRect(fit).top),
            );
          } else {
            expect(
              tester.getRect(find.byType(FlutterMap)).right,
              lessThanOrEqualTo(tester.getRect(find.text('Site details')).left),
            );
          }
          await tester.ensureVisible(find.text('Proceed to Location'));
          await settle(tester);
          expect(
            find.text('Proceed to Location').hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull, reason: '$size at $scale');
        }
      },
    );
  }

  testWidgets(
    'collapse/fullscreen/rotation keep the map and restore disclosure state',
    (tester) async {
      await mount(tester, const Size(390, 844));
      final mapState = tester.state(find.byType(FlutterMap));
      await tester.tap(find.byTooltip('Hide site details'));
      await settle(tester);
      expect(find.text('Site distance'), findsNothing);
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
      expect(find.text('Site distance'), findsOneWidget);
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
        find.textContaining('Offline'),
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
      InspectionProgress.instance.ensureActiveInspection(task.id, initialStep: 0);
      await mount(tester, const Size(390, 844));
      expect(find.text('Location unavailable'), findsOneWidget);
      expect(find.byType(PolylineLayer), findsNothing);
      await tester.ensureVisible(find.text('Proceed to Location'));
      await tester.tap(find.text('Proceed to Location'));
      await settle(tester);
      expect(find.byType(GpsVerificationScreen), findsOneWidget);
      expect(InspectionProgress.instance.highestCompleted, 1);
      final saved = await tester.runAsync(() => db.query('local_inspections',
          columns: ['current_step'], where: 'id = ?', whereArgs: [task.id]));
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
