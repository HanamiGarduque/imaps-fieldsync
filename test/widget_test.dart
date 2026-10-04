import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:imaps_fieldsync/main.dart';
import 'package:imaps_fieldsync/modules/profile_settings/widgets/dashboard_widgets.dart';
import 'package:imaps_fieldsync/modules/profile_settings/models/analytics_activity_range.dart';

void main() {
  testWidgets('App builds and shows login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    // Splash renders the brand as two separate Text widgets (not one
    // 'iMAPS\nFieldSync' string as the old expectation assumed).
    expect(find.text('iMAPS'), findsOneWidget);
    expect(find.text('FieldSync'), findsOneWidget);

    // Session check waits 3s, then routes to LoginScreen via a 700ms fade
    // (splash_screen.dart _checkSession/_goToLogin).
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Sign in'), findsOneWidget);
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