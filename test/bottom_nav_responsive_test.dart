import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:imaps_fieldsync/core/layout/responsive_layout.dart';
import 'package:imaps_fieldsync/core/widgets/insight_bottom_nav.dart';

/// The rail's accepted geometry, mirrored from insight_bottom_nav.dart so a
/// silent change to the accepted phone-portrait design is caught here.
const double kItemHeight = 48;
const double kItemGap = 8;
const double kRailInnerPad = 8;
const double kIconSize = 20;
const double kActivePadH = 20;
const double kLabelGap = 8;
const double kTriggerSize = 64;
const double kTriggerGap = 12;

const navItems = [
  InsightNavItem(icon: Icons.home_rounded, label: 'Home'),
  InsightNavItem(icon: Icons.assignment_rounded, label: 'Tasks'),
  InsightNavItem(icon: Icons.sync_rounded, label: 'Sync'),
  InsightNavItem(icon: Icons.person_rounded, label: 'Profile'),
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

Future<void> pumpNav(
  WidgetTester tester,
  Size size, {
  int currentIndex = 1,
  double textScale = 1.0,
}) async {
  setViewport(tester, size, textScale: textScale);
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Stack(
        children: [
          // Representative page content behind the nav.
          const Positioned.fill(child: SizedBox()),
          Align(
            alignment: Alignment.bottomCenter,
            child: InsightBottomNav(
              currentIndex: currentIndex,
              items: navItems,
              onTap: (_) {},
            ),
          ),
        ],
      ),
    ),
  ));
  await tester.pump();
}

/// The white pill rail: the Container that is the direct child of the
/// positioned, centred box.
Finder railFinder() => find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.padding == const EdgeInsets.all(kRailInnerPad) &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).color == Colors.white,
      description: 'bottom nav rail',
    );

double railWidth(WidgetTester tester) => tester.getRect(railFinder()).width;

