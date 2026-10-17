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
import '../../../core/services/app_bootstrap.dart';
import '../../profile_settings/services/notification_service.dart';
import '../services/biometric_service.dart';
import '../services/secure_prefs_service.dart';
import '../../../core/services/supabase_service.dart';
import '../services/local_data_guard_service.dart';
import '../../../core/widgets/imaps_loading_indicator.dart';
import '../../../core/widgets/fieldsync_brand.dart';
import '../../../core/widgets/fieldsync_entrance_animation.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/sensitive_screen.dart';
import 'app_resume_lock_screen.dart';
import '../../../core/navigation/main_shell_screen.dart';
import '../../../core/theme/insight_theme.dart';
import '../../../core/layout/responsive_layout.dart';
import '../../../core/services/app_info_service.dart';
import '../../profile_settings/screens/terms_privacy_screen.dart';


/// ==================================================================
/// SCREEN 1 — SPLASH
/// ==================================================================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  // The approved splash entrance is the screen's own identity moment;
  // navigation waits for it so the journey is never cut off mid-flight.
  // Reduced motion completes it immediately, restoring the old timing.
  final Completer<void> _entranceDone = Completer<void>();

  /// Releases the bootstrap gate below if bootstrap is still running when the
  /// app's eight-second startup recovery budget expires. Cancelled as soon as
  /// the gate resolves (or on dispose): no timer may outlive the wait — the
  /// layout tests assert no pending timers after teardown.
  Timer? _bootstrapRecoveryTimer;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  void _onEntranceCompleted() {
    if (!_entranceDone.isCompleted) _entranceDone.complete();
  }

  @override
  void dispose() {
    // Never strand a pending navigation when the screen is torn down
    // (route replacement and tests both do this).
    if (!_entranceDone.isCompleted) _entranceDone.complete();
    _bootstrapRecoveryTimer?.cancel();
    super.dispose();
  }

  /// Upper bound for the bootstrap gate below: the app's established
  /// eight-second startup recovery budget. If bootstrap is still running
  /// when it expires, the gate releases and the session check routes on with
  /// an honest classified failure instead of holding the splash forever.
  /// The bound only releases the gate — initialization itself is never
  /// cancelled and keeps running in the background.
  static const Duration _bootstrapGateBudget = Duration(seconds: 8);

  Future<void> _checkSession() async {
    // Startup gate: no session decision before the moved service bootstrap
    // has settled, while keeping the existing three-second minimum — both
    // run in parallel and are bounded by _bootstrapGateBudget.
    final budgetExpired = Completer<void>();
    _bootstrapRecoveryTimer =
        Timer(_bootstrapGateBudget, budgetExpired.complete);
    await Future.any<void>(<Future<void>>[
      Future.wait<void>(<Future<void>>[
        AppBootstrap.ready,
        Future<void>.delayed(const Duration(seconds: 3)),
      ]),
      budgetExpired.future,
    ]);
    _bootstrapRecoveryTimer?.cancel();
    _bootstrapRecoveryTimer = null;
    if (!mounted) return;

    final bootstrapError = AppBootstrap.error;
    if (bootstrapError != null) {
      final failure = AuthFailure.classify(bootstrapError,
          fallback: AuthFailure.sessionRestoreFailed);
      debugPrint('[SPLASH] Bootstrap did not complete: ${failure.name}');
      await _goToLogin(failure);
      return;
    }
    if (AppBootstrap.started && !AppBootstrap.settled) {
      // A bootstrap step outlived the recovery budget. Route on honestly;
      // the chain keeps running and the app recovers once services are up.
      debugPrint('[SPLASH] Bootstrap still running after '
          '${_bootstrapGateBudget.inSeconds}s; continuing to login.');
      await _goToLogin(AuthFailure.sessionRestoreFailed);
      return;
    }

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

      // The entrance plays while the checks above run; hold only the
      // hand-off until it has settled, so the completed logo is what
      // leaves the splash. Reduced motion releases this immediately.
      await _entranceDone.future;
      if (!mounted) return;

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
    await _entranceDone.future;
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
        // Approved entrance: the inspector's route journey, settled on the
        // official artwork at video scale (video ≈ 72% of screen width).
        FieldSyncEntranceAnimation(
          width: min(MediaQuery.sizeOf(context).width * 0.72, 360.0),
          onCompleted: _onEntranceCompleted,
        ),
        const SizedBox(height: 24),
        Text('iMAPS', style: InsightTheme.inter(16, w: FontWeight.w600, c: Colors.white)),
        Semantics(label: 'FieldSync', header: true, excludeSemantics: true,
          child: Wrap(children: [
            Text('Field', style: InsightTheme.urbanist(44, w: FontWeight.w800, c: Colors.white)),
            Text('Sync', style: InsightTheme.urbanist(44, w: FontWeight.w800, c: Colors.white)),
          ])),
      ]),
    ));
    final status = Container(
      key: const ValueKey('splash-status'),
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: const BoxDecoration(color: InsightTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const ImapsLoadingIndicator(size: 24),
          const SizedBox(width: 12),
          Expanded(child: Text('Initializing field unit…', style: InsightTheme.inter(13, w: FontWeight.w600, c: InsightTheme.blueInk))),
        ]),
        const SizedBox(height: 20),
        Text('Municipal Planning & Zoning Office', style: InsightTheme.inter(12, w: FontWeight.w600, c: InsightTheme.ink2)),
        const SizedBox(height: 6),
        Text(AppInfoService.fullVersionString, style: InsightTheme.inter(12, w: FontWeight.w600, c: InsightTheme.ink3)),
      ]),
    );
    return Scaffold(backgroundColor: InsightTheme.blue2,
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
        AppFeedback.show(
          context,
          message: 'Admin email copied to clipboard!',
          icon: Icons.content_copy_rounded,
        );
      }
    }
  }

  /// Pinned identity: app mark, wordmark and connectivity.
  ///
  /// It sits OUTSIDE the scroll view, so it is not part of the scrollable
  /// column and nothing can push it: opening the keyboard, tapping between the
  /// two fields, or the auto-scroll that focus triggers all move the form
  /// underneath it while the brand stays exactly where it is.
  Widget _brandBlock() => Padding(
    padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            const FieldSyncBrand(height: 56),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('iMAPS', style: InsightTheme.inter(13, w: FontWeight.w600, c: InsightTheme.ink3)),
                Text('FieldSync', style: InsightTheme.urbanist(28, w: FontWeight.w800, c: InsightTheme.blue1)),
              ],
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: InsightTheme.surface,
            borderRadius: BorderRadius.circular(24), boxShadow: InsightTheme.cardShadow),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(
              color: _isOnline ? InsightTheme.green : InsightTheme.red,
              shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(_isOnline ? 'Online' : 'Offline', style: InsightTheme.inter(12,
              w: FontWeight.w600, c: _isOnline ? InsightTheme.greenInk : InsightTheme.redInk)),
          ]),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    return SensitiveScreen(
      child: Scaffold(
        backgroundColor: InsightTheme.bg,
        body: SafeArea(
          child: ConstrainedContent(
            maxWidth: 480,
            child: Column(
              children: [
                _brandBlock(),
                Expanded(
                  // Only the heading and the form scroll. At rest the pair stays
                  // bottom-anchored so the primary action lands in the thumb
                  // zone; once the keyboard claims the lower half this column is
                  // simply taller than its viewport and reads from the top.
                  child: LayoutBuilder(builder: (context, constraints) => SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                    physics: const BouncingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: max(0, constraints.maxHeight - 24)),
                      child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Semantics(header: true, child: Text('Sign in',
                              style: InsightTheme.urbanist(28, w: FontWeight.w800))),
                            const SizedBox(height: 4),
                            Text('Access your workspace', style: InsightTheme.inter(14, w: FontWeight.w500, c: InsightTheme.ink3)),
                          ]),
                        ),
                        const SizedBox(height: 16),
                        Container(
                        key: const ValueKey('login-form-card'),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: InsightTheme.surface,
                          borderRadius: InsightTheme.roundedLg,
                          boxShadow: InsightTheme.cardShadow),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          if (!_isOnline) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(color: InsightTheme.redTint,
                                borderRadius: InsightTheme.roundedSm),
                              child: Text('Offline. You can still sign in if you\'ve logged in before on this device.',
                                style: InsightTheme.inter(12, w: FontWeight.w500, c: InsightTheme.redInk, h: 1.35)),
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
                              if (_emailError != null) { setState(() => _emailError = null); }
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
                              if (_passcodeError != null) { setState(() => _passcodeError = null); }
                            },
                          ),
                          Align(alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _isLoading ? null : _handleForgotPasscode,
                              style: TextButton.styleFrom(minimumSize: const Size(48, 48),
                                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4)),
                              child: Text('Forgot passcode?', style: InsightTheme.inter(13,
                                w: FontWeight.w600, c: InsightTheme.blueInk)),
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
                                Expanded(child: Text(_errorMessage!, style: InsightTheme.inter(12,
                                  w: FontWeight.w600, c: InsightTheme.redInk))),
                              ]),
                            ),
                            const SizedBox(height: 12),
                          ],
                          ElevatedButton(
                            onPressed: (_isLoading || _cooldownSecondsRemaining > 0) ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: InsightTheme.blue1, foregroundColor: Colors.white,
                              disabledBackgroundColor: InsightTheme.blueTint,
                              disabledForegroundColor: InsightTheme.blueInk,
                              elevation: 0, minimumSize: const Size(48, 48),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: InsightTheme.roundedSm)),
                            child: Wrap(alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, runSpacing: 4,
                              children: [
                                if (_isLoading) const SizedBox(width: 18, height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2,
                                    color: InsightTheme.blueInk)),
                                Text(_isLoading ? 'Signing in…' : _cooldownSecondsRemaining > 0
                                  ? 'Try again in ${_cooldownSecondsRemaining}s' : 'Sign in',
                                  textAlign: TextAlign.center, style: InsightTheme.inter(16,
                                    w: FontWeight.w600, c: (_isLoading || _cooldownSecondsRemaining > 0)
                                      ? InsightTheme.blueInk : Colors.white)),
                              ]),
                          ),
                          // Eligibility and callback remain the existing device-auth policy.
                          if (_biometricEnrolled && _bioConfirmed && AuthService.hasLiveUnderlyingSession) ...[
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: _isLoading ? null : _handleBiometricLogin,
                              icon: const Icon(Icons.fingerprint_rounded, size: 22),
                              label: Text('Sign in with $_biometricLabel', textAlign: TextAlign.center,
                                style: InsightTheme.inter(14, w: FontWeight.w600, c: InsightTheme.blueInk)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: InsightTheme.blueInk,
                                backgroundColor: InsightTheme.blueTint,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                side: BorderSide(color: InsightTheme.blue1.withValues(alpha: 0.7)),
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
            ],
          ),
        ),
      ),
    ),
  );
  }

  Widget _buildLegalNoticeRichText({bool isCentered = false}) {
    final linkStyle = InsightTheme.inter(12, w: FontWeight.w600, c: InsightTheme.blue1)
        .copyWith(decoration: TextDecoration.underline, decorationColor: InsightTheme.blue1);
    // Inline text links keep the sentence together and retain native keyboard
    // focus.
    //
    // Both `textScaler: TextScaler.noScaling` calls below and the 24px box are
    // load-bearing and were verified against login_concept_d_layout_test.dart
    // ("Legal inline links honor text scaling exactly once"). Raising the box to
    // the 48px accessibility floor makes it the line height and drove the legal
    // paragraph from 34px to 136px at 200% scale. Do not change either without
    // running that test.
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
          style: InsightTheme.inter(12, w: FontWeight.w600, c: InsightTheme.ink3, h: 1.3),
        ),
        const SizedBox(height: 2),
        Text('Authorized MPDO personnel only.',
          textAlign: isCentered ? TextAlign.center : TextAlign.start,
          style: InsightTheme.inter(12, w: FontWeight.w600, c: InsightTheme.ink3, h: 1.2)),
      ],
    );
  }

  Widget _buildFieldLabel(String text) {
    return Text(text, style: InsightTheme.inter(13, w: FontWeight.w600, c: InsightTheme.ink));
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
      // 16px / w400 and the shared grey border are what every other input in the
      // app already uses; login was the only screen still on 14px w500 with a
      // blue-tinted field border.
      style: InsightTheme.inter(16, c: InsightTheme.ink),
      cursorColor: InsightTheme.blue1,
      decoration: InsightTheme.compactFormInput.copyWith(
        hintText: hintText,
        prefixIcon: Icon(icon, color: InsightTheme.ink3, size: 20),
        counterText: '',
        errorText: errorText,
        suffixIcon: isPassword
            ? IconButton(
                tooltip: obscureText ? 'Show passcode' : 'Hide passcode',
                icon: Icon(
                  obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: InsightTheme.ink3,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              )
            : null,
      ),
    );
  }
}
