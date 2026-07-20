import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import '../config/feature_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/quick_unlock_service.dart';
import '../widgets/pattern_lock_pad.dart';
import 'home_dashboard_screen.dart';
import 'main_shell_screen.dart';
import 'quick_unlock_screen.dart';

/// ==================================================================
/// EXACT MATCH DESIGN TOKENS
/// ==================================================================
class AppColors {
  static const bg = Color(0xFFF2F4FB);
  static const surface = Color(0xFFFFFFFF);
  
  static const ink = Color(0xFF12141F);
  static const ink2 = Color(0xFF666C82);
  static const ink3 = Color(0xFFA2A7BC);
  
  static const blue1 = Color(0xFF3D6BFF);
  static const blue2 = Color(0xFF0B2FBF);
  static const blueInk = Color(0xFF1A3FC4);
  
  static const amber = Color(0xFFFFB700);
  
  static const line = Color(0x12141628); 
  static const lineStrong = Color(0x21141628); 
}

class AppText {
  static TextStyle poppins(double size, {FontWeight w = FontWeight.w700, Color? c, double? ls}) => 
      GoogleFonts.poppins(fontSize: size, fontWeight: w, color: c ?? AppColors.ink, letterSpacing: ls);
      
  static TextStyle inter(double size, {FontWeight w = FontWeight.w600, Color? c, double? ls, double? lh}) => 
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: c ?? AppColors.ink, letterSpacing: ls, height: lh);
      
  static TextStyle mono(double size, {FontWeight w = FontWeight.w500, Color? c, double? ls}) => 
      GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: w, color: c ?? AppColors.ink3, letterSpacing: ls);
}

