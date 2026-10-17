import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:imaps_fieldsync/main.dart';
import 'package:imaps_fieldsync/modules/auth_startup/screens/splash_screen.dart' show LoginScreen;
import 'package:imaps_fieldsync/modules/profile_settings/widgets/dashboard_widgets.dart';
import 'package:imaps_fieldsync/modules/profile_settings/models/analytics_activity_range.dart';

void main() {
  setUpAll(() async {
    // The app's real startup stands a Supabase client up before the session
    // gate is reached (AppBootstrap's first step). This isolate must model
    // that foundation: with no client, the corrected gate correctly refuses
    // to mount an interactive login — a shape production never reaches.
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://fs03.test',
      publishableKey: 'fixture-publishable-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
    );
  });

  testWidgets('App builds and shows login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    // The approved wordmark separates Field and Sync visually, while exposing
    // the full brand name as a single accessible header.
    expect(find.text('iMAPS'), findsOneWidget);
    expect(find.byWidgetPredicate((widget) => widget is Semantics &&
      widget.properties.label == 'FieldSync' && widget.properties.header == true), findsOneWidget);

    // One 13.35 s cinematic drives the whole launch: the completed logo holds
    // until 9.85 s, Page 3 (the login) mounts in place at 10.85 s, the route
    // re-enters and the logo reveals by 13.15 s. The splash hands the frame
    // to the login exactly once, on the journey's own beats.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 8300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Sign in'), findsOneWidget);
  });

  testWidgets('Activity heatmap renders in a constrained card without overflow', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 340,
              child: SingleChildScrollView(
                child: ActivityHeatmapCard(
                  activityRange: AnalyticsActivityRange.month(
                    2026,
                    8,
                    const {},
                  ),
                  activeColor: Colors.green,
                  inactiveColor: const Color(0xFFE9EEF6),
                  textColor: Colors.black,
                  mutedTextColor: const Color(0xFF5D6472),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(GridView), findsOneWidget);
    final gridRect = tester.getRect(find.byType(GridView));
    expect(gridRect.height, greaterThan(120));
  });
}
