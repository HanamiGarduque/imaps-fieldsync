import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:imaps_fieldsync/main.dart';
import 'package:imaps_fieldsync/modules/profile_settings/widgets/dashboard_widgets.dart';

void main() {
  testWidgets('App builds and shows login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.text('iMAPS\nFieldSync'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });

  testWidgets('Activity heatmap renders in a constrained card without overflow', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 340,
              child: ActivityHeatmapCard(
                activeDays: const {1, 3, 5, 11, 17, 21, 23, 26},
                month: 8,
                year: 2026,
                activeColor: Colors.green,
                inactiveColor: const Color(0xFFE9EEF6),
                textColor: Colors.black,
                mutedTextColor: const Color(0xFF5D6472),
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