import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:app_links/app_links.dart';
import 'services/supabase_service.dart';
import 'services/notification_service.dart';
import 'services/sync_outbox_service.dart';
import 'providers/inspection_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/reset_password_screen.dart';
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
  await NotificationService.initialize();
  
  SyncOutboxService.start();
  _listenForPasswordResetLinks();
  
  runApp(
    ChangeNotifierProvider(
      create: (_) => InspectionProvider(),
      child: const MyApp(),
    ),
  );
}

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