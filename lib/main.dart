import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState;
import 'core/services/app_info_service.dart';
import 'core/services/app_bootstrap.dart';
import 'core/services/supabase_service.dart';
import './modules/inspection/providers/inspection_provider.dart';
import 'modules/auth_startup/screens/splash_screen.dart';
import 'modules/auth_startup/services/screen_protection_service.dart';
import 'modules/auth_startup/services/screen_protection_observer.dart';
import 'modules/auth_startup/widgets/auto_lock_activity_host.dart';
import 'core/widgets/sensitive_screen.dart';
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

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.authEvents});
  final Stream<AuthState>? authEvents;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _protection = ScreenProtectionService.instance;
  late final _protectionObserver = ScreenProtectionObserver(_protection);
  StreamSubscription<AuthState>? _authPrivacySubscription;

  @override
  void initState() {
    super.initState();
    // Bootstrap now runs beside the first frames. Subscribe only once its
    // auth foundation exists; cancellation also prevents a late attachment.
    _authPrivacySubscription = (widget.authEvents ??
        Stream<void>.fromFuture(AppBootstrap.ready).asyncExpand((_) =>
            SupabaseService.hasClient
                ? SupabaseService.client.auth.onAuthStateChange
                : const Stream<AuthState>.empty())).listen(
      (_) => _protection.invalidateDocumentation(),
    );
  }

  @override
  void dispose() {
    _authPrivacySubscription?.cancel();
    _protection.invalidateDocumentation();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [_protectionObserver],
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
      builder: (context, child) => AutoLockActivityHost(
        child: ScreenProtectionHost(
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