/// ==================================================================
/// SCREEN 1 — SPLASH
/// ==================================================================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    // Artificial delay to allow the splash screen branding to show
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final staySignedIn = prefs.getBool('stay_signed_in') ?? false;
      debugPrint('[STAY_SIGNED_IN] pref value: $staySignedIn');
      debugPrint('[STAY_SIGNED_IN] currentUser: ${AuthService.currentUserDebug}');
      debugPrint('[STAY_SIGNED_IN] session expiry: ${AuthService.sessionExpiryDebug}');

      if (staySignedIn) {
        final profile = await AuthService.getCurrentProfile();
        debugPrint('[STAY_SIGNED_IN] profile fetch result: ${profile?.fullName ?? "NULL"}');
        if (profile != null && mounted) {
          final quickUnlockOn = kQuickUnlockEnabled && await QuickUnlockService.isAnyEnabled();
          if (quickUnlockOn) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => QuickUnlockScreen(profile: profile)),
            );
          } else {
            // Valid session found, no quick unlock configured — go straight in
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => MainShellScreen(profile: profile)),
            );
          }
          return;
        }
      } else {
        // Force sign out to clear Supabase's auto-persisted local cache if user opted out
        if (AuthService.isLoggedIn) {
          await AuthService.signOut();
          await QuickUnlockService.clearAll();
        }
      }
    } catch (e, st) {
      debugPrint('[STAY_SIGNED_IN] Session verification failed: $e');
      debugPrint('[STAY_SIGNED_IN] Stack: $st');
    }

    // If no valid session or user opted out of stay signed in, route to Login
    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 700),
          pageBuilder: (_, anim, __) => FadeTransition(opacity: anim, child: const LoginScreen()),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.blue1, AppColors.blue2],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                            ),
                            child: const Center(
                              child: _ExactLogoSVG(size: 36, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      
                      RichText(
                        text: TextSpan(children: [
                          TextSpan(
                            text: 'InSight', 
                            style: AppText.poppins(28, w: FontWeight.w800, c: Colors.white, ls: -0.01)
                          ),
                          TextSpan(
                            text: '.', 
                            style: AppText.poppins(28, w: FontWeight.w800, c: Colors.white.withValues(alpha: 0.7), ls: -0.01)
                          ),
                        ]),
                      ),
                      const SizedBox(height: 8),
                      
                      Text(
                        'INITIALIZING FIELD UNIT…', 
                        style: AppText.mono(10.5, c: Colors.white.withValues(alpha: 0.7), ls: 0.8)
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.amber),
                ),
              ),
              const SizedBox(height: 24),
              
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'MUNICIPAL PLANNING & ZONING OFFICE · V1.0.0', 
                  style: AppText.mono(10, c: Colors.white.withValues(alpha: 0.6)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ------------------------------------------------------------------
/// REFINED LOGIN SCREEN
/// ------------------------------------------------------------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _staySignedIn = false;
  String? _errorMessage;

  bool _quickUnlockAvailable = false;
  bool _patEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();
  }

  Future<void> _loadSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('saved_email');
    debugPrint('[QUICK_UNLOCK] saved_email: $savedEmail');
    debugPrint('[QUICK_UNLOCK] isLoggedIn: ${AuthService.isLoggedIn}');
    debugPrint('[QUICK_UNLOCK] currentUser: ${AuthService.currentUserDebug}');
    debugPrint('[QUICK_UNLOCK] session expiry: ${AuthService.sessionExpiryDebug}');
    if (savedEmail != null && mounted) {
      setState(() {
        _emailController.text = savedEmail;
        _staySignedIn = prefs.getBool('stay_signed_in') ?? false;
      });
      await _checkQuickUnlock(savedEmail);
    }
  }

  // Quick unlock only ever shows up here for the account it was set up
  // for on this device — never as a way to register a new one.
  Future<void> _checkQuickUnlock(String email) async {
    if (!kQuickUnlockEnabled) return;
    if (!await QuickUnlockService.isBoundTo(email)) return;
    // The manual login form is only ever reached when Splash's own
    // session check already failed (or "stay signed in" was off) — so
    // if there's no live Supabase session right now, quick unlock is
    // guaranteed to fail with "session expired" no matter what. Showing
    // the button anyway was the actual bug users were hitting.
    if (!AuthService.isLoggedIn) {
      if (mounted) setState(() => _quickUnlockAvailable = false);
      return;
    }
    final pat = await QuickUnlockService.isPatternEnabled();
    if (!mounted) return;
    setState(() {
      _patEnabled = pat;
      _quickUnlockAvailable = pat;
    });
  }

  /// Icon is always visible (per design). Tapping it is what gates on
  /// setup status now, instead of hiding the button — unregistered/new
  /// users get a clear one-time explanation instead of a dead control.
  ///
  /// Checks the *stored* bound email, not the email textfield — the
  /// whole point of quick unlock is that the inspector shouldn't have to
  /// type anything first. Gating on textfield content was the bug: an
  /// empty/unfilled field always looked "unregistered" even with pattern
  /// unlock fully configured.
  Future<void> _onQuickUnlockTap() async {
    final boundEmail = await QuickUnlockService.boundEmail();
    final registered = boundEmail != null && await QuickUnlockService.isAnyEnabled();
    if (!registered) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Quick unlock is not yet set up. Please log in using your credentials and configure it inside your Profile Settings.'),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }
    // Pre-fill for display/consistency — getCurrentProfile() after a
    // successful scan doesn't need this, it's purely cosmetic.
    if (_emailController.text.trim().isEmpty) {
      _emailController.text = boundEmail;
    }
    await _checkQuickUnlock(boundEmail);
    await _handleQuickUnlock();
  }

  Future<void> _handleQuickUnlock() async {
    setState(() => _errorMessage = null);

    bool verified = false;
    if (_patEnabled && mounted) {
      verified = await _showPatternSheet();
    }
    if (!verified || !mounted) return;

    setState(() => _isLoading = true);
    try {
      // 1. SESSION TOKEN CHECK — cheap local check immediately after the
      // hardware scan succeeds, before spending a network call on it.
      if (AuthService.isLocalSessionExpired) {
        final refreshed = await AuthService.tryRefreshSession();
        if (!refreshed) {
          await _forceCredentialFallback();
          return;
        }
      }

      // Local token looked valid (or was refreshed) — confirm against
      // the server. This is where a revoked/invalidated token surfaces
      // even if the local expiry timestamp hadn't passed yet.
      final profile = await AuthService.getCurrentProfile();
      if (!mounted) return;
      if (profile == null) {
        await _forceCredentialFallback();
        return;
      }

      await NotificationService.registerCurrentDevice();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => MainShellScreen(profile: profile)),
      );
    } on AuthException catch (e) {
      // 2. GRACEFUL FALLBACK — explicit 401/invalid-token/refresh-token-
      // expired cases from the server.
      debugPrint('QUICK UNLOCK AUTH ERROR: ${e.statusCode} ${e.message}');
      await _forceCredentialFallback();
    } catch (e) {
      debugPrint('QUICK UNLOCK ERROR: $e');
      await _forceCredentialFallback();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 3 & 4. UI RESET + CLEAR STALE DATA — never leaves the inspector
  /// stuck. Wipes the dead token/quick-unlock config from secure storage
  /// and drops back to the same screen's plain email/passcode form
  /// (already visible/enabled here — nothing extra to unhide), with the
  /// expiry message left on screen so it's clear why they're re-entering
  /// credentials.
  Future<void> _forceCredentialFallback() async {
    await AuthService.signOut();       // purge the dead access/refresh token
    await QuickUnlockService.clearAll(); // purge local pattern-unlock config
    if (!mounted) return;
    setState(() {
      _quickUnlockAvailable = false;
      _patEnabled = false;
      _errorMessage = 'Your session expired. Please sign in with email & passcode.';
    });
  }

  Future<bool> _showPatternSheet() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _PatternVerifySheet(),
    );
    return result ?? false;
  }

  Future<void> _handleLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await AuthService.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      await NotificationService.registerCurrentDevice();
      final profile = await AuthService.getCurrentProfile();

      if (!mounted) return;

      if (profile != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('stay_signed_in', _staySignedIn);
        if (_staySignedIn) {
          await prefs.setString('saved_email', _emailController.text.trim());
        } else {
          await prefs.remove('saved_email');
        }

        // If quick unlock on this device is bound to a different
        // inspector's account, wipe it — it should never carry over
        // to whoever logs in next on a shared device.
        final thisEmail = _emailController.text.trim();
        final boundEmail = await QuickUnlockService.boundEmail();
        if (boundEmail != null && !await QuickUnlockService.isBoundTo(thisEmail)) {
          await QuickUnlockService.clearAll();
        }

        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => MainShellScreen(profile: profile)),
        );
      } else {
        setState(() {
          _errorMessage = 'Login succeeded, but no profile found. Contact your MPDO office administrator.';
        });
      }
    } catch (e) {
      debugPrint('LOGIN ERROR: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Invalid ID or passcode. Please try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleForgotPasscode() async {
    final email = _emailController.text.trim();
    
    if (email.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your email to reset your passcode.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await AuthService.resetPassword(email: email);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Reset instructions sent to $email', 
              style: AppText.inter(13, c: Colors.white),
            ),
            backgroundColor: const Color(0xFF10B981), 
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('RESET ERROR: $e');
      await _contactAdministrator();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _contactAdministrator() async {
    // No admin exists inside this app — account management happens on the
    // intranet (MPDO web portal). This just opens an email to the office,
    // it is NOT an in-app admin action.
    const officeEmail = 'mpdo@rosario.gov.ph';
    final String subject = Uri.encodeComponent('Passcode Reset Request — FieldSync');
    final String body = Uri.encodeComponent(
      'Hi MPDO,\n\nI am unable to reset my FieldSync passcode using the automated '
      'email link. Please assist.\n\nInspector email: ${_emailController.text.trim()}',
    );

    final Uri emailLaunchUri = Uri.parse('mailto:$officeEmail?subject=$subject&body=$body');

    try {
      final bool launched = await launchUrl(emailLaunchUri);
      if (!launched) throw Exception('No default mail client found.');
    } catch (e) {
      debugPrint('Could not launch email client: $e');
      await Clipboard.setData(const ClipboardData(text: officeEmail));
      
      if (mounted) {
        setState(() => _errorMessage = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Admin email copied to clipboard!', 
              style: AppText.inter(13, c: Colors.white),
            ),
            backgroundColor: AppColors.ink,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          const _DeviceBackground(),
          
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Column(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: const LinearGradient(
                              colors: [AppColors.blue1, AppColors.blue2],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.blue1.withValues(alpha: 0.35),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              )
                            ],
                          ),
                          child: const Center(
                            child: _ExactLogoSVG(size: 26, color: Colors.white),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('InSight', style: AppText.poppins(24, w: FontWeight.w800, ls: -0.01)),
                            Text('.', style: AppText.poppins(24, w: FontWeight.w800, c: AppColors.blue1, ls: -0.01)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.blue1.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.blue1.withValues(alpha: 0.1)),
                          ),
                          child: Text(
                            'ZONING & LAND USE VERIFICATION',
                            style: AppText.mono(9.5, ls: 0.8, c: AppColors.blue2),
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 36),
                    
                    Row(
                      children: [
                        Container(
                          width: 10, 
                          height: 2.5, 
                          decoration: BoxDecoration(
                            color: AppColors.blue1, 
                            borderRadius: BorderRadius.circular(1.5),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('LOG IN TO CONTINUE', style: AppText.mono(10, w: FontWeight.w600, ls: 1.0)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.line),
                        boxShadow: const [
                          BoxShadow(color: Color(0x0A141628), blurRadius: 2, offset: Offset(0, 1)),
                          BoxShadow(color: Color(0x0F141628), blurRadius: 30, offset: Offset(0, 14)),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel('EMAIL'),
                          const SizedBox(height: 6),
                          _buildTextField(
                            controller: _emailController,
                            hintText: 'inspector@test.com',
                            icon: Icons.badge_outlined,
                            obscureText: false,
                          ),
                          
                          const SizedBox(height: 16),
                          
                          _buildFieldLabel('PASSCODE'),
                          const SizedBox(height: 6),
                          _buildTextField(
                            controller: _passwordController,
                            hintText: '••••••••',
                            icon: Icons.lock_outline,
                            obscureText: _obscurePassword,
                            isPassword: true,
                          ),

                          if (kQuickUnlockEnabled) ...[
                            const SizedBox(height: 14),
                            _QuickUnlockButton(
                              label: 'Unlock with pattern',
                              enabled: !_isLoading,
                              onTap: _onQuickUnlockTap,
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: Checkbox(
                                  value: _staySignedIn,
                                  onChanged: (val) {
                                    setState(() => _staySignedIn = val ?? false);
                                  },
                                  activeColor: AppColors.blue1,
                                  checkColor: Colors.white,
                                  fillColor: WidgetStateProperty.resolveWith((states) {
                                    if (states.contains(WidgetState.selected)) {
                                      return AppColors.blue1;
                                    }
                                    return Colors.transparent;
                                  }),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4.5)),
                                  side: const BorderSide(color: AppColors.ink3, width: 1.5),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => setState(() => _staySignedIn = !_staySignedIn),
                                child: Text('Stay signed in', style: AppText.inter(13, w: FontWeight.w500, c: AppColors.ink2)),
                              ),
                            ],
                          ),
                          
                          GestureDetector(
                            onTap: _isLoading ? null : _handleForgotPasscode,
                            child: Text(
                              'Forgot passcode?',
                              style: AppText.inter(13, w: FontWeight.w600, c: AppColors.blueInk),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE23B4E).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE23B4E).withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Color(0xFFE23B4E), size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_errorMessage!, style: AppText.inter(12, w: FontWeight.w600, c: const Color(0xFFE23B4E))),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 28),
                    
                    Container(
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.blue1, AppColors.blue2],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.blue1.withValues(alpha: 0.32),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          )
                        ],
                      ),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _isLoading ? null : _handleLogin,
                        child: _isLoading 
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.0, color: Colors.white))
                            : Text('Sign in', style: AppText.poppins(14, w: FontWeight.w600, c: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldLabel(String text) {
    return Text(text, style: AppText.mono(10, ls: 0.6, w: FontWeight.w600, c: AppColors.ink2));
  }

  Widget _buildTextField({
    required TextEditingController controller, 
    required String hintText, 
    required IconData icon,
    required bool obscureText,
    bool isPassword = false,
    Widget? extraSuffix,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      obscuringCharacter: '•',
      style: AppText.inter(13, w: FontWeight.w600, c: AppColors.ink),
      cursorColor: AppColors.blue1,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: AppText.inter(13, w: FontWeight.w500, c: AppColors.ink3),
        filled: true,
        fillColor: AppColors.bg.withValues(alpha: 0.6),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        prefixIcon: Icon(icon, color: AppColors.ink3, size: 18),
        suffixIcon: (isPassword || extraSuffix != null)
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (extraSuffix != null) extraSuffix,
                if (isPassword)
                  IconButton(
                    icon: Icon(
                      obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: AppColors.ink3,
                      size: 18,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
              ],
            )
          : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.lineStrong, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.lineStrong, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.blue1, width: 1.2),
        ),
      ),
    );
  }
}

