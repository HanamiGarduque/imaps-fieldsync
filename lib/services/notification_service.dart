import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'supabase_service.dart';

class NotificationService {
  static const String _oneSignalAppId = "3c4a56cf-d8da-4e2e-a3a8-b4ce0e74463d";

  static Future<void> initialize() async {
    OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    OneSignal.initialize(_oneSignalAppId);
    OneSignal.Notifications.requestPermission(true);

    // Bago: kapag nagbago yung subscription ID (bagong device o re-install),
    // awtomatikong i-save ulit natin sa Supabase kung naka-login
    OneSignal.User.pushSubscription.addObserver((state) {
      final subscriptionId = state.current.id;
      if (subscriptionId != null) {
        SupabaseService.registerDeviceForPush(deviceToken: subscriptionId);
      }
    });
  }

  // Tatawagin natin ito right after successful login
  static Future<void> registerCurrentDevice() async {
    final subscriptionId = OneSignal.User.pushSubscription.id;
    if (subscriptionId != null) {
      await SupabaseService.registerDeviceForPush(deviceToken: subscriptionId);
    }
  }
}