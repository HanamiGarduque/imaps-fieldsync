import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:imaps_fieldsync/modules/inspection/providers/inspection_provider.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/compass_preview_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/gps_verification_screen.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://compass.test', publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false, detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async => http.Response(
        request.url.path.contains('/rpc/') ? '23000' :
            jsonEncode({'latitude': 14.75, 'longitude': 121.3}),
        200, headers: {'content-type': 'application/json'}, request: request,
      )),
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());

  setUp(() {
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'), (call) async {
        switch (call.method) {
          case 'isLocationServiceEnabled': return true;
          case 'checkPermission': return 3;
          case 'getCurrentPosition': return {
            'latitude': 14.7, 'longitude': 121.2, 'accuracy': 5.0,
            'timestamp': 0, 'altitude': 0.0, 'heading': 166.0, 'speed': 0.0,
            'speed_accuracy': 0.0,
          };
        }
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (_) async => ['wifi'],
    );
    for (final channel in [
      'hemanthraj/flutter_compass', 'flutter.baseflow.com/geolocator_updates',
      'screen_protector',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), (_) async => null);
    }
  });

  for (final gps in [true, false]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('${gps ? "GPS" : "standalone"} rotates and restores headers / $scale',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() {
          tester.view.reset();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        tester.view.physicalSize = const Size(390, 844);
        await tester.pumpWidget(ChangeNotifierProvider(
          create: (_) => InspectionProvider(),
          child: MaterialApp(home: gps ? GpsVerificationScreen(task: TaskItem(
            id: 'test-job', parcelId: 'test-parcel', name: 'Test',
            location: 'San Carlos', parcels: '1', status: 'assigned',
            inspectionNo: 'TEST',
          )) : const StandaloneCompassScreen()),
        ));
        // Pump async GPS and HTTP boundaries without waiting on the live
        // compass needle's repeating animation.
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await messenger.handlePlatformMessage(
          'hemanthraj/flutter_compass',
          const StandardMethodCodec().encodeSuccessEnvelope([166.0, 0.0, 5.0]),
          (_) {},
        );
        await tester.pump();
        final title = gps ? 'GPS Verification' : 'Compass';
        expect(find.text(title), findsOneWidget);
        for (final size in [
          const Size(844, 390), const Size(932, 430),
          const Size(640, 360), const Size(740, 320),
          const Size(1280, 800),
        ]) {
          tester.view.physicalSize = size;
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text(title), findsNothing, reason: '$size');
          expect(find.text('STEP 2 OF 6'), findsNothing);
          expect(find.text('VERIFY COORDINATES'), findsNothing);
          expect(find.text('Live orientation'), findsNothing);
          expect(find.text('STANDALONE'), findsNothing);
          expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
          expect(tester.takeException(), isNull, reason: '$size at $scale');
          expect(find.text('166'), findsOneWidget,
              reason: 'real sensor-driven dial must render');
          final dial = find.ancestor(
            of: find.text('166'), matching: find.byType(Stack),
          ).first;
          expect(tester.getSize(dial).height, greaterThan(170),
              reason: 'the dial must use the reclaimed header space at $size');
        }
        tester.view.physicalSize = const Size(390, 844);
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text(title), findsOneWidget);
        expect(find.text(gps ? 'STEP 2 OF 6' : 'STANDALONE'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      });
    }
  }
}
