import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../widgets/sensitive_screen.dart';
import 'splash_screen.dart' show LoginScreen;

/// Shown when the app resumes from background and the resume-lock policy
/// (Security Settings → "Require on App Open" + the auto-lock timer) says
/// it's time to re-check. See AUTH_SECURITY_MASTER_DOC.md §5d for the full
/// design rationale — the short version:
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
  const AppResumeLockScreen({super.key});

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
      Navigator.of(context).pop();
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
          backgroundColor: const Color(0xFFF2F4FB),
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        color: Color(0xFF3D6BFF),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.lock_outline_rounded, size: 34, color: Colors.white),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'App Locked',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF12141F)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _lastAttemptFailed
                          ? 'That didn\'t match. Try again with $_bioLabel.'
                          : 'Use $_bioLabel to continue',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, color: Color(0xFF666C82)),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3D6BFF),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _checking ? null : _attempt,
                        child: _checking
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text('Unlock with $_bioLabel'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _checking ? null : _signOutInstead,
                      child: const Text('Sign Out Instead', style: TextStyle(color: Color(0xFF666C82))),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}