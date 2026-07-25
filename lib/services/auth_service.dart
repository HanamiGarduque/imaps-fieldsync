import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/user_profile.dart';
import 'secure_prefs_service.dart';
import 'supabase_service.dart';

class AuthService {
  static final SupabaseClient _client = SupabaseService.client; //[cite: 2]

  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await _client.auth.signInWithPassword( //[cite: 2]
      email: email,
      password: password,
    );
  }

  static Future<void> signOut() async {
    await _client.auth.signOut(); //[cite: 2]
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

  // ADDED: Triggers Supabase's built-in password reset workflow
  static Future<void> resetPassword({required String email}) async {
    await _client.auth.resetPasswordForEmail(email);
  }

  // Called from ResetPasswordScreen after the inspector follows the emailed
  // link. Requires an active recovery session (set by the deep-link handler
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