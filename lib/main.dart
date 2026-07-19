import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:app_links/app_links.dart'; // pubspec: app_links: ^6.0.0
import 'services/supabase_service.dart';
import 'services/notification_service.dart';
import 'services/sync_outbox_service.dart';
import 'providers/inspection_provider.dart';
import 'screens/splash_screen.dart'; // draft screen 1 — new entry point
import 'screens/reset_password_screen.dart';

// Global navigator key so the deep-link handler (which runs outside any
// widget's BuildContext) can push ResetPasswordScreen on top of whatever
// screen the app happens to be showing when the link is opened.
final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");
  await SupabaseService.initialize();
  await NotificationService.initialize();
  // FieldSync: drains anything queued from a prior offline session, then
  // listens for connectivity coming back so queued actions sync
  // automatically without needing an app restart.
  SyncOutboxService.start();
  _listenForPasswordResetLinks();
  runApp(
    ChangeNotifierProvider(
      create: (_) => InspectionProvider(),
      child: const MyApp(),
    ),
  );
}

// Catches the link the inspector taps from the "forgot passcode" email
// (e.g. imapsfieldsync://reset-password#access_token=...&type=recovery)
// and, once Supabase has turned it into a real recovery session, pushes
// ResetPasswordScreen so they can actually set a new passcode.
//
// REQUIRES NATIVE CONFIG NOT INCLUDED IN THIS FILE:
//   Android: add an intent-filter for scheme "imapsfieldsync" in
//            android/app/src/main/AndroidManifest.xml
//   iOS:     add "imapsfieldsync" under CFBundleURLSchemes in
//            ios/Runner/Info.plist
//   Supabase Dashboard: add "imapsfieldsync://reset-password" under
//            Authentication -> URL Configuration -> Redirect URLs
void _listenForPasswordResetLinks() {
  final appLinks = AppLinks();
  appLinks.uriLinkStream.listen((uri) async {
    if (uri.toString().contains('reset-password') || uri.toString().contains('type=recovery')) {
      try {
        await SupabaseService.client.auth.getSessionFromUrl(uri);
        navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
        );
      } catch (e) {
        debugPrint('[RESET_LINK] Failed to parse recovery link: $e');
      }
    }
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'InSight — iMAPS FieldSync',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.indigo, useMaterial3: true),
      home: const SplashScreen(),
    );
  }
}