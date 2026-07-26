import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/notification_service.dart';
import '../services/secure_prefs_service.dart';
import '../services/supabase_service.dart';
import 'main_shell_screen.dart';
import '../widgets/imaps_loading_indicator.dart';
import '../widgets/sensitive_screen.dart';

// ==================================================================
// DESIGN TOKENS
// ==================================================================
class AppColors {
  static const bg          = Color(0xFFF2F4FB);
  static const surface     = Color(0xFFFFFFFF);
  static const ink         = Color(0xFF12141F);
  static const ink2        = Color(0xFF666C82);
  static const ink3        = Color(0xFFA2A7BC);
  static const blue1       = Color(0xFF3D6BFF);
  static const blue2       = Color(0xFF0B2FBF);
  static const blueInk     = Color(0xFF1A3FC4);
  static const amber       = Color(0xFFFFB700);
  static const line        = Color(0x12141628);
  static const lineStrong  = Color(0x21141628);
}

class AppText {
  static TextStyle poppins(double size, {FontWeight w = FontWeight.w700, Color? c, double? ls}) =>
      GoogleFonts.poppins(fontSize: size, fontWeight: w, color: c ?? AppColors.ink, letterSpacing: ls);

  static TextStyle inter(double size, {FontWeight w = FontWeight.w600, Color? c, double? ls, double? lh}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: c ?? AppColors.ink, letterSpacing: ls, height: lh);

  static TextStyle mono(double size, {FontWeight w = FontWeight.w500, Color? c, double? ls}) =>
      GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: w, color: c ?? AppColors.ink3, letterSpacing: ls);
}

