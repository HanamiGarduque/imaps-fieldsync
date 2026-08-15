import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/user_profile.dart';
import '../../modules/auth_startup/services/secure_prefs_service.dart';
import 'supabase_service.dart';
import '../../modules/auth_startup/services/biometric_service.dart';

class AuthService {
  static final SupabaseClient _client = SupabaseService.client; //[cite: 2]

  // In-memory cache of the soft-logout flag (see signOut() below). Kept as
  // a plain static bool, not read from storage on every access, because
  // isLoggedIn is a synchronous getter called directly from build()
  // methods throughout the UI — it can't become async without rippling
  // through a lot of screens. loadSoftLogoutState() populates this once at
  // startup, before anything else needs it.
  static bool _softLoggedOut = false;

  /// Call once at app startup (see main.dart), before runApp(). Loads the
  /// persisted soft-logout flag so isLoggedIn is already correct for
  /// Splash's very first _checkSession() call on a cold start.
  static Future<void> loadSoftLogoutState() async {
    _softLoggedOut = await SecurePrefsService.isSoftLoggedOut();
  }

  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    final res = await _client.auth.signInWithPassword( //[cite: 2]
      email: email,
      password: password,
    );
    // Any real password login — including the one-time biometric
    // confirmation login — means the session should read as logged in.
    await _setSoftLoggedOut(false);
    return res;
  }

  /// "Logs out." If biometric is enrolled AND confirmed, this deliberately
  /// does NOT call Supabase's real signOut() at all — it only flags the
  /// session as hidden on this device (see [_setSoftLoggedOut]).
  ///
  /// Why: Supabase's signOut() revokes the CURRENT session's refresh token
  /// server-side no matter what scope is passed — 'local' vs 'global' only
  /// changes whether OTHER sessions/devices are also revoked, not whether
  /// this one survives. Confirmed directly from a device log: a 'local'
  /// sign-out followed by a biometric attempt failed with the server's own
  /// "Invalid Refresh Token: Refresh Token Not Found" — the token was
  /// genuinely gone, not just stale from a timing race. There is no
  /// signOut() scope that means "sign out but leave this session usable" —
  /// that would defeat the actual meaning of signing out. So the only way
  /// to let biometric bring someone back in without a network round-trip
  /// (and without ever risking a rejected/rotated token) is to never
  /// destroy the real session in the first place, and just hide it.
  ///
  /// Pass [revokeEverywhere]: true for flows that should actually kill the
  /// session for real — password reset, explicit "sign out of all
  /// devices," or a detected genuine revocation. Also falls through to a
  /// real (local-scope) sign-out automatically if biometric isn't
  /// enrolled+confirmed, since there's nothing to preserve access through
  /// in that case anyway.
  static Future<void> signOut({bool revokeEverywhere = false}) async {
    if (!revokeEverywhere &&
        await BiometricService.isEnrolled() &&
        await BiometricService.isConfirmed()) {
      await _setSoftLoggedOut(true);
      return;
    }
    await _client.auth.signOut( //[cite: 2]
      scope: revokeEverywhere ? SignOutScope.global : SignOutScope.local,
    );
    await _setSoftLoggedOut(false); // nothing left to hide, the real session is gone
  }

  static Future<void> _setSoftLoggedOut(bool v) async {
    _softLoggedOut = v;
    await SecurePrefsService.setSoftLoggedOut(v);
  }

  /// True if the underlying Supabase session is genuinely alive on this
  /// device, regardless of the soft-logout flag. A soft logout never
  /// touches this — that's the entire point. This is what the Login
  /// screen's biometric button actually checks for, and what
  /// [clearSoftLogout] un-hides.
  static bool get hasLiveUnderlyingSession => _client.auth.currentUser != null; //[cite: 2]

  /// What the UI should treat as "is someone logged in." False while
  /// soft-logged-out, even though the real session may still be alive
  /// underneath — that's what makes Login correctly reappear after a
  /// normal logout.
  static bool get isLoggedIn => hasLiveUnderlyingSession && !_softLoggedOut; //[cite: 2]

  /// Called after a successful biometric scan when there's a live
  /// underlying session to un-hide. No network call, no token exchange —
  /// nothing was ever revoked, so there's nothing to restore.
  static Future<void> clearSoftLogout() => _setSoftLoggedOut(false);

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
      return res.session != null;
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