import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';

void main() {
  test('Check field_jobs and zoning applications columns', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;

    // Complete mock for shared_preferences MethodChannel
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/shared_preferences'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'getAll') {
            return <String, Object>{};
          }
          if (methodCall.method.startsWith('set') ||
              methodCall.method == 'remove' ||
              methodCall.method == 'clear') {
            return true;
          }
          return null;
        },
      );

    dotenv.testLoad(fileInput: File('.env').readAsStringSync());
    
    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL']!,
      publishableKey: dotenv.env['SUPABASE_PUBLISHABLE_KEY']!,
    );
    
    final client = Supabase.instance.client;
    
    // Try signing up or signing in
    bool loggedIn = false;
    
    try {
      debugPrint('Trying to sign up admin...');
      final signUpRes = await client.auth.signUp(
        email: 'admin@test.com',
        password: 'AdminPassword2026!',
      );
      debugPrint('Admin sign up result: ${signUpRes.user?.email}');
      if (signUpRes.session != null) {
        debugPrint('Admin sign up auto-login succeeded! Session is active.');
        loggedIn = true;
      } else {
        debugPrint('Admin sign up succeeded but no session (email confirmation might be required).');
      }
    } catch (e) {
      debugPrint('Admin sign up failed/skipped: $e');
    }
    
    if (!loggedIn) {
      try {
        debugPrint('Trying to sign in as admin...');
        await client.auth.signInWithPassword(
          email: 'admin@test.com',
          password: 'AdminPassword2026!',
        );
        debugPrint('Admin sign in succeeded!');
        loggedIn = true;
      } catch (e) {
        debugPrint('Admin sign in failed: $e');
      }
    }
    
    if (!loggedIn) {
      try {
        debugPrint('Trying to sign up inspector...');
        final signUpRes = await client.auth.signUp(
          email: 'inspector@test.com',
          password: 'Password123!',
        );
        debugPrint('Inspector sign up result: ${signUpRes.user?.email}');
        if (signUpRes.session != null) {
          debugPrint('Inspector sign up auto-login succeeded! Session is active.');
          loggedIn = true;
        } else {
          debugPrint('Inspector sign up succeeded but no session.');
        }
      } catch (e) {
        debugPrint('Inspector sign up failed/skipped: $e');
      }
    }

    if (!loggedIn) {
      try {
        debugPrint('Trying to sign in as inspector...');
        await client.auth.signInWithPassword(
          email: 'inspector@test.com',
          password: 'Password123!',
        );
        debugPrint('Inspector sign in succeeded!');
        loggedIn = true;
      } catch (e) {
        debugPrint('Inspector sign in failed: $e');
      }
    }
    
    // If both failed, check if we can query anyway (in case RLS is disabled)
    debugPrint('Current session: ${client.auth.currentSession}');
    debugPrint('Current user: ${client.auth.currentUser}');
    
    debugPrint('--- profiles Sample ---');
    try {
      final profiles = await client.from('profiles').select().limit(1);
      debugPrint('Profiles success: $profiles');
    } catch (e) {
      debugPrint('Error profiles: $e');
    }
    
    debugPrint('--- field_jobs Sample ---');
    try {
      final fieldJobs = await client.from('field_jobs').select().limit(1);
      debugPrint('Field jobs success: $fieldJobs');
    } catch (e) {
      debugPrint('Error field_jobs: $e');
    }

    debugPrint('--- supabase_zoning_applications Sample ---');
    try {
      final apps = await client.from('supabase_zoning_applications').select().limit(1);
      debugPrint('Apps success: $apps');
    } catch (e) {
      debugPrint('Error apps: $e');
    }
  });
}
