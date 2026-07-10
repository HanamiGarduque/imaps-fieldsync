import 'package:flutter_test/flutter_test.dart';

import 'package:imaps_fieldsync/main.dart';

void main() {
  testWidgets('App builds and shows login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.text('iMAPS\nFieldSync'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });
}