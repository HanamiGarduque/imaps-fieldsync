import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/services/auth_failure.dart';
import '../../profile_settings/services/notification_service.dart';
import '../services/biometric_service.dart';
import '../services/secure_prefs_service.dart';
import '../../../core/services/supabase_service.dart';
import '../services/local_data_guard_service.dart';
import '../../../core/widgets/imaps_loading_indicator.dart';
import '../../../core/widgets/sensitive_screen.dart';
import 'app_resume_lock_screen.dart';
import '../../../core/navigation/main_shell_screen.dart';
import '../../../core/theme/insight_theme.dart';
import '../../../core/layout/responsive_layout.dart';
import '../../../core/services/app_info_service.dart';
import '../../profile_settings/screens/terms_privacy_screen.dart';


/// ==================================================================
/// EXACT MATCH DESIGN TOKENS (Canonical Urbanist + Inter)
/// ==================================================================
class AppColors {
  static const bg = InsightTheme.bg;
  static const surface = InsightTheme.surface;
  
  static const ink = InsightTheme.ink;
  static const ink2 = InsightTheme.ink2;
  static const ink3 = InsightTheme.ink3;
  static const inkMuted = InsightTheme.inkMuted;
  
  static const blue1 = InsightTheme.blue1;
  static const blue2 = InsightTheme.blue2;
  static const blueInk = InsightTheme.blueInk;
  
  static const amber = InsightTheme.amber;
  
  static const line = InsightTheme.line;
  static const lineStrong = InsightTheme.lineStrong;
}

class AppText {
  static TextStyle poppins(double size, {FontWeight w = FontWeight.w700, Color? c, double? ls}) => 
      InsightTheme.urbanist(size < 12.0 ? 12.0 : size, w: w, c: c ?? AppColors.ink, ls: ls);
      
  static TextStyle inter(double size, {FontWeight w = FontWeight.w600, Color? c, double? ls, double? lh}) => 
      InsightTheme.inter(size < 12.0 ? 12.0 : size, w: w, c: c ?? AppColors.ink, ls: ls, h: lh);
      
  static TextStyle mono(double size, {FontWeight w = FontWeight.w500, Color? c, double? ls}) => 
      InsightTheme.mono(size < 12.0 ? 12.0 : size, w: w, c: c ?? AppColors.ink3, ls: ls);
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

      // Connectivity, refresh and profile share ONE eight-second network
      // recovery budget. Known offline owners use their authorized cache.
      final profile = await AuthService.getCurrentProfileOfflineAware(
        restoreSession: true,
      );
      if (profile == null || !mounted) {
        await _goToLogin(AuthFailure.profileUnavailable);
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
      final failure = AuthFailure.classify(e,
          fallback: AuthFailure.sessionRestoreFailed);
      debugPrint('[SPLASH] Session check: ${failure.name}');
      await _goToLogin(failure);
    }
  }


  Future<void> _goToLogin([AuthFailure? failure]) async {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 700),
        pageBuilder: (_, anim, _) =>
            FadeTransition(opacity: anim, child: LoginScreen(initialFailure: failure)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    final brand = SizedBox(width: double.infinity, child: Padding(
      key: const ValueKey('splash-brand'),
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(borderRadius: InsightTheme.roundedMd,
          child: Image.asset('assets/icon/app_icon.png', width: 80, height: 80,
            excludeFromSemantics: true, fit: BoxFit.contain)),
        const SizedBox(height: 24),
        Text('iMAPS', style: AppText.inter(16, c: Colors.white)),
        Semantics(label: 'FieldSync', header: true, excludeSemantics: true,
          child: Wrap(children: [
            Text('Field', style: AppText.poppins(44, w: FontWeight.w800, c: Colors.white)),
            Text('Sync', style: AppText.poppins(44, w: FontWeight.w800, c: Colors.white)),
          ])),
      ]),
    ));
    final status = Container(
      key: const ValueKey('splash-status'),
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: const BoxDecoration(color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const ImapsLoadingIndicator(size: 24),
          const SizedBox(width: 12),
          Expanded(child: Text('Initializing field unit…', style: AppText.inter(13, c: AppColors.blueInk))),
        ]),
        const SizedBox(height: 20),
        Text('Municipal Planning & Zoning Office', style: AppText.inter(12, c: AppColors.ink2)),
        const SizedBox(height: 6),
        Text(AppInfoService.fullVersionString, style: AppText.inter(12, c: AppColors.ink3)),
      ]),
    );
    return Scaffold(backgroundColor: AppColors.blue2,
      body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
        if (context.responsive.canSplitTwoPane) {
          return Row(children: [
            Expanded(child: Center(child: SingleChildScrollView(child: brand))),
            Expanded(child: Align(alignment: Alignment.bottomCenter, child: status)),
          ]);
        }
        return Column(children: [
          Expanded(child: Center(child: SingleChildScrollView(child: brand))),
          status,
        ]);
      })),
    );
  }
}