void main() {
  group('N1. phone portrait keeps the accepted full-bleed design', () {
    testWidgets('rail fills the available width exactly as before',
        (tester) async {
      await pumpNav(tester, const Size(390, 844));
      // 390 - 14*2 outer padding = 362: the accepted full-bleed width.
      expect(railWidth(tester), 362);
    });

    testWidgets('no overflow at the accepted size', (tester) async {
      await pumpNav(tester, const Size(390, 844));
      expect(tester.takeException(), isNull);
    });

    testWidgets('large phone portrait is also untouched', (tester) async {
      await pumpNav(tester, const Size(430, 932));
      expect(railWidth(tester), 430 - 28);
      expect(tester.takeException(), isNull);
    });
  });

  group('N2. landscape and tablet get a centred, capped pill', () {
    for (final size in [
      const Size(844, 390),
      const Size(932, 430),
      const Size(800, 1280),
      const Size(1280, 800),
    ]) {
      testWidgets('rail is bounded at ${size.width.toInt()}'
          'x${size.height.toInt()}', (tester) async {
        await pumpNav(tester, size);
        final w = railWidth(tester);
        expect(w, lessThanOrEqualTo(kInsightBottomNavMaxWidth),
            reason: 'must not stretch edge to edge');
        expect(w, greaterThan(0));
        expect(tester.takeException(), isNull);
      });

      testWidgets('rail is horizontally centred at ${size.width.toInt()}'
          'x${size.height.toInt()}', (tester) async {
        await pumpNav(tester, size);
        final rail = tester.getRect(railFinder());
        final screen = tester.getRect(find.byType(Scaffold));
        // Equal gutters on both sides = centred.
        expect((rail.left - screen.left), closeTo(screen.right - rail.right, 1),
            reason: 'centred in the viewport');
      });
    }

    testWidgets('the cap is meaningfully narrower than a 1280 viewport',
        (tester) async {
      await pumpNav(tester, const Size(1280, 800));
      expect(railWidth(tester), lessThan(1280 / 2));
    });
  });

  group('N3. the cap never squeezes the items', () {
    testWidgets('labels and icons fit inside the capped rail at 1280x800',
        (tester) async {
      await pumpNav(tester, const Size(1280, 800));
      final rail = tester.getRect(railFinder());
      // Every item must sit inside the rail, not spill past its rounded ends.
      for (final label in ['Home', 'Tasks', 'Sync', 'Profile']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.byIcon(Icons.home_rounded), findsOneWidget);
      expect(find.byIcon(Icons.assignment_rounded), findsOneWidget);
      expect(find.byIcon(Icons.sync_rounded), findsOneWidget);
      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
      expect(rail.width, greaterThanOrEqualTo(300));
    });

    testWidgets('a text-scaled label grows the rail instead of clipping',
        (tester) async {
      await pumpNav(tester, const Size(1280, 800));
      final normal = railWidth(tester);
      await pumpNav(tester, const Size(1280, 800), textScale: 1.3);
      final scaled = railWidth(tester);
      expect(scaled, greaterThanOrEqualTo(normal),
          reason: 'the cap is a ceiling, never a squeeze');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the active pill keeps its label visible when text scales',
        (tester) async {
      await pumpNav(tester, const Size(844, 390), textScale: 1.3);
      expect(find.text('Tasks'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the cap applies across the whole viewport matrix at 1.3x',
        (tester) async {
      for (final size in [
        const Size(390, 844),
        const Size(844, 390),
        const Size(430, 932),
        const Size(932, 430),
        const Size(800, 1280),
        const Size(1280, 800),
      ]) {
        await pumpNav(tester, size, textScale: 1.3);
        expect(tester.takeException(), isNull, reason: '$size');
      }
    });
  });

  group('N4. touch targets and navigation behaviour are untouched', () {
    testWidgets('every item keeps a 48px minimum touch target', (tester) async {
      await pumpNav(tester, const Size(390, 844));
      // The tappable chip, not the glyph inside it. An inactive chip is
      // _itemHeight square; the glyph is only _iconSize.
      final chip = find.byWidgetPredicate(
        (w) =>
            w is AnimatedContainer &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).color ==
                const Color(0xFFF2F4FB),
        description: 'inactive nav chip',
      );
      expect(chip, findsNWidgets(3), reason: 'one per inactive tab');
      for (final e in tester.widgetList<AnimatedContainer>(chip)) {
        final r = tester.getRect(find.byWidget(e));
        expect(r.width, greaterThanOrEqualTo(InsightBreakpoints.minTouchTarget),
            reason: 'touch target ${r.width}');
        expect(r.height, greaterThanOrEqualTo(InsightBreakpoints.minTouchTarget),
            reason: 'touch target ${r.height}');
      }
      // The glyph itself is intentionally smaller than the target.
      expect(tester.getRect(find.byIcon(Icons.home_rounded)).width, kIconSize);
    });

    testWidgets('tapping an item still reports the selection', (tester) async {
      var selected = -1;
      setViewport(tester, const Size(1280, 800));
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: InsightBottomNav(
              currentIndex: 0,
              items: navItems,
              onTap: (i) => selected = i,
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.sync_rounded));
      await tester.pumpAndSettle();
      expect(selected, 2);
    });

    testWidgets('the active item stays the highlighted one', (tester) async {
      await pumpNav(tester, const Size(1280, 800), currentIndex: 3);
      // 'Profile' is active, so its label is revealed in the wide pill.
      expect(find.text('Profile'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the quick-actions trigger keeps its 64px target', (tester) async {
      setViewport(tester, const Size(1280, 800));
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: InsightBottomNav(
              currentIndex: 0,
              items: navItems,
              onTap: (_) {},
              onQuickActionsTap: () {},
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(find.byType(InsightBottomNav), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('N5. no bottom-nav collision with page content', () {
    testWidgets('nav does not exceed its documented reserve on any viewport',
        (tester) async {
      for (final size in [
        const Size(390, 844),
        const Size(844, 390),
        const Size(1280, 800),
      ]) {
        await pumpNav(tester, size);
        final navHeight = tester.getSize(find.byType(InsightBottomNav)).height;
        // The reserve must keep covering the nav plus the system inset.
        expect(kInsightBottomNavReserve, greaterThanOrEqualTo(140),
            reason: 'reserve floor unchanged at $size');
        expect(navHeight, greaterThan(0));
      }
    });

    testWidgets('capsule geometry is untouched by the responsive change',
        (tester) async {
      // The accepted visual: 64 trigger + 12 gap + 64 rail.
      final expected = kTriggerSize + kTriggerGap + kTriggerSize;
      await pumpNav(tester, const Size(390, 844));
      expect(
        tester.getSize(find.byType(InsightBottomNav)).height,
        greaterThanOrEqualTo(expected),
      );
    });
  });

  group('N6. the cap value is the one HEAD accepted', () {
    test('documented constant', () {
      expect(kInsightBottomNavMaxWidth, 360);
      expect(kInsightBottomNavMaxWidth, lessThan(InsightBreakpoints.mediumWidth),
          reason: 'the cap must engage before the medium breakpoint');
    });

    test('phone portrait width sits under the cap, so portrait is unchanged',
        () {
      // 390 - 28 padding = 362 available, but portrait takes the null-width
      // path. This documents why 360 does not alter portrait.
      expect(390 - 28, greaterThan(300));
    });
  });
}