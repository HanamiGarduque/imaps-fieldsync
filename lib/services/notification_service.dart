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

    // Previously nothing captured a push that arrived while the app was
    // already open — it just wouldn't show anywhere in-app (no entry in
    // the activity feed, no bump to the bell's unread count). This logs it
    // into activity_log like any other event, and lets the system banner
    // still display normally.
    OneSignal.Notifications.addForegroundWillDisplayListener((event) {
      final notification = event.notification;
      SupabaseService.logActivity(
        eventType: 'push_received',
        title: notification.title ?? 'New notification',
        subtitle: notification.body,
      );
      // Let the OS still show the banner — we're only mirroring it into
      // the in-app feed, not replacing the native notification.
      event.notification.display();
    });
  }

  static Future<void> registerCurrentDevice() async {
    final subscriptionId = OneSignal.User.pushSubscription.id;
    if (subscriptionId != null) {
      await SupabaseService.registerDeviceForPush(deviceToken: subscriptionId);
    }
  }
}