import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:screen_protector/screen_protector.dart';

enum DocumentationPhase { off, hidingControl, active }

/// Visible-scope policy, independently observable from native acknowledgments.
/// The plugin remains the only native protection mechanism.
class ScreenProtectionService extends ChangeNotifier
    with WidgetsBindingObserver {
  ScreenProtectionService({
    Future<void> Function(bool)? applyProtection,
    bool documentationEnabled = true,
  }) : _apply = applyProtection ?? _applyNative,
       _documentationEnabled = kDebugMode && documentationEnabled;

  static final instance = ScreenProtectionService();
  static const documentationDuration = Duration(seconds: 20);
  static const controlFadeDuration = Duration(milliseconds: 200);
  static const nativeTimeout = Duration(seconds: 2);

  final Future<void> Function(bool) _apply;
  final bool _documentationEnabled;
  final _scopes = <Object, ({ModalRoute<dynamic>? route, bool visible})>{};
  final _navigation = <NavigatorObserver, _NavigationVisibility>{};
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  DocumentationPhase _phase = DocumentationPhase.off;
  Timer? _expiry;
  Timer? _fade;
  bool _documentationRequested = false;
  bool _controlHidden = false;
  bool _fadeElapsed = false;
  bool? _applied;
  bool _failed = false;
  bool _running = false;
  bool _scheduled = false;
  bool _notificationScheduled = false;
  bool _disposed = false;
  int _hosts = 0;
  int _generation = 0;
  int _securityEpoch = 0;

  static Future<void> _applyNative(bool secure) async {
    // screen_protector only ships an Android/iOS implementation. On other
    // platforms (desktop dev runs, widget tests) there is no channel to call,
    // so report instant success instead of leaving a hanging plugin future
    // whose acknowledgement timer can outlive the test's FakeAsync zone.
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    return secure
        ? ScreenProtector.preventScreenshotOn()
        : ScreenProtector.preventScreenshotOff();
  }

  bool get documentationEnabled => _documentationEnabled;
  bool get foreground => _lifecycle == AppLifecycleState.resumed;
  DocumentationPhase get documentationPhase => _phase;
  bool get isDocumentationActive => _phase == DocumentationPhase.active;
  bool? get appliedProtection => _applied;
  bool get nativeFailure => _failed;
  int get securityEpoch => _securityEpoch;
  int get documentationGeneration => _generation;
  Object? get visibleScope => _scopes.entries
      .where((entry) => entry.value.visible && _visible(entry.value.route))
      .map((entry) => entry.key)
      .lastOrNull;

  bool _visible(ModalRoute<dynamic>? route, [Set<Route<dynamic>>? visiting]) {
    if (route == null || _navigation.isEmpty) return true;
    visiting ??= <Route<dynamic>>{};
    if (!visiting.add(route)) return false;
    for (final entry in _navigation.entries) {
      if (!entry.value.known.contains(route)) continue;
      if (entry.key.navigator == null || !entry.value.visible.contains(route)) {
        return false;
      }
      return _visible(entry.value.parent, visiting);
    }
    // An unobserved navigator is conservative, never silently fail-open.
    return route.isActive;
  }

  bool get requiresProtection =>
      _scopes.values.any((scope) => scope.visible && _visible(scope.route));

  Iterable<_NavigationVisibility> get _visibleNavigators => _navigation.entries
      .where(
        (entry) => entry.key.navigator != null && _visible(entry.value.parent),
      )
      .map((entry) => entry.value);

  bool get transitioning => _visibleNavigators.any((nav) => nav.transitioning);
  bool get hasPopup => _visibleNavigators.any((nav) => nav.popup);
  bool get showControl =>
      _documentationEnabled &&
      foreground &&
      requiresProtection &&
      !transitioning &&
      !hasPopup &&
      _phase == DocumentationPhase.off &&
      _applied == true;
  bool get mustObscure =>
      requiresProtection &&
      (!foreground || (!isDocumentationActive && _applied != true));
  bool get _desired => requiresProtection && !_documentationRequested;

  void register(
    Object token,
    ModalRoute<dynamic>? route, {
    bool visible = true,
  }) {
    final next = (route: route, visible: visible);
    if (_scopes[token] == next) return;
    _scopes[token] = next;
    invalidateDocumentation();
  }

  void unregister(Object token) {
    if (_scopes.remove(token) == null) return;
    invalidateDocumentation();
  }

  /// Called by the observer for structural navigation and animation completion.
  void updateNavigation(
    NavigatorObserver observer, {
    required Set<Route<dynamic>> known,
    required Set<Route<dynamic>> visible,
    required ModalRoute<dynamic>? parent,
    required bool transitioning,
    required bool popup,
  }) {
    _navigation[observer] = _NavigationVisibility(
      known,
      visible,
      parent,
      transitioning,
      popup,
    );
    endDocumentation();
  }

  void attach() {
    if (_hosts++ != 0) return;
    WidgetsBinding.instance.addObserver(this);
    _lifecycle =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    endDocumentation();
  }

  void detach() {
    if (_hosts == 0 || --_hosts != 0) return;
    WidgetsBinding.instance.removeObserver(this);
    _navigation.clear();
    endDocumentation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    // Also revoke for inactive: this affects capture permission only, NOT the
    // separate biometric/resume-lock algorithm's paused/hidden policy.
    invalidateDocumentation();
  }

  bool beginDocumentation() {
    if (!showControl) return false;
    final generation = ++_generation;
    _controlHidden = false;
    _fadeElapsed = false;
    _phase = DocumentationPhase.hidingControl;
    _expiry = Timer(documentationDuration, endDocumentation);
    _fade = Timer(controlFadeDuration, () {
      if (_disposed || generation != _generation) return;
      _fadeElapsed = true;
      _requestDocumentationOff();
    });
    _changed();
    return true;
  }

  /// UI acknowledgment comes after a frame with the control fully absent.
  /// If painting stalls or the widget is abandoned, permission stays ON.
  void confirmControlHidden(int generation) {
    if (_disposed ||
        generation != _generation ||
        _controlHidden ||
        _phase != DocumentationPhase.hidingControl) {
      return;
    }
    _controlHidden = true;
    _requestDocumentationOff();
  }

  void _requestDocumentationOff() {
    if (!_documentationEnabled ||
        !_controlHidden ||
        !_fadeElapsed ||
        _phase != DocumentationPhase.hidingControl ||
        !foreground ||
        !requiresProtection ||
        transitioning ||
        hasPopup) {
      return;
    }
    _documentationRequested = true;
    _changed();
  }

  void _revokeDocumentation() {
    _generation++;
    _expiry?.cancel();
    _fade?.cancel();
    _expiry = _fade = null;
    _documentationRequested = false;
    _phase = DocumentationPhase.off;
  }

  void endDocumentation() {
    if (_disposed) return;
    _revokeDocumentation();
    _changed();
  }

  /// Account, lock, active-tab and lifecycle boundaries invalidate pending UI
  /// confirmations too, not just an already-running documentation timer.
  void invalidateDocumentation() {
    _securityEpoch++;
    endDocumentation();
  }

  void retryProtection() {
    _applied = null;
    endDocumentation();
  }

  void _notifyLater() {
    if (_notificationScheduled || _disposed) return;
    _notificationScheduled = true;
    scheduleMicrotask(() {
      _notificationScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  void _changed() {
    _notifyLater();
    if (_scheduled || _disposed) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      if (!_running && !_disposed) unawaited(_reconcile());
    });
  }

  Future<void> _reconcile() async {
    _running = true;
    try {
      while (!_disposed && _applied != _desired) {
        final target = _desired;
        _applied = null;
        _notifyLater();
        var timedOut = false;
        try {
          final operation = _apply(target);
          // A timed-out platform reply cannot be canceled. A late completion
          // invalidates our observation and re-applies the latest policy.
          unawaited(
            operation.then((_) {
              if (!timedOut) return;
              if (_disposed) {
                if (!target) unawaited(_apply(true).catchError((Object _) {}));
                return;
              }
              _applied = null;
              _changed();
            }, onError: (Object _) {}),
          );
          await operation.timeout(
            nativeTimeout,
            onTimeout: () {
              timedOut = true;
              throw TimeoutException(
                'Screen protection acknowledgment timed out',
              );
            },
          );
          if (_disposed) return;
          _applied = target;
          _failed = false;
          if (!target && _documentationRequested && requiresProtection) {
            _phase = DocumentationPhase.active;
          }
        } catch (_) {
          if (_disposed) return;
          _applied = null;
          _failed = true;
          _revokeDocumentation();
          // Failed OFF authorization immediately falls back to ON. Failed ON
          // stays obscured until explicit retry or another policy/lifecycle
          // event; never spin an endless plugin/timer loop.
          if (target || !_desired) break;
        }
        _notifyLater();
      }
    } finally {
      _running = false;
      _notifyLater();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    final restore =
        requiresProtection && (_documentationRequested || _applied != true);
    _expiry?.cancel();
    _fade?.cancel();
    if (_hosts > 0) WidgetsBinding.instance.removeObserver(this);
    _disposed = true;
    if (restore) unawaited(_apply(true).catchError((Object _) {}));
    super.dispose();
  }
}

class _NavigationVisibility {
  const _NavigationVisibility(
    this.known,
    this.visible,
    this.parent,
    this.transitioning,
    this.popup,
  );
  final Set<Route<dynamic>> known;
  final Set<Route<dynamic>> visible;
  final ModalRoute<dynamic>? parent;
  final bool transitioning;
  final bool popup;
}
