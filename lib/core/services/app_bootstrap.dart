import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../modules/auth_startup/services/secure_prefs_service.dart';
import '../../modules/profile_settings/services/notification_service.dart';
import 'auth_service.dart';
import 'supabase_service.dart';
import 'sync_outbox_service.dart';

/// One named step of the startup bootstrap chain.
typedef BootstrapStep = ({String name, Future<void> Function() run});

/// Reported through [AppBootstrap.error] when the startup gate is reached
/// without [AppBootstrap.initialize] ever having been called — a wiring bug,
/// not a service failure. AuthFailure classification falls through to its
/// caller-provided fallback for this object.
class BootstrapNeverStarted implements Exception {
  const BootstrapNeverStarted();

  @override
  String toString() =>
      'AppBootstrap.initialize() was never called before the startup gate.';
}

/// Startup bootstrap: the heavy service chain that used to run awaited,
/// before `runApp()`. It now runs concurrently with the first frames (the
/// launch cinematic's Page 1) in the exact order it always ran:
///
///   SupabaseService.initialize
///     -> AuthService.loadSoftLogoutState
///     -> NotificationService.initialize
///     -> SecurePrefsService.purgeLegacyPatternLockData
///     -> SyncOutboxService.start
///
/// Consumers gate on [ready] — SplashScreen._checkSession awaits it before
/// any session decision — so no widget or service can observe a dependency
/// before the chain reached it. A step failure keeps the old aborting
/// semantics (later steps skipped), is preserved on [error] for the
/// existing classified-failure handling, and [ready] still settles: startup
/// can never hang on this gate because a step threw.
class AppBootstrap {
  AppBootstrap._();

  static Completer<void>? _completer;
  static Object? _error;
  static StackTrace? _errorStackTrace;
  static bool _settled = false;

  /// Test hook: pins [isTestEnvironment] so the never-started production
  /// branch stays exercisable from `flutter test` (where the environment
  /// check below is always true). Never set by app code.
  @visibleForTesting
  static bool? debugTestEnvironmentOverride;

  /// Runtime environment check, verified against the actual runner: the
  /// `flutter test` process exports `FLUTTER_TEST=true` in
  /// [Platform.environment]. The compile-time
  /// `bool.fromEnvironment('FLUTTER_TEST')` is false in that same process —
  /// the two are NOT interchangeable, and only this runtime check (plus
  /// [kReleaseMode]) enables the test-only default below.
  static bool get isTestEnvironment =>
      !kReleaseMode && Platform.environment.containsKey('FLUTTER_TEST');

  static bool get _testDefaultsAllowed =>
      debugTestEnvironmentOverride ?? isTestEnvironment;

  /// True once [initialize] has been called (idempotent).
  static bool get started => _completer != null;

  /// True once the chain finished — success or captured failure. False while
  /// steps are still running.
  static bool get settled => _settled;

  /// The first step failure, in the shape the existing `AuthFailure`
  /// classification consumes; null when every started step succeeded.
  ///
  /// When the gate is reached without [initialize] ever being called, this
  /// reports [BootstrapNeverStarted] (debug builds hit the assert in [ready]
  /// first, at the mistake's source) so callers classify it and route on
  /// instead of waiting forever.
  static Object? get error {
    if (_error != null) return _error;
    if (_completer == null && !_testDefaultsAllowed) {
      return const BootstrapNeverStarted();
    }
    return null;
  }

  /// Where [error] was thrown, for diagnostics.
  static StackTrace? get errorStackTrace => _errorStackTrace;

  /// Settles when the chain finishes (success or failure). Observed before
  /// [initialize] was ever called:
  ///  * under `flutter test`: completes immediately — the test-only default,
  ///    isolated by [isTestEnvironment];
  ///  * debug device builds: asserts loudly (a missing call is a wiring bug);
  ///  * release builds: completes immediately and reports
  ///    [BootstrapNeverStarted] through [error], so startup can never
  ///    silently wait forever on an initialization that will not come.
  static Future<void> get ready {
    final completer = _completer;
    if (completer != null) return completer.future;
    if (_testDefaultsAllowed) return Future<void>.value();
    assert(false,
        'AppBootstrap.initialize() was never called before startup reached '
        'its gate. main() must call it before runApp().');
    return Future<void>.value();
  }

  /// Starts the chain (idempotent — later calls return the same future, and
  /// [steps] is only consulted on the first call). The chain runs to
  /// completion even when the returned future is not awaited.
  static Future<void> initialize({List<BootstrapStep>? steps}) {
    final existing = _completer;
    if (existing != null) return existing.future;
    final completer = Completer<void>();
    _completer = completer;
    unawaited(_run(steps ?? defaultSteps(), completer));
    return completer.future;
  }

  /// The production chain, in its original order (see class docs).
  static List<BootstrapStep> defaultSteps() => <BootstrapStep>[
        (name: 'SupabaseService.initialize', run: SupabaseService.initialize),
        (name: 'AuthService.loadSoftLogoutState',
            run: AuthService.loadSoftLogoutState),
        (name: 'NotificationService.initialize',
            run: NotificationService.initialize),
        (name: 'SecurePrefsService.purgeLegacyPatternLockData',
            run: SecurePrefsService.purgeLegacyPatternLockData),
        (name: 'SyncOutboxService.start',
            run: () async {
          SyncOutboxService.start();
        }),
      ];

  static Future<void> _run(
      List<BootstrapStep> steps, Completer<void> completer) async {
    try {
      for (final step in steps) {
        final watch = Stopwatch()..start();
        try {
          await step.run();
          debugPrint('[AppBootstrap] ${step.name} ok '
              '(${watch.elapsedMilliseconds} ms)');
        } catch (e, stack) {
          // Same abort semantics as the awaited chain this replaced: later
          // steps are skipped, the failure is preserved for the existing
          // classified handling, and `ready` still settles so the startup
          // gate cannot hang because a step threw.
          _error = e;
          _errorStackTrace = stack;
          debugPrint('[AppBootstrap] ${step.name} FAILED '
              '(${watch.elapsedMilliseconds} ms): $e');
          break;
        }
      }
    } finally {
      _settled = true;
      if (!completer.isCompleted) completer.complete();
    }
  }

  /// Restores the pre-`main()` state for tests that drive the gate.
  @visibleForTesting
  static void resetForTests() {
    _completer = null;
    _error = null;
    _errorStackTrace = null;
    _settled = false;
    debugTestEnvironmentOverride = null;
  }
}
