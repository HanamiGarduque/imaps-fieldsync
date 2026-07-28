import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/user_profile.dart';
import 'secure_prefs_service.dart';
import 'supabase_service.dart';
import 'biometric_service.dart';

class AuthService {
  static final SupabaseClient _client = SupabaseService.client; //[cite: 2]
  static bool _listenerAttached = false;

  /// Call once at app startup (see main.dart). Supabase's own SDK
  /// silently refreshes the session in the background on its own timer
  /// (`autoRefreshToken`, on by default — see Supabase.initialize() in
  /// supabase_service.dart, never overridden) completely independently of
  /// anything this app explicitly calls. Refresh tokens are single-use —
  /// every refresh, from ANY source, invalidates the previous one. Without
  /// this listener, the token saved for biometric restore
  /// (_persistBiometricSessionToken, called from signIn/
  /// tryRefreshSession/restoreSessionFromBiometric) only ever reflected
  /// refreshes *this app* triggered — the SDK's own internal auto-refresh
  /// could silently rotate the token in between, leaving a stale/
  /// already-used token behind that the server correctly rejects the next
  /// time biometric tries to use it. Subscribing here instead of only at
  /// the explicit call sites is what actually closes that gap.
  static void attachSessionListener() {
    if (_listenerAttached) return;
    _listenerAttached = true;
    _client.auth.onAuthStateChange.listen((data) {
      debugPrint('[AUTH][DIAG] onAuthStateChange event: ${data.event} at ${DateTime.now()}');
      if (data.event == AuthChangeEvent.tokenRefreshed ||
          data.event == AuthChangeEvent.signedIn) {
        _persistBiometricSessionToken();
      }
    });
  }

  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    final res = await _client.auth.signInWithPassword( //[cite: 2]
      email: email,
      password: password,
    );
    // If biometric is already enrolled on this device, capture the fresh
    // refresh token now so a later local-only sign-out still leaves
    // biometric able to restore this session. Harmless no-op if biometric
    // was never enrolled, or isn't confirmed yet — the Login screen still
    // won't offer the button until BiometricService.isConfirmed() is true,
    // this just makes sure the token is *ready* the moment it is.
    await _persistBiometricSessionToken();
    return res;
  }

  /// Signs out. By default this is LOCAL ONLY — it clears this device's
  /// live session (so [isLoggedIn] correctly goes false and the app shows
  /// Login) without revoking the refresh token server-side. That's
  /// deliberate: a confirmed biometric enrollment stores that same refresh
  /// token (see [_persistBiometricSessionToken]) specifically so the person
  /// can come straight back in with a fingerprint/face instead of retyping
  /// their password — a global sign-out would kill that token and defeat
  /// the entire point of biometric login. Pass [revokeEverywhere]: true for
  /// flows that should actually kill the session for real (e.g. password
  /// reset, explicit "sign out of all devices") — those already separately
  /// wipe biometric enrollment via SecurePrefsService.clearAll(), so there's
  /// nothing left for a global revoke to protect here anyway once combined
  /// with that wipe.
  static Future<void> signOut({bool revokeEverywhere = false}) async {
    await _client.auth.signOut( //[cite: 2]
      scope: revokeEverywhere ? SignOutScope.global : SignOutScope.local,
    );
  }

  /// Saves the current session's refresh token to secure storage, but only
  /// if biometric is enrolled on this device — otherwise there's nothing to
  /// protect it with, so don't stash a bare credential for no reason.
  /// Refresh tokens rotate on every use (setSession/refreshSession), so
  /// this must be called again after each successful restore/refresh, not
  /// just once at initial login.
  static Future<void> _persistBiometricSessionToken() async {
    try {
      final enrolled = await BiometricService.isEnrolled();
      if (!enrolled) {
        debugPrint('[AUTH][DIAG] _persistBiometricSessionToken: not enrolled, skipping save.');
        return;
      }
      final refreshToken = _client.auth.currentSession?.refreshToken;
      if (refreshToken == null) {
        debugPrint('[AUTH][DIAG] _persistBiometricSessionToken: enrolled=true but currentSession/refreshToken is null — nothing to save.');
        return;
      }
      await SecurePrefsService.setBioSessionToken(refreshToken);
      debugPrint('[AUTH][DIAG] _persistBiometricSessionToken: saved token ending in '
          '"${refreshToken.length > 6 ? refreshToken.substring(refreshToken.length - 6) : refreshToken}" at ${DateTime.now()}');
    } catch (e) {
      debugPrint('[AUTH] Could not persist biometric session token: $e');
    }
  }

  /// Restores a session after a local-only sign-out using the refresh
  /// token saved for biometric login. Requires connectivity — Supabase
  /// validates and rotates the token server-side, it's never trusted
  /// purely on-device. Returns true only on a genuine successful restore;
  /// re-persists the newly-rotated token on success so the next biometric
  /// attempt has a fresh, still-usable token.
  static Future<bool> restoreSessionFromBiometric() async {
    try {
      final storedToken = await SecurePrefsService.getBioSessionToken();
      if (storedToken == null) {
        debugPrint('[AUTH][DIAG] restoreSessionFromBiometric: no stored token found in secure storage — nothing was ever saved, or it was already cleared.');
        return false;
      }
      debugPrint('[AUTH][DIAG] restoreSessionFromBiometric: found stored token ending in '
          '"${storedToken.length > 6 ? storedToken.substring(storedToken.length - 6) : storedToken}", calling setSession()...');
      final res = await _client.auth.setSession(storedToken);
      if (res.session == null) {
        debugPrint('[AUTH][DIAG] restoreSessionFromBiometric: setSession() returned no error but res.session was null.');
        return false;
      }
      debugPrint('[AUTH][DIAG] restoreSessionFromBiometric: setSession() succeeded, session restored for user ${res.session!.user.email}.');
      await _persistBiometricSessionToken();
      return true;
    } catch (e) {
      debugPrint('[AUTH][DIAG] restoreSessionFromBiometric: setSession() THREW: $e (${e.runtimeType})');
      return false;
    }
  }

  static bool get isLoggedIn => _client.auth.currentUser != null; //[cite: 2]

  /// Local-only check (no network call) — true if there's no session at
  /// all, or its JWT expiry timestamp has already passed. Used to fail
  /// fast right after quick-unlock success, before spending a request on it.
  static bool get isLocalSessionExpired {
    final exp = _client.auth.currentSession?.expiresAt;
    if (exp == null) return true;
    return DateTime.fromMillisecondsSinceEpoch(exp * 1000).isBefore(DateTime.now());
  }

  /// Tries to refresh the current session using the stored refresh token.
  /// A session can look "expired" simply because the access token's 1hr
  /// lifetime passed while the app was closed — that's still recoverable
  /// as long as the refresh token itself hasn't been revoked. Returns
  /// true only on a genuine successful refresh.
  static Future<bool> tryRefreshSession() async {
    try {
      if (_client.auth.currentSession == null) return false;
      final res = await _client.auth.refreshSession();
      if (res.session == null) return false;
      await _persistBiometricSessionToken();
      return true;
    } catch (e) {
      debugPrint('[AUTH] Session refresh failed: $e');
      return false;
    }
  }

  // Debug-only: prints in _checkSession() to reveal exactly why stay-signed-in
  // does or doesn't work on a given device. Remove once confirmed working.
  static String get currentUserDebug => _client.auth.currentUser?.email ?? 'null';
  static String get sessionExpiryDebug {
    final exp = _client.auth.currentSession?.expiresAt;
    if (exp == null) return 'no session';
    final expiry = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    return '$expiry (${expiry.isBefore(DateTime.now()) ? "EXPIRED" : "valid"})';
  }

  // NOTE: unused as of the admin-mediated passcode reset decision — see
  // splash_screen.dart _handleForgotPasscode and
  // AUTH_SECURITY_MASTER_DOC.md §12. Only reset_password_screen.dart.bak
  // (retired, not compiled) still references these. Left in place rather
  // than deleted outright, consistent with how login_screen.dart.bak was
  // handled — safe to remove for real once confirmed nothing else needs
  // Supabase's self-service recovery flow.
  // ADDED: Triggers Supabase's built-in password reset workflow
  static Future<void> resetPassword({required String email}) async {
    await _client.auth.resetPasswordForEmail(email);
  }

  // Called from ResetPasswordScreen (now retired — see note on
  // resetPassword() above) after the inspector follows the emailed link.
  // Requires an active recovery session (set by the deep-link handler
  // calling supabase.auth.getSessionFromUrl/exchangeCodeForSession first).
  static Future<void> updatePassword({required String newPassword}) async {
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  static Future<UserProfile?> getCurrentProfile() async {
    final user = _client.auth.currentUser; //[cite: 2]
    if (user == null) return null; //[cite: 2]

    final data = await _client //[cite: 2]
        .from('profiles')
        .select()
        .eq('id', user.id)
        .single();

    return UserProfile.fromMap(data, email: user.email);
  }

  /// True if the device currently appears to have network connectivity.
  /// Same version-safe pattern already used elsewhere in this codebase
  /// (gps_verification_screen.dart, site_map_screen.dart) since
  /// connectivity_plus's checkConnectivity() return type changed between
  /// major versions (single ConnectivityResult pre-v5, List<> from v5+).
  static Future<bool> hasConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    return result is List
        ? (result as List).any((r) => r != ConnectivityResult.none)
        : result != ConnectivityResult.none;
  }

  /// True if [error] looks like a connectivity failure rather than a
  /// genuine server-side rejection (wrong credentials, revoked session,
  /// deactivated account, etc.). Text-matching is a fallback signal only —
  /// callers should check [hasConnectivity] first.
  static bool looksLikeConnectivityError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('socketexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('network is unreachable') ||
        msg.contains('connection timed out') ||
        msg.contains('clientexception') ||
        msg.contains('timeoutexception');
  }

  /// Like [getCurrentProfile], but falls back to the last-known-good
  /// locally-cached profile (SecurePrefsService) if the fresh fetch fails
  /// *specifically because there's no connectivity* — so a previously-
  /// authenticated inspector isn't bounced back to Login just because one
  /// network call couldn't reach the server while their session is still
  /// perfectly valid. Refreshes the cache on every successful fetch.
  ///
  /// Does NOT fall back on a genuine server-side rejection (e.g. the
  /// account row no longer exists) — that error is rethrown so the caller
  /// treats it as a real failure, not silently masked by a stale cache.
  static Future<UserProfile?> getCurrentProfileOfflineAware() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    try {
      final profile = await getCurrentProfile();
      if (profile != null) {
        await SecurePrefsService.setCachedProfile(profile);
      }
      return profile;
    } catch (e) {
      final offline = !(await hasConnectivity()) || looksLikeConnectivityError(e);
      if (!offline) rethrow;

      debugPrint('[AUTH] Profile fetch failed offline, trying cache: $e');
      final cached = await SecurePrefsService.getCachedProfile();
      if (cached != null && cached.id == user.id) return cached;
      rethrow; // no usable cache for this specific user — surface the real error
    }
  }
}