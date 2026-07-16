import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'services/supabase_service.dart';
import 'services/notification_service.dart';
import 'screens/splash_screen.dart'; // draft screen 1 — new entry point

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await SupabaseService.initialize();
  await NotificationService.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InSight — iMAPS FieldSync',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.indigo, useMaterial3: true),
      // Original entry point was WelcomeScreen (screens/login_screen.dart).
      // SplashScreen (screen 1 of the prototype) now runs first and
      // auto-advances into WelcomeScreen unchanged.
      home: const SplashScreen(),
    );
  }
}