/// ------------------------------------------------------------------
/// REFINED LOGIN SCREEN
/// ------------------------------------------------------------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.initialFailure});

  /// Sanitized reason a previous stage could not complete, so a user sent back
  /// here is never left believing their passcode was rejected.
  final AuthFailure? initialFailure;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  String? _emailError;
  String? _passcodeError;

  bool _biometricEnrolled = false;
  bool _bioConfirmed = false;
  String _biometricLabel = 'Biometric';

  // ── Offline login state ────────────────────────────────────────────────────
  bool _isOnline = true;

  // ── Local passcode verifier constants ──────────────────────────────────────
  static const int _passcodeIterations = 10000;
  static const int _saltLength = 16;

  /// Generates a fresh random salt and derives a verifier from the given
  /// passcode. Returns (base64Salt, base64Hash). The raw passcode is never
  /// stored.
  static (String salt, String hash) _deriveVerifier(String passcode) {
    final salt = List<int>.generate(_saltLength, (_) => Random.secure().nextInt(256));
    final key = utf8.encode(passcode) + salt;
    var digest = Hmac(sha256, key).convert([0x00]).bytes;
    for (var i = 1; i < _passcodeIterations; i++) {
      digest = Hmac(sha256, key).convert(digest).bytes;
    }
    return (base64.encode(salt), base64.encode(digest));
  }

  /// Derives a verifier from the entered passcode + stored salt and compares
  /// it against the stored hash using constant-time comparison.
  static Future<bool> _verifyPasscode({
    required String passcode,
    required String storedSaltBase64,
    required String storedHashBase64,
  }) async {
    final salt = base64.decode(storedSaltBase64);
    final key = utf8.encode(passcode) + salt;
    var digest = Hmac(sha256, key).convert([0x00]).bytes;
    for (var i = 1; i < _passcodeIterations; i++) {
      digest = Hmac(sha256, key).convert(digest).bytes;
    }
    final derivedHash = base64.encode(digest);
    // Constant-time comparison
    if (derivedHash.length != storedHashBase64.length) return false;
    var result = 0;
    for (var i = 0; i < derivedHash.length; i++) {
      result |= derivedHash.codeUnitAt(i) ^ storedHashBase64.codeUnitAt(i);
    }
    return result == 0;
  }

  /// Cooldown thresholds: maps cumulative fail count → cooldown duration.
  static Duration _cooldownForAttempt(int failCount) {
    if (failCount >= 8) return const Duration(minutes: 5);
    if (failCount >= 5) return const Duration(minutes: 2);
    if (failCount >= 3) return const Duration(seconds: 30);
    return Duration.zero;
  }

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _cooldownTimer;
  int _cooldownSecondsRemaining = 0;

  @override
  void initState() {
    super.initState();
    _errorMessage = widget.initialFailure?.message;
    _loadSavedEmailAndBio();
    _startConnectivityListener();
  }

  void _startConnectivityListener() {
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (mounted && online != _isOnline) {
        setState(() => _isOnline = online);
      }
    });
  }

  void _startCooldownTimer(DateTime cooldownUntil) {
    _cooldownTimer?.cancel();
    final remaining = cooldownUntil.difference(DateTime.now()).inSeconds;
    if (remaining <= 0) {
      SecurePrefsService.clearLocalPasscodeCooldownUntil();
      if (mounted) {
        setState(() {
          _cooldownSecondsRemaining = 0;
          _errorMessage = null;
        });
      }
      return;
    }

    setState(() {
      _isLoading = false;
      _cooldownSecondsRemaining = remaining;
      _updateCooldownErrorMessage();
    });

    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final rem = cooldownUntil.difference(DateTime.now()).inSeconds;
      if (rem <= 0) {
        timer.cancel();
        _cooldownTimer = null;
        SecurePrefsService.clearLocalPasscodeCooldownUntil();
        if (mounted) {
          setState(() {
            _cooldownSecondsRemaining = 0;
            _errorMessage = null;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _cooldownSecondsRemaining = rem;
            _updateCooldownErrorMessage();
          });
        }
      }
    });
  }

  void _updateCooldownErrorMessage() {
    final m = _cooldownSecondsRemaining ~/ 60;
    final s = _cooldownSecondsRemaining % 60;
    _errorMessage = 'Too many failed attempts. '
        'Try again in ${m > 0 ? '$m min ' : ''}${s}s.';
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _connSub?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedEmailAndBio() async {
    final savedEmail = await SecurePrefsService.getSavedEmail();
    final bioEnrolled = await BiometricService.isEnrolled();
    final bioConfirmed = await BiometricService.isConfirmed();
    final bioLabel = await BiometricService.primaryBiometricLabel();
    final online = await AuthService.hasConnectivity();
    final cooldownUntil = await SecurePrefsService.getLocalPasscodeCooldownUntil();

    if (mounted) {
      setState(() {
        if (savedEmail != null && savedEmail.isNotEmpty) {
          _emailController.text = savedEmail;
        }
        _biometricEnrolled = bioEnrolled;
        _bioConfirmed = bioConfirmed;
        _biometricLabel = bioLabel;
        _isOnline = online;
      });

      if (cooldownUntil != null && cooldownUntil.isAfter(DateTime.now())) {
        _startCooldownTimer(cooldownUntil);
      }
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
        await AuthService.restoreSessionOfflineAware();
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
          (e) => debugPrint('[BIOMETRIC] registerCurrentDevice failed (non-fatal).'),
        );
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => MainShellScreen(profile: profile)),
        );
      } else {
        setState(() {
          _errorMessage = AuthFailure.profileUnavailable.message;
        });
      }
    } catch (e) {
      final failure = AuthFailure.classify(e,
          fallback: AuthFailure.sessionRestoreFailed);
      debugPrint('[BIOMETRIC] Login: ${failure.name}');
      if (mounted) {
        setState(() {
          _errorMessage = failure.message;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Validates email and passcode client-side for UX and input hygiene.
  /// Returns true if valid, false otherwise (updating inline error messages).
  bool _validateInputs() {
    final rawEmail = _emailController.text;
    final email = rawEmail.trim();
    final passcode = _passwordController.text;

    String? emailErr;
    String? passcodeErr;

    // Email validation
    if (email.isEmpty) {
      emailErr = 'Enter your email address.';
    } else if (rawEmail.length > 254 || email.length > 254) {
      emailErr = 'Email address is too long (maximum 254 characters).';
    } else if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(email)) {
      emailErr = 'Enter a valid email address.';
    }

    // Passcode validation (policy: required, reasonable max length)
    if (passcode.isEmpty) {
      passcodeErr = 'Enter your passcode.';
    } else if (passcode.length > 256) {
      passcodeErr = 'Passcode is too long (maximum 256 characters).';
    }

    setState(() {
      _emailError = emailErr;
      _passcodeError = passcodeErr;
    });

    return emailErr == null && passcodeErr == null;
  }

  Future<void> _handleLogin() async {
    // Clear top banner error
    setState(() {
      _errorMessage = null;
    });

    if (!_validateInputs()) {
      return;
    }

    setState(() {
      _isLoading = true;
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
      // ── Offline Email + Passcode Login ────────────────────────────────
      // When there's no connectivity, the passcode is verified against the
      // locally-stored salted HMAC-SHA256 verifier instead of reaching
      // Supabase. This is the only path that skips signInWithPassword().
      if (!await AuthService.hasConnectivity()) {
        navigatedAway = await _handleOfflineLogin();
        return;
      }

      await AuthService.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      // Fire-and-forget — see the same fix in _handleBiometricLogin for
      // why this must not be able to block a successful login.
      NotificationService.registerCurrentDevice().catchError(
        (e) => debugPrint('[LOGIN] registerCurrentDevice failed (non-fatal).'),
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
            .catchError((e) => debugPrint('[LOGIN] login_success log failed.'));

        await SecurePrefsService.setSavedEmail(_emailController.text.trim());
        await SecurePrefsService.setAcceptedLegalVersion(SecurePrefsService.currentLegalVersion);

        // Offline Email + Passcode Login — enrollment/refresh of the local
        // salted HMAC-SHA256 verifier. Runs on EVERY successful online
        // password login, so the stored verifier always reflects the current
        // real passcode. The raw passcode is never persisted — only a fresh
        // 16-byte salt and the derived hash.
        final (salt, hash) = _deriveVerifier(_passwordController.text);
        await SecurePrefsService.setLocalPasscodeSalt(salt);
        await SecurePrefsService.setLocalPasscodeHash(hash);

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
          _errorMessage = AuthFailure.profileUnavailable.message;
        });
      }

    } catch (e) {
      final failure = AuthFailure.classify(e,
          fallback: AuthFailure.unknownPostAuth);
      debugPrint('[LOGIN] ${failure.name}');
      if (mounted) {
        // Classified at the Auth/profile/session boundary (see AuthFailure), so
        // "Invalid ID or passcode" can only ever mean Supabase Auth rejected the
        // credentials. Every other stage keeps its own honest message.
        setState(() {
          _errorMessage = failure.message;
        });
      }
    } finally {
      if (mounted && !navigatedAway) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// ── Offline Email + Passcode Login ────────────────────────────────────
  /// Verifies the entered passcode against the locally-stored salted
  /// HMAC-SHA256 verifier when there is no connectivity. Modeled on the
  /// existing `_handleBiometricLogin()` session-restoration structure.
  ///
  /// Safety rules:
  /// - NEVER calls `signInWithPassword()` / `AuthService.signIn()`.
  /// - NEVER deletes the verifier, salt, or cached data.
  /// - NEVER force-signs-out the user.
  /// - NEVER creates a hard lockout.
  ///
  /// Returns true when the login succeeded and the screen was replaced by
  /// MainShellScreen (caller should treat it like a successful online login).
  Future<bool> _handleOfflineLogin() async {
    // ── 1. Cooldown gate ─────────────────────────────────────────────
    final cooldownUntil =
        await SecurePrefsService.getLocalPasscodeCooldownUntil();
    if (cooldownUntil != null) {
      final remaining = cooldownUntil.difference(DateTime.now());
      if (remaining > Duration.zero) {
        _startCooldownTimer(cooldownUntil);
        return false;
      }
      // Cooldown expired — clear it so the attempt proceeds.
      await SecurePrefsService.clearLocalPasscodeCooldownUntil();
    }

    // ── 2. Precondition: live underlying session ──────────────────────
    if (!AuthService.hasLiveUnderlyingSession) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'No internet connection. '
              'Offline sign-in requires a previous login on this device.';
        });
      }
      return false;
    }

    // ── 3. Precondition: local verifier must exist ────────────────────
    final storedSalt = await SecurePrefsService.getLocalPasscodeSalt();
    final storedHash = await SecurePrefsService.getLocalPasscodeHash();
    if (storedSalt == null || storedHash == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'No internet connection. '
              'Offline sign-in requires a previous login on this device.';
        });
      }
      return false;
    }

    // ── 4. Verify entered passcode against stored verifier ────────────
    final passcodeMatches = await _verifyPasscode(
      passcode: _passwordController.text,
      storedSaltBase64: storedSalt,
      storedHashBase64: storedHash,
    );

    if (!passcodeMatches) {
      // ── 4a. Failed attempt: persist count + cooldown ────────────────
      await SecurePrefsService.incrementLocalPasscodeFailCount();
      final failCount = await SecurePrefsService.getLocalPasscodeFailCount();
      final cooldown = _cooldownForAttempt(failCount);
      if (cooldown > Duration.zero) {
        final until = DateTime.now().add(cooldown);
        await SecurePrefsService.setLocalPasscodeCooldownUntil(until);
        _startCooldownTimer(until);
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Incorrect passcode. Please try again.';
          });
        }
      }
      return false;
    }

    // ── 5. Success: reset cooldown state ──────────────────────────────
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
    _cooldownSecondsRemaining = 0;
    await SecurePrefsService.clearLocalPasscodeFailCount();
    await SecurePrefsService.clearLocalPasscodeCooldownUntil();

    // ── 6. Clear soft-logout (same as biometric path) ────────────────
    await AuthService.clearSoftLogout();

    // ── 7. Handle expired local session (same as biometric) ──────────
    if (AuthService.isLocalSessionExpired) {
      await AuthService.restoreSessionOfflineAware();
    }

    // ── 8. Load cached/offline-aware profile ──────────────────────────
    final profile = await AuthService.getCurrentProfileOfflineAware();
    if (!mounted) return false;

    if (profile != null) {
      // Fire-and-forget device registration (non-fatal, may fail offline).
      NotificationService.registerCurrentDevice().catchError(
        (e) => debugPrint('[OFFLINE LOGIN] registerCurrentDevice failed (non-fatal).'),
      );
      await SecurePrefsService.setAcceptedLegalVersion(SecurePrefsService.currentLegalVersion);
      if (!mounted) return false;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MainShellScreen(profile: profile, offlineSession: true),
        ),
      );
      return true;
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = AuthFailure.profileUnavailable.message;
      });
      return false;
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

    return SensitiveScreen(
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.surface, InsightTheme.blueTint],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: CustomPaint(
            painter: const _LoginContourPainter(),
            child: SafeArea(
              child: ConstrainedContent(
                maxWidth: 480,
                // The whole composition scrolls above the keyboard/short windows.
                child: LayoutBuilder(builder: (context, constraints) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  physics: const BouncingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: max(0, constraints.maxHeight - 40)),
                    child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Image.asset('assets/icon/app_icon.png',
                                    width: 56, height: 56, excludeFromSemantics: true,
                                    fit: BoxFit.contain, filterQuality: FilterQuality.high),
                                ),
                                Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('iMAPS', style: AppText.inter(13, w: FontWeight.w600, c: AppColors.ink3)),
                                      Text('FieldSync', style: AppText.poppins(28, w: FontWeight.w800, c: AppColors.blue1)),
                                    ],
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(color: AppColors.surface,
                                borderRadius: BorderRadius.circular(24), boxShadow: InsightTheme.cardShadow),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Container(width: 6, height: 6, decoration: BoxDecoration(
                                  color: _isOnline ? InsightTheme.green : InsightTheme.red,
                                  shape: BoxShape.circle)),
                                const SizedBox(width: 8),
                                Text(_isOnline ? 'Online' : 'Offline', style: AppText.inter(12,
                                  w: FontWeight.w600, c: _isOnline ? InsightTheme.greenInk : InsightTheme.redInk)),
                              ]),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Semantics(header: true, child: Text('Sign in',
                            style: AppText.poppins(28, w: FontWeight.w800))),
                          const SizedBox(height: 4),
                          Text('Access your workspace', style: AppText.inter(14, c: AppColors.ink3)),
                        ]),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        key: const ValueKey('login-form-card'),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: AppColors.surface,
                          borderRadius: InsightTheme.roundedLg, boxShadow: InsightTheme.cardShadow),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          if (!_isOnline) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(color: InsightTheme.redTint,
                                borderRadius: InsightTheme.roundedSm),
                              child: Text('Offline. You can still sign in if you\'ve logged in before on this device.',
                                style: AppText.inter(12, w: FontWeight.w500, c: InsightTheme.redInk, lh: 1.35)),
                            ),
                            const SizedBox(height: 12),
                          ],
                          _buildFieldLabel('Email'),
                          const SizedBox(height: 6),
                          _buildTextField(
                            controller: _emailController,
                            hintText: 'Your inspector email',
                            icon: Icons.mail_outline_rounded,
                            obscureText: false,
                            keyboardType: TextInputType.emailAddress,
                            textCapitalization: TextCapitalization.none,
                            autocorrect: false,
                            maxLength: 254,
                            errorText: _emailError,
                            onChanged: (_) {
                              if (_emailError != null) setState(() => _emailError = null);
                            },
                          ),
                          const SizedBox(height: 12),
                          _buildFieldLabel('Passcode'),
                          const SizedBox(height: 6),
                          _buildTextField(
                            controller: _passwordController,
                            hintText: '••••••••',
                            icon: Icons.lock_outline,
                            obscureText: _obscurePassword,
                            isPassword: true,
                            keyboardType: TextInputType.visiblePassword,
                            textCapitalization: TextCapitalization.none,
                            autocorrect: false,
                            maxLength: 256,
                            errorText: _passcodeError,
                            onChanged: (_) {
                              if (_passcodeError != null) setState(() => _passcodeError = null);
                            },
                          ),
                          Align(alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _isLoading ? null : _handleForgotPasscode,
                              style: TextButton.styleFrom(minimumSize: const Size(48, 48),
                                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4)),
                              child: Text('Forgot passcode?', style: AppText.inter(13,
                                w: FontWeight.w600, c: AppColors.blueInk)),
                            ),
                          ),
                          if (_errorMessage != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(color: InsightTheme.redTint,
                                borderRadius: InsightTheme.roundedSm),
                              child: Row(children: [
                                const Icon(Icons.error_outline_rounded, color: InsightTheme.redInk, size: 18),
                                const SizedBox(width: 8),
                                Expanded(child: Text(_errorMessage!, style: AppText.inter(12,
                                  w: FontWeight.w600, c: InsightTheme.redInk))),
                              ]),
                            ),
                            const SizedBox(height: 12),
                          ],
                          ElevatedButton(
                            onPressed: (_isLoading || _cooldownSecondsRemaining > 0) ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.blue1, foregroundColor: Colors.white,
                              disabledBackgroundColor: InsightTheme.blueTint,
                              disabledForegroundColor: AppColors.blueInk,
                              elevation: 0, minimumSize: const Size(48, 48),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: InsightTheme.roundedSm)),
                            child: Wrap(alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, runSpacing: 4,
                              children: [
                                if (_isLoading) const SizedBox(width: 18, height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2,
                                    color: AppColors.blueInk)),
                                Text(_isLoading ? 'Signing in…' : _cooldownSecondsRemaining > 0
                                  ? 'Try again in ${_cooldownSecondsRemaining}s' : 'Sign in',
                                  textAlign: TextAlign.center, style: AppText.inter(16,
                                    w: FontWeight.w600, c: (_isLoading || _cooldownSecondsRemaining > 0)
                                      ? AppColors.blueInk : Colors.white)),
                              ]),
                          ),
                          // Eligibility and callback remain the existing device-auth policy.
                          if (_biometricEnrolled && _bioConfirmed && AuthService.hasLiveUnderlyingSession) ...[
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: _isLoading ? null : _handleBiometricLogin,
                              icon: const Icon(Icons.fingerprint_rounded, size: 22),
                              label: Text('Sign in with $_biometricLabel', textAlign: TextAlign.center,
                                style: AppText.inter(14, w: FontWeight.w600, c: AppColors.blueInk)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.blueInk,
                                backgroundColor: InsightTheme.blueTint,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                side: BorderSide(color: AppColors.blue1.withValues(alpha: 0.7)),
                                shape: RoundedRectangleBorder(borderRadius: InsightTheme.roundedSm),
                                minimumSize: const Size(48, 48)),
                            ),
                          ],
                          const SizedBox(height: 8),
                          _buildLegalNoticeRichText(isCentered: true),
                        ]),
                      ),
                    ],
                  ),
                  ),
                )),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegalNoticeRichText({bool isCentered = false}) {
    final linkStyle = AppText.inter(12, w: FontWeight.w600, c: AppColors.blue1)
        .copyWith(decoration: TextDecoration.underline, decorationColor: AppColors.blue1);
    // Inline text links keep the sentence together and retain native keyboard focus.
    // WidgetSpan applies the paragraph scaler to its child, including the label.
    final linkButtonStyle = TextButton.styleFrom(
      padding: EdgeInsets.zero,
      minimumSize: const Size(48, 24),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Column(
      crossAxisAlignment: isCentered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text.rich(
          key: const ValueKey('login-legal-sentence'),
          TextSpan(text: 'By signing in, you agree to the ', children: [
            WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic,
              child: Semantics(link: true,
              child: TextButton(style: linkButtonStyle,
                onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const TermsPrivacyScreen(initialShowTerms: true))),
                child: Text('Terms of Use', textScaler: TextScaler.noScaling, style: linkStyle)))),
            const TextSpan(text: ' and '),
            WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic,
              child: Semantics(link: true,
              child: TextButton(style: linkButtonStyle,
                onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const TermsPrivacyScreen(initialShowTerms: false))),
                child: Text('Privacy Policy', textScaler: TextScaler.noScaling, style: linkStyle)))),
            const TextSpan(text: '.'),
          ]),
          textAlign: isCentered ? TextAlign.center : TextAlign.start,
          style: AppText.inter(12, c: AppColors.ink3, lh: 1.3),
        ),
        const SizedBox(height: 2),
        Text('Authorized MPDO personnel only.',
          textAlign: isCentered ? TextAlign.center : TextAlign.start,
          style: AppText.inter(12, c: AppColors.ink3, lh: 1.2)),
      ],
    );
  }

  Widget _buildFieldLabel(String text) {
    return Text(text, style: AppText.inter(13, w: FontWeight.w600, c: AppColors.ink));
  }

  Widget _buildTextField({
    required TextEditingController controller, 
    required String hintText, 
    required IconData icon,
    required bool obscureText,
    bool isPassword = false,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    bool autocorrect = true,
    int? maxLength,
    String? errorText,
    ValueChanged<String>? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      obscuringCharacter: '•',
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      autocorrect: autocorrect,
      maxLength: maxLength,
      onChanged: onChanged,
      style: AppText.inter(14, w: FontWeight.w500, c: AppColors.ink),
      cursorColor: AppColors.blue1,
      decoration: InsightTheme.compactFormInput.copyWith(
        hintText: hintText,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        filled: true,
        fillColor: AppColors.surface,
        enabledBorder: OutlineInputBorder(borderRadius: InsightTheme.roundedSm,
          borderSide: BorderSide(color: AppColors.blue1.withValues(alpha: 0.3))),
        prefixIcon: Icon(icon, color: AppColors.ink3, size: 20),
        counterText: '',
        errorText: errorText,
        suffixIcon: isPassword
            ? IconButton(
                tooltip: obscureText ? 'Show passcode' : 'Hide passcode',
                icon: Icon(
                  obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: AppColors.ink3,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              )
            : null,
      ),
    );
  }
}