// ==================================================================
// SPLASH SCREEN
// ==================================================================
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
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;

    try {
      // STEP 1: Local token check (no network)
      if (!AuthService.isLoggedIn) {
        await _goToLogin();
        return;
      }

      // STEP 2: Refresh expired token if needed
      if (AuthService.isLocalSessionExpired) {
        final refreshed = await AuthService.tryRefreshSession();
        if (!refreshed) {
          await AuthService.signOut();
          await QuickUnlockService.clearAll();
          await BiometricService.clearEnrollment();
          await SecurePrefsService.clearAll();
          await _goToLogin();
          return;
        }
      }

      // STEP 3: Fetch profile
      final profile = await AuthService.getCurrentProfile();
      if (profile == null || !mounted) {
        await _goToLogin();
        return;
      }

      // STEP 4: Route through Quick Unlock if configured (legacy pattern)
      if (kQuickUnlockEnabled && await QuickUnlockService.isAnyEnabled()) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => QuickUnlockScreen(profile: profile)),
          );
        }
        return;
      }

      // STEP 5: Direct to app
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => MainShellScreen(profile: profile)),
        );
      }
    } catch (e) {
      debugPrint('[SPLASH] Session check error: $e');
      await _goToLogin();
    }
  }

  Future<void> _goToLogin() async {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 700),
        pageBuilder: (_, anim, __) => FadeTransition(opacity: anim, child: const LoginScreen()),
      ),
    );
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
                        borderRadius: BorderRadius.circular(28),
                        child: SizedBox(
                          width: 96,
                          height: 96,
                          child: Transform.scale(
                            scale: 1.45,
                            child: Image.asset(
                              'assets/icon/app_icon.png',
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('iMAPS', style: AppText.poppins(28, w: FontWeight.w800, c: Colors.white, ls: -0.01)),
                          Text('inSight', style: AppText.poppins(14, w: FontWeight.w600, c: Colors.white.withValues(alpha: 0.72), ls: 0.02)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'INITIALIZING FIELD UNIT…',
                        style: AppText.mono(10.5, c: Colors.white.withValues(alpha: 0.7), ls: 0.8),
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

// ==================================================================
// LOGIN SCREEN
// ==================================================================
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading       = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  // Quick unlock (legacy pattern)
  bool _quickUnlockAvailable = false;
  bool _patEnabled           = false;

  // Biometric
  bool   _biometricEnrolled = false;
  String _biometricLabel    = 'Biometric';

  @override
  void initState() {
    super.initState();
    _loadSavedPrefs();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedPrefs() async {
    final savedEmail  = await SecurePrefsService.getSavedEmail();
    final bioEnrolled = await BiometricService.isEnrolled();
    final bioLabel    = await BiometricService.primaryBiometricLabel();

    if (mounted) {
      setState(() {
        if (savedEmail != null && savedEmail.isNotEmpty) {
          _emailController.text = savedEmail;
        }
        _biometricEnrolled = bioEnrolled;
        _biometricLabel    = bioLabel;
      });
    }

    // Check pattern unlock state
    await _checkQuickUnlock(savedEmail ?? '');
  }

  Future<void> _checkQuickUnlock(String email) async {
    if (!kQuickUnlockEnabled) return;
    final pat = await QuickUnlockService.isPatternEnabled();
    final bound = await QuickUnlockService.boundEmail();
    final isBound = email.isEmpty || bound == null || await QuickUnlockService.isBoundTo(email);
    if (!mounted) return;
    setState(() {
      _patEnabled           = pat && isBound;
      _quickUnlockAvailable = pat && isBound;
    });
  }

  Future<void> _onQuickUnlockTap() async {
    final boundEmail = await QuickUnlockService.boundEmail();
    final registered = await QuickUnlockService.isAnyEnabled();
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
    if (_emailController.text.trim().isEmpty && boundEmail != null) {
      _emailController.text = boundEmail;
    }
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
      // 1. Check if active session exists
      if (AuthService.isLoggedIn && !AuthService.isLocalSessionExpired) {
        final profile = await AuthService.getCurrentProfile();
        if (mounted && profile != null) {
          await NotificationService.registerCurrentDevice();
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => MainShellScreen(profile: profile)),
          );
          return;
        }
      }

      // 2. Pattern verified — restore session using saved email and encrypted bio secret
      final savedEmail = await SecurePrefsService.getSavedEmail() ?? _emailController.text.trim();
      final bioSecret  = await SecurePrefsService.getBioSecret();

      if (savedEmail.isNotEmpty && bioSecret != null && bioSecret.isNotEmpty) {
        await AuthService.signIn(email: savedEmail, password: bioSecret);
        await NotificationService.registerCurrentDevice();
        final profile = await AuthService.getCurrentProfile();
        if (mounted && profile != null) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => MainShellScreen(profile: profile)),
          );
          return;
        }
      }

      if (mounted) {
        setState(() => _errorMessage = 'Pattern verified. Please enter passcode once to re-sync.');
      }
    } catch (e) {
      debugPrint('QUICK UNLOCK ERROR: $e');
      if (mounted) setState(() => _errorMessage = 'Pattern verification error. Please use email & passcode.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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

  // ── Biometric login ────────────────────────────────────────────────
  Future<void> _handleBiometricLogin() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final success = await BiometricService.authenticate(
        reason: 'Sign in to iMAPS FieldSync',
        useDeviceCredentialAsFallback: false, // Strict fingerprint/face prompt
      );
      if (!success) {
        if (mounted) setState(() { _isLoading = false; _errorMessage = 'Biometric authentication canceled or failed.'; });
        return;
      }

      // Check if current session is active
      if (AuthService.isLoggedIn && !AuthService.isLocalSessionExpired) {
        final profile = await AuthService.getCurrentProfile();
        if (mounted && profile != null) {
          await NotificationService.registerCurrentDevice();
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => MainShellScreen(profile: profile)),
          );
          return;
        }
      }

      // Session signed out or expired — restore session using Keystore-protected bio secret
      final savedEmail = await SecurePrefsService.getSavedEmail() ?? _emailController.text.trim();
      final bioSecret  = await SecurePrefsService.getBioSecret();

      if (savedEmail.isNotEmpty && bioSecret != null && bioSecret.isNotEmpty) {
        await AuthService.signIn(email: savedEmail, password: bioSecret);
        await NotificationService.registerCurrentDevice();
        final profile = await AuthService.getCurrentProfile();
        if (mounted && profile != null) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => MainShellScreen(profile: profile)),
          );
          return;
        }
      }

      if (mounted) {
        setState(() => _errorMessage = 'Biometric verified. Please enter passcode once to re-sync.');
      }
    } catch (e) {
      debugPrint('BIOMETRIC LOGIN ERROR: $e');
      if (mounted) setState(() => _errorMessage = 'Biometric error. Please use email & passcode.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Email/passcode login ──────────────────────────────────────────
  Future<void> _handleLogin() async {
    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      await AuthService.signIn(
        email:    _emailController.text.trim(),
        password: _passwordController.text,
      );
      await NotificationService.registerCurrentDevice();
      final profile = await AuthService.getCurrentProfile();

      if (!mounted) return;

      if (profile != null) {
        SupabaseService.logSecurityEvent(eventType: 'login_success', severity: 'info');

        // Persist email & encrypted secret for pre-fill and biometric auto-login
        await SecurePrefsService.setSavedEmail(_emailController.text.trim());
        await SecurePrefsService.setBioSecret(_passwordController.text);

        // Wipe quick-unlock if bound to a different account
        final thisEmail  = _emailController.text.trim();
        final boundEmail = await QuickUnlockService.boundEmail();
        if (boundEmail != null && !await QuickUnlockService.isBoundTo(thisEmail)) {
          await QuickUnlockService.clearAll();
        }

        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => MainShellScreen(profile: profile)),
        );
      } else {
        setState(() => _errorMessage = 'Login succeeded, but no profile found. Contact your MPDO office administrator.');
      }
    } catch (e) {
      debugPrint('LOGIN ERROR: $e');
      if (mounted) setState(() => _errorMessage = 'Invalid ID or passcode. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Forgot passcode ───────────────────────────────────────────────
  Future<void> _handleForgotPasscode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _errorMessage = 'Please enter your email to reset your passcode.');
      return;
    }

    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      await AuthService.resetPassword(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Reset instructions sent to $email', style: AppText.inter(13, c: Colors.white)),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 4),
        ));
      }
    } catch (e) {
      debugPrint('RESET ERROR: $e');
      await _contactAdministrator();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _contactAdministrator() async {
    const officeEmail = 'mpdo@rosario.gov.ph';
    final subject = Uri.encodeComponent('Passcode Reset Request — FieldSync');
    final body    = Uri.encodeComponent(
      'Hi MPDO,\n\nI am unable to reset my FieldSync passcode using the automated '
      'email link. Please assist.\n\nInspector email: ${_emailController.text.trim()}',
    );
    final emailUri = Uri.parse('mailto:$officeEmail?subject=$subject&body=$body');

    try {
      final launched = await launchUrl(emailUri);
      if (!launched) throw Exception('No default mail client found.');
    } catch (e) {
      debugPrint('Could not launch email client: $e');
      await Clipboard.setData(const ClipboardData(text: officeEmail));
      if (mounted) {
        setState(() => _errorMessage = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Admin email copied to clipboard!', style: AppText.inter(13, c: Colors.white)),
          backgroundColor: AppColors.ink,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 4),
        ));
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    return SensitiveScreen(child: Scaffold(
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
                    // Logo
                    Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: SizedBox(
                            width: 68,
                            height: 68,
                            child: Transform.scale(
                              scale: 1.45,
                              child: Image.asset(
                                'assets/icon/app_icon.png',
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('iMAPS', style: AppText.poppins(24, w: FontWeight.w800, ls: -0.01)),
                            Text('inSight', style: AppText.poppins(12, w: FontWeight.w600, c: AppColors.blueInk, ls: 0.02)),
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
                          width: 10, height: 2.5,
                          decoration: BoxDecoration(color: AppColors.blue1, borderRadius: BorderRadius.circular(1.5)),
                        ),
                        const SizedBox(width: 8),
                        Text('LOG IN TO CONTINUE', style: AppText.mono(10, w: FontWeight.w600, ls: 1.0)),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Login card
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.line),
                        boxShadow: const [
                          BoxShadow(color: Color(0x0A141628), blurRadius: 2,  offset: Offset(0, 1)),
                          BoxShadow(color: Color(0x0F141628), blurRadius: 30, offset: Offset(0, 14)),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel('EMAIL'),
                          const SizedBox(height: 6),
                          _buildTextField(controller: _emailController, hintText: 'inspector@test.com', icon: Icons.badge_outlined, obscureText: false),

                          const SizedBox(height: 16),

                          _buildFieldLabel('PASSCODE'),
                          const SizedBox(height: 6),
                          _buildTextField(controller: _passwordController, hintText: '••••••••', icon: Icons.lock_outline, obscureText: _obscurePassword, isPassword: true),

                          // Pattern quick-unlock (legacy)
                          if (kQuickUnlockEnabled && _quickUnlockAvailable) ...[
                            const SizedBox(height: 14),
                            _QuickUnlockButton(label: 'Unlock with pattern', enabled: !_isLoading, onTap: _onQuickUnlockTap),
                          ],

                          // Biometric — only shown when enrolled AND session is alive
                          if (_biometricEnrolled) ...[
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _isLoading ? null : _handleBiometricLogin,
                              icon: const Icon(Icons.fingerprint_rounded, size: 20),
                              label: Text('Sign in with $_biometricLabel', style: AppText.inter(13, w: FontWeight.w600, c: AppColors.blue1)),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                side: const BorderSide(color: AppColors.blue1, width: 1.2),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                minimumSize: const Size(double.infinity, 44),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Forgot passcode
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: _isLoading ? null : _handleForgotPasscode,
                          child: Text('Forgot passcode?', style: AppText.inter(13, w: FontWeight.w600, c: AppColors.blueInk)),
                        ),
                      ),
                    ),

                    // Error message
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
                            Expanded(child: Text(_errorMessage!, style: AppText.inter(12, w: FontWeight.w600, c: const Color(0xFFE23B4E)))),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 28),

                    // Sign in button
                    Container(
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [AppColors.blue1, AppColors.blue2], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(color: AppColors.blue1.withValues(alpha: 0.32), blurRadius: 18, offset: const Offset(0, 8))],
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
    ));
  }

  Widget _buildFieldLabel(String text) =>
      Text(text, style: AppText.mono(10, ls: 0.6, w: FontWeight.w600, c: AppColors.ink2));

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    required bool obscureText,
    bool isPassword = false,
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
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: AppColors.ink3, size: 18),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              )
            : null,
        border:        OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.lineStrong, width: 1.2)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.lineStrong, width: 1.2)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.blue1,      width: 1.2)),
      ),
    );
  }
}

