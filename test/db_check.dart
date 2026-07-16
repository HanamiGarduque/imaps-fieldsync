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
    const MethodChannel('plugins.flutter.io/shared_preferences')
        .setMockMethodCallHandler((MethodCall methodCall) async {
      if (methodCall.method == 'getAll') {
        return <String, Object>{};
      }
      if (methodCall.method.startsWith('set') || 
          methodCall.method == 'remove' || 
          methodCall.method == 'clear') {
        return true;
      }
      return null;
    });

    dotenv.testLoad(fileInput: File('.env').readAsStringSync());
    
    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL']!,
      publishableKey: dotenv.env['SUPABASE_PUBLISHABLE_KEY']!,
    );
    
    final client = Supabase.instance.client;
    
    // Try signing up or signing in
    bool loggedIn = false;
    
    try {
      print('Trying to sign up admin...');
      final signUpRes = await client.auth.signUp(
        email: 'admin@test.com',
        password: 'AdminPassword2026!',
      );
      print('Admin sign up result: ${signUpRes.user?.email}');
      if (signUpRes.session != null) {
        print('Admin sign up auto-login succeeded! Session is active.');
        loggedIn = true;
      } else {
        print('Admin sign up succeeded but no session (email confirmation might be required).');
      }
    } catch (e) {
      print('Admin sign up failed/skipped: $e');
    }
    
    if (!loggedIn) {
      try {
        print('Trying to sign in as admin...');
        final res = await client.auth.signInWithPassword(
          email: 'admin@test.com',
          password: 'AdminPassword2026!',
        );
        print('Admin sign in succeeded!');
        loggedIn = true;
      } catch (e) {
        print('Admin sign in failed: $e');
      }
    }
    
    if (!loggedIn) {
      try {
        print('Trying to sign up inspector...');
        final signUpRes = await client.auth.signUp(
          email: 'inspector@test.com',
          password: 'Password123!',
        );
        print('Inspector sign up result: ${signUpRes.user?.email}');
        if (signUpRes.session != null) {
          print('Inspector sign up auto-login succeeded! Session is active.');
          loggedIn = true;
        } else {
          print('Inspector sign up succeeded but no session.');
        }
      } catch (e) {
        print('Inspector sign up failed/skipped: $e');
      }
    }

    if (!loggedIn) {
      try {
        print('Trying to sign in as inspector...');
        await client.auth.signInWithPassword(
          email: 'inspector@test.com',
          password: 'Password123!',
        );
        print('Inspector sign in succeeded!');
        loggedIn = true;
      } catch (e) {
        print('Inspector sign in failed: $e');
      }
    }
    
    // If both failed, check if we can query anyway (in case RLS is disabled)
    print('Current session: ${client.auth.currentSession}');
    print('Current user: ${client.auth.currentUser}');
    
    print('--- profiles Sample ---');
    try {
      final profiles = await client.from('profiles').select().limit(1);
      print('Profiles success: $profiles');
    } catch (e) {
      print('Error profiles: $e');
    }
    
    print('--- field_jobs Sample ---');
    try {
      final fieldJobs = await client.from('field_jobs').select().limit(1);
      print('Field jobs success: $fieldJobs');
    } catch (e) {
      print('Error field_jobs: $e');
    }

    print('--- supabase_zoning_applications Sample ---');
    try {
      final apps = await client.from('supabase_zoning_applications').select().limit(1);
      print('Apps success: $apps');
    } catch (e) {
      print('Error apps: $e');
    }
  });
}
