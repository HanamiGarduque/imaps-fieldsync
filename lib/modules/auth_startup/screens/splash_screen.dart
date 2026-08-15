import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../../../core/services/auth_service.dart';
import '../../profile_settings/services/notification_service.dart';
import '../services/biometric_service.dart';
import '../services/secure_prefs_service.dart';
import '../../../core/services/supabase_service.dart';
import '../services/local_data_guard_service.dart';
import '../../../core/widgets/imaps_loading_indicator.dart';
import '../../../core/widgets/sensitive_screen.dart';
import 'app_resume_lock_screen.dart';
import '../../../core/navigation/main_shell_screen.dart';


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
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;

    try {
      // ── STEP 1: Local token check (no network) ────────────────────────
      if (!AuthService.isLoggedIn) {
        await _goToLogin();
        return;
      }

      // ── STEP 2: Refresh expired token if needed ───────────────────────
      if (AuthService.isLocalSessionExpired) {
        final refreshed = await AuthService.tryRefreshSession();
        if (!refreshed) {
          // Only treat this as a real logout if the refresh actually failed
          // for a reason other than "no connectivity" — e.g. the refresh
          // token was genuinely revoked. Offline, the refresh token itself
          // may still be perfectly valid; we just can't reach the server
          // to redeem it right now. Wiping in that case would lock out an
          // inspector with an otherwise-valid session for no real reason.
          if (await AuthService.hasConnectivity()) {
            await AuthService.signOut();
            await _goToLogin();
            return;
          }
          debugPrint('[SPLASH] Refresh failed offline — proceeding with cached session/profile.');
        }

      }

      // ── STEP 3: Fetch profile (offline-aware) ──────────────────────────
      final profile = await AuthService.getCurrentProfileOfflineAware();
      if (profile == null || !mounted) {
        await _goToLogin();
        return;
      }

      // ── STEP 4: Cold-start biometric gate ──────────────────────────────
      // "Require on App Open" (Security Settings) previously only gated
      // resume-from-background (main_shell_screen.dart's lifecycle
      // observer) — a genuine cold start (app fully closed/killed, then
      // reopened) went straight through to Home with no biometric check
      // at all, since this splash/session-check flow never consulted the
      // setting. Same gate, same screen, reused here for the other entry
      // point the setting's own name promises to cover.
      final requireOnOpen = await SecurePrefsService.getBioRequireOnOpen();
      final bioEnrolled = await BiometricService.isEnrolled();
      final bioConfirmed = await BiometricService.isConfirmed();
      // Don't gate behind an unconfirmed biometric — that would lock out
      // someone who hasn't done their one confirmation login yet with no
      // way through (this screen has no password field). Fall through to
      // STEP 5 instead, same as if biometric weren't enrolled at all.
      if (requireOnOpen && bioEnrolled && bioConfirmed) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => AppResumeLockScreen(
                nextScreenBuilder: (_) => MainShellScreen(profile: profile),
              ),
            ),
          );
        }
        return;
      }

      // ── STEP 5: Direct to MainShellScreen ────────────────────────────
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
        pageBuilder: (_, anim, __) =>
            FadeTransition(opacity: anim, child: const LoginScreen()),
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
              
              const ImapsLoadingIndicator(size: 54),
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
  String? _errorMessage;

  bool _biometricEnrolled = false;
  bool _bioConfirmed = false;
  String _biometricLabel = 'Biometric';

  @override
  void initState() {
    super.initState();
    _loadSavedEmailAndBio();
  }

  Future<void> _loadSavedEmailAndBio() async {
    final savedEmail = await SecurePrefsService.getSavedEmail();
    final bioEnrolled = await BiometricService.isEnrolled();
    final bioConfirmed = await BiometricService.isConfirmed();
    final bioLabel = await BiometricService.primaryBiometricLabel();

    if (mounted) {
      setState(() {
        if (savedEmail != null && savedEmail.isNotEmpty) {
          _emailController.text = savedEmail;
        }
        _biometricEnrolled = bioEnrolled;
        _bioConfirmed = bioConfirmed;
        _biometricLabel = bioLabel;
      });
    }
  }


  Future<void> _handleBiometricLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final success = await BiometricService.authenticate(
        reason: 'Sign in to iMAPS FieldSync',
      );

      if (!success) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Biometric authentication canceled or failed.';
          });
        }
        return;
      }

      if (!AuthService.hasLiveUnderlyingSession) {
        // Genuinely nothing left underneath — the real session actually
        // died (server-side revocation, or a refresh that failed while
        // the app was closed long enough for even the refresh token to
        // expire). This is the one case that legitimately needs a wipe.
        final online = await AuthService.hasConnectivity();
        if (online) {
          await BiometricService.clearEnrollment();
          await SecurePrefsService.clearAll();
        }
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = online
                ? 'Session unrecoverable. Please sign in with password.'
                : 'No internet connection. Please reconnect and try again, '
                  'or sign in with your password.';
          });
        }
        return;
      }

      // The real session was never touched by logging out (see
      // AuthService.signOut) — this is just un-hiding it. No network call,
      // no token to redeem, nothing that can be "rejected."
      await AuthService.clearSoftLogout();

      if (AuthService.isLocalSessionExpired) {
        final refreshed = await AuthService.tryRefreshSession();
        if (!refreshed) {
          // Same distinction as the cold-start path: only wipe if this is a
          // genuine revocation, not just "couldn't reach the server right
          // now." A stolen/lost device losing biometric access the moment
          // it goes offline would actually be the *wrong* failure mode for
          // an offline-first field app — the wipe should be reserved for
          // when we can positively confirm the session is actually dead.
          if (await AuthService.hasConnectivity()) {
            await AuthService.signOut(revokeEverywhere: true);
            await BiometricService.clearEnrollment();
            await SecurePrefsService.clearAll();
            if (mounted) {
              setState(() {
                _isLoading = false;
                _errorMessage = 'Session unrecoverable. Please sign in with password.';
              });
            }
            return;
          }
          debugPrint('[BIOMETRIC] Refresh failed offline — proceeding with cached session/profile.');
        }
      }

      final profile = await AuthService.getCurrentProfileOfflineAware();
      if (!mounted) return;

      if (profile != null) {
        // Fire-and-forget: this is push-notification device registration,
        // unrelated to authentication itself. If it fails (most commonly
        // because we're offline — the exact scenario biometric login is
        // supposed to keep working in, per §14), it must NOT throw into
        // this function's outer catch and block navigation to Home with a
        // misleading "Biometric authentication error" message. It'll
        // naturally succeed next time this runs while online.
        NotificationService.registerCurrentDevice().catchError(
          (e) => debugPrint('[BIOMETRIC] registerCurrentDevice failed (non-fatal): $e'),
        );
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => MainShellScreen(profile: profile)),
        );
      } else {
        setState(() {
          _errorMessage = 'Login succeeded, but profile was not found.';
        });
      }
    } catch (e) {
      debugPrint('BIOMETRIC LOGIN ERROR: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Biometric authentication error. Please use passcode.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Navigator.pushReplacement() doesn't block until the transition
    // animation finishes — it returns almost immediately. That means the
    // old `finally` block's setState(() => _isLoading = false) was still
    // running on this screen, mid-transition, right after a *successful*
    // login — and at that exact moment AuthService.isLoggedIn had just
    // become true, so the biometric button's visibility condition
    // suddenly matched for one frame, flashing it into view on the
    // outgoing screen for an instant before it fully replaced. Skipping
    // the reset once we've actually started navigating avoids that
    // rebuild entirely — nothing needs `_isLoading` reset on a screen
    // that's being torn down anyway.
    var navigatedAway = false;

    try {
      await AuthService.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      // Fire-and-forget — see the same fix in _handleBiometricLogin for
      // why this must not be able to block a successful login.
      NotificationService.registerCurrentDevice().catchError(
        (e) => debugPrint('[LOGIN] registerCurrentDevice failed (non-fatal): $e'),
      );

      // Known Issue #4 fix — only meaningful right after a *fresh*
      // password login, since that's the only path that can introduce a
      // different inspector's session onto a device than whoever's data
      // is already cached locally (biometric/cold-start can only ever
      // resume the one session already live on the device).
      final authenticatedUserId = SupabaseService.client.auth.currentUser?.id;
      if (authenticatedUserId != null) {
        final result = await LocalDataGuardService.reconcileLocalDataOwnership(
          authenticatedUserId,
        );
        if (result == LocalDataReconcileResult.blockedPendingSync) {
          // Don't leave them logged in with another inspector's unsynced
          // work sitting on the device — sign back out for real (this
          // inspector never actually got to see anything yet) and explain.
          await AuthService.signOut(revokeEverywhere: true);
          if (mounted) {
            setState(() {
              _isLoading = false;
              _errorMessage = 'This device has unsynced work from another '
                  'inspector. Please have them log in and sync while '
                  'online before switching users, or contact the admin.';
            });
          }
          return;
        }
      }

      final profile = await AuthService.getCurrentProfileOfflineAware();

      if (!mounted) return;

      if (profile != null) {
        SupabaseService.logSecurityEvent(eventType: 'login_success', severity: 'info')
            .catchError((e) => debugPrint('[LOGIN] login_success log error: $e'));

        await SecurePrefsService.setSavedEmail(_emailController.text.trim());

        // New request: a freshly-enrolled biometric isn't trusted for
        // sign-in yet — this real credentials login is exactly the "one
        // confirmation" it's waiting for. Only writes if it was actually
        // pending, so this is a no-op on every ordinary login once biometric
        // is already confirmed (or was never enrolled).
        final bioEnrolledAtLogin = await BiometricService.isEnrolled();
        final bioConfirmedAtLogin = await BiometricService.isConfirmed();
        debugPrint('[AUTH][DIAG] _handleLogin: post-password-login check — '
            'enrolled=$bioEnrolledAtLogin, confirmed(before)=$bioConfirmedAtLogin');
        if (bioEnrolledAtLogin && !bioConfirmedAtLogin) {
          await SecurePrefsService.setBioConfirmed(true);
          debugPrint('[AUTH][DIAG] _handleLogin: set bioConfirmed=true.');
        }

        if (!mounted) return;
        navigatedAway = true;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => MainShellScreen(profile: profile)),
        );
      } else {
        setState(() {
          _errorMessage = 'Login succeeded, but no profile found. Contact Administrator.';
        });
      }

    } catch (e) {
      debugPrint('LOGIN ERROR: $e');
      if (mounted) {
        // AuthService.signIn() is a network call — a connectivity failure
        // throws here too, and was previously shown as "Invalid ID or
        // passcode," which sends someone with a correct password and no
        // signal down the wrong troubleshooting path entirely. Password
        // login fundamentally requires connectivity (the password is never
        // checked locally, only Supabase's server verifies it).
        //
        // Check real connectivity first (connectivity_plus is already a
        // project dependency) rather than only guessing from the
        // exception's message text, since that varies by platform and SDK
        // version. Fall back to the text-based guess only if connectivity
        // *looks* fine but the request still failed (e.g. connected to
        // Wi-Fi with no actual internet, or a Supabase outage).
        final connectivityResult = await Connectivity().checkConnectivity();
        final hasConnection = connectivityResult is List
            ? (connectivityResult as List).any((r) => r != ConnectivityResult.none)
            : connectivityResult != ConnectivityResult.none;
        final msg = e.toString().toLowerCase();
        final looksLikeNetworkError = msg.contains('socketexception') ||
            msg.contains('failed host lookup') ||
            msg.contains('network is unreachable') ||
            msg.contains('connection timed out') ||
            msg.contains('clientexception') ||
            msg.contains('timeoutexception');

        setState(() {
          _errorMessage = (!hasConnection || looksLikeNetworkError)
              ? 'No internet connection. Password sign-in needs connectivity — '
                'try biometric or pattern unlock if you\'ve set one up, or '
                'reconnect and try again.'
              : 'Invalid ID or passcode. Please try again.';
        });
      }
    } finally {
      if (mounted && !navigatedAway) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Forgot Passcode is admin-mediated, not self-service. Only the MPDO
  // admin (an operator of the separate MPDO system this app never talks
  // to — they have no account/session inside this app at all) can
  // actually change an inspector's passcode. This just opens the phone's
  // mail app addressed to them; the admin resets it on their end and
  // emails the new one back. There is deliberately no Supabase
  // resetPasswordForEmail() call here — that would let an inspector set
  // their own new password via an emailed magic link, which is exactly
  // the self-service flow this project doesn't want.
  Future<void> _handleForgotPasscode() async {
    await _contactAdministrator();
  }

  Future<void> _contactAdministrator() async {
    const adminEmail = 'admin@mpdo-rosario.gov.ph';
    final String subject = Uri.encodeComponent('Passcode Reset Request');
    final String body = Uri.encodeComponent('Please assist with resetting my passcode.');
    
    final Uri emailLaunchUri = Uri.parse('mailto:$adminEmail?subject=$subject&body=$body');

    try {
      final bool launched = await launchUrl(emailLaunchUri);
      if (!launched) throw Exception('No default mail client found.');
    } catch (e) {
      debugPrint('Could not launch email client: $e');
      await Clipboard.setData(const ClipboardData(text: adminEmail));
      
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

    return SensitiveScreen(child: Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
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
                
                const SizedBox(height: 32),
                
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

                      // Offer biometric whenever it's enrolled + confirmed
                      // AND the real underlying Supabase session is still
                      // alive on this device (AuthService.
                      // hasLiveUnderlyingSession) — regardless of whether
                      // it's currently "soft-logged-out" (AuthService.
                      // isLoggedIn false, see AuthService.signOut). A
                      // normal logout never actually destroys the session
                      // — Supabase's own signOut() would revoke the
                      // refresh token server-side no matter what scope is
                      // passed, so instead of trying to restore a killed
                      // token afterward, the session is just hidden and
                      // left alone. Tapping this button un-hides it
                      // (AuthService.clearSoftLogout()) — no network call,
                      // nothing that can be rejected.
                      //
                      // _bioConfirmed: newly-enrolled biometric isn't
                      // trusted for sign-in until one real password login
                      // has succeeded after enrolling — see
                      // BiometricService.isConfirmed().
                      if (_biometricEnrolled && _bioConfirmed &&
                          AuthService.hasLiveUnderlyingSession) ...[
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _isLoading ? null : _handleBiometricLogin,
                          icon: const Icon(Icons.fingerprint_rounded, size: 20),
                          label: Text(
                            'Sign in with $_biometricLabel',
                            style: AppText.inter(13, w: FontWeight.w600, c: AppColors.blue1),
                          ),
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

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
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
    ));
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
                icon: Icon(
                  obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: AppColors.ink3,
                  size: 18,
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
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