// ==================================================================
// HELPER WIDGETS
// ==================================================================

class _DeviceBackground extends StatelessWidget {
  const _DeviceBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -40, right: -40,
          child: Container(
            width: 300, height: 300,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [AppColors.blue1.withValues(alpha: 0.15), Colors.transparent],
                stops: const [0.0, 0.7],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -60, left: -60,
          child: Container(
            width: 260, height: 260,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [AppColors.blue1.withValues(alpha: 0.10), Colors.transparent],
                stops: const [0.0, 0.7],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PatternVerifySheet extends StatefulWidget {
  const _PatternVerifySheet();

  @override
  State<_PatternVerifySheet> createState() => _PatternVerifySheetState();
}

class _PatternVerifySheetState extends State<_PatternVerifySheet> {
  bool _error    = false;
  bool _checking = false;

  Future<void> _onPattern(List<int> pattern) async {
    setState(() => _checking = true);
    final ok = await QuickUnlockService.verifyPattern(pattern);
    if (!mounted) return;
    if (ok) { Navigator.of(context).pop(true); return; }
    setState(() { _checking = false; _error = true; });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _error = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(left: 28, right: 28, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 28),
      decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.lineStrong, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Text(
            _error ? 'Wrong pattern, try again' : 'Draw your pattern',
            style: AppText.inter(14, w: FontWeight.w700, c: _error ? const Color(0xFFE23B4E) : AppColors.ink),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 220, height: 220,
            child: _checking
                ? const Center(child: ImapsLoadingIndicator(size: 50))
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
        icon: const Icon(Icons.pattern_rounded, size: 18),
        label: Text(label, style: AppText.inter(13, w: FontWeight.w600, c: AppColors.ink2)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 11),
          side: const BorderSide(color: AppColors.lineStrong, width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
