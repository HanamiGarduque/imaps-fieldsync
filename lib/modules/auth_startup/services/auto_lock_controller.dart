import 'dart:async';

import 'package:flutter/widgets.dart';

import '../services/biometric_service.dart';
import 'secure_prefs_service.dart';

/// Immutable lock policy cached for the authenticated session.
///
/// Persisted values keep their existing meaning:
///   -1 = immediately, 0 = never, 1/5/10 = minutes.
@immutable
class AutoLockPolicy {
  const AutoLockPolicy({
    required this.requireOnOpen,
    required this.minutes,
    required this.biometricReady,
  });

  const AutoLockPolicy.disabled()
    : requireOnOpen = false,
      minutes = 0,
      biometricReady = false;

  /// Fail-closed policy used when secure storage cannot be read.
  ///
  /// A read failure must not silently remove a required lock. One minute is the
  /// shortest selectable idle period; the lock screen always exposes "Log Out"
  /// to the normal password login, so a biometric failure cannot strand the
  /// user permanently.
  const AutoLockPolicy.secureFallback()
    : requireOnOpen = true,
      minutes = 1,
      biometricReady = true;

  final bool requireOnOpen;
  final int minutes;

  /// True only when biometric is enrolled AND confirmed. Without a working
  /// unlock path an auto-lock would strand the inspector on the lock screen.
  final bool biometricReady;

  bool get hasIdlePeriod => minutes > 0;

  /// Opening protection is explicit, and "Immediately" is its own explicit
  /// choice. "Never" must not silently cancel an enabled opening lock.
  bool get locksOnResume => requireOnOpen || minutes < 0;

  bool get canLock => biometricReady && (requireOnOpen || minutes != 0);

  Duration get idlePeriod => Duration(minutes: minutes);

  /// Reads the persisted policy once per start/settings change. Never called
  /// from the pointer/timer hot path.
  static Future<AutoLockPolicy> load() => loadWith(_readPersistedPolicy);

  /// Test seam for the fail-closed path. A read failure must never silently
  /// disable a required lock.
  @visibleForTesting
  static Future<AutoLockPolicy> loadWith(
    Future<AutoLockPolicy> Function() reader,
  ) async {
    try {
      return await reader();
    } catch (_) {
      // Never fail open: if the persisted policy cannot be read, keep opening
      // protection and the shortest idle period. The lock screen's Log Out
      // path is the recovery route if biometrics are unavailable.
      return const AutoLockPolicy.secureFallback();
    }
  }

  static Future<AutoLockPolicy> _readPersistedPolicy() async {
    final requireOnOpen = await SecurePrefsService.getBioRequireOnOpen();
    final minutes = await SecurePrefsService.getBioAutoLockMins();
    final enrolled = await BiometricService.isEnrolled();
    final confirmed = await BiometricService.isConfirmed();
    return AutoLockPolicy(
      requireOnOpen: requireOnOpen,
      minutes: minutes,
      biometricReady: enrolled && confirmed,
    );
  }
}

typedef AutoLockNow = Duration Function();
typedef AutoLockTimerFactory =
    Timer Function(Duration duration, void Function() callback);
typedef LockRequestCallback = FutureOr<void> Function();

/// App-wide inactivity coordinator.
///
/// Keeps one cached policy, one monotonic last-activity timestamp and at most
/// one idle timer. Foreground idle time and background elapsed time both count
/// against the same timestamp, so moving a route or backgrounding the app
/// cannot reset inactivity.
class AutoLockController {
  AutoLockController({AutoLockNow? now, AutoLockTimerFactory? timerFactory})
    : _now = now ?? _defaultNow,
      _timerFactory = timerFactory ?? Timer.new;

  /// The process-wide instance used by the app shell and activity host.
  static final AutoLockController instance = AutoLockController();

  static final Stopwatch _processClock = Stopwatch()..start();
  static Duration _defaultNow() => _processClock.elapsed;

  /// Pointer moves can be very frequent; one reset per half-second is enough
  /// to represent continuous interaction without churning timers.
  static const Duration _activityThrottle = Duration(milliseconds: 500);

