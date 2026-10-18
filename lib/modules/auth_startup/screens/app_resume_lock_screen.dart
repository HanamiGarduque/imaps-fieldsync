import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/services/auth_service.dart';
import '../services/biometric_service.dart';
import '../../../core/widgets/sensitive_screen.dart';
import '../../../core/widgets/fieldsync_brand.dart';
import '../../../core/theme/insight_theme.dart';
import '../../../core/layout/responsive_layout.dart';
import 'splash_screen.dart' show LoginScreen;

/// Shown two places: (1) app-resume, per the original §5d design, and
/// (2) cold start, when "Require on App Open" is on — see splash_screen.dart
/// _checkSession(). Same screen, same rule, either entry point:
///
/// - Biometric-only, deliberately. No pattern or password field lives on
///   this screen — that's not an oversight, it's so the app tells one
///   consistent "biometric is the sole re-entry mechanism" story
///   everywhere, matching the direction of removing the App Pattern
///   feature entirely.
/// - On repeated failure/cancel, the way out is a full sign-out back to
///   the normal Login screen (which already has its own password +
///   biometric options) — not a second, parallel login flow bolted onto
///   this screen.
/// - Can't be dismissed with the back button/gesture (PopScope canPop:
///   false) — the only ways off this screen are "unlock" or "sign out."
class AppResumeLockScreen extends StatefulWidget {
  /// What to show after a successful unlock. If null (the app-resume
  /// case), this screen was pushed on top of an already-visible
  /// MainShellScreen, so success just pops back to it. If provided (the
  /// cold-start case), there's nothing to pop back to yet — this screen
  /// itself replaces the route with whatever's built here instead.
  final WidgetBuilder? nextScreenBuilder;

  /// Cinematic-only presentation controls. Null retains ordinary resume/idle
  /// behavior: the brand is visible and the first frame prompts immediately.
  final Key? brandKey;
  final Animation<double>? brandReveal;
  final ValueListenable<bool>? cinematicReady;

  const AppResumeLockScreen({super.key, this.nextScreenBuilder,
    this.brandKey, this.brandReveal, this.cinematicReady});

  @override
  State<AppResumeLockScreen> createState() => _AppResumeLockScreenState();
}

