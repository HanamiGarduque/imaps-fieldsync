import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'services/supabase_service.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/sync_outbox_service.dart';
import 'services/secure_prefs_service.dart';
import 'providers/inspection_provider.dart';
import 'screens/splash_screen.dart';
import 'widgets/debug_screenshot_toggle.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await dotenv.load(fileName: ".env");
  await SupabaseService.initialize();
  await AuthService.loadSoftLogoutState();
  await NotificationService.initialize();

  // One-time cleanup: purges any pattern-lock data left over from before
  // the App Pattern feature was removed (see AUTH_SECURITY_MASTER_DOC.md,
  // Phase 3a). Idempotent, cheap no-op on any device that never had a
  // pattern set up.
  await SecurePrefsService.purgeLegacyPatternLockData();

  SyncOutboxService.start();

  runApp(
    ChangeNotifierProvider(
      create: (_) => InspectionProvider(),
      child: const MyApp(),
    ),
  );
}

// Forgot Passcode is admin-mediated (see splash_screen.dart
// _handleForgotPasscode), not a self-service emailed-link reset — so this
// app deliberately does NOT listen for Supabase recovery deep links.
// If that ever changes, this is where a uriLinkStream listener (e.g. via
// app_links) routing to a password-reset screen would go back in.

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
      // Phase 3b (debug-only, see AUTH_SECURITY_MASTER_DOC.md and
      // widgets/debug_screenshot_toggle.dart): DebugScreenshotToggle
      // returns `child` completely unwrapped outside kDebugMode, so this
      // line is inert in release/profile builds.
      builder: (context, child) =>
          DebugScreenshotToggle(child: child ?? const SizedBox.shrink()),
    );
  }
}