  final AutoLockNow _now;
  final AutoLockTimerFactory _timerFactory;

  AutoLockPolicy _policy = const AutoLockPolicy.disabled();
  bool _active = false;
  bool _locked = false;
  bool _backgrounded = false;
  Duration? _lastActivityAt;
  Timer? _timer;
  LockRequestCallback? _onLockRequested;

  bool get isActive => _active;
  bool get isLocked => _locked;
  Duration? get lastActivityAt => _lastActivityAt;
  AutoLockPolicy get policy => _policy;

  /// Begins monitoring an authenticated session. Replaces any previous one.
  void start({
    required AutoLockPolicy policy,
    required LockRequestCallback onLockRequested,
    bool backgrounded = false,
  }) {
    _cancelTimer();
    _policy = policy;
    _onLockRequested = onLockRequested;
    _active = true;
    _locked = false;
    _backgrounded = backgrounded;
    _lastActivityAt = _now();
    _schedule();
  }

  /// Applies a settings change without touching secure storage on this path.
  void updatePolicy(AutoLockPolicy policy) {
    _policy = policy;
    if (!_active || _locked) return;
    if (!policy.canLock || !policy.hasIdlePeriod) {
      _cancelTimer();
      return;
    }
    _schedule();
  }

  /// Records genuine authenticated interaction. Lock-screen touches never
  /// reach here as activity because [isLocked] is true for the whole lock.
  void recordActivity() {
    // A stray pointer/key event during a pause/resume transition must not
    // erase the background time that is about to be checked.
    if (!_active || _locked || _backgrounded) return;
    final now = _now();
    final last = _lastActivityAt;
    if (last != null && now >= last && now - last < _activityThrottle) return;
    _lastActivityAt = now;
    _schedule();
  }

  /// `inactive` is deliberately ignored: Android emits it while the native
  /// biometric prompt is up, which must not look like a real app switch.
  void handleLifecycle(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _backgrounded = true;
        _cancelTimer();
        break;
      case AppLifecycleState.resumed:
        final wasBackgrounded = _backgrounded;
        _backgrounded = false;
        if (!_active || _locked || !wasBackgrounded) return;
        if (_policy.locksOnResume ||
            (_policy.hasIdlePeriod && _idleElapsed() >= _policy.idlePeriod)) {
          _requestLock();
          return;
        }
        _schedule();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Sign-out, session expiry or shell teardown.
  void stop() {
    _active = false;
    _locked = false;
    _backgrounded = false;
    _lastActivityAt = null;
    _onLockRequested = null;
    _policy = const AutoLockPolicy.disabled();
    _cancelTimer();
  }

  Duration _idleElapsed() {
    final last = _lastActivityAt;
    if (last == null) return Duration.zero;
    final now = _now();
    return now >= last ? now - last : Duration.zero;
  }

  void _schedule() {
    _cancelTimer();
    if (!_active || _locked || _backgrounded) return;
    if (!_policy.canLock || !_policy.hasIdlePeriod) return;

    final remaining = _policy.idlePeriod - _idleElapsed();
    _timer = _timerFactory(
      remaining > Duration.zero ? remaining : Duration.zero,
      _requestLock,
    );
  }

  void _requestLock() {
    if (!_active || _locked || !_policy.canLock) return;
    final callback = _onLockRequested;
    if (callback == null) return;

    // Set before awaiting so overlapping timers/lifecycle events cannot open
    // a second lock screen or biometric prompt.
    _locked = true;
    _cancelTimer();
    unawaited(_holdLock(callback));
  }

  Future<void> _holdLock(LockRequestCallback callback) async {
    try {
      await Future<void>.sync(callback);
    } catch (_) {
      // A failed presentation must not leave the session permanently locked.
    } finally {
      if (_active) {
        _locked = false;
        _backgrounded = false;
        // Unlock starts a fresh period even if authentication was slow.
        _lastActivityAt = _now();
        _schedule();
      }
    }
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }
}
