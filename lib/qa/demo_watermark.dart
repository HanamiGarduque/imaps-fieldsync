import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/insight_theme.dart';
import '../modules/auth_startup/services/screen_protection_service.dart';
import 'demo_fixtures.dart';

/// Root builder wrapper: the Navigator and all its Flutter overlays occupy the
/// space below the mark. Reserving this strip avoids covering action labels.
/// This makes no claim about physical OS permission windows.
class DemoWatermark extends StatefulWidget {
  const DemoWatermark({super.key, required this.fixtures, required this.child});
  final DemoFixtures fixtures;
  final Widget child;

  @override
  State<DemoWatermark> createState() => _DemoWatermarkState();
}

class _DemoWatermarkState extends State<DemoWatermark> {
  final _protection = ScreenProtectionService.instance;
  Object? _lastAttempt;
  int _mountGeneration = 0;
  bool _attached = true;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _protection.addListener(_scheduleReadiness);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.of(context) &&
        MediaQuery.maybeOf(context)?.size.isEmpty != true;
    _withdrawReadiness();
    _scheduleReadiness();
  }

  @override
  void didUpdateWidget(covariant DemoWatermark oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.fixtures, widget.fixtures)) {
      oldWidget.fixtures.watermarkMounted(false);
    }
    _withdrawReadiness();
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
    widget.fixtures.watermarkMounted(false);
  }

  void _scheduleReadiness() {
    if (!mounted || !_attached || !_visible) return;
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
    final live = identical(widget.fixtures, DemoFixtures.instance);
    if (live && (!state.foreground || !state.sensitive ||
        state.applied != true || state.failed || state.transitioning ||
        state.popup || state.phase != DocumentationPhase.off)) {
      widget.fixtures.watermarkMounted(false);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_attached || !_visible ||
          generation != _mountGeneration) {
        return;
      }
      final laidOut = context.size?.isEmpty == false;
      widget.fixtures.watermarkMounted(laidOut);
      if (live && laidOut) {
        // Only the D26 service can establish readiness. No post-await state
        // writes: teardown and service generations fence stale completions.
        unawaited(_protection.registerDemoReadiness(context));
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _protection.removeListener(_scheduleReadiness);
    _withdrawReadiness();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
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
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'DEMO · SYNTHETIC DATA',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
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
  );
}