/// ------------------------------------------------------------------
/// EXACT UI COMPONENTS
/// ------------------------------------------------------------------

class _DeviceBackground extends StatelessWidget {
  const _DeviceBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -40,
          right: -40,
          child: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.blue1.withValues(alpha: 0.15),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.7],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -60,
          left: -60,
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.blue1.withValues(alpha: 0.10),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.7],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ExactLogoSVG extends StatelessWidget {
  final double size;
  final Color color;
  
  const _ExactLogoSVG({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size * 0.75,
            height: size * 0.75,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.5), width: 1.8),
            ),
          ),
          Container(
            width: size * 0.458, 
            height: size * 0.458,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 1.8),
            ),
          ),
          Container(
            width: size * 0.15,
            height: size * 0.15,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}
/// ------------------------------------------------------------------
/// PATTERN VERIFY SHEET — used by the Login page's "Unlock with
/// pattern" shortcut. Verify-only: one attempt at a time against the
/// pattern hash already stored on this device, nothing is registered
/// or changed here.
/// ------------------------------------------------------------------
class _PatternVerifySheet extends StatefulWidget {
  const _PatternVerifySheet();

  @override
  State<_PatternVerifySheet> createState() => _PatternVerifySheetState();
}

class _PatternVerifySheetState extends State<_PatternVerifySheet> {
  bool _error = false;
  bool _checking = false;

