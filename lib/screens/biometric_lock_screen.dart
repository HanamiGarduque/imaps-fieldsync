import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/quick_unlock_service.dart';
import '../services/secure_prefs_service.dart';
import 'splash_screen.dart' show LoginScreen;

class _Colors {
  static const bg = Color(0xFFF2F4FB);
  static const ink = Color(0xFF12141F);
  static const ink2 = Color(0xFF666C82);
  static const blue1 = Color(0xFF3D6BFF);
  static const blue2 = Color(0xFF0B2FBF);
  static const coral = Color(0xFFE23B4E);
}


/// Shown when the app requires biometric verification (e.g. app launch,
/// returning from background, or sensitive action confirmation).
class BiometricLockScreen extends StatefulWidget {
  final UserProfile profile;
  final VoidCallback onSuccess;
  final String title;
  final String subtitle;

  const BiometricLockScreen({
    super.key,
    required this.profile,
    required this.onSuccess,
    this.title = 'App Locked',
    this.subtitle = 'Authenticate to resume your session',
  });

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen> {
  bool _authenticating = false;
  String? _errorMsg;
  int _failedAttempts = 0;
  String _biometricLabel = 'Biometric';

  @override
  void initState() {
    super.initState();
    _loadLabelAndAuth();
  }

  Future<void> _loadLabelAndAuth() async {
    final label = await BiometricService.primaryBiometricLabel();
    if (mounted) {
      setState(() => _biometricLabel = label);
    }
    // Auto-trigger biometric prompt on screen open
    _triggerAuth();
  }

  Future<void> _triggerAuth() async {
    if (_authenticating) return;
    setState(() {
      _authenticating = true;
      _errorMsg = null;
    });

    final success = await BiometricService.authenticate(
      reason: 'Unlock iMAPS FieldSync',
    );

    if (!mounted) return;
    setState(() => _authenticating = false);

    if (success) {
      widget.onSuccess();
    } else {
      _failedAttempts++;
      if (_failedAttempts >= 3) {
        setState(() {
          _errorMsg = 'Multiple failed attempts. Please sign in with email & passcode.';
        });
      } else {
        setState(() {
          _errorMsg = 'Authentication failed. Tap button to try again.';
        });
      }
    }
  }

  Future<void> _fallbackToLogin() async {
    await AuthService.signOut();
    await QuickUnlockService.clearAll();
    await BiometricService.clearEnrollment();
    await SecurePrefsService.clearAll();
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Colors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            children: [
              const Spacer(),
              // Icon Badge
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_Colors.blue1, _Colors.blue2],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _Colors.blue1.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.fingerprint_rounded,
                  color: Colors.white,
                  size: 38,
                ),
              ),
              const SizedBox(height: 24),

              Text(
                widget.title,
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: _Colors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.profile.fullName,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _Colors.blue2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.subtitle,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  color: _Colors.ink2,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 32),

              if (_errorMsg != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _Colors.coral.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _Colors.coral.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    _errorMsg!,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _Colors.coral,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Retry Biometric Button
              ElevatedButton.icon(
                onPressed: _authenticating ? null : _triggerAuth,
                icon: const Icon(Icons.fingerprint_rounded, size: 20),
                label: Text('Unlock with $_biometricLabel'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _Colors.blue1,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 2,
                ),
              ),

              const Spacer(),

              // Fallback to password
              TextButton(
                onPressed: _fallbackToLogin,
                child: Text(
                  'Sign in with Email & Passcode',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _Colors.ink2,
                  ),
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
