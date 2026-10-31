import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState;

import '../../core/services/app_bootstrap.dart';
import '../../core/services/supabase_service.dart';
import '../../modules/auth_startup/services/screen_protection_observer.dart';
import '../../modules/auth_startup/services/screen_protection_service.dart';
import '../../modules/auth_startup/screens/splash_screen.dart';
import '../../modules/auth_startup/widgets/auto_lock_activity_host.dart';
import '../theme/insight_theme.dart';
import '../widgets/sensitive_screen.dart';

final navigatorKey = GlobalKey<NavigatorState>();

class FieldSyncApp extends StatefulWidget {
  const FieldSyncApp({super.key, this.captureHost});

  final Widget Function(Widget child)? captureHost;

  @override
  State<FieldSyncApp> createState() => _FieldSyncAppState();
}

class _FieldSyncAppState extends State<FieldSyncApp> {
  final _protection = ScreenProtectionService.instance;
  late final _protectionObserver = ScreenProtectionObserver(_protection);
  StreamSubscription<AuthState>? _authPrivacySubscription;

  @override
  void initState() {
    super.initState();
    _authPrivacySubscription = Stream<void>.fromFuture(AppBootstrap.ready)
        .asyncExpand(
          (_) => SupabaseService.hasClient
              ? SupabaseService.client.auth.onAuthStateChange
              : const Stream<AuthState>.empty(),
        )
        .listen((_) => _protection.invalidateDocumentation());
  }

  @override
  void dispose() {
    _authPrivacySubscription?.cancel();
    _protection.invalidateDocumentation();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child = ScreenProtectionHost(child: const SplashScreen());
    final captureHost = widget.captureHost;
    if (captureHost != null) child = captureHost(child);
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
      builder: (context, child) {
        Widget content = AutoLockActivityHost(
          child: ScreenProtectionHost(child: child ?? const SizedBox.shrink()),
        );
        final captureHost = widget.captureHost;
        if (captureHost != null) content = captureHost(content);
        return content;
      },
    );
  }
}