/// Static, screen-owned contour artwork; contains no location or map data.
class _LoginContourPainter extends CustomPainter {
  const _LoginContourPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width, size.height);
    final fill = Paint()..color = AppColors.blue1.withValues(alpha: 0.035);
    for (var layer = 0; layer < 4; layer++) {
      final y = 0.36 + layer * 0.07;
      canvas.drawPath(Path()..moveTo(0, y)
        ..cubicTo(0.2, y + 0.13, 0.3, y + 0.2, 0.5, y + 0.13)
        ..cubicTo(0.72, y + 0.04, 0.8, y + 0.05, 1, y - 0.08)
        ..lineTo(1, 1)..lineTo(0, 1)..close(), fill);
    }
    // Normalize stroke width separately to avoid stretching it on short screens.
    canvas.restore();
    final line = Paint()..color = AppColors.blue1.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke..strokeWidth = 0.8;
    for (var contour = 0; contour < 4; contour++) {
      final offset = contour * 0.045;
      canvas.drawPath(Path()..moveTo(size.width * 1.05, size.height * (0.14 + offset))
        ..cubicTo(size.width * 0.92, size.height * (0.35 + offset),
          size.width * 0.7, size.height * (0.2 + offset), size.width * 0.67, size.height * (0.4 + offset))
        ..cubicTo(size.width * 0.62, size.height * (0.57 + offset),
          size.width * 0.27, size.height * (0.5 + offset), -size.width * 0.05, size.height * (0.78 + offset)), line);
    }
  }

  @override
  bool shouldRepaint(_LoginContourPainter oldDelegate) => false;
}
