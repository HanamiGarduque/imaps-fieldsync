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
    httpFixture.routeJson = null;
    httpFixture.streetTilesAvailable = true;
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
              expect(tester.getCenter(full).dx, tester.getCenter(fit).dx);
              expect(
                tester.getRect(full).bottom,
                lessThanOrEqualTo(tester.getRect(fit).top),
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
      final site = tester.getRect(find.text('Site distance'));
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
          .ancestor(of: action, matching: find.byType(SingleChildScrollView))
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
      greaterThan(tester.getRect(find.text('Site distance')).bottom),
      reason: 'the actual enlarged caption size requires stacked metrics',
    );
    final backControl = find
        .ancestor(of: find.byTooltip('Back'), matching: find.byType(Container))
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
    expect(find.text('3.4 km · ~8 min'), findsOneWidget);
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
