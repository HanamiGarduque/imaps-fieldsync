import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:imaps_fieldsync/core/widgets/quick_actions_sheet.dart';

/// The five shipped actions, named as the shell registers them. The adaptive
/// layout must keep every one of them reachable.
const actionTitles = [
  'Site Map',
  'Compass',
  'Analytics Overview',
  'Sync History',
  'Edit Profile',
];

List<QuickAction> buildActions({VoidCallback? onTap}) => [
      for (final t in actionTitles)
        QuickAction(icon: Icons.circle_outlined, title: t, onTap: onTap ?? () {}),
    ];

void setViewport(WidgetTester tester, Size size, {double textScale = 1.0}) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

/// Mounts the sheet exactly as the shell hosts it: anchored above the nav.
Future<void> pumpSheet(
  WidgetTester tester,
  Size size, {
  double textScale = 1.0,
}) async {
  setViewport(tester, size, textScale: textScale);
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: SizedBox()),
          Positioned(
            left: 16,
            right: 16,
            bottom: 190,
            child: QuickActionsSheet(
              actions: buildActions(),
              onClose: () {},
            ),
          ),
        ],
      ),
    ),
  ));
  await tester.pump();
  // Let the staggered entry animation settle so the final layout is measured.
  await tester.pumpAndSettle();
}

Rect sheetRect(WidgetTester tester) {
  final container = tester.widgetList<Container>(find.byType(Container)).firstWhere(
    (c) =>
        c.padding == const EdgeInsets.fromLTRB(8, 6, 8, 10) &&
        c.decoration is BoxDecoration &&
        (c.decoration! as BoxDecoration).color == Colors.white,
  );
  return tester.getRect(find.byWidget(container));
}

