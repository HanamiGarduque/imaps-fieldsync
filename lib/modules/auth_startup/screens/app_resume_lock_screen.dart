import 'package:flutter/material.dart';
import '../../../core/services/auth_service.dart';
import '../services/biometric_service.dart';
import '../../../core/widgets/sensitive_screen.dart';
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

  const AppResumeLockScreen({super.key, this.nextScreenBuilder});

  @override
  State<AppResumeLockScreen> createState() => _AppResumeLockScreenState();
}

class _AppResumeLockScreenState extends State<AppResumeLockScreen> {
  bool _checking = false;
  bool _lastAttemptFailed = false;
  String _bioLabel = 'biometric';

  @override
  void initState() {
    super.initState();
    _loadLabel();
    // Auto-trigger the prompt as soon as this screen is actually on screen,
    // rather than waiting for the person to tap a button first.
    WidgetsBinding.instance.addPostFrameCallback((_) => _attempt());
  }

  Future<void> _loadLabel() async {
    final label = await BiometricService.primaryBiometricLabel();
    if (mounted) setState(() => _bioLabel = label);
  }

  Future<void> _attempt() async {
    if (_checking) return;
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
    return PopScope(
      canPop: false,
      child: SensitiveScreen(
        child: Scaffold(
          backgroundColor: InsightTheme.bg,
          body: SafeArea(
            child: Center(
              // Bounded and scrollable: the fixed column below summed to ~304px
              // with only ~26px of slack, so a wrapped bio label or a system
              // inset overflowed a 390px-tall landscape viewport.
              child: ConstrainedContent(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        color: InsightTheme.blue1,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.lock_outline_rounded, size: 34, color: Colors.white),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'App Locked',
                      style: InsightTheme.urbanist(22, w: FontWeight.w700, c: InsightTheme.ink),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _lastAttemptFailed
                          ? 'That didn\'t match. Try again with $_bioLabel.'
                          : 'Use $_bioLabel to continue',
                      textAlign: TextAlign.center,
                      style: InsightTheme.inter(14, w: FontWeight.w400, c: InsightTheme.ink2),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: InsightTheme.blue1,
                          foregroundColor: Colors.white,
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _checking ? null : _attempt,
                        child: _checking
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text(
                                'Unlock with $_bioLabel',
                                style: InsightTheme.inter(15, w: FontWeight.w600, c: Colors.white),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(120, 44),
                      ),
                      onPressed: _checking ? null : _signOutInstead,
                      child: Text(
                        'Log Out',
                        style: InsightTheme.inter(14, w: FontWeight.w600, c: InsightTheme.red),
                      ),
                    ),
                  ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}