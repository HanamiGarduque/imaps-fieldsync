import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/screen_protection_service.dart';
import 'package:imaps_fieldsync/modules/offline_sync/screens/updates_screen.dart';
import 'package:imaps_fieldsync/qa/demo_fixtures.dart';
import 'package:imaps_fieldsync/qa/demo_watermark.dart';

import 'support/offline_reliability_fixture.dart';

void main() {
  final fixture = OfflineReliabilityFixture();
  late DemoFixtures demo;
  var trusted = true;
  setUpAll(fixture.initialize);
  setUp(() async {
    await fixture.reset();
    await fixture.db.delete('local_jobs');
    await fixture.client.auth.setInitialSession(
      jsonEncode(DemoFixtures.session()),
    );
    trusted = true;
    demo = DemoFixtures.forTesting(verifyIdentity: () async => trusted);
  });
  tearDown(fixture.closeCase);
  tearDownAll(fixture.dispose);

  testWidgets(
    'actual Sync receipt presentation is visibly qualified as simulation',
    (tester) async {
      await tester.runAsync(
        () => demo.initialize(documents: fixture.directory),
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) =>
              DemoWatermark(fixtures: demo, child: child!),
          home: UpdatesScreen(profile: DemoFixtures.profile),
        ),
      );
      try {
        await fixture.flush(tester);
        await tester.pump(const Duration(seconds: 2));
        final receipt = find.text('FieldSync-Supabase received');
        await tester.scrollUntilVisible(
          receipt,
          400,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('sync_body')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(receipt, findsOneWidget);
        await tester.ensureVisible(receipt);
        await tester.pumpAndSettle();
        expect(
          find.text('Simulated receipts—nothing delivered'),
          findsOneWidget,
        );
        final qualifier = tester.getRect(
          find.text('Simulated receipts—nothing delivered'),
        );
        expect(qualifier.top, greaterThanOrEqualTo(0));
        expect(qualifier.bottom, lessThan(tester.getRect(receipt).top));
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.unmount(tester);
      }
    },
  );

  test(
    'readiness needs complete fixtures, live trust, owner and mounted watermark',
    () async {
      expect(await demo.captureSourceReady, isFalse);
      demo.watermarkMounted(true);
      expect(await demo.captureSourceReady, isFalse);
      await demo.initialize(documents: fixture.directory);
      expect(await demo.captureSourceReady, isTrue);
      // Source readiness must never authorize the B1 capture service.
      expect(ScreenProtectionService.instance.documentationEnabled, isFalse);
      expect(
        await ScreenProtectionService.instance.beginDocumentation(),
        isFalse,
      );
      demo.watermarkMounted(false);
      expect(await demo.captureSourceReady, isFalse);
      demo.watermarkMounted(true);
      trusted = false;
      expect(await demo.captureSourceReady, isFalse);
      trusted = true;
      expect(
        await demo.captureSourceReady,
        isFalse,
        reason:
            'lost trust latches this runtime closed; a fresh verified startup is required',
      );
    },
  );

  test(
    'owner or revision changes revoke readiness and simulated hardware',
    () async {
      await demo.initialize(documents: fixture.directory);
      demo.watermarkMounted(true);
      expect(await demo.captureSourceReady, isTrue);
      await fixture.client.auth.setInitialSession(
        jsonEncode(fixture.session()),
      );
      expect(await demo.captureSourceReady, isFalse);
      var nativeCalls = 0;
      await expectLater(
        demo.positionOrNative(() async {
          nativeCalls++;
          throw StateError('native GPS must not run');
        }),
        throwsStateError,
      );
      expect(nativeCalls, 0);
      await fixture.client.auth.setInitialSession(
        jsonEncode(DemoFixtures.session()),
      );
      demo = DemoFixtures.forTesting(verifyIdentity: () async => true);
      await demo.initialize(documents: fixture.directory);
      demo.watermarkMounted(true);
      await fixture.db.update('demo_fixture_state', {
        'revision': 'wrong-revision',
      });
      expect(await demo.captureSourceReady, isFalse);
      expect(
        await demo.hardwareMode(jobId: DemoFixtures.jobId(8)),
        DemoHardwareMode.denied,
      );
    },
  );

  test(
    'simulated GPS and camera entry never invoke native hardware or gallery',
    () async {
      await demo.initialize(documents: fixture.directory);
      var nativeCalls = 0;
      var syntheticCalls = 0;
      final before = DateTime.now();
      final position = await demo.positionOrNative(() async {
        nativeCalls++;
        throw StateError('unexpected physical GPS');
      });
      expect(position.latitude, closeTo(0.00012, 0.000001));
      expect(position.longitude, closeTo(-139.99989, 0.000001));
      expect(position.accuracy, 8);
      expect(position.timestamp.isBefore(before), isFalse);
      expect(position.isMocked, isTrue);
      await demo.cameraEntry(
        jobId: DemoFixtures.jobId(8),
        native: () async {
          nativeCalls++;
        },
        synthetic: () async {
          syntheticCalls++;
        },
      );
      expect(nativeCalls, 0);
      expect(syntheticCalls, 1);
      await expectLater(
        demo.cameraEntry(
          jobId: 'foreign-job',
          native: () async {
            nativeCalls++;
          },
          synthetic: () async {
            syntheticCalls++;
          },
        ),
        throwsStateError,
      );
      expect(nativeCalls, 0);
      expect(syntheticCalls, 1);
    },
  );

  test(
    'regular app hardware policy preserves native behavior, never simulation',
    () async {
      final regular = DemoFixtures.forTesting(
        demoBuild: false,
        verifyIdentity: () async => false,
      );
      var nativeCalls = 0;
      await regular.cameraEntry(
        jobId: 'ordinary-job',
        native: () async {
          nativeCalls++;
        },
        synthetic: () async =>
            fail('regular app must not use generated evidence'),
      );
      expect(nativeCalls, 1);
      expect(await regular.captureSourceReady, isFalse);
      expect(
        await DemoFixtures.instance.hardwareMode(),
        DemoHardwareMode.production,
        reason:
            'an isolated test instance cannot install a global debug bypass',
      );
    },
  );

  testWidgets(
    'root watermark stays above routes, dialog, sheet and overlay without covering controls',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final semantics = tester.ensureSemantics();
      try {
        final navigator = GlobalKey<NavigatorState>();
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            builder: (context, child) =>
                DemoWatermark(fixtures: demo, child: child!),
            home: Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => taps++,
                  child: const Text('Primary action'),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final mark = find.text('DEMO · SYNTHETIC DATA');
        expect(mark, findsOneWidget);
        expect(
          find.bySemanticsLabel(RegExp('DEMO · SYNTHETIC DATA')),
          findsOneWidget,
        );
        expect(
          tester.getRect(mark).bottom,
          lessThan(tester.getRect(find.text('Primary action')).top),
        );
        await tester.tap(find.text('Primary action'));
        expect(taps, 1);
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Next route')),
          ),
        );
        await tester.pumpAndSettle();
        expect(mark, findsOneWidget);
        expect(
          find.bySemanticsLabel(RegExp('DEMO · SYNTHETIC DATA')),
          findsOneWidget,
        );
        final context = navigator.currentState!.overlay!.context;
        showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(content: Text('Dialog content')),
        );
        await tester.pumpAndSettle();
        expect(mark, findsOneWidget);
        expect(
          find.bySemanticsLabel(RegExp('DEMO · SYNTHETIC DATA')),
          findsOneWidget,
        );
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        showModalBottomSheet<void>(
          context: context,
          builder: (_) =>
              const SizedBox(height: 120, child: Text('Sheet content')),
        );
        await tester.pumpAndSettle();
        expect(mark, findsOneWidget);
        expect(
          find.bySemanticsLabel(RegExp('DEMO · SYNTHETIC DATA')),
          findsOneWidget,
        );
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        final entry = OverlayEntry(
          builder: (_) =>
              const Positioned.fill(child: ColoredBox(color: Colors.blue)),
        );
        navigator.currentState!.overlay!.insert(entry);
        await tester.pump();
        expect(mark, findsOneWidget);
        expect(
          find.bySemanticsLabel(RegExp('DEMO · SYNTHETIC DATA')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        entry.remove();
        entry.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        expect(await demo.captureSourceReady, isFalse);
      } finally {
        // Flutter verifies handle cleanup before package:test addTearDown runs.
        semantics.dispose();
      }
    },
  );
}
