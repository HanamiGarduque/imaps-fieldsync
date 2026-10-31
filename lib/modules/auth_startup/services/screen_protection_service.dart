import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:screen_protector/screen_protector.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../qa/demo_fixtures.dart';
import '../../../qa/demo_watermark.dart';
import 'native_screen_protection_ack.dart';

enum DocumentationPhase { off, active }

typedef _DemoReadiness = ({
  BuildContext context,
  RenderParagraph watermark,
  Session session,
  int generation,
  int epoch,
  int authorization,
});

/// Visible-scope policy, independently observable from native acknowledgments.
/// Android uses app-owned window readback; other platforms retain their policy.
class ScreenProtectionService extends ChangeNotifier
    with WidgetsBindingObserver {
  ScreenProtectionService({
    Future<void> Function(bool)? applyProtection,
    bool documentationEnabled = true,
    Future<bool> Function()? verifyIdentity,
  }) : _apply = applyProtection ?? _applyNative,
       _verifyIdentity = verifyIdentity ?? isVerifiedDocumentationContext,
       _documentationEnabled = kDebugMode && documentationEnabled;

  static final instance = ScreenProtectionService();
  static const nativeTimeout = NativeScreenProtectionAck.timeout;
  static final _androidAck = NativeScreenProtectionAck(
    onWindowChanged: () => instance.retryProtection(),
  );

  /// The isolated demo application id (`android/app/build.gradle.kts`).
  static const demoPackageName = 'com.example.imaps_fieldsync.demo';
  static const normalPackageName = 'com.example.imaps_fieldsync';

  /// Capture permission, granted only through a verified debug documentation
  /// identity and withdrawn again by [revokeQaDocumentation]. Static because
  /// [_applyNative] is a static tear-off.
  // ponytail: static capture flags leak across instances; every test tearDown
  // must revokeQaDocumentation. Split per-instance if lifecycle scoping lands.
  static bool _qaScreenshotsAllowed = false;
  static bool _identityVerified = false;
  // Shared flags require a shared fence, including revoke/regrant by another instance.
  static int _authorizationRevision = 0;

  /// Explicit trusted-identity source for tests; defaults to the live
  /// device/package attestation.
  final Future<bool> Function() _verifyIdentity;

  final Future<void> Function(bool) _apply;
  final bool _documentationEnabled;
  final _scopes = <Object, ({ModalRoute<dynamic>? route, bool visible})>{};
  final _navigation = <NavigatorObserver, _NavigationVisibility>{};
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  DocumentationPhase _phase = DocumentationPhase.off;
  bool _documentationRequested = false;
  bool? _applied;
  bool _failed = false;
  bool _running = false;
  bool _scheduled = false;
  bool _notificationScheduled = false;
  bool _disposed = false;
  int _hosts = 0;
  int _generation = 0;
  int _securityEpoch = 0;
  int _biometricPrompts = 0;
  int _readinessRevision = 0;
  _DemoReadiness? _demoReadiness;
  StreamSubscription<AuthState>? _demoAuthSubscription;

  static Future<void> _applyNative(bool secure) async {
    // Demo permission never substitutes for Android window acknowledgment.
    // There is exactly one Android writer: the application-owned channel.
    if (!kIsWeb && Platform.isAndroid) return _androidAck.setSecure(secure);
    // Capture-only opt-out, granted exclusively through a verified demo
    // identity. Preserve the existing non-Android behavior only.
    if (_qaScreenshotsAllowed) return;
    // screen_protector only ships an Android/iOS implementation. On other
    // platforms (desktop dev runs, widget tests) there is no channel to call,
    // so report instant success instead of leaving a hanging plugin future
    // whose acknowledgement timer can outlive the test's FakeAsync zone.
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    return secure
        ? ScreenProtector.preventScreenshotOn()
        : ScreenProtector.preventScreenshotOff();
  }

  bool get documentationEnabled => _documentationEnabled && _identityVerified;
  bool get foreground => _lifecycle == AppLifecycleState.resumed;
  bool get backgrounded =>
      _lifecycle == AppLifecycleState.paused ||
      _lifecycle == AppLifecycleState.detached ||
      _lifecycle == AppLifecycleState.hidden;
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
      !_disposed &&
      !_documentationRequested &&
      _documentationEnabled &&
      _identityVerified &&
      _qaScreenshotsAllowed &&
      foreground &&
      requiresProtection &&
      !transitioning &&
      !hasPopup &&
      _phase == DocumentationPhase.off &&
      _applied == true;
  // A screenshot/recorder overlay may temporarily make the *verified*
  // documentation window inactive. Only an already-acknowledged manual ON
  // survives it; an incomplete activation or real background must still keep
  // private content obscured.
  bool get _verifiedDemoActiveWhileInactive =>
      _lifecycle == AppLifecycleState.inactive &&
      _phase == DocumentationPhase.active &&
      _documentationRequested &&
      _identityVerified &&
      _qaScreenshotsAllowed &&
      _applied == false &&
      !_failed;

  bool get mustObscure =>
      requiresProtection &&
      ((!foreground &&
              !_verifiedDemoActiveWhileInactive &&
              !(_lifecycle == AppLifecycleState.inactive &&
                  _biometricPrompts > 0 &&
                  _applied == true)) ||
          (!isDocumentationActive && _applied != true));
  bool get _desired => requiresProtection && !_documentationRequested;

  /// Source readiness only, never a native capture grant. The B2 root must
  /// register its actual DemoWatermark context after layout and revoke on exit.
  /// Caller-supplied flags, test instances and identity overrides cannot grant it.
  Future<bool> registerDemoReadiness(BuildContext watermarkContext) async {
    revokeDemoReadiness();
    final revision = _readinessRevision;
    try {
      final auth = Supabase.instance.client.auth;
      final session = auth.currentSession;
      final watermark = _visibleDemoWatermark(watermarkContext);
      if (session == null || watermark == null) return false;
      final candidate = (
        context: watermarkContext,
        watermark: watermark,
        session: session,
        generation: _generation,
        epoch: _securityEpoch,
        authorization: _authorizationRevision,
      );
      if (!_currentDemoReadiness(candidate, revision)) return false;
      void revokeIfCurrent() {
        if (revision == _readinessRevision) revokeDemoReadiness();
      }

      _demoAuthSubscription = auth.onAuthStateChange.listen(
        (state) {
          if (!identical(state.session, session)) revokeIfCurrent();
        },
        onError: (Object _) => revokeIfCurrent(),
        onDone: revokeIfCurrent,
      );
      if (await _validateDemoReadiness(candidate, revision) &&
          _currentDemoReadiness(candidate, revision)) {
        _demoReadiness = candidate;
        _notifyLater();
        return true;
      }
    } catch (_) {
      // Uninitialized auth, failed trust or layout is never readiness.
    }
    if (revision == _readinessRevision) revokeDemoReadiness();
    return false;
  }

  /// Re-attests every read; no cached Boolean can outlive fixture/session trust.
  Future<bool> get demoCaptureReady async {
    final registration = _demoReadiness;
    if (registration == null) return false;
    final revision = _readinessRevision;
    if (await _validateDemoReadiness(registration, revision) &&
        _currentDemoReadiness(registration, revision)) {
      return true;
    }
    if (revision == _readinessRevision) revokeDemoReadiness();
    return false;
  }

  void revokeDemoReadiness() {
    _readinessRevision++;
    final hadRegistration = _demoReadiness != null;
    _demoReadiness = null;
    final subscription = _demoAuthSubscription;
    _demoAuthSubscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel().catchError((Object _) {}));
    }
    if (hadRegistration) _notifyLater();
  }

  Future<bool> _validateDemoReadiness(
    _DemoReadiness registration,
    int revision,
  ) async {
    try {
      if (!_currentDemoReadiness(registration, revision) ||
          !await isVerifiedDemoContext().timeout(nativeTimeout) ||
          !_currentDemoReadiness(registration, revision)) {
        return false;
      }
      // The live B2 singleton checks successful owner-scoped initialization
      // against the persisted ready revision, not just watermarkMounted(bool).
      return await DemoFixtures.instance.captureSourceReady.timeout(
            nativeTimeout,
          ) &&
          _currentDemoReadiness(registration, revision);
    } catch (_) {
      return false;
    }
  }

  bool _currentDemoReadiness(_DemoReadiness registration, int revision) {
    try {
      return identical(this, instance) &&
          !_disposed &&
          _documentationEnabled &&
          _hosts > 0 &&
          foreground &&
          requiresProtection &&
          !transitioning &&
          !hasPopup &&
          !_failed &&
          _applied == true &&
          !_documentationRequested &&
          _phase == DocumentationPhase.off &&
          !_qaScreenshotsAllowed &&
          revision == _readinessRevision &&
          registration.generation == _generation &&
          registration.epoch == _securityEpoch &&
          registration.authorization == _authorizationRevision &&
          DemoFixtures.owner == '11111111-1111-4111-8111-111111111111' &&
          DemoFixtures.revision == 'demo-fixtures-20261028-v1' &&
          registration.session.user.id == DemoFixtures.owner &&
          registration.session.accessToken == DemoFixtures.accessToken &&
          registration.session.user.appMetadata['provider'] == 'demo-preview' &&
          identical(
            registration.session,
            Supabase.instance.client.auth.currentSession,
          ) &&
          identical(
            _visibleDemoWatermark(registration.context),
            registration.watermark,
          );
    } catch (_) {
      return false;
    }
  }

  static RenderParagraph? _visibleDemoWatermark(BuildContext context) {
    if (!context.mounted || context is! Element) return null;
    final widget = context.widget;
    if (widget is! DemoWatermark ||
        !identical(widget.fixtures, DemoFixtures.instance)) {
      return null;
    }
    RenderParagraph? mark;
    void findMark(Element element) {
      if (mark != null) return;
      if (element is RenderObjectElement) {
        final render = element.renderObject;
        if (render is RenderParagraph &&
            render.text.toPlainText() == 'DEMO · SYNTHETIC DATA') {
          mark = render;
          return;
        }
      }
      element.visitChildElements(findMark);
    }

    context.visitChildElements(findMark);
    final paragraph = mark;
    if (paragraph == null ||
        !paragraph.attached ||
        !paragraph.hasSize ||
        paragraph.size.isEmpty) {
      return null;
    }
    final local = Offset.zero & paragraph.size;
    final bounds = MatrixUtils.transformRect(
      paragraph.getTransformTo(null),
      local,
    );
    final view = View.of(context);
    final screen = Offset.zero & (view.physicalSize / view.devicePixelRatio);
    if (!bounds.isFinite ||
        bounds.isEmpty ||
        screen.intersect(bounds) != bounds) {
      return null;
    }
    RenderObject child = paragraph;
    for (var parent = child.parent; parent != null; parent = parent.parent) {
      if ((parent is RenderOffstage && parent.offstage) ||
          (parent is RenderOpacity && parent.opacity != 1) ||
          (parent is RenderAnimatedOpacity && parent.opacity.value != 1)) {
        return null;
      }
      final clip = parent.describeApproximatePaintClip(child);
      final rect = MatrixUtils.transformRect(
        paragraph.getTransformTo(parent),
        local,
      );
      if (clip != null && clip.intersect(rect) != rect) return null;
      child = parent;
    }
    return paragraph;
  }

  /// Presentation only: the OS prompt may make a secured window inactive.
  /// Hidden/paused windows and unconfirmed native protection stay covered.
  void beginBiometricPrompt() {
    _biometricPrompts++;
    invalidateDocumentation();
  }

  void endBiometricPrompt() {
    if (_biometricPrompts > 0) _biometricPrompts--;
    _changed();
  }

  void register(
    Object token,
    ModalRoute<dynamic>? route, {
    bool visible = true,
  }) {
    final next = (route: route, visible: visible);
    if (_scopes[token] == next) return;
    _scopes[token] = next;
    _securityEpoch++;
    _changed();
  }

  void unregister(Object token) {
    if (_scopes.remove(token) == null) return;
    _securityEpoch++;
    _changed();
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
    _changed();
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
    // Preserve an already-active manual demo grant across a brief OS overlay.
    // This does NOT change foreground eligibility for a new grant or change
    // how normal inspector screens are obscured while inactive.
    final wasVerifiedActive =
        _phase == DocumentationPhase.active &&
        _documentationRequested &&
        _identityVerified &&
        _qaScreenshotsAllowed &&
        _applied == false &&
        !_failed;
    _lifecycle = state;
    if (state == AppLifecycleState.inactive && wasVerifiedActive) {
      _changed();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      // Return from the same transient inactive without silently re-granting.
      _changed();
      return;
    }
    // No ON yet, or genuine hidden/paused/detached: fail closed and require
    // a fresh identity-verified manual action after return.
    invalidateDocumentation();
  }

  Future<bool> beginDocumentation() async {
    if (!showControl) return false;
    final generation = _generation;
    final epoch = _securityEpoch;
    final authorization = _authorizationRevision;
    // Re-attest the debug documentation identity at activation time, not only
    // at grant time; a stale grant cannot open a capture session.
    if (!await _verifyIdentity()) {
      revokeDemoReadiness();
      return false;
    }

    if (!showControl ||
        generation != _generation ||
        epoch != _securityEpoch ||
        authorization != _authorizationRevision) {
      return false;
    }
    _generation++;
    _documentationRequested = true;
    _changed();
    return true;
  }

  Future<bool> authorizeDebugDocumentation() async {
    if (_disposed || !await isVerifiedDocumentationContext()) return false;
    final generation = _generation;
    final authorization = _authorizationRevision;
    if (_disposed ||
        generation != _generation ||
        authorization != _authorizationRevision) {
      return false;
    }
    _authorizationRevision++;
    _identityVerified = true;
    _qaScreenshotsAllowed = true;
    _changed();
    return true;
  }

  /// Attaches the capture permission to a fully verified demo identity
  /// ([isVerifiedDemoContext]). Tests pass the explicit matrix; the normal
  /// debug flow uses [authorizeDebugDocumentation].
  @visibleForTesting
  Future<bool> grantQaDocumentation({
    bool? debugMode,
    bool? onAndroid,
    bool? qaPreview,
    String? flavor,
    String? pin,
    String? packageName,
    String? buildSignature,
  }) async {
    if (_disposed) return false;
    final generation = _generation;
    final authorization = _authorizationRevision;
    if (!await isVerifiedDemoContext(
      debugMode: debugMode,
      onAndroid: onAndroid,
      qaPreview: qaPreview,
      flavor: flavor,
      pin: pin,
      packageName: packageName,
      buildSignature: buildSignature,
    )) {
      revokeDemoReadiness();
      return false;
    }
    if (_disposed ||
        generation != _generation ||
        authorization != _authorizationRevision) {
      return false;
    }
    _authorizationRevision++;
    _identityVerified = true;
    _qaScreenshotsAllowed = true;
    // No _changed(): the flags are not part of _desired, and a microtask
    // queued from a real-zone setUp would never be flushed by a later
    // FakeAsync test body (it would also swallow the body's own scheduling).
    return true;
  }

  /// Test/teardown hook: withdraws the capture permission entirely.
  @visibleForTesting
  void revokeQaDocumentation() {
    _authorizationRevision++;
    _identityVerified = false;
    _qaScreenshotsAllowed = false;
    _revokeDocumentation();
    // Direct re-apply instead of _changed(): revoke can run in a real-zone
    // tearDown, whose microtasks a later FakeAsync test never flushes. The
    // reconcile loop re-reads _desired each iteration, so an overlapping
    // run self-heals.
    unawaited(_reconcile());
  }

  /// Full demo identity matrix, fail-closed in this order: debug build,
  /// Android, QA_PREVIEW define, demo flavor define, demo package name, a
  /// 64-hex approved-signer pin, and a signing-certificate signature that
  /// matches the pin. Anything absent or mismatched denies.
  @visibleForTesting
  static Future<bool> isVerifiedDemoContext({
    bool? debugMode,
    bool? onAndroid,
    bool? qaPreview,
    String? flavor,
    String? pin,
    String? packageName,
    String? buildSignature,
  }) async {
    if (!(debugMode ?? kDebugMode)) return false;
    if (!(onAndroid ?? (kIsWeb ? false : Platform.isAndroid))) return false;
    if (!(qaPreview ?? const bool.fromEnvironment('QA_PREVIEW'))) {
      return false;
    }
    if ((flavor ?? const String.fromEnvironment('FLUTTER_APP_FLAVOR')) !=
        'demo') {
      return false;
    }
    final info = packageName == null || buildSignature == null
        ? await PackageInfo.fromPlatform()
        : null;
    if ((packageName ?? info!.packageName) != demoPackageName) return false;
    final approvedPin =
        pin ?? const String.fromEnvironment('FIELDSYNC_DEMO_SIGNER_SHA256');
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(approvedPin)) return false;
    if ((buildSignature ?? info!.buildSignature).toUpperCase() !=
        approvedPin.toUpperCase()) {
      return false;
    }
    return true;
  }

  @visibleForTesting
  static Future<bool> isVerifiedDocumentationContext({
    bool? debugMode,
    bool? onAndroid,
    bool? qaPreview,
    String? flavor,
    String? packageName,
    String? buildSignature,
  }) async {
    if (!(debugMode ?? kDebugMode)) return false;
    if (!(onAndroid ?? (kIsWeb ? false : Platform.isAndroid))) return false;
    final effectiveQaPreview =
        qaPreview ?? const bool.fromEnvironment('QA_PREVIEW');
    final effectiveFlavor =
        flavor ?? const String.fromEnvironment('FLUTTER_APP_FLAVOR');
    if (effectiveQaPreview || effectiveFlavor == 'demo') {
      return isVerifiedDemoContext(
        debugMode: debugMode,
        onAndroid: onAndroid,
        qaPreview: qaPreview,
        flavor: flavor,
        packageName: packageName,
        buildSignature: buildSignature,
      );
    }
    final info = packageName == null || buildSignature == null
        ? await PackageInfo.fromPlatform()
        : null;
    // The normal application id is the stable production identity. Flutter
    // does not guarantee that the flavor name is available at runtime in
    // every toolchain configuration, so package identity is the gate here.
    return (packageName ?? info!.packageName) == normalPackageName;
  }

  void _revokeDocumentation() {
    revokeDemoReadiness();
    _generation++;
    _documentationRequested = false;
    _phase = DocumentationPhase.off;
  }

  void endDocumentation() {
    if (_disposed) return;
    _revokeDocumentation();
    _changed();
  }

  /// Account, lock and lifecycle boundaries invalidate pending confirmations
  /// and the manual debug session. Ordinary navigation keeps the setting.
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
    if (_running || _disposed) return;
    _running = true;
    try {
      while (!_disposed && _applied != _desired) {
        final target = _desired;
        final generation = _generation;
        final epoch = _securityEpoch;
        final authorization = _authorizationRevision;
        bool current() =>
            !_disposed &&
            target == _desired &&
            generation == _generation &&
            epoch == _securityEpoch &&
            authorization == _authorizationRevision;
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
              _revokeDocumentation();
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
          if (!current()) {
            // A real native result for an older policy is not confirmation of
            // the current policy, and can never activate documentation.
            _applied = null;
            _revokeDocumentation();
            continue;
          }
          _applied = target;
          _failed = false;
          if (!target && _documentationRequested) {
            _phase = DocumentationPhase.active;
          }
        } catch (_) {
          if (_disposed) return;
          if (!current()) {
            // Superseded failures cannot poison a newer policy. Serialization
            // guarantees no newer result is overwritten while we retry it.
            _applied = null;
            _revokeDocumentation();
            continue;
          }
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
    revokeDemoReadiness();
    final restore =
        requiresProtection && (_documentationRequested || _applied != true);
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
