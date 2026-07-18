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

  // ADDED: Triggers Supabase's built-in password reset workflow
  static Future<void> resetPassword({required String email}) async {
    await _client.auth.resetPasswordForEmail(email);
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