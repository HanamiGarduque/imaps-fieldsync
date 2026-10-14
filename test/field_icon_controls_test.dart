import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/widgets/field_form_widgets.dart';

void main() {
  testWidgets('Compact plates retain independent 48dp targets and native button semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    var back = 0;
    var info = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Row(children: [
      FieldBackButton(onPressed: () => back++, tooltip: 'Exit inspection'),
      const SizedBox(width: 8),
      FieldInfoButton(label: 'About task details', onPressed: () => info++),
    ]))));
    final targets = [find.byType(FieldBackButton), find.byType(FieldInfoButton)];
    for (final target in targets) {
      expect(tester.getSize(target), const Size(48, 48));
      final button = find.descendant(of: target, matching: find.byType(IconButton));
      expect(tester.getSemantics(button).getSemanticsData().flagsCollection.isButton, isTrue);
      await tester.tapAt(tester.getTopLeft(target) + const Offset(1, 1));
    }
    expect(back, 1, reason: 'The quiet plate must not shrink the reachable Back target.');
    expect(info, 1);
    expect(tester.getRect(targets.first).overlaps(tester.getRect(targets.last)), isFalse);
    expect(find.byTooltip('Exit inspection'), findsOneWidget);
    expect(find.byTooltip('About task details'), findsOneWidget);
    for (final (target, dimension) in [(targets.first, 38.0), (targets.last, 28.0)]) {
      final plate = find.descendant(of: target, matching: find.byType(DecoratedBox));
      expect(tester.getSize(plate), Size.square(dimension));
    }
    semantics.dispose();
  });

  testWidgets('Back and Info activate the supplied callback through pointer and keyboard', (tester) async {
    var back = 0;
    var info = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Row(children: [
      FieldBackButton(onPressed: () => back++),
      FieldInfoButton(label: 'About Sync Center', onPressed: () => info++),
    ]))));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(back, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(info, 1);
    await tester.tap(find.byType(FieldBackButton));
    await tester.tap(find.byType(FieldInfoButton));
    expect(back, 2);
    expect(info, 2);
    expect(tester.takeException(), isNull);
  });
}
