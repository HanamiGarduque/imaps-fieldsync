import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/insight_theme.dart';
import '../core/widgets/sensitive_screen.dart';
import '../modules/auth_startup/services/screen_protection_service.dart';
import '../modules/auth_startup/widgets/debug_screenshot_toggle.dart';
import 'demo_fixtures.dart';

/// Root builder wrapper: the Navigator and all its Flutter overlays occupy the
/// space below the mark. Reserving this strip avoids covering action labels.
/// This makes no claim about physical OS permission windows.
class DemoWatermark extends StatefulWidget {
  const DemoWatermark({
    super.key,
    required this.fixtures,
    required this.child,
    this.protection,
    this.navigatorKey,
  });
  final DemoFixtures fixtures;
  final Widget child;
  final ScreenProtectionService? protection;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<DemoWatermark> createState() => _DemoWatermarkState();
}

class _DemoWatermarkState extends State<DemoWatermark>
    with WidgetsBindingObserver {
  ScreenProtectionService? _bound;
  ScreenProtectionService get _protection => _bound!;
  final _mark = GlobalKey();
  StreamSubscription<AuthState>? _auth;
  Session? _session;
  Timer? _watchdog;
  bool _granted = false;
  bool _granting = false;
  bool _checking = false;
  bool _closed = false;
  bool _foreground = true;
  bool _lastLaidOut = false;
  int _lease = 0;
  int? _allowedGeneration;
  Object? _lastAttempt;
  int _mountGeneration = 0;
  bool _attached = true;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    try {
      final auth = Supabase.instance.client.auth;
      _session = auth.currentSession;
      _auth = auth.onAuthStateChange.listen(
        (state) {
          if (!identical(state.session, _session)) _loseTrust();
        },
        onError: (Object _) => _loseTrust(),
        onDone: _loseTrust,
      );
    } catch (_) {
      // An uninitialized fictional session cannot authorize capture.
    }
    // ponytail: fixtures expose async attestation, not a change stream.
    // Re-attest at most once/second and before every manual activation;
    // session, lifecycle and detach revocation are event-driven.
    _watchdog = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_watchSource());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final protection =
        widget.protection ??
        ScreenProtectionScope.maybeOf(context) ??
        ScreenProtectionService.instance;
    if (!identical(_bound, protection)) {
      _bound?.removeListener(_scheduleReadiness);
      _revoke();
      _bound = protection;
      protection.addListener(_scheduleReadiness);
    }
    _visible =
        TickerMode.valuesOf(context).enabled &&
        MediaQuery.maybeOf(context)?.size.isEmpty != true;
    if (!_visible) _withdrawReadiness();
    _scheduleReadiness();
  }

  @override
  void didUpdateWidget(covariant DemoWatermark oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.fixtures, widget.fixtures)) {
      oldWidget.fixtures.watermarkMounted(false);
      _loseTrust();
    }
    _scheduleReadiness();
  }

  @override
  void activate() {
    super.activate();
    _attached = true;
    _scheduleReadiness();
  }

  @override
  void deactivate() {
    _attached = false;
    _withdrawReadiness();
    super.deactivate();
  }

  void _withdrawReadiness() {
    _mountGeneration++;
    _lastAttempt = null;
    _lastLaidOut = false;
    widget.fixtures.watermarkMounted(false);
    _revoke();
  }

  void _revoke() {
    final wasGranted = _granted;
    _lease++;
    _granted = false;
    _allowedGeneration = null;
    _lastAttempt = null;
    if (wasGranted || _granting) {
      // B1's revocable demo API is test-annotated but is also the runtime gate.
      // ignore: invalid_use_of_visible_for_testing_member
      _bound?.revokeQaDocumentation();
    }
    if (wasGranted && mounted && _attached) setState(() {});
  }

  void _loseTrust() {
    _closed = true;
    _revoke();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only the already-verified, active fictional demo survives a transient
    // screenshot/recorder overlay. All other inactive states and any actual
    // hidden/paused/detached transition revoke the source grant.
    final temporaryOverlay = state == AppLifecycleState.inactive &&
        _bound != null && _granted &&
        _protection.isDocumentationActive &&
        _sameSession && _watermarkVisible;
    _foreground = state == AppLifecycleState.resumed || temporaryOverlay;
    if (!_foreground) _revoke();
    _scheduleReadiness();
  }

  bool get _sameSession {
    try {
      return _session != null &&
          identical(_session, Supabase.instance.client.auth.currentSession);
    } catch (_) {
      return false;
    }
  }

  bool get _watermarkVisible {
    if (!mounted || !_attached || !_visible) return false;
    final render = _mark.currentContext?.findRenderObject();
    if (render is! RenderBox ||
        !render.attached ||
        !render.hasSize ||
        render.size.isEmpty) {
      return false;
    }
    final local = Offset.zero & render.size;
    final bounds = MatrixUtils.transformRect(
      render.getTransformTo(null),
      local,
    );
    final view = View.of(context);
    final screen = Offset.zero & (view.physicalSize / view.devicePixelRatio);
    if (!bounds.isFinite ||
        bounds.isEmpty ||
        screen.intersect(bounds) != bounds) {
      return false;
    }
    RenderObject child = render;
    for (var parent = child.parent; parent != null; parent = parent.parent) {
      if ((parent is RenderOffstage && parent.offstage) ||
          (parent is RenderOpacity && parent.opacity != 1) ||
          (parent is RenderAnimatedOpacity && parent.opacity.value != 1)) {
        return false;
      }
      final clip = parent.describeApproximatePaintClip(child);
      final rect = MatrixUtils.transformRect(
        render.getTransformTo(parent),
        local,
      );
      if (clip != null && clip.intersect(rect) != rect) return false;
      child = parent;
    }
    return true;
  }

  Future<bool> _sourceValid() async =>
      !_closed &&
      _foreground &&
      _sameSession &&
      _watermarkVisible &&
      await widget.fixtures.captureSourceReady.timeout(
        ScreenProtectionService.nativeTimeout,
      ) &&
      !_closed &&
      _foreground &&
      _sameSession &&
      _watermarkVisible;

  Future<void> _watchSource() async {
    if (_closed || !mounted || !_attached) return;
    if (!_granted) {
      final laidOut = _watermarkVisible;
      if (laidOut && !_lastLaidOut) _lastAttempt = null;
      _lastLaidOut = laidOut;
      _scheduleReadiness();
      return;
    }
    if (!_watermarkVisible) {
      _withdrawReadiness();
      return;
    }
    if (_checking) return;
    _checking = true;
    final lease = _lease;
    try {
      if (!await _sourceValid() && lease == _lease) _loseTrust();
    } catch (_) {
      if (lease == _lease) _loseTrust();
    } finally {
      _checking = false;
    }
  }

  Future<void> _grantFromReadiness() async {
    if (_granting || _granted || _closed || !_foreground) return;
    _granting = true;
    final lease = _lease;
    final generation = _protection.documentationGeneration;
    final epoch = _protection.securityEpoch;
    bool current() =>
        mounted &&
        _attached &&
        !_closed &&
        _foreground &&
        lease == _lease &&
        generation == _protection.documentationGeneration &&
        epoch == _protection.securityEpoch &&
        _watermarkVisible;
    try {
      if (!await _protection.registerDemoReadiness(context) ||
          !current() ||
          !await _protection.demoCaptureReady ||
          !current() ||
          !await _sourceValid() ||
          !current()) {
        return;
      }
      // No identity overrides: the live service checks Android/package/signer.
      // This grants eligibility only. Only the confirmed manual action asks OFF.
      // ignore: invalid_use_of_visible_for_testing_member
      final granted = await _protection.grantQaDocumentation().timeout(
        ScreenProtectionService.nativeTimeout,
      );
      if (!granted) return;
      if (!current()) {
        _revoke();
        return;
      }
      _granted = true;
      _protection.endDocumentation();
      _allowedGeneration = _protection.documentationGeneration;
      if (mounted) setState(() {});
    } catch (_) {
      _revoke();
    } finally {
      _granting = false;
      if (!_granted &&
          !_closed &&
          mounted &&
          (generation != _protection.documentationGeneration ||
              epoch != _protection.securityEpoch)) {
        _lastAttempt = null;
        _scheduleReadiness();
      }
    }
  }

  Future<bool> _beginDocumentation() async {
    final lease = _lease;
    final generation = _protection.documentationGeneration;
    final epoch = _protection.securityEpoch;
    final owner = _protection.visibleScope;
    try {
      if (!_granted) return false;
      final sourceValid = await _sourceValid();
      if (lease != _lease) return false;
      if (!sourceValid) {
        _loseTrust();
        return false;
      }
      if (generation != _protection.documentationGeneration ||
          epoch != _protection.securityEpoch ||
          !identical(owner, _protection.visibleScope) ||
          !_protection.showControl) {
        return false;
      }
      // beginDocumentation increments exactly once. Any further generation
      // change is a genuine invalidation, unlike ordinary navigation epochs.
      _allowedGeneration = generation + 1;
      final accepted = await _protection.beginDocumentation().timeout(
        ScreenProtectionService.nativeTimeout,
      );
      if (accepted &&
          lease == _lease &&
          _allowedGeneration == _protection.documentationGeneration) {
        return true;
      }
    } catch (_) {
      // Failed source validation or activation never authorizes capture.
    }
    if (lease == _lease) _revoke();
    return false;
  }

  void _scheduleReadiness() {
    if (_bound == null || !mounted || !_attached || !_visible || _closed) {
      return;
    }
    if (_granted &&
        (_allowedGeneration != _protection.documentationGeneration ||
            !_foreground ||
            _protection.nativeFailure)) {
      _revoke();
    }
    if (_granted || _granting || !_foreground) return;
    final state = (
      generation: _protection.documentationGeneration,
      epoch: _protection.securityEpoch,
      foreground: _protection.foreground,
      sensitive: _protection.requiresProtection,
      applied: _protection.appliedProtection,
      failed: _protection.nativeFailure,
      transitioning: _protection.transitioning,
      popup: _protection.hasPopup,
      phase: _protection.documentationPhase,
    );
    // Registration's own notification must not register again in a loop.
    if (_lastAttempt == state) return;
    _lastAttempt = state;
    final generation = ++_mountGeneration;
    if (!state.foreground ||
        !state.sensitive ||
        state.applied != true ||
        state.failed ||
        state.transitioning ||
        state.popup ||
        state.phase != DocumentationPhase.off) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_attached ||
          !_visible ||
          generation != _mountGeneration) {
        return;
      }
      final laidOut = _watermarkVisible;
      _lastLaidOut = laidOut;
      widget.fixtures.watermarkMounted(laidOut);
      if (laidOut) unawaited(_grantFromReadiness());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _attached = false;
    WidgetsBinding.instance.removeObserver(this);
    _bound?.removeListener(_scheduleReadiness);
    _watchdog?.cancel();
    unawaited(_auth?.cancel());
    _withdrawReadiness();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DemoCaptureScope(
    beginDocumentation: _beginDocumentation,
    child: Column(
      children: [
        IgnorePointer(
          child: Semantics(
            container: true,
            label:
                'DEMO · SYNTHETIC DATA. '
                'Simulated receipts—nothing delivered. '
                'Source: ${DemoFixtures.revision}. No real records or receipts.',
            child: ExcludeSemantics(
              child: Material(
                color: InsightTheme.ink,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'DEMO · SYNTHETIC DATA',
                            key: _mark,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Text(
                            'Simulated receipts—nothing delivered',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_granted)
          Material(
            color: InsightTheme.surface,
            child: ScreenProtectionScope(
              protection: _protection,
              child: DebugScreenshotToggle(navigatorKey: widget.navigatorKey),
            ),
          ),
        Expanded(
          // ModalRoute blocks earlier semantics within its nearest boundary.
          // Keep that boundary inside the Navigator, not around the watermark.
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: widget.child,
            ),
          ),
        ),
      ],
    ),
  );
}

/// The demo root owns source authorization; the existing manual control still
/// owns confirmation. No global callback or alternate native writer is added.
class DemoCaptureScope extends InheritedWidget {
  const DemoCaptureScope({
    super.key,
    required this.beginDocumentation,
    required super.child,
  });
  final Future<bool> Function() beginDocumentation;

  static DemoCaptureScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DemoCaptureScope>();

  @override
  bool updateShouldNotify(DemoCaptureScope oldWidget) =>
      beginDocumentation != oldWidget.beginDocumentation;
}