class _AppResumeLockScreenState extends State<AppResumeLockScreen>
    with WidgetsBindingObserver {
  bool _checking = false;
  bool _lastAttemptFailed = false;
  String _bioLabel = 'biometric';
  bool _initialAttemptStarted = false;
  bool _attemptQueued = false;

  bool get _presentationReady => widget.cinematicReady?.value ?? true;

  bool get _canPresentPrompt {
    if (widget.cinematicReady == null) return true;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return (lifecycle == null || lifecycle == AppLifecycleState.resumed) &&
        (ModalRoute.of(context)?.isCurrent ?? false);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.cinematicReady?.addListener(_presentationChanged);
    _loadLabel();
    // Auto-trigger the prompt as soon as this screen is actually on screen,
    // rather than waiting for the person to tap a button first.
    _queueInitialAttempt();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _queueInitialAttempt();
  }

  @override
  void didUpdateWidget(covariant AppResumeLockScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cinematicReady != widget.cinematicReady) {
      oldWidget.cinematicReady?.removeListener(_presentationChanged);
      widget.cinematicReady?.addListener(_presentationChanged);
      _queueInitialAttempt();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _queueInitialAttempt();
  }

  @override
  void dispose() {
    widget.cinematicReady?.removeListener(_presentationChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _presentationChanged() {
    if (!mounted) return;
    setState(() {});
    _queueInitialAttempt();
  }

  void _queueInitialAttempt() {
    if (!mounted || !_presentationReady || _initialAttemptStarted || _attemptQueued) return;
    _attemptQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attemptQueued = false;
      if (!mounted || !_presentationReady || _initialAttemptStarted || !_canPresentPrompt) return;
      _attempt();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _loadLabel() async {
    final label = await BiometricService.primaryBiometricLabel();
    if (mounted) setState(() => _bioLabel = label);
  }

  Future<void> _attempt() async {
    if (!mounted || _checking || !_presentationReady || !_canPresentPrompt) return;
    _initialAttemptStarted = true;
    setState(() {
      _checking = true;
      _lastAttemptFailed = false;
    });

    final ok = await BiometricService.authenticate(
      reason: 'Unlock iMAPS FieldSync',
    );

    if (!mounted) return;

    if (ok) {
      if (widget.nextScreenBuilder != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: widget.nextScreenBuilder!),
        );
      } else {
        Navigator.of(context).pop();
      }
    } else {
      setState(() {
        _checking = false;
        _lastAttemptFailed = true;
      });
    }
  }

  Widget _brandGroup() {
    final brand = Wrap(spacing: 12, runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center, children: [
        FieldSyncBrand(key: widget.brandKey,
          variant: FieldSyncBrandVariant.white, height: 44),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('iMAPS', style: InsightTheme.inter(12, c: Colors.white)),
          Text('FieldSync', style: InsightTheme.urbanist(20, w: FontWeight.w800, c: Colors.white)),
        ]),
      ]);
    final reveal = widget.brandReveal;
    if (reveal == null) return brand;
    return AnimatedBuilder(animation: reveal, child: brand,
      builder: (context, child) => Opacity(
        opacity: reveal.value.clamp(0.0, 1.0),
        child: ExcludeSemantics(excluding: reveal.value <= 0, child: child!),
      ));
  }

  Future<void> _signOutInstead() async {
    setState(() => _checking = true);
    try {
      await AuthService.signOut();
    } catch (_) {
      // Best-effort — either way, send them to a real login screen next.
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _brandGroup(),
        const SizedBox(height: 32),
        Text('Your work.\nKept private.', style: InsightTheme.urbanist(34, w: FontWeight.w800, c: Colors.white)),
        const SizedBox(height: 12),
        Text('Confirm your identity to continue.', style: InsightTheme.inter(13, c: Colors.white)),
      ]),
    );
    final workspace = Container(
      decoration: const BoxDecoration(color: InsightTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(children: [
        Expanded(child: Center(child: ConstrainedContent(maxWidth: 480,
          child: Padding(padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 72, height: 72,
                decoration: BoxDecoration(color: InsightTheme.blueTint,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: InsightTheme.blue1.withValues(alpha: 0.2))),
                child: const Icon(Icons.lock_outline_rounded, size: 30, color: InsightTheme.blueInk)),
              const SizedBox(height: 24),
              Text('App Locked', style: InsightTheme.urbanist(24, w: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(_lastAttemptFailed ? 'That didn\'t match. Try again with $_bioLabel.' : 'Use $_bioLabel to continue',
                textAlign: TextAlign.center, style: InsightTheme.inter(14)),
              const SizedBox(height: 24),
              SizedBox(width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: InsightTheme.blue1,
                    foregroundColor: Colors.white, elevation: 0,
                    minimumSize: const Size(48, 52),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: InsightTheme.roundedMd)),
                  onPressed: _checking || !_presentationReady ? null : _attempt,
                  child: Wrap(spacing: 8, runSpacing: 4, alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center, children: [
                      if (_checking) const SizedBox.square(dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                      else const Icon(Icons.fingerprint_rounded, size: 20),
                      Text(_checking ? 'Checking…' : 'Unlock with $_bioLabel', textAlign: TextAlign.center,
                        style: InsightTheme.inter(16, w: FontWeight.w600,
                          c: _checking || !_presentationReady ? InsightTheme.ink3 : Colors.white)),
                    ]),
                )),
              const SizedBox(height: 8),
              TextButton(style: TextButton.styleFrom(minimumSize: const Size(120, 48)),
                onPressed: _checking || !_presentationReady ? null : _signOutInstead,
                child: Text('Log Out', style: InsightTheme.inter(14, w: FontWeight.w600, c: InsightTheme.redInk))),
            ]),
          ),
        ))),
        Padding(padding: const EdgeInsets.only(bottom: 20),
          child: Text('iMAPS FieldSync', style: InsightTheme.inter(12, c: InsightTheme.ink3))),
      ]),
    );
    return PopScope(
      canPop: false,
      child: SensitiveScreen(
        child: Scaffold(
          // The cinematic host owns the background; the opaque workspace and
          // header content paint in front of its journey, not underneath it.
          backgroundColor: widget.brandReveal == null
              ? InsightTheme.blue2 : Colors.transparent,
          body: SafeArea(
            child: LayoutBuilder(builder: (context, constraints) {
              Widget scrollWorkspace() => SingleChildScrollView(child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(child: workspace)));
              if (context.responsive.canSplitTwoPane) {
                return Row(children: [
                  Expanded(child: Center(child: SingleChildScrollView(child: header))),
                  Expanded(child: scrollWorkspace()),
                ]);
              }
              return SingleChildScrollView(child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [header, Expanded(child: workspace)]))));
            }),
          ),
        ),
      ),
    );
  }
}
