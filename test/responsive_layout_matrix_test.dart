import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:imaps_fieldsync/core/layout/responsive_layout.dart';

/// The viewport matrix from the responsive contract. Every screen has to hold
/// up at each of these.
class Viewport {
  const Viewport(this.label, this.size);
  final String label;
  final Size size;

  @override
  String toString() => '$label ${size.width.toInt()}x${size.height.toInt()}';
}

const viewports = <Viewport>[
  Viewport('phone portrait', Size(390, 844)),
  Viewport('phone landscape', Size(844, 390)),
  Viewport('large phone portrait', Size(430, 932)),
  Viewport('large phone landscape', Size(932, 430)),
  Viewport('tablet portrait', Size(800, 1280)),
  Viewport('tablet landscape', Size(1280, 800)),
];

/// Resizes the *real* render surface, not just the MediaQuery.
///
/// Overriding `MediaQueryData(size:)` alone would leave the layout surface at
/// the 800x600 test default, so the breakpoints and the actual layout would
/// disagree. Driving `tester.view` is what makes these genuine viewport tests.
void setViewport(WidgetTester tester, Viewport v, {double textScale = 1.0}) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = v.size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  // MediaQuery derives size from the view; the text scaler does not.
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> pumpAt(
  WidgetTester tester,
  Widget child,
  Viewport v, {
  double textScale = 1.0,
}) async {
  setViewport(tester, v, textScale: textScale);
  await tester.pumpWidget(
    MaterialApp(debugShowCheckedModeBanner: false, home: Scaffold(body: child)),
  );
  await tester.pump();
}

