import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'dart:math';

// Complete mock for shared_preferences MethodChannel
class SharedPrefsMock {
  static void register() {
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
  }
}

void main() {
  test('Insert test job to field_jobs to trigger webhook and push notification', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
    SharedPrefsMock.register();

    dotenv.testLoad(fileInput: File('.env').readAsStringSync());
    
    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL']!,
      publishableKey: dotenv.env['SUPABASE_PUBLISHABLE_KEY']!,
    );
    
    final client = Supabase.instance.client;
    
    debugPrint('Signing in as admin...');
    final authRes = await client.auth.signInWithPassword(
      email: 'admin@test.com',
      password: 'AdminPassword2026!',
    );
    debugPrint('Admin sign in succeeded! User: ${authRes.user?.email}');
    
    // 1. Fetch inspector profile
    debugPrint('Fetching inspector profile from profiles table...');
    final profilesRes = await client
        .from('profiles')
        .select()
        .eq('role', 'inspector')
        .limit(1);
        
    if (profilesRes.isEmpty) {
      fail('No inspector profile found. Make sure inspector@test.com is registered and has the "inspector" role.');
    }
    
    final inspectorId = profilesRes.first['id'];
    final inspectorName = profilesRes.first['full_name'] ?? 'Inspector';
    debugPrint('Found Inspector: $inspectorName (ID: $inspectorId)');
    
    // 2. Fetch a zoning application to link the job to
    debugPrint('Fetching a zoning application to link the assignment...');
    final appsRes = await client
        .from('supabase_zoning_applications')
        .select()
        .limit(1);
        
    if (appsRes.isEmpty) {
      fail('No zoning applications found. Create at least one zoning application record first.');
    }
    
    final appId = appsRes.first['id'];
    final applicantName = appsRes.first['applicant_name'];
    final barangay = appsRes.first['barangay'];
    debugPrint('Found Zoning Application: $applicantName in $barangay (ID: $appId)');
    
    // 3. Check for device subscriptions
    debugPrint('Checking device subscriptions for the inspector...');
    final devicesRes = await client
        .from('inspector_device_subscriptions')
        .select()
        .eq('inspector_id', inspectorId);
        
    debugPrint('Active subscription tokens found: ${devicesRes.length}');
    for (final d in devicesRes) {
      debugPrint(' - Token: ${d['device_token']}');
    }
    
    if (devicesRes.isEmpty) {
      debugPrint('WARNING: No active push tokens found for this inspector. The webhook will skip sending the push notification.');
    }
    
    // 4. Insert the job record
    final testLocalId = Random().nextInt(999999);
    debugPrint('Inserting test job in field_jobs (local_inspection_id: $testLocalId)...');
    
    final insertRes = await client.from('field_jobs').insert({
      'assigned_inspector_id': inspectorId,
      'supabase_application_id': appId,
      'status': 'assigned',
      'scheduled_date': DateTime.now().add(const Duration(days: 1)).toIso8601String().split('T')[0],
      'local_inspection_id': testLocalId,
    }).select();
    
    debugPrint('Job successfully inserted!');
    debugPrint(insertRes.toString());
    debugPrint('Webhook should now be triggered! Check Supabase Edge Function logs for status 200.');
  });
}
