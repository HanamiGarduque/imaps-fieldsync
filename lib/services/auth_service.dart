import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile.dart';
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
  /// fast right after biometric success, before spending a request on it.
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

    return UserProfile.fromMap(data); //[cite: 2]
  }
}