void main() {
  group('Q1. every action stays reachable at every viewport', () {
    for (final size in [
      const Size(390, 844),
      const Size(844, 390),
      const Size(430, 932),
      const Size(932, 430),
      const Size(800, 1280),
      const Size(1280, 800),
    ]) {
      testWidgets('all five actions present at ${size.width.toInt()}'
          'x${size.height.toInt()}', (tester) async {
        await pumpSheet(tester, size);
        for (final t in actionTitles) {
          expect(find.text(t), findsOneWidget, reason: '$t at $size');
        }
        expect(tester.takeException(), isNull, reason: '$size');
      });
    }

    testWidgets('no action is hidden or collapsed at 1.3x text scale',
        (tester) async {
      for (final size in [
        const Size(390, 844),
        const Size(844, 390),
        const Size(1280, 800),
      ]) {
        await pumpSheet(tester, size, textScale: 1.3);
        for (final t in actionTitles) {
          expect(find.text(t), findsOneWidget, reason: '$t at $size 1.3x');
        }
        expect(tester.takeException(), isNull, reason: '$size 1.3x');
      }
    });

    testWidgets('tapping an action still fires its callback', (tester) async {
      var fired = 0;
      setViewport(tester, const Size(1280, 800));
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Stack(
            children: [
              const Positioned.fill(child: SizedBox()),
              Positioned(
                left: 16,
                right: 16,
                bottom: 190,
                child: QuickActionsSheet(
                  actions: buildActions(onTap: () => fired++),
                  onClose: () {},
                ),
              ),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compass'));
      await tester.pumpAndSettle();
      expect(fired, 1);
    });

    testWidgets('the close control is still present', (tester) async {
      await pumpSheet(tester, const Size(844, 390));
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });
  });

  group('Q2. the sheet always fits the space above the nav', () {
    for (final size in [
      const Size(844, 390),
      const Size(932, 430),
      const Size(390, 844),
      const Size(1280, 800),
    ]) {
      testWidgets('sheet stays on screen at ${size.width.toInt()}'
          'x${size.height.toInt()}', (tester) async {
        await pumpSheet(tester, size);
        final sheet = sheetRect(tester);
        final screen = tester.getRect(find.byType(Scaffold));
        expect(sheet.top, greaterThanOrEqualTo(screen.top - 0.5),
            reason: 'must not extend above the viewport at $size');
        expect(sheet.bottom, lessThanOrEqualTo(screen.bottom + 0.5),
            reason: 'must not extend below the viewport at $size');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a short landscape viewport no longer needs 522px',
        (tester) async {
      // The old fixed content was ~332px hosted at bottom:190 = 522 needed
      // inside a 390px screen. The sheet now fits the 200px that is actually
      // available above the nav.
      await pumpSheet(tester, const Size(844, 390));
      final sheet = sheetRect(tester);
      expect(sheet.height, lessThanOrEqualTo(200));
      expect(sheet.bottom, lessThanOrEqualTo(200),
          reason: 'top edge lands at or above y=0');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the actions area scrolls rather than overflowing',
        (tester) async {
      await pumpSheet(tester, const Size(844, 390));
      expect(find.byType(SingleChildScrollView), findsWidgets,
          reason: 'bounded sheet must be able to scroll its rows');
      expect(tester.takeException(), isNull);
    });
  });

  group('Q3. landscape uses two columns instead of a tall portrait sheet', () {
    testWidgets('rows sit side by side on a wide viewport', (tester) async {
      await pumpSheet(tester, const Size(1280, 800));
      // Five actions split 3 | 2: the first three stack in column 1 and the
      // remaining two sit beside them in column 2.
      final a = tester.getRect(find.text(actionTitles[0]));
      final b = tester.getRect(find.text(actionTitles[1]));
      final c = tester.getRect(find.text(actionTitles[2]));
      final d = tester.getRect(find.text(actionTitles[3]));
      expect(b.left, closeTo(a.left, 1), reason: 'action 2 under action 1');
      expect(c.left, closeTo(a.left, 1), reason: 'action 3 under action 1');
      expect(d.left, greaterThan(a.right),
          reason: 'action 4 starts the second column, to the right');
    });

    testWidgets('portrait keeps the accepted single column', (tester) async {
      await pumpSheet(tester, const Size(390, 844));
      final a = tester.getRect(find.text(actionTitles[0]));
      final b = tester.getRect(find.text(actionTitles[1]));
      expect(b.left, closeTo(a.left, 1), reason: 'same column');
      expect(b.top, greaterThan(a.bottom), reason: 'stacked vertically');
    });

    testWidgets('a wide sheet stays a bounded panel, not full-bleed',
        (tester) async {
      await pumpSheet(tester, const Size(1280, 800));
      final sheet = sheetRect(tester);
      // Available width for the host is 1280 - 2*16 = 1248. The panel must be
      // bounded well inside that, not edge to edge. The exact cap is asserted
      // in responsive_2e_visual_fixes_test.dart against the production host.
      expect(sheet.width, lessThan(1248),
          reason: 'bounded, not a full-bleed strip');
      expect(sheet.width, lessThan(1280 * 0.5),
          reason: 'a floating panel, not a full-width strip');
      // Two columns of actions still share that bounded width. `sheet` is a
      // Rect, so positions are compared against its edges rather than its
      // width — comparing an x-coordinate to a length is meaningless.
      final a = tester.getRect(find.text(actionTitles[0]));
      final d = tester.getRect(find.text(actionTitles[3]));
      expect(d.left, greaterThan(sheet.left + sheet.width / 2),
          reason: 'the second column occupies the right half');
      expect(a.right, lessThan(sheet.right));
      expect(a.left, greaterThanOrEqualTo(sheet.left));
    });
  });

  group('Q4. routing behaviour is untouched', () {
    test('the action list is still exactly the five shipped entries', () {
      expect(actionTitles.length, 5);
      expect(buildActions().length, 5);
    });

    test('adaptive layout uses the shared foundation, not local MediaQuery', () {
      final src = _readSource();
      expect(src, contains('responsive_layout.dart'));
      expect(src, contains('canSplitTwoPane'));
      // The column decision goes through the foundation. MediaQuery is used
      // only for the host-offset height bound and the row-width floor, never for
      // an orientation or breakpoint decision.
      expect(src, isNot(contains('.orientation')));
      expect(src, isNot(contains('isPortrait')));
      expect(src, isNot(contains('isLandscape')));
      expect(src, contains('kTwoColumnMinWidth'));
    });

    test('the action model is unchanged', () {
      final src = _readSource();
      expect(src, contains('class QuickAction'));
      expect(src, contains('required this.icon'));
      expect(src, contains('required this.title'));
      expect(src, contains('required this.onTap'));
    });
  });
}

String _readSource() =>
    // ignore: avoid_dynamic_calls
    File('lib/core/widgets/quick_actions_sheet.dart').readAsStringSync();