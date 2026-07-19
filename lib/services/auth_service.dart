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