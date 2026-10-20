import 'dart:async';

/// Deterministic clock + timer scheduler for auto-lock tests. No real waiting.
class FakeAutoLockClock {
  Duration current = Duration.zero;
  final List<FakeAutoLockTimer> timers = <FakeAutoLockTimer>[];

  Timer create(Duration delay, void Function() callback) {
    final timer = FakeAutoLockTimer._(this, current + delay, callback);
    timers.add(timer);
    return timer;
  }

  void advance(Duration by) {
    final target = current + by;
    var guard = 0;
    while (true) {
      FakeAutoLockTimer? next;
      for (final timer in timers) {
        if (!timer.isActive || timer.due > target) continue;
        if (next == null || timer.due < next.due) next = timer;
      }
      if (next == null) break;
      current = next.due;
      next._fire();
      if (++guard > 10000) {
        throw StateError('Fake timer loop did not settle');
      }
    }
    current = target;
  }
}

class FakeAutoLockTimer implements Timer {
  FakeAutoLockTimer._(this._clock, this.due, this._callback);

  final FakeAutoLockClock _clock;
  final Duration due;
  final void Function() _callback;
  bool _active = true;
  int _tick = 0;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;

  @override
  void cancel() {
    _active = false;
    _clock.timers.remove(this);
  }

  void _fire() {
    if (!_active) return;
    _active = false;
    _tick++;
    _clock.timers.remove(this);
    _callback();
  }
}

/// Holds each lock request open, like a real lock screen awaiting biometric.
class LockGate {
  int count = 0;
  Completer<void>? _gate;

  Future<void> request() {
    count++;
    final gate = Completer<void>();
    _gate = gate;
    return gate.future;
  }

  Future<void> release() async {
    final gate = _gate;
    _gate = null;
    if (gate != null && !gate.isCompleted) gate.complete();
    await Future<void>.delayed(Duration.zero);
  }
}
