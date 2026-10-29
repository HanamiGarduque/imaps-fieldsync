import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/widgets/sensitive_screen.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/screen_protection_observer.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/screen_protection_service.dart';
import 'package:imaps_fieldsync/modules/offline_sync/screens/updates_screen.dart';
import 'package:imaps_fieldsync/qa/demo_fixtures.dart';
import 'package:imaps_fieldsync/qa/demo_watermark.dart';

import 'support/offline_reliability_fixture.dart';

void main() {
  final fixture = OfflineReliabilityFixture();
  late DemoFixtures demo;
  var trusted = true;
  Completer<bool>? sourceAttestation;
  setUpAll(fixture.initialize);
  setUp(() async {
    await fixture.reset();
    await fixture.db.delete('local_jobs');
    await fixture.client.auth.setInitialSession(
      jsonEncode(DemoFixtures.session()),
    );
    trusted = true;
    sourceAttestation = null;
    demo = DemoFixtures.forTesting(
      verifyIdentity: () => sourceAttestation?.future ?? Future.value(trusted),
    );
  });
  tearDown(fixture.closeCase);
  tearDownAll(fixture.dispose);

  Future<void> mountCapture(
    WidgetTester tester,
    ScreenProtectionService protection, {
    GlobalKey<NavigatorState>? navigator,
    ValueNotifier<bool>? visible,
    ValueNotifier<double>? opacity,
  }) async {
    final key = navigator ?? GlobalKey<NavigatorState>();
    await tester.runAsync(() => demo.initialize(documents: fixture.directory));
    await tester.pumpWidget(
      ScreenProtectionScope(
        protection: protection,
        child: MaterialApp(
          navigatorKey: key,
          navigatorObservers: [ScreenProtectionObserver(protection)],
          builder: (context, child) {
            final root = DemoWatermark(
              fixtures: demo,
              navigatorKey: key,
              child: ScreenProtectionHost(
                protection: protection,
                child: child!,
              ),
            );
            if (opacity != null) {
              return ValueListenableBuilder<double>(
                valueListenable: opacity,
                child: root,
                builder: (_, value, child) =>
                    Opacity(opacity: value, child: child),
              );
            }
            return visible == null
                ? root
                : ValueListenableBuilder<bool>(
                    valueListenable: visible,
                    child: root,
                    builder: (_, value, child) =>
                        TickerMode(enabled: value, child: child!),
                  );
          },
          home: const SensitiveScreen(child: Scaffold(body: Text('Demo home'))),
        ),
      ),
    );
    await fixture.flush(tester);
  }

  Future<void> confirmCapture(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('demo-screenshot-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Enable demo screenshots'),
    );
    await tester.pumpAndSettle();
    await fixture.flush(tester);
  }

  testWidgets('root readiness grants eligibility, never automatic native OFF', (
    tester,
  ) async {
    final calls = <bool>[];
    final off = Completer<void>();
    final protection = _ReadyProtection((secure) {
      calls.add(secure);
      return secure ? Future.value() : off.future;
    });
    try {
      await mountCapture(tester, protection);
      expect(protection.documentationEnabled, isTrue);
      expect(protection.isDocumentationActive, isFalse);
      expect(protection.appliedProtection, isTrue);
      expect(calls, [true]);
      await confirmCapture(tester);
      expect(protection.isDocumentationActive, isFalse);
      expect(protection.mustObscure, isTrue);
      expect(calls, [true, false]);
      off.complete();
      await tester.pump();
      expect(protection.isDocumentationActive, isTrue);
      expect(protection.appliedProtection, isFalse);
      expect(find.text('DEMO · SYNTHETIC DATA'), findsOneWidget);
    } finally {
      if (!off.isCompleted) off.complete();
      await fixture.unmount(tester);
      protection.revokeQaDocumentation();
      protection.dispose();
    }
  });

  testWidgets(
    'uninterrupted foreground navigation retains capture authorization',
    (tester) async {
      final calls = <bool>[];
      final protection = _ReadyProtection((secure) async => calls.add(secure));
      final navigator = GlobalKey<NavigatorState>();
      try {
        await mountCapture(tester, protection, navigator: navigator);
        await confirmCapture(tester);
        final generation = protection.documentationGeneration;
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const SensitiveScreen(
              child: Scaffold(body: Text('Demo inspection')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 2));
        await fixture.flush(tester);
        expect(protection.isDocumentationActive, isTrue);
        expect(protection.documentationGeneration, generation);
        expect(calls, [true, false]);
        expect(find.text('DEMO · SYNTHETIC DATA'), findsOneWidget);
      } finally {
        await fixture.unmount(tester);
        protection.revokeQaDocumentation();
        protection.dispose();
      }
    },
  );

  testWidgets('a false genuine readiness gate cannot grant capture', (
    tester,
  ) async {
    final protection = _ReadyProtection((_) async {})..ready = false;
    try {
      await mountCapture(tester, protection);
      expect(protection.documentationEnabled, isFalse);
      expect(protection.grants, 0);
      expect(
        find.byKey(const ValueKey('demo-screenshot-switch')),
        findsNothing,
      );
    } finally {
      await fixture.unmount(tester);
      protection.revokeQaDocumentation();
      protection.dispose();
    }
  });

  for (final boundary in [
    'session',
    'fixtures',
    'revision',
    'watermark',
    'inactive',
  ]) {
    testWidgets(
      '$boundary invalidation revokes capture and restores protection',
      (tester) async {
        final calls = <bool>[];
        final protection = _ReadyProtection(
          (secure) async => calls.add(secure),
        );
        final visible = ValueNotifier(true);
        try {
          await mountCapture(tester, protection, visible: visible);
          await confirmCapture(tester);
          expect(protection.isDocumentationActive, isTrue);
          switch (boundary) {
            case 'session':
              await fixture.client.auth.setInitialSession(
                jsonEncode(fixture.session()),
              );
            case 'fixtures':
              trusted = false;
            case 'revision':
              await fixture.db.update('demo_fixture_state', {
                'revision': 'invalid',
              });
            case 'watermark':
              visible.value = false;
            case 'inactive':
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.inactive,
              );
          }
          await tester.pump(const Duration(seconds: 1));
          await fixture.flush(tester);
          expect(protection.documentationEnabled, isFalse);
          expect(protection.isDocumentationActive, isFalse);
          expect(protection.appliedProtection, isTrue);
          expect(calls.take(2), [true, false]);
          expect(calls.skip(2), isNotEmpty);
          expect(calls.skip(2), everyElement(true));
        } finally {
          await fixture.unmount(tester);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          protection.revokeQaDocumentation();
          protection.dispose();
          visible.dispose();
        }
      },
    );
  }

  testWidgets('source loss at activation revokes before requesting OFF', (
    tester,
  ) async {
    final calls = <bool>[];
    final protection = _ReadyProtection((secure) async => calls.add(secure));
    try {
      await mountCapture(tester, protection);
      final scope = DemoCaptureScope.maybeOf(
        tester.element(find.text('Demo home')),
      )!;
      trusted = false;
      expect(await tester.runAsync(scope.beginDocumentation), isFalse);
      expect(protection.documentationEnabled, isFalse);
      expect(protection.isDocumentationActive, isFalse);
      expect(calls, [true]);
    } finally {
      await fixture.unmount(tester);
      protection.revokeQaDocumentation();
      protection.dispose();
    }
  });

  testWidgets(
    'navigation during source attestation rejects the old confirmation',
    (tester) async {
      final calls = <bool>[];
      final protection = _ReadyProtection((secure) async => calls.add(secure));
      final navigator = GlobalKey<NavigatorState>();
      final held = Completer<bool>();
      try {
        await mountCapture(tester, protection, navigator: navigator);
        final scope = DemoCaptureScope.maybeOf(
          tester.element(find.text('Demo home')),
        )!;
        sourceAttestation = held;
        final pending = scope.beginDocumentation();
        await tester.pump();
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const SensitiveScreen(
              child: Scaffold(body: Text('Another demo screen')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        held.complete(true);
        await fixture.flush(tester);
        expect(await pending, isFalse);
        expect(protection.isDocumentationActive, isFalse);
        expect(calls, [true]);
      } finally {
        if (!held.isCompleted) held.complete(false);
        await fixture.unmount(tester);
        protection.revokeQaDocumentation();
        protection.dispose();
      }
    },
  );

  testWidgets(
    'first-grant readiness recovers when a hidden watermark becomes visible',
    (tester) async {
      final protection = _ReadyProtection((_) async {});
      final opacity = ValueNotifier(0.0);
      try {
        await mountCapture(tester, protection, opacity: opacity);
        expect(protection.documentationEnabled, isFalse);
        opacity.value = 1;
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await fixture.flush(tester);
        expect(protection.documentationEnabled, isTrue);
        expect(protection.isDocumentationActive, isFalse);
        expect(protection.appliedProtection, isTrue);
      } finally {
        await fixture.unmount(tester);
        protection.revokeQaDocumentation();
        protection.dispose();
        opacity.dispose();
      }
    },
  );

  for (final replacement in [false, true]) {
    testWidgets(
      '${replacement ? 'window replacement' : 'security invalidation'} '
      'requires fresh confirmation, never automatic OFF',
      (tester) async {
        final calls = <bool>[];
        final protection = _ReadyProtection(
          (secure) async => calls.add(secure),
        );
        try {
          await mountCapture(tester, protection);
          await confirmCapture(tester);
          if (replacement) {
            protection.retryProtection();
          } else {
            protection.invalidateDocumentation();
          }
          await tester.pump();
          await fixture.flush(tester);
          expect(protection.isDocumentationActive, isFalse);
          expect(protection.appliedProtection, isTrue);
          expect(calls, [true, false, true]);
        } finally {
          await fixture.unmount(tester);
          protection.revokeQaDocumentation();
          protection.dispose();
        }
      },
    );
  }

  testWidgets('late readiness cannot grant after the demo root is removed', (
    tester,
  ) async {
    final readiness = Completer<bool>();
    final protection = _ReadyProtection((_) async {})
      ..readinessReply = readiness;
    try {
      await mountCapture(tester, protection);
      expect(protection.grants, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      readiness.complete(true);
      await tester.pump();
      expect(protection.grants, 0);
      expect(protection.documentationEnabled, isFalse);
    } finally {
      if (!readiness.isCompleted) readiness.complete(false);
      await fixture.unmount(tester);
      protection.revokeQaDocumentation();
      protection.dispose();
    }
  });

  testWidgets(
    'recorder interruption needs new manual confirmation after resume',
    (tester) async {
      final calls = <bool>[];
      final protection = _ReadyProtection((secure) async => calls.add(secure));
      try {
        await mountCapture(tester, protection);
        await confirmCapture(tester);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        expect(protection.documentationEnabled, isFalse);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await fixture.flush(tester);
        await tester.pumpAndSettle();
        expect(protection.appliedProtection, isTrue);
        expect(protection.isDocumentationActive, isFalse);
        expect(calls.where((secure) => !secure), hasLength(1));
        await confirmCapture(tester);
        expect(protection.isDocumentationActive, isTrue);
        expect(calls.where((secure) => !secure), hasLength(2));
      } finally {
        await fixture.unmount(tester);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        protection.revokeQaDocumentation();
        protection.dispose();
      }
    },
  );

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

/// Only the live Android/package-readiness boundary is replaced. The root,
/// fictional SQLite fixtures, grant matrix and native-ack policy remain real.
class _ReadyProtection extends ScreenProtectionService {
  _ReadyProtection(Future<void> Function(bool) apply)
    : super(applyProtection: apply, verifyIdentity: () async => true);

  bool ready = true;
  Completer<bool>? readinessReply;
  int grants = 0;
  bool _registered = false;

  @override
  Future<bool> registerDemoReadiness(BuildContext context) async {
    _registered = true;
    return true;
  }

  @override
  Future<bool> get demoCaptureReady async => readinessReply == null
      ? _registered && ready && appliedProtection == true
      : await readinessReply!.future;

  @override
  Future<bool> grantQaDocumentation({
    bool? debugMode,
    bool? onAndroid,
    bool? qaPreview,
    String? flavor,
    String? pin,
    String? packageName,
    String? buildSignature,
  }) {
    grants++;
    return super.grantQaDocumentation(
      debugMode: true,
      onAndroid: true,
      qaPreview: true,
      flavor: 'demo',
      pin: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      packageName: ScreenProtectionService.demoPackageName,
      buildSignature:
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    );
  }
}
