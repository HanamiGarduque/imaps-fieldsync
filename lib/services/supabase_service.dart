import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL']!,
      publishableKey: dotenv.env['SUPABASE_PUBLISHABLE_KEY']!,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> registerDeviceForPush({
    required String deviceToken,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) {
      debugPrint('No logged-in user found, unable to save device token.');
      return;
    }

    try {
      await client.from('inspector_device_subscriptions').upsert(
        {
          'inspector_id': user.id,
          'device_token': deviceToken,
        },
        onConflict: 'inspector_id,device_token',
      );
    } catch (e) {
      debugPrint('Failed to save notification subscription: $e');
    }
  }
static Future<List<Map<String, dynamic>>> fetchMyJobs() async {
  final userId = client.auth.currentUser?.id;
  if (userId == null) return [];

  final response = await client
      .from('field_jobs')
      .select('''
        id,
        local_inspection_id,
        status,
        scheduled_date,
        supabase_parcel_id,
        supabase_zoning_applications!field_jobs_supabase_application_id_fkey (
          reference_number,
          applicant_name,
          barangay
        )
      ''')
      .eq('assigned_inspector_id', userId)
      .order('scheduled_date', ascending: true);

  return List<Map<String, dynamic>>.from(response);
}
}