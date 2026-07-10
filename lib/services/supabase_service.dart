import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static const String _supabaseUrl = "https://laapipjyprmmaylunxib.supabase.co";
  static const String _supabasePublishableKey = "sb_publishable_LZJLxNjhPbvXTGwj2tvnpg_cZGcXiT8";

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: _supabaseUrl,
      publishableKey: _supabasePublishableKey,
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
}