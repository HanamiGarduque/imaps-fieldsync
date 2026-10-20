// FS-03 P1–P4 regression suite for the Step 2 GPS verification gates.
//
// Covers: accuracy ≤ 25 m and freshness ≤ 15 s required alongside the
// preserved inclusive ≤ 30 m distance rule; outright rejection of missing,
// invalid, stale or significantly future-dated fixes; the Acquiring /
// Inaccurate / Outdated / Unavailable / Ready states; stationary expiry;
// bounded, lifecycle-aware stream recovery; the bounded initial-fix timeout
// with a working Retry; and evidence saved from the same accepted fix.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
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
import 'package:imaps_fieldsync/modules/inspection/providers/inspection_provider.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/gps_verification_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/inspection_progress.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const inspectorId = 'gps-gate-inspector';
  const jobId = 'gps-gate-job';
  const parcelId = 'gps-gate-parcel';
  const locationChannelName = 'flutter.baseflow.com/geolocator';
  const updatesChannelName = 'flutter.baseflow.com/geolocator_updates';

  final task = TaskItem(
    id: jobId,
    parcelId: parcelId,
    name: 'GPS gate fixture',
    location: 'Fictional fixture location',
    parcels: '1',
    status: 'in_progress',
    inspectionNo: 'DEMO-FS03',
  );

  late TestDefaultBinaryMessenger messenger;
  late Database db;
  late InspectionProvider provider;

  var online = true;
  var distance = 10.0;
  var gpsEnabled = true;
  var permission = 3;
  var requestedPermission = 3;
  var holdInitialFix = false;
  var fixAccuracy = 5.0;
  var fixLatitude = 13.8425;
  var fixLongitude = 121.1765;
  Map<String, Object>? servedInitialFix;
  var listenCount = 0;
  Map<dynamic, dynamic>? streamSettings;
  Completer<http.Response>? heldGpsConfirm;
  Map<String, dynamic>? attemptedGpsEvidence;
  var fakeNow = DateTime(2026, 10, 16, 12, 0, 0);

  Map<String, Object> fixMap({
    double? lat,
    double? lng,
    double? accuracy,
    DateTime? timestamp,
  }) => {
    'latitude': lat ?? fixLatitude,
    'longitude': lng ?? fixLongitude,
    'accuracy': accuracy ?? fixAccuracy,
    'timestamp': (timestamp ?? fakeNow).millisecondsSinceEpoch,
    'altitude': 0.0,
    'heading': 0.0,
    'speed': 0.0,
    'speed_accuracy': 0.0,
  };

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    final sdkFonts = Directory(
      '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts',
    );
    final sdkBytes = ByteData.sublistView(
      sdkFonts
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
          final asset = const StringCodec().decodeMessage(message)!;
          if (asset == 'AssetManifest.bin') {
            return const StandardMessageCodec().encodeMessage(manifest);
          }
          if (!asset.endsWith('.ttf')) return null;
          final folder = Platform.environment['IMAPS_LAYOUT_FONT_DIR'];
          return folder == null
              ? sdkBytes
              : ByteData.sublistView(
                  File(
                    '$folder/${asset.split('-').first}.ttf',
                  ).readAsBytesSync(),
                );
        });
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    for (final match in RegExp(
      r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)',
    ).allMatches(File('lib/core/services/db_helper.dart').readAsStringSync())) {
      await db.execute(match.group(0)!);
    }
    DBHelper.useDatabaseForTesting(db);
    DBHelper.inspectorIdForTesting = inspectorId;

    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel(locationChannelName),
      (call) async {
        switch (call.method) {
          case 'isLocationServiceEnabled':
            return gpsEnabled;
          case 'checkPermission':
            return permission;
          case 'requestPermission':
            return requestedPermission;
          case 'getCurrentPosition':
            if (holdInitialFix) return Completer<Object?>().future;
            return servedInitialFix ?? fixMap();
        }
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel(updatesChannelName),
      (call) async {
        if (call.method == 'listen') {
          listenCount++;
          streamSettings = call.arguments as Map?;
        }
        return null;
      },
    );
    for (final channel in [
      'hemanthraj/flutter_compass',
      'screen_protector',
      'dev.fluttercommunity.plus/connectivity_status',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(channel),
        (_) async => null,
      );
    }
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (_) async => [online ? 'wifi' : 'none'],
    );

    await Supabase.initialize(
      url: 'https://gps-gate.test',
      publishableKey: 'isolated-fixture-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        if (request.url.host != 'gps-gate.test') {
          throw StateError('Unexpected request host');
        }
        if (request.method == 'PATCH' &&
            request.url.path.endsWith('/field_jobs') &&
            heldGpsConfirm != null) {
          attemptedGpsEvidence =
              jsonDecode(request.body) as Map<String, dynamic>;
          return heldGpsConfirm!.future;
        }
        if (request.method != 'GET' && !request.url.path.contains('/rpc/')) {
          throw StateError(
            'Fixture must not submit an inspection while online',
          );
        }
        Object response = [];
        if (request.url.path.contains('/rpc/')) response = distance;
        if (request.url.path.endsWith('/supabase_parcels')) {
          response = {'latitude': 13.8486, 'longitude': 121.19};
        }
        return http.Response(
          jsonEncode(response),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });

  setUp(() async {
    online = true;
    distance = 10.0;
    gpsEnabled = true;
    permission = 3;
    requestedPermission = 3;
    holdInitialFix = false;
    fixAccuracy = 5.0;
    fixLatitude = 13.8425;
    fixLongitude = 121.1765;
    servedInitialFix = null;
    listenCount = 0;
    streamSettings = null;
    heldGpsConfirm = null;
    attemptedGpsEvidence = null;
    fakeNow = DateTime(2026, 10, 16, 12, 0, 0);
    provider = InspectionProvider();
    await db.delete('pending_actions');
  });

  tearDown(() => provider.dispose());

  tearDownAll(() async {
    await Supabase.instance.dispose();
    DBHelper.useDatabaseForTesting(null);
    DBHelper.inspectorIdForTesting = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
    await db.close();
  });

  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
    }
  }

  Future<void> mountGps(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          home: GpsVerificationScreen(task: task, clock: () => fakeNow),
        ),
      ),
    );
    await flush(tester);
  }

  Future<void> unmountGps(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await flush(tester);
  }

  bool confirmEnabled(WidgetTester tester) {
    final button = find.widgetWithText(ElevatedButton, 'Confirm GPS');
    return tester.widget<ElevatedButton>(button).onPressed != null;
  }

  Future<void> deliverStreamFix(
    WidgetTester tester,
    Map<String, Object> fix,
  ) async {
    await messenger.handlePlatformMessage(
      updatesChannelName,
      const StandardMethodCodec().encodeSuccessEnvelope(fix),
      (_) {},
    );
    await flush(tester);
  }

  Future<void> deliverStreamError(WidgetTester tester) async {
    await messenger.handlePlatformMessage(
      updatesChannelName,
      const StandardMethodCodec().encodeErrorEnvelope(
        code: 'GPS_STREAM_LOST',
        message: 'interrupted',
      ),
      (_) {},
    );
    await tester.pump();
  }

  Future<void> advance(WidgetTester tester, Duration span) async {
    fakeNow = fakeNow.add(span);
    await tester.pump(span + const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 20));
  }

  testWidgets(
    'an accurate fresh in-range fix shows Ready to confirm and enables Confirm GPS',
    (tester) async {
      distance = 12.0;
      await mountGps(tester);
      expect(find.text('Ready to confirm'), findsOneWidget);
      expect(find.text('Outside zone'), findsNothing);
      expect(find.text('12 m'), findsOneWidget);
      expect(find.text('± 5 m'), findsOneWidget);
      expect(confirmEnabled(tester), isTrue);
    },
  );

  testWidgets(
    'accuracy worse than 25 m shows Inaccurate and disables Confirm GPS',
    (tester) async {
      distance = 8.0;
      fixAccuracy = 40.0;
      await mountGps(tester);
      expect(find.text('Inaccurate'), findsOneWidget);
      expect(find.text('± 40 m'), findsOneWidget);
      expect(
        find.text('Move to an open area — accuracy must be ≤ 25 m.'),
        findsOneWidget,
      );
      expect(confirmEnabled(tester), isFalse);
    },
  );

  testWidgets('accuracy exactly at the 25 m gate stays confirmable', (
    tester,
  ) async {
    distance = 8.0;
    fixAccuracy = 25.0;
    await mountGps(tester);
    expect(find.text('Ready to confirm'), findsOneWidget);
    expect(confirmEnabled(tester), isTrue);
  });

  testWidgets('a fix older than 15 s on delivery is rejected outright', (
    tester,
  ) async {
    servedInitialFix = fixMap(
      timestamp: fakeNow.subtract(const Duration(seconds: 16)),
    );
    await mountGps(tester);
    expect(find.text('Acquiring'), findsOneWidget);
    expect(find.text('-- m'), findsOneWidget);
    expect(confirmEnabled(tester), isFalse);
  });

  testWidgets('a significantly future-dated fix is rejected outright', (
    tester,
  ) async {
    servedInitialFix = fixMap(
      timestamp: fakeNow.add(const Duration(seconds: 60)),
    );
    await mountGps(tester);
    expect(find.text('Acquiring'), findsOneWidget);
    expect(confirmEnabled(tester), isFalse);
  });

  testWidgets('two seconds of clock skew still counts as fresh', (
    tester,
  ) async {
    servedInitialFix = fixMap(
      timestamp: fakeNow.add(const Duration(seconds: 2)),
    );
    await mountGps(tester);
    expect(find.text('Ready to confirm'), findsOneWidget);
    expect(confirmEnabled(tester), isTrue);
  });

  for (final invalid in <String, Map<String, Object>>{
    'zero accuracy': {'accuracy': 0.0},
    'negative accuracy': {'accuracy': -1.0},
    'NaN accuracy': {'accuracy': double.nan},
    'infinite accuracy': {'accuracy': double.infinity},
    'invalid latitude': {'latitude': 91.0},
    'invalid longitude': {'longitude': 181.0},
    'NaN coordinate': {'latitude': double.nan},
    'infinite coordinate': {'longitude': double.infinity},
  }.entries) {
    testWidgets('${invalid.key} cannot become a confirmable fix', (
      tester,
    ) async {
      servedInitialFix = {...fixMap(), ...invalid.value};
      await mountGps(tester);
      expect(find.text('Acquiring'), findsOneWidget);
      expect(find.text('-- m'), findsOneWidget);
      expect(confirmEnabled(tester), isFalse);
    });
  }

  testWidgets('missing accuracy cannot become a confirmable fix', (
    tester,
  ) async {
    servedInitialFix = fixMap()..remove('accuracy');
    await mountGps(tester);
    expect(find.text('Acquiring'), findsOneWidget);
    expect(confirmEnabled(tester), isFalse);
  });

  testWidgets('a missing coordinate fails acquisition with a retry action', (
    tester,
  ) async {
    servedInitialFix = fixMap()..remove('longitude');
    await mountGps(tester);
    expect(find.text('Location unavailable'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Confirm GPS'), findsNothing);
  });

  testWidgets('a fix exactly 15 seconds old is accepted', (tester) async {
    servedInitialFix = fixMap(
      timestamp: fakeNow.subtract(const Duration(seconds: 15)),
    );
    await mountGps(tester);
    expect(confirmEnabled(tester), isTrue);
  });

  testWidgets(
    'an accepted fix expires stationary: Outdated, disabled, then recovers on a stream fix',
    (tester) async {
      distance = 9.0;
      await mountGps(tester);
      expect(confirmEnabled(tester), isTrue);

      await advance(tester, const Duration(seconds: 16));
      expect(find.text('Outdated'), findsOneWidget);
      expect(find.text('Waiting for a fresh GPS fix...'), findsOneWidget);
      expect(confirmEnabled(tester), isFalse);

      await deliverStreamFix(tester, fixMap());
      expect(find.text('Ready to confirm'), findsOneWidget);
      expect(confirmEnabled(tester), isTrue);
    },
  );

  testWidgets('the inclusive 30 m boundary is preserved with a valid fix', (
    tester,
  ) async {
    distance = 30.0;
    await mountGps(tester);
    expect(find.text('Ready to confirm'), findsOneWidget);
    expect(confirmEnabled(tester), isTrue);

    await unmountGps(tester);
    distance = 30.01;
    await mountGps(tester);
    expect(find.text('Outside zone'), findsOneWidget);
    expect(find.text('Required ≤ 30 m'), findsOneWidget);
    expect(
      find.byTooltip('Move within 30 m of the site to confirm.'),
      findsOneWidget,
    );
    expect(confirmEnabled(tester), isFalse);
  });

  testWidgets(
    'denied permission shows Location unavailable and Try again recovers',
    (tester) async {
      // 0 = LocationPermission.denied (which triggers a runtime request);
      // 1 would be deniedForever, a different message and no request dialog.
      permission = 0;
      requestedPermission = 0;
      await mountGps(tester);
      expect(find.text('Location unavailable'), findsOneWidget);
      expect(
        find.text(
          'Location access is needed to verify the site. Allow location access '
          'for FieldSync in your device settings, then try again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
      expect(find.byKey(const ValueKey('gps-details')), findsNothing);

      permission = 3;
      requestedPermission = 3;
      await tester.tap(find.text('Try again'));
      await flush(tester);
      expect(find.text('Location unavailable'), findsNothing);
      expect(find.text('Ready to confirm'), findsOneWidget);
      expect(confirmEnabled(tester), isTrue);
    },
  );

  testWidgets(
    'disabled location services show Location unavailable and Try again recovers',
    (tester) async {
      gpsEnabled = false;
      await mountGps(tester);
      expect(find.text('Location unavailable'), findsOneWidget);
      expect(
        find.text(
          'Location services are off. Turn on GPS/location in your device '
          'settings, then try again.',
        ),
        findsOneWidget,
      );

      gpsEnabled = true;
      await tester.tap(find.text('Try again'));
      await flush(tester);
      expect(find.text('Ready to confirm'), findsOneWidget);
      expect(confirmEnabled(tester), isTrue);
    },
  );

  testWidgets('the initial fix wait is bounded and Try again recovers', (
    tester,
  ) async {
    holdInitialFix = true;
    await mountGps(tester);
    expect(find.text('Acquiring satellite lock...'), findsOneWidget);
    expect(find.text('Location unavailable'), findsNothing);

    await tester.pump(const Duration(seconds: 16));
    await flush(tester);
    expect(find.text('Location unavailable'), findsOneWidget);
    expect(
      find.text('No GPS fix yet. Move to an open area and try again.'),
      findsOneWidget,
    );

    holdInitialFix = false;
    await tester.tap(find.text('Try again'));
    await flush(tester);
    expect(find.text('Ready to confirm'), findsOneWidget);
    expect(confirmEnabled(tester), isTrue);
  });

  testWidgets(
    'stream failures recover through a bounded backoff and then stop with Reconnect GPS',
    (tester) async {
      distance = 10.0;
      await mountGps(tester);
      expect(listenCount, 1);
      expect(find.text('Ready to confirm'), findsOneWidget);

      await deliverStreamError(tester);
      await tester.pump(const Duration(seconds: 4));
      await flush(tester);
      expect(listenCount, 2);

      await deliverStreamError(tester);
      await tester.pump(const Duration(seconds: 7));
      await flush(tester);
      expect(listenCount, 3);

      await deliverStreamError(tester);
      await tester.pump(const Duration(seconds: 13));
      await flush(tester);
      expect(listenCount, 4);

      await deliverStreamError(tester);
      await tester.pump(const Duration(seconds: 20));
      await flush(tester);
      expect(
        listenCount,
        4,
        reason: 'recovery attempts are bounded, not endless polling',
      );
      expect(find.text('Reconnect GPS'), findsOneWidget);

      await tester.ensureVisible(find.text('Reconnect GPS'));
      await tester.tap(find.text('Reconnect GPS'));
      await flush(tester);
      expect(listenCount, 5);
      expect(find.text('Reconnect GPS'), findsNothing);

      await deliverStreamFix(tester, fixMap());
      expect(find.text('Ready to confirm'), findsOneWidget);
      expect(confirmEnabled(tester), isTrue);
    },
  );

  testWidgets(
    'app resume after a stream failure restarts tracking without waiting for the backoff',
    (tester) async {
      await mountGps(tester);
      expect(listenCount, 1);

      await deliverStreamError(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(listenCount, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await flush(tester);
      expect(listenCount, 2);

      await tester.pump(const Duration(seconds: 10));
      expect(
        listenCount,
        2,
        reason: 'the superseded backoff must not double-subscribe',
      );
    },
  );

  testWidgets(
    'stationary verification requests updates without a movement filter',
    (tester) async {
      await mountGps(tester);
      expect(
        streamSettings?['distanceFilter'],
        0,
        reason: 'a stationary inspector still needs a fresh fix',
      );
    },
  );

  testWidgets(
    'silent GPS is restarted with a bounded budget and offers Reconnect',
    (tester) async {
      await mountGps(tester);
      for (final backoff in [4, 7, 13]) {
        await advance(tester, const Duration(seconds: 21));
        await tester.pump(Duration(seconds: backoff));
        await flush(tester);
      }
      expect(
        listenCount,
        4,
        reason: 'initial subscription plus three recovery attempts',
      );
      await advance(tester, const Duration(seconds: 60));
      await flush(tester);
      expect(
        listenCount,
        4,
        reason: 'silence must not create endless resubscriptions',
      );
      expect(find.text('Reconnect GPS'), findsOneWidget);
      expect(confirmEnabled(tester), isFalse);
    },
  );

  testWidgets('a closed stream recovers and accepts a fresh fix', (
    tester,
  ) async {
    await mountGps(tester);
    await messenger.handlePlatformMessage(updatesChannelName, null, (_) {});
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    await flush(tester);
    expect(listenCount, 2);
    await deliverStreamFix(tester, fixMap());
    expect(find.text('Ready to confirm'), findsOneWidget);
  });

  testWidgets(
    'GPS recovery waits while backgrounded and restarts once on resume',
    (tester) async {
      await mountGps(tester);
      await deliverStreamError(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      try {
        await tester.pump(const Duration(seconds: 60));
        await flush(tester);
        expect(
          listenCount,
          1,
          reason: 'no GPS retry or polling while backgrounded',
        );
      } finally {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      await flush(tester);
      expect(listenCount, 2);
      await deliverStreamFix(tester, fixMap());
      expect(confirmEnabled(tester), isTrue);
    },
  );

  testWidgets(
    'resume replaces a silent expired subscription without waiting for an error',
    (tester) async {
      await mountGps(tester);
      fakeNow = fakeNow.add(const Duration(seconds: 16));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await flush(tester);
      expect(listenCount, 2);
      expect(confirmEnabled(tester), isFalse);
      await deliverStreamFix(tester, fixMap());
      expect(confirmEnabled(tester), isTrue);
    },
  );

  testWidgets(
    'Confirm queues evidence from the accepted fix, never from a rejected delivery',
    (tester) async {
      online = false;
      await tester.runAsync(
        () => DBHelper.cacheJobs([
          {
            'id': jobId,
            'assigned_inspector_id': inspectorId,
            'status': 'assigned',
            'supabase_parcel_id': parcelId,
            'supabase_parcels': {'latitude': 13.8425, 'longitude': 121.1765},
          },
        ]),
      );
      // The confirm path records into the provider, which requires the session
      // owner — normally set when the inspection starts (mirrors the app flow).
      await tester.runAsync(() => provider.startInspection(task));
      InspectionProgress.instance.ensureActiveInspection(jobId, initialStep: 0);
      await mountGps(tester);

      expect(find.text('0 m'), findsOneWidget);
      expect(find.text('± 5 m'), findsOneWidget);
      expect(find.text('13°50\'33"N   121°10\'35"E'), findsOneWidget);
      expect(find.text('Offline'), findsOneWidget);
      expect(
        find.byTooltip('Offline · Distance to cached site point'),
        findsOneWidget,
      );
      expect(confirmEnabled(tester), isTrue);

      // A stale delivery with unrelated coordinates must not replace the
      // accepted fix used for the readouts or the saved evidence.
      await deliverStreamFix(
        tester,
        fixMap(
          lat: 13.9,
          lng: 121.25,
          accuracy: 4.0,
          timestamp: fakeNow.subtract(const Duration(seconds: 60)),
        ),
      );
      expect(find.text('13°50\'33"N   121°10\'35"E'), findsOneWidget);
      expect(find.text('0 m'), findsOneWidget);
      expect(confirmEnabled(tester), isTrue);

      await tester.ensureVisible(find.text('Confirm GPS'));
      await tester.tap(find.text('Confirm GPS'));
      await flush(tester);
      expect(
        find.text(
          'No signal — GPS check-in saved offline, will sync automatically.',
        ),
        findsOneWidget,
      );

      final actions = (await tester.runAsync(
        () => DBHelper.getActionableActions(),
      ))!;
      final gps = actions.firstWhere((a) => a['type'] == 'gps_confirm');
      final payload =
          jsonDecode(gps['payload'] as String) as Map<String, dynamic>;
      expect(payload['latitude'], 13.8425);
      expect(payload['longitude'], 121.1765);
      expect(payload['accuracyMeters'], 5.0);

      // Step 2 remains mounted under Photos. Its new watchdog must not keep
      // restarting high-accuracy GPS while that route is covered.
      expect(listenCount, 1);
      await advance(tester, const Duration(seconds: 30));
      await flush(tester);
      expect(
        listenCount,
        1,
        reason: 'covered GPS verification must release tracking',
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await flush(tester);
      expect(
        listenCount,
        1,
        reason: 'app resume must not restart a covered route',
      );
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await flush(tester);
      expect(
        listenCount,
        2,
        reason: 'returning to Step 2 restarts tracking once',
      );
      await deliverStreamFix(tester, fixMap());
      expect(confirmEnabled(tester), isTrue);
    },
  );

  testWidgets(
    'a failed online confirm queues the fix and distance accepted at the tap',
    (tester) async {
      await tester.runAsync(() async {
        await DBHelper.cacheJobs([
          {
            'id': jobId,
            'assigned_inspector_id': inspectorId,
            'status': 'assigned',
            'supabase_parcel_id': parcelId,
          },
        ]);
        await provider.startInspection(task);
        // Fictional local session; all traffic is restricted to the MockClient.
        await Supabase.instance.client.auth.setInitialSession(
          jsonEncode({
            'access_token': 'isolated-demo-token',
            'refresh_token': 'isolated-demo-refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': inspectorId,
              'app_metadata': {},
              'user_metadata': {},
              'aud': 'authenticated',
              'created_at': '2026-01-01T00:00:00Z',
            },
          }),
        );
      });
      InspectionProgress.instance.ensureActiveInspection(jobId, initialStep: 0);
      await mountGps(tester);
      heldGpsConfirm = Completer<http.Response>();
      await tester.ensureVisible(find.text('Confirm GPS'));
      await tester.tap(find.text('Confirm GPS'));
      await flush(tester);
      expect(attemptedGpsEvidence?['confirmed_latitude'], 13.8425);

      distance = 80;
      await deliverStreamFix(
        tester,
        fixMap(lat: 13.9, lng: 121.25, accuracy: 9),
      );
      expect(find.text('80 m'), findsOneWidget);
      heldGpsConfirm!.complete(
        http.Response(
          '{"message":"fixture unavailable"}',
          503,
          headers: {'content-type': 'application/json'},
        ),
      );
      await flush(tester);

      final actions = (await tester.runAsync(
        () => DBHelper.getActionableActions(),
      ))!;
      final gps = actions.firstWhere((a) => a['type'] == 'gps_confirm');
      final payload =
          jsonDecode(gps['payload'] as String) as Map<String, dynamic>;
      expect(payload['latitude'], 13.8425);
      expect(payload['longitude'], 121.1765);
      expect(payload['accuracyMeters'], 5.0);
      expect(
        provider.boundaryStatus,
        'Verified on-site — 10m from declared location',
      );
    },
  );
}
