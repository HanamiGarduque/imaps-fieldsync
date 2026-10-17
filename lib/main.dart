import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'core/services/app_info_service.dart';
import 'core/services/app_bootstrap.dart';
import './modules/inspection/providers/inspection_provider.dart';
import 'modules/auth_startup/screens/splash_screen.dart';
import 'modules/auth_startup/widgets/debug_screenshot_toggle.dart';
import 'core/theme/insight_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await dotenv.load(fileName: ".env");
  await AppInfoService.initialize();

  // Everything below this point used to run awaited, before runApp() — a
  // measured contributor to the ~5-second native launch window. It now runs
  // in the same order inside AppBootstrap, concurrently with the launch
  // cinematic's first frames. Consumers gate on AppBootstrap.ready (see
  // SplashScreen._checkSession), so no service can be observed before it is
  // ready.
  unawaited(AppBootstrap.initialize());

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
      title: 'iMAPS:FieldSync',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: InsightTheme.blue1,
        colorScheme: ColorScheme.light(
          primary: InsightTheme.blue1,
          secondary: InsightTheme.blue2,
          surface: InsightTheme.surface,
          error: InsightTheme.red,
        ),
        scaffoldBackgroundColor: InsightTheme.bg,
        appBarTheme: AppBarTheme(
          backgroundColor: InsightTheme.surface,
          foregroundColor: InsightTheme.ink,
          elevation: 0,
        ),
      ),
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
