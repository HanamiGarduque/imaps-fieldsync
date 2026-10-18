import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/services/app_bootstrap.dart';
import 'package:imaps_fieldsync/core/services/supabase_service.dart';

void main() {
  setUp(() {
    AppBootstrap.resetForTests();
    SupabaseService.debugClientAvailableOverride = null;
  });
  tearDown(() {
    AppBootstrap.resetForTests();
    SupabaseService.debugClientAvailableOverride = null;
  });

  test('test runner exposes FLUTTER_TEST as a runtime environment variable', () {
    // The test-only default relies on the runtime environment, which is what
    // the actual runner sets. The compile-time equivalent is NOT
    // interchangeable: bool.fromEnvironment('FLUTTER_TEST') is false in this
    // same process (probe run during T2 implementation).
    expect(Platform.environment.containsKey('FLUTTER_TEST'), isTrue);
    expect(Platform.environment['FLUTTER_TEST'], 'true');
    expect(const bool.fromEnvironment('FLUTTER_TEST'), isFalse);
    expect(AppBootstrap.isTestEnvironment, isTrue);
  });

  test('default chain preserves the original initialization order', () {
    expect([for (final step in AppBootstrap.defaultSteps()) step.name], [
      'SupabaseService.initialize',
      'AuthService.loadSoftLogoutState',
      'NotificationService.initialize',
      'SecurePrefsService.purgeLegacyPatternLockData',
      'SyncOutboxService.start',
    ]);
  });

  test('runs every step in order and waits for each before the next', () async {
    final order = <String>[];
    final firstStepGate = Completer<void>();
    final run = AppBootstrap.initialize(steps: [
      (name: 'first', run: () async {
        order.add('first-start');
        await firstStepGate.future;
        order.add('first-end');
      }),
      (name: 'second', run: () async { order.add('second'); }),
    ]);

    // The chain starts synchronously: the first step is already in flight.
    expect(order, ['first-start']);
    expect(AppBootstrap.started, isTrue);
    expect(AppBootstrap.settled, isFalse);

    firstStepGate.complete();
    await run;
    expect(order, ['first-start', 'first-end', 'second']);
    expect(AppBootstrap.settled, isTrue);
    expect(AppBootstrap.error, isNull);
  });

  test('captures the first failure, skips the rest, and still settles',
      () async {
    final order = <String>[];
    await AppBootstrap.initialize(steps: [
      (name: 'ok', run: () async { order.add('ok'); }),
      (name: 'boom', run: () async {
        order.add('boom');
        throw const SocketException('isolated bootstrap failure');
      }),
      (name: 'never', run: () async { order.add('never'); }),
    ]);

    expect(order, ['ok', 'boom']);
    expect(AppBootstrap.error, isA<SocketException>());
    expect(AppBootstrap.errorStackTrace, isNotNull);
    expect(AppBootstrap.settled, isTrue);
  });

  test('initialize is idempotent and later calls reuse the first chain',
      () async {
    var runs = 0;
    final first = AppBootstrap.initialize(steps: [
      (name: 'once', run: () async { runs++; }),
    ]);
    final second = AppBootstrap.initialize(steps: [
      (name: 'again', run: () async { runs++; }),
    ]);

    expect(identical(first, second), isTrue);
    await first;
    expect(runs, 1);
  });

  test('supabaseInitialized records the Supabase step only, never a substitute',
      () async {
    expect(AppBootstrap.supabaseInitialized, isFalse);
    await AppBootstrap.initialize(steps: [
      (name: 'something-else', run: () async {}),
    ]);
    expect(AppBootstrap.supabaseInitialized, isFalse,
        reason: 'only the real step name counts');
  });

  test('supabaseInitialized survives a later-step failure', () async {
    await AppBootstrap.initialize(steps: [
      (name: AppBootstrap.supabaseStep, run: () async {}),
      (name: 'boom', run: () async {
        throw const SocketException('isolated late failure');
      }),
    ]);
    expect(AppBootstrap.supabaseInitialized, isTrue);
    expect(AppBootstrap.error, isA<SocketException>());
  });

  test('supabaseInitialized stays false when the Supabase step itself failed',
      () async {
    await AppBootstrap.initialize(steps: [
      (name: AppBootstrap.supabaseStep, run: () async {
        throw const SocketException('isolated early failure');
      }),
      (name: 'never', run: () async {}),
    ]);
    expect(AppBootstrap.supabaseInitialized, isFalse);
    expect(AppBootstrap.error, isA<SocketException>());
  });

  test('resetForTests clears the completed-step record', () async {
    await AppBootstrap.initialize(steps: [
      (name: AppBootstrap.supabaseStep, run: () async {}),
    ]);
    expect(AppBootstrap.supabaseInitialized, isTrue);
    AppBootstrap.resetForTests();
    expect(AppBootstrap.supabaseInitialized, isFalse);
    expect(AppBootstrap.settled, isFalse);
  });

  test('hasClient is false — never fatal — before any Supabase initialization',
      () {
    // This isolate never calls Supabase.initialize: the probe must swallow
    // the uninitialized-instance assert (debug) / missing-instance failure
    // (release) and answer false instead of crashing its caller.
    expect(SupabaseService.hasClient, isFalse);
  });

  test('ready completes without initialize under flutter test (isolated default)',
      () async {
    expect(AppBootstrap.started, isFalse);
    await AppBootstrap.ready;
    expect(AppBootstrap.error, isNull);
    expect(AppBootstrap.settled, isFalse);
  });

  test('ready follows a still-running chain and settles with it', () async {
    final stepGate = Completer<void>();
    final run = AppBootstrap.initialize(steps: [
      (name: 'deferred', run: () => stepGate.future),
    ]);

    var returned = false;
    unawaited(AppBootstrap.ready.then((_) => returned = true));
    await Future<void>.delayed(Duration.zero);
    expect(returned, isFalse, reason: 'ready must not settle while a step runs');

    stepGate.complete();
    await run;
    await Future<void>.delayed(Duration.zero);
    expect(returned, isTrue);
    expect(AppBootstrap.settled, isTrue);
  });

  test('never-started with production detection: debug asserts at the source',
      () {
    AppBootstrap.debugTestEnvironmentOverride = false;
    expect(() => AppBootstrap.ready, throwsAssertionError);
  });

  test('never-started with production detection: error reports BootstrapNeverStarted',
      () {
    AppBootstrap.debugTestEnvironmentOverride = false;
    final error = AppBootstrap.error;
    expect(error, isA<BootstrapNeverStarted>());
    expect(error.toString(), contains('initialize'));
    expect(AppBootstrap.isTestEnvironment, isTrue,
        reason: 'the override must not disturb real environment detection');
  });
}