void main() {
  group('A. width classes are layout classes, not device identities', () {
    test('phone portrait and large phone portrait are both compact', () {
      for (final v in [viewports[0], viewports[2]]) {
        final bp = InsightBreakpoints(v.size);
        expect(bp.isCompactWidth, isTrue, reason: v.toString());
        expect(bp.widthClass, InsightWidthClass.compact, reason: v.toString());
      }
    });

    test('tablet landscape is expanded, tablet portrait is medium', () {
      expect(InsightBreakpoints(viewports[5].size).widthClass,
          InsightWidthClass.expanded);
      expect(InsightBreakpoints(viewports[4].size).widthClass,
          InsightWidthClass.medium);
    });

    test('breakpoints sit on the documented boundaries', () {
      expect(InsightBreakpoints(const Size(599, 800)).isCompactWidth, isTrue);
      expect(InsightBreakpoints(const Size(600, 800)).isMediumWidth, isTrue);
      expect(InsightBreakpoints(const Size(899, 800)).isMediumWidth, isTrue);
      expect(InsightBreakpoints(const Size(900, 800)).isExpandedWidth, isTrue);
    });

    testWidgets('the breakpoints a screen sees match the real viewport',
        (tester) async {
      // Guards the harness itself: if this fails, every other test in this file
      // is measuring the wrong box.
      late InsightBreakpoints seen;
      await pumpAt(
        tester,
        Builder(builder: (context) {
          seen = context.responsive;
          return const SizedBox.shrink();
        }),
        viewports[5],
      );
      expect(seen.width, 1280);
      expect(seen.height, 800);
      expect(seen.isExpandedWidth, isTrue);
      expect(find.byType(SizedBox), findsWidgets);
    });
  });

  group('B. a wide-but-short viewport is recognised as short height', () {
    test('phone landscape is wide but short', () {
      final bp = InsightBreakpoints(viewports[1].size);
      expect(bp.isLandscape, isTrue);
      expect(bp.isMediumWidth, isTrue, reason: '844 is not compact');
      expect(bp.isShortHeight, isTrue, reason: '390 height is scarce');
    });

    test('large phone landscape is wide but short', () {
      final bp = InsightBreakpoints(viewports[3].size);
      expect(bp.isLandscape, isTrue);
      expect(bp.isShortHeight, isTrue);
    });

    test('portrait viewports are tall', () {
      for (final v in [viewports[0], viewports[2], viewports[4]]) {
        final bp = InsightBreakpoints(v.size);
        expect(bp.isShortHeight, isFalse, reason: v.toString());
        expect(bp.isPortrait, isTrue, reason: v.toString());
      }
    });

    test('tablet landscape has room in both axes', () {
      final bp = InsightBreakpoints(viewports[5].size);
      expect(bp.isShortHeight, isFalse);
      expect(bp.isExpandedWidth, isTrue);
    });

    test('short-height boundary is 480', () {
      expect(InsightBreakpoints(const Size(800, 479)).isShortHeight, isTrue);
      expect(InsightBreakpoints(const Size(800, 480)).isShortHeight, isFalse);
    });
  });

  group('C. a split needs width AND height', () {
    test('both phone-landscape viewports split', () {
      expect(InsightBreakpoints(viewports[1].size).canSplitTwoPane, isTrue);
      expect(InsightBreakpoints(viewports[3].size).canSplitTwoPane, isTrue);
    });

    test('both tablet viewports split', () {
      expect(InsightBreakpoints(viewports[4].size).canSplitTwoPane, isTrue);
      expect(InsightBreakpoints(viewports[5].size).canSplitTwoPane, isTrue);
    });

    test('phones in portrait never split', () {
      expect(InsightBreakpoints(viewports[0].size).canSplitTwoPane, isFalse);
      expect(InsightBreakpoints(viewports[2].size).canSplitTwoPane, isFalse);
    });

    test('wide but too short never splits - a half-height pane is unusable', () {
      final bp = InsightBreakpoints(const Size(1280, 300));
      expect(bp.isExpandedWidth, isTrue);
      expect(bp.canSplitTwoPane, isFalse);
    });

    test('tall but too narrow never splits', () {
      final bp = InsightBreakpoints(const Size(500, 1000));
      expect(bp.isCompactWidth, isTrue);
      expect(bp.canSplitTwoPane, isFalse);
    });
  });

  group('D. ConstrainedContent stops content stretching', () {
    testWidgets('caps at the form width on a wide viewport', (tester) async {
      const inner = Key('inner');
      await pumpAt(
        tester,
        const ConstrainedContent(
          child: SizedBox(key: inner, width: double.infinity, height: 10),
        ),
        viewports[5],
      );
      final r = tester.getRect(find.byKey(inner));
      expect(r.width, InsightBreakpoints.contentMaxWidth);
      expect(r.center.dx, closeTo(640, 0.5), reason: 'centred on the canvas');
    });

    testWidgets('wide variant allows the wider card width', (tester) async {
      const inner = Key('inner');
      await pumpAt(
        tester,
        const ConstrainedContent.wide(
          child: SizedBox(key: inner, width: double.infinity, height: 10),
        ),
        viewports[5],
      );
      expect(tester.getRect(find.byKey(inner)).width,
          InsightBreakpoints.contentMaxWidthWide);
    });

    testWidgets('fill opts out entirely so maps keep the whole canvas',
        (tester) async {
      const inner = Key('inner');
      await pumpAt(
        tester,
        const ConstrainedContent(
          fill: true,
          child: SizedBox(key: inner, width: double.infinity, height: 10),
        ),
        viewports[5],
      );
      expect(tester.getRect(find.byKey(inner)).width, 1280);
    });

    testWidgets('never caps content narrower than the viewport',
        (tester) async {
      const inner = Key('inner');
      await pumpAt(
        tester,
        const ConstrainedContent(
          child: SizedBox(key: inner, width: double.infinity, height: 10),
        ),
        viewports[0],
      );
      expect(tester.getRect(find.byKey(inner)).width, 390);
    });

    testWidgets('caps on tablet landscape and centres', (tester) async {
      const inner = Key('inner');
      await pumpAt(
        tester,
        const ConstrainedContent(
          child: SizedBox(key: inner, width: double.infinity, height: 10),
        ),
        viewports[5],
      );
      // A 1240px-wide form is the failure this prevents.
      expect(tester.getRect(find.byKey(inner)).width,
          lessThan(InsightBreakpoints.expandedWidth));
    });

    testWidgets('no overflow at any viewport in the matrix', (tester) async {
      for (final v in viewports) {
        await pumpAt(
          tester,
          const ConstrainedContent(
            child: SizedBox(width: double.infinity, height: 40),
          ),
          v,
        );
        expect(tester.takeException(), isNull, reason: v.toString());
      }
    });

    testWidgets('survives a larger text scale', (tester) async {
      for (final v in viewports) {
        await pumpAt(
          tester,
          const ConstrainedContent(
            child: SizedBox(width: double.infinity, height: 40),
          ),
          v,
          textScale: 1.3,
        );
        expect(tester.takeException(), isNull, reason: v.toString());
      }
    });
  });

  group('E. SplitPane adapts instead of merely reflowing', () {
    testWidgets('stacks on phone portrait', (tester) async {
      await pumpAt(
        tester,
        const SplitPane(
          primary: SizedBox(key: Key('p'), height: 20),
          secondary: SizedBox(key: Key('s'), height: 20),
        ),
        viewports[0],
      );
      final p = tester.getRect(find.byKey(const Key('p')));
      final s = tester.getRect(find.byKey(const Key('s')));
      expect(s.top, greaterThan(p.bottom), reason: 'stacked vertically');
    });

    testWidgets('splits side by side on phone landscape', (tester) async {
      await pumpAt(
        tester,
        const SplitPane(
          primary: SizedBox(key: Key('p'), height: 20),
          secondary: SizedBox(key: Key('s'), height: 20),
        ),
        viewports[1],
      );
      final p = tester.getRect(find.byKey(const Key('p')));
      final s = tester.getRect(find.byKey(const Key('s')));
      expect(s.left, greaterThan(p.right), reason: 'side by side');
    });

    testWidgets('splits on both tablet viewports', (tester) async {
      for (final v in [viewports[4], viewports[5]]) {
        await pumpAt(
          tester,
          const SplitPane(
            primary: SizedBox(key: Key('p'), height: 20),
            secondary: SizedBox(key: Key('s'), height: 20),
          ),
          v,
        );
        final p = tester.getRect(find.byKey(const Key('p')));
        final s = tester.getRect(find.byKey(const Key('s')));
        expect(s.left, greaterThan(p.right), reason: v.toString());
      }
    });

    testWidgets('primary keeps the dominant share', (tester) async {
      await pumpAt(
        tester,
        const SplitPane(
          primary: SizedBox(key: Key('p'), height: 20),
          secondary: SizedBox(key: Key('s'), height: 20),
        ),
        viewports[5],
      );
      final p = tester.getRect(find.byKey(const Key('p'))).width;
      final s = tester.getRect(find.byKey(const Key('s'))).width;
      expect(p, greaterThan(s), reason: 'primary is the larger pane');
      expect(p / (p + s), closeTo(0.62, 0.02));
    });

    testWidgets('both panes get real height on a short landscape viewport',
        (tester) async {
      // The reason canSplitTwoPane checks height as well as width.
      await pumpAt(
        tester,
        const SplitPane(
          primary: SizedBox(key: Key('p')),
          secondary: SizedBox(key: Key('s')),
        ),
        viewports[1],
      );
      expect(tester.getRect(find.byKey(const Key('s'))).height, 390);
      expect(tester.getRect(find.byKey(const Key('p'))).height, 390);
    });

    testWidgets('no overflow at any viewport in the matrix', (tester) async {
      for (final v in viewports) {
        await pumpAt(
          tester,
          const SplitPane(
            primary: SizedBox(height: 40),
            secondary: SizedBox(height: 40),
          ),
          v,
        );
        expect(tester.takeException(), isNull, reason: v.toString());
      }
    });

    testWidgets('survives a larger text scale', (tester) async {
      for (final v in viewports) {
        await pumpAt(
          tester,
          const SplitPane(
            primary: SizedBox(height: 40),
            secondary: SizedBox(height: 40),
          ),
          v,
          textScale: 1.3,
        );
        expect(tester.takeException(), isNull, reason: v.toString());
      }
    });
  });

  group('F. breakpoint decisions are centralised', () {
    test('the documented values are the ones screens depend on', () {
      // Screens must ask context.responsive rather than reading the
      // orientation flag inline. These are the numbers that makes possible.
      expect(InsightBreakpoints.mediumWidth, 600);
      expect(InsightBreakpoints.expandedWidth, 900);
      expect(InsightBreakpoints.shortHeight, 480);
      expect(InsightBreakpoints.splitMinWidth, 720);
      expect(InsightBreakpoints.splitMinHeight, 340);
      expect(InsightBreakpoints.contentMaxWidth, 640);
      expect(InsightBreakpoints.contentMaxWidthWide, 900);
      expect(InsightBreakpoints.minTouchTarget, 48);
    });

    test('a minimum 48px touch target is preserved as the floor', () {
      expect(InsightBreakpoints.minTouchTarget, greaterThanOrEqualTo(48));
    });
  });
}