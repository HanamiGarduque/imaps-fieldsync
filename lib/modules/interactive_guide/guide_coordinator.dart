import 'package:flutter/foundation.dart';

import 'guide_preferences.dart';
import 'guide_script.dart';

enum GuidePhase { idle, invitation, active, suspended }

/// Owned by one authenticated shell. No business services or global state.
class GuideCoordinator extends ChangeNotifier {
  final String inspectorId;
  final GuidePreferences preferences;
  final bool Function() canPresent;

  GuideCoordinator({
    required this.inspectorId,
    required this.preferences,
    required this.canPresent,
  });

  GuidePhase _phase = GuidePhase.idle;
  GuidePhase _resumePhase = GuidePhase.idle;
  GuideLanguage _language = GuideLanguage.english;
  int _stopIndex = 0;
  int _generation = 0;
  // Layout cancellation must not cancel same-owner metadata or a pending offer.
  int _operation = 0;
  bool _invalid = false;
  bool _disposed = false;
  bool _launching = false;
  bool _offerAttempted = false;
  bool _loaded = false;
  bool _readable = true;
  GuideRecord? _record;
  Future<void> _pending = Future<void>.value();

  GuidePhase get phase => _phase;
  GuideLanguage get language => _language;
  int get stopIndex => _stopIndex;
  int get generation => _generation;

  bool get _alive => !_disposed && !_invalid;
  bool _current(int token) => _alive && token == _operation;
  bool get _eligible => !_disposed && !_invalid && canPresent();

  // Preserve order when Skip races an already-issued platform write.
  Future<void> _queue(Future<void> Function() action) {
    final work = _pending.then((_) => action());
    _pending = work.catchError((Object _) {});
    return work;
  }

  Future<void> _load() async {
    if (_loaded || !_alive) return;
    try {
      final record = await preferences.read(inspectorId);
      if (!_alive) return;
      _record = record;
      _loaded = true;
    } catch (_) {
      if (!_alive) return;
      // Suppress automatic interruption; manual replay can still be ephemeral.
      _loaded = true;
      _readable = false;
    }
  }

  Future<bool> _save(
    GuideStatus status,
    GuideLanguage language, {
    int? token,
  }) async {
    await _load();
    if (!_alive || (token != null && !_current(token)) || !_readable) {
      return false;
    }
    final previous = _record;
    final record = GuideRecord(
      (previous?.version ?? 0) > currentGuideVersion
          ? previous!.version
          : currentGuideVersion,
      language,
      previous?.status == GuideStatus.completed
          ? GuideStatus.completed
          : status,
    );
    try {
      await preferences.write(inspectorId, record);
      if (!_alive) return false;
      _record = record;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> offerIfEligible() async {
    if (!_eligible ||
        _offerAttempted ||
        _launching ||
        _phase != GuidePhase.idle) {
      return;
    }
    _offerAttempted = true;
    _launching = true;
    _generation++;
    final token = ++_operation;
    await _queue(() async {
      await _load();
      if (!_current(token)) return;
      if (_record != null) _language = _record!.language;
      if (!_readable || _record != null) return;
      if (!_eligible) {
        _offerAttempted = false;
        return;
      }
      if (!await _save(GuideStatus.offered, _language, token: token)) return;
      if (!_current(token)) return;
      _resumePhase = GuidePhase.invitation;
      _phase = _eligible ? GuidePhase.invitation : GuidePhase.suspended;
      notifyListeners();
    });
    if (_current(token)) _launching = false;
  }

  Future<void> start(GuideLanguage language, {bool replay = false}) async {
    if (!_eligible ||
        _launching ||
        _phase == GuidePhase.active ||
        _phase == GuidePhase.suspended) {
      return;
    }
    _launching = true;
    _offerAttempted = true;
    _generation++;
    final token = ++_operation;
    await _queue(() async {
      await _save(GuideStatus.offered, language, token: token);
      if (!_current(token)) return;
      _language = language;
      _stopIndex = 0;
      _resumePhase = GuidePhase.active;
      _phase = _eligible ? GuidePhase.active : GuidePhase.suspended;
      notifyListeners();
    });
    if (_current(token)) _launching = false;
  }

  void next() {
    if (_phase != GuidePhase.active || _stopIndex == guideStops.length - 1) {
      return;
    }
    _stopIndex++;
    _generation++;
    notifyListeners();
  }

  void back() {
    if (_phase != GuidePhase.active || _stopIndex == 0) return;
    _stopIndex--;
    _generation++;
    notifyListeners();
  }

  Future<void> finish() async {
    if (_phase != GuidePhase.active || _stopIndex != guideStops.length - 1) {
      return;
    }
    await _end(GuideStatus.completed);
  }

  Future<void> skip() async {
    if (_disposed || _invalid || (_phase == GuidePhase.idle && !_launching)) {
      return;
    }
    await _end(GuideStatus.skipped);
  }

  Future<void> _end(GuideStatus status) {
    _generation++;
    _operation++;
    final language = _language;
    _launching = false;
    _phase = _resumePhase = GuidePhase.idle;
    notifyListeners();
    return _queue(() async {
      // A later replay or lifecycle frame cannot discard the user's Done/Skip.
      // Invalidation/disposal still rejects persistence for an ended owner.
      await _save(status, language);
    });
  }

  void suspend() {
    if (_disposed || _invalid || _phase == GuidePhase.suspended) return;
    _generation++;
    if (_phase == GuidePhase.idle) return;
    _resumePhase = _phase;
    _phase = GuidePhase.suspended;
    notifyListeners();
  }

  void resumeIfEligible() {
    if (!_eligible || _phase != GuidePhase.suspended) return;
    _phase = _resumePhase;
    _generation++;
    notifyListeners();
  }

  void invalidate() {
    if (_disposed || _invalid) return;
    _invalid = true;
    _generation++;
    _operation++;
    _phase = _resumePhase = GuidePhase.idle;
    _launching = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _operation++;
    super.dispose();
  }
}
