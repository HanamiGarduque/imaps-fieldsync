import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'supabase_service.dart';

class NotificationService {
  static Future<void> initialize() async {
    OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    OneSignal.initialize(dotenv.env['ONESIGNAL_APP_ID']!);
    OneSignal.Notifications.requestPermission(true);

    OneSignal.User.pushSubscription.addObserver((state) {
      final subscriptionId = state.current.id;
      if (subscriptionId != null) {
        SupabaseService.registerDeviceForPush(deviceToken: subscriptionId);
      }
    });
  }

  static Future<void> registerCurrentDevice() async {
    final subscriptionId = OneSignal.User.pushSubscription.id;
    if (subscriptionId != null) {
      await SupabaseService.registerDeviceForPush(deviceToken: subscriptionId);
    }
  }
}