  Future<void> _onPattern(List<int> pattern) async {
    setState(() => _checking = true);
    final ok = await QuickUnlockService.verifyPattern(pattern);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _checking = false;
      _error = true;
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _error = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 28,
        right: 28,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(color: AppColors.lineStrong, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 20),
          Text(
            _error ? 'Wrong pattern, try again' : 'Draw your pattern',
            style: AppText.inter(14, w: FontWeight.w700, c: _error ? const Color(0xFFE23B4E) : AppColors.ink),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 220,
            height: 220,
            child: _checking
                ? const Center(child: CircularProgressIndicator())
                : PatternLockPad(onComplete: _onPattern, showError: _error),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: AppText.inter(13, w: FontWeight.w600, c: AppColors.ink2)),
          ),
        ],
      ),
    );
  }
}

/// Permanently visible below the passcode field — visibility never
/// depends on setup status, per design; setup status is only checked
/// on tap (see _onQuickUnlockTap).
class _QuickUnlockButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  const _QuickUnlockButton({required this.label, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: enabled ? onTap : null,
        icon: const Icon(Icons.pattern, size: 20),
        label: Text(label, style: AppText.inter(13, w: FontWeight.w700)),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.blue1,
          side: BorderSide(color: AppColors.blue1.withValues(alpha: 0.35)),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}