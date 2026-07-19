import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/quick_unlock_service.dart';
import '../widgets/pattern_lock_pad.dart';
import 'home_dashboard_screen.dart';
import 'login_screen.dart';

class _Colors {
  static const bg = Color(0xFFF2F4FB);
  static const surface = Colors.white;
  static const ink = Color(0xFF12141F);
  static const ink2 = Color(0xFF666C82);
  static const ink3 = Color(0xFFA2A7BC);
  static const blue1 = Color(0xFF3D6BFF);
  static const blue2 = Color(0xFF0B2FBF);
  static const coral = Color(0xFFE23B4E);
}

/// Shown instead of jumping straight to Home when the inspector has
/// "stay signed in" + quick unlock both on. A valid Supabase session
/// already exists (restored by supabase_flutter) — this screen is
/// purely a local gate in front of it.
class QuickUnlockScreen extends StatefulWidget {
  final UserProfile profile;
  const QuickUnlockScreen({super.key, required this.profile});

  @override
  State<QuickUnlockScreen> createState() => _QuickUnlockScreenState();
}

class _QuickUnlockScreenState extends State<QuickUnlockScreen> with WidgetsBindingObserver {
  bool _biometricEnabled = false;
  bool _patternEnabled = false;
  bool _checking = true;
  bool _patternError = false;
  int _failedAttempts = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _init() async {
    final bio = await QuickUnlockService.isBiometricEnabled();
    final pat = await QuickUnlockService.isPatternEnabled();
    if (!mounted) return;
    setState(() {
      _biometricEnabled = bio;
      _patternEnabled = pat;
      _checking = false;
    });
    if (bio) _attemptBiometric();
  }

  Future<void> _attemptBiometric() async {
    final ok = await BiometricService.authenticate(
      reason: 'Unlock InSight',
    );
    if (ok) {
      _goHome();
    }
    // On failure/cancel we just stay on this screen — pattern (if set)
    // or the "Use email & passcode" fallback are still visible below.
  }

  void _onPatternDrawn(List<int> pattern) async {
    final ok = await QuickUnlockService.verifyPattern(pattern);
    if (ok) {
      _goHome();
      return;
    }
    setState(() {
      _patternError = true;
      _failedAttempts++;
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _patternError = false);
    });
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => HomeDashboardScreen(profile: widget.profile)),
    );
  }

  Future<void> _useEmailFallback() async {
    // Falling back to full login means treating this as a fresh sign-in:
    // sign out of the cached session and clear this device's quick
    // unlock so a mistaken/lost-phone scenario can't be waved through.
    await AuthService.signOut();
    await QuickUnlockService.clearAll();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(backgroundColor: _Colors.bg, body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: _Colors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 60,
                height: 60,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [_Colors.blue1, _Colors.blue2]),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_outline_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 18),
              Text('Welcome back', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: _Colors.ink)),
              const SizedBox(height: 6),
              Text(
                widget.profile.fullName,
                style: GoogleFonts.inter(fontSize: 13, color: _Colors.ink2, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 36),

              if (_patternEnabled) ...[
                Text(
                  _patternError ? 'Wrong pattern, try again' : 'Draw your pattern to unlock',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: _patternError ? _Colors.coral : _Colors.ink2),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 220,
                  height: 220,
                  child: PatternLockPad(onComplete: _onPatternDrawn, showError: _patternError),
                ),
                const SizedBox(height: 16),
              ],

              if (_biometricEnabled)
                TextButton.icon(
                  onPressed: _attemptBiometric,
                  icon: const Icon(Icons.fingerprint, color: _Colors.blue1),
                  label: Text('Try biometric again', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: _Colors.blue1)),
                ),

              const Spacer(),
              TextButton(
                onPressed: _useEmailFallback,
                child: Text(
                  'Use email & passcode instead',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: _Colors.ink2),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
