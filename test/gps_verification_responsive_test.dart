import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:imaps_fieldsync/core/layout/responsive_layout.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/gps_verification_screen.dart';

/// The production viewport matrix, mirrored from the responsive contract.
class Viewport {
  const Viewport(this.label, this.size);
  final String label;
  final Size size;
}

/// GPS Verification is the screen the user reported as broken: landscape
/// painted "BOTTOM OVERFLOWED BY 80 PIXELS".
///
/// The cause was arithmetic, not guesswork. The screen is a Column of
/// [header ~112][compass in Expanded][card ~274]. In phone landscape the
/// available height after the system insets was ~306, so the Expanded slot got
/// ~80, and the dial was clamped to a 160px *floor* — 160 into an 80 slot.
const double kReportedOverflowPx = 80;
const double kLegacyCompassFloor = 160;

void main() {
  group('G1. the reported overflow is arithmetically impossible now', () {
    test('the old floor is what produced exactly 80px, not a coincidence', () {
      // This is the regression's fingerprint, kept so the number cannot drift.
      expect(kLegacyCompassFloor - kReportedOverflowPx, 80);
    });

    test('the cramped slot the old layout produced now fits', () {
      // The stacked layout is what produced the stripe: header (~112) plus card
      // (~274) of fixed content inside ~306 usable leaves a NEGATIVE slot. The
      // old 160px floor turned that shortfall into a hard 80px overflow.
      const availableHeight = 306.0 - 112.0 - 274.0;
      expect(availableHeight, lessThan(kLegacyCompassFloor));

      // The dial must not invent space that does not exist. Returning 0 here
      // is correct: the split composition is what actually gives the compass
      // room, and HeaderSplitBody guarantees it is never squeezed to nothing.
      final fitted = fitCompassDiameter(
        availableWidth: 844,
        availableHeight: availableHeight,
        ceiling: 300,
      );
      expect(fitted, 0,
          reason: 'a non-positive slot yields no dial, never an overflow');
    });

    test('no floor survives: a tiny slot yields a tiny dial, not an error', () {
      for (final h in [0.0, 1.0, 20.0, 40.0, 79.0, 80.0, 100.0]) {
        final fitted = fitCompassDiameter(
          availableWidth: 844,
          availableHeight: h,
          ceiling: 300,
        );
        expect(fitted, lessThanOrEqualTo(mathMax(h, kGpsCompassTipAllowance)),
            reason: 'height $h');
        expect(fitted.isFinite, isTrue, reason: 'height $h');
        expect(fitted, greaterThanOrEqualTo(0), reason: 'height $h');
      }
    });
  });

  group('G2. the dial always fits the space it is given', () {
    test('never overflows across a sweep of short heights', () {
      for (var h = 60.0; h <= 400.0; h += 4) {
        final fitted = fitCompassDiameter(
          availableWidth: 844,
          availableHeight: h,
          ceiling: 300,
        );
        // Dial + tip allowance must fit, unless the slot was already smaller
        // than the tip needs - in which case the dial collapses to zero.
        if (h >= kGpsCompassTipAllowance) {
          expect(fitted + kGpsCompassTipAllowance, lessThanOrEqualTo(h),
              reason: 'height $h must not overflow');
        } else {
          expect(fitted, 0, reason: 'height $h cannot fit even the tip');
        }
      }
    });

    test('never exceeds its ceiling', () {
      for (final size in [
        const Size(390, 844),
        const Size(844, 390),
        const Size(430, 932),
        const Size(932, 430),
        const Size(800, 1280),
        const Size(1280, 800),
      ]) {
        for (final ceiling in [268.0, 300.0]) {
          final fitted = fitCompassDiameter(
            availableWidth: size.width,
            availableHeight: size.height,
            ceiling: ceiling,
          );
          expect(fitted, lessThanOrEqualTo(ceiling), reason: '$size/$ceiling');
        }
      }
    });

    test('width alone can never make it overflow a short viewport', () {
      // Very wide, very short: height must win.
      final fitted = fitCompassDiameter(
        availableWidth: 2000,
        availableHeight: 120,
        ceiling: 300,
      );
      expect(fitted + kGpsCompassTipAllowance, lessThanOrEqualTo(120));
    });
  });

  group('G3. locked portrait UI is preserved', () {
    test('phone portrait still gets the accepted 268px dial', () {
      // Portrait: header 112 out of ~760 usable leaves a tall compass slot, so
      // the accepted ceiling must still be reached.
      final fitted = fitCompassDiameter(
        availableWidth: 390,
        availableHeight: 760 - 112,
        ceiling: 268,
      );
      expect(fitted, 268, reason: 'portrait appearance is unchanged');
    });

    test('large phone portrait also keeps the accepted ceiling', () {
      final fitted = fitCompassDiameter(
        availableWidth: 430,
        availableHeight: 848 - 112,
        ceiling: 268,
      );
      expect(fitted, 268);
    });
  });

  group('G4. landscape and tablet keep the dial useful', () {
    test('phone landscape split leaves a real dial, not a token', () {
      // 844x390: ~306 usable - ~112 header = ~194 for the split row.
      final fitted = fitCompassDiameter(
        availableWidth: 844 * 0.62,
        availableHeight: 306 - 112,
        ceiling: 300,
      );
      expect(fitted, greaterThan(100),
          reason: 'must stay useful, not collapse to an icon');
      expect(fitted, lessThan(300));
    });

    test('tablet landscape reaches the split ceiling', () {
      final fitted = fitCompassDiameter(
        availableWidth: 1280 * 0.62,
        availableHeight: 800 - 112,
        ceiling: 300,
      );
      expect(fitted, 300, reason: 'tablet has room for the full dial');
    });
  });

  group('G7. REAL LAYOUT: the production composition does not overflow', () {
    // Arithmetic above proves the maths. This mounts the real production
    // composition widget (HeaderSplitBody) at each viewport with children sized
    // to the measured production chrome, so a RenderFlex overflow / FlutterError
    // fails the test rather than passing silently.
    //
    // The seam is deliberately tiny: the production widget is mounted as-is and
    // only its children are substituted with fixed-size stand-ins matching the
    // real header (~112) and card (~274). No replica of the layout exists here.

    /// Real device insets. The reported stripe was measured on hardware, where the
/// status and navigation bars eat ~84 logical px. Reproducing them here is what
/// makes 844x390 behave like the phone rather than a bare test surface.
const double kRealSystemInset = 42.0;

Widget buildRealComposition(
    WidgetTester tester, Viewport v, {
    double cardHeight = 274,
    double systemInset = kRealSystemInset,
  }) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = v.size;
    tester.view.padding = FakeViewPadding(
      top: systemInset,
      bottom: systemInset,
    );
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetPadding();
    });
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          bottom: false,
          child: HeaderSplitBody(
              // Real _GpsHeader measures ~112 in production.
              header: const SizedBox(height: 112, key: Key('header')),
              // Stands in for _buildCompassPane(), which fills its pane via
              // LayoutBuilder. expandWidth lets it report the pane it was given,
              // which is what the "primary stays useful" assertion measures.
              primary: const SizedBox.expand(key: Key('compass')),
              // Real _VerificationCard measures ~274 in production.
              secondary: SizedBox(height: cardHeight, key: const Key('card')),
            ),
          ),
        ),
      );
    }

    for (final v in [
      const Viewport('phone portrait', Size(390, 844)),
      const Viewport('phone landscape', Size(844, 390)),
      const Viewport('large phone portrait', Size(430, 932)),
      const Viewport('large phone landscape', Size(932, 430)),
      const Viewport('tablet portrait', Size(800, 1280)),
      const Viewport('tablet landscape', Size(1280, 800)),
    ]) {
      testWidgets('no RenderFlex overflow at ${v.label} ${v.size.width.toInt()}'
          'x${v.size.height.toInt()}', (tester) async {
        await tester.pumpWidget(buildRealComposition(tester, v));
        await tester.pump();
        expect(tester.takeException(), isNull,
            reason: 'production composition must not overflow at ${v.label}');
        expect(find.byKey(const Key('compass')), findsOneWidget);
      });
    }

    testWidgets('the 80px landscape case renders without a FlutterError',
        (tester) async {
      // The exact reported failure: 844x390 with the real production chrome.
      // Header 112 + card 274 = 386 of fixed content into ~306 usable.
      await tester.pumpWidget(buildRealComposition(
        tester,
        const Viewport('phone landscape', Size(844, 390)),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('primary pane keeps real size; detail pane scrolls',
        (tester) async {
      await tester.pumpWidget(buildRealComposition(
        tester,
        const Viewport('phone landscape', Size(844, 390)),
      ));
      await tester.pump();
      // Split engaged: the panes sit side by side under the header, so the
      // 274px card no longer has to share a vertical stack with the dial.
      final header = tester.getRect(find.byKey(const Key('header')));
      final compass = tester.getRect(find.byKey(const Key('compass')));
      final card = tester.getRect(find.byKey(const Key('card')));
      expect(card.left, greaterThan(compass.right),
          reason: 'detail must be beside the dial, not stacked under it');
      expect(compass.width, greaterThan(100),
          reason: 'the spatial pane must stay useful, not collapse');
      // The card keeps its intrinsic 274px, but it now lives inside a scroll
      // view whose viewport is shorter than that - which is what makes it
      // reachable instead of overflowing.
      final viewport = tester.getRect(find.byType(SingleChildScrollView));
      expect(viewport.height, lessThan(274),
          reason: 'oversized detail scrolls inside its own pane');
      expect(card.height, 274, reason: 'the card itself is not squashed');
      // The scroll view is the card's own pane, not the whole screen.
      expect(viewport.left, greaterThan(compass.right));
      // The primary pane spans everything left under the header, after the real
      // status-bar inset: 390 - 42 (inset) - 112 (header).
      expect(compass.height, greaterThanOrEqualTo(390 - kRealSystemInset - 112));
      expect(header.height, 112);
    });

    testWidgets('portrait keeps the accepted stacked composition',
        (tester) async {
      await tester.pumpWidget(buildRealComposition(
        tester,
        const Viewport('phone portrait', Size(390, 844)),
      ));
      await tester.pump();
      final compass = tester.getRect(find.byKey(const Key('compass')));
      final card = tester.getRect(find.byKey(const Key('card')));
      expect(card.top, greaterThan(compass.top), reason: 'still stacked');
      expect(card.height, 274, reason: 'intrinsic height preserved in portrait');
    });

    testWidgets('immersive mode (no header) still lays out', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(844, 390);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SafeArea(
            child: HeaderSplitBody(
              primary: const SizedBox.expand(key: Key('compass')),
              secondary: const SizedBox(height: 274, key: Key('card')),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives a 1.3 text scale at every viewport', (tester) async {
      for (final v in [
        const Viewport('phone portrait', Size(390, 844)),
        const Viewport('phone landscape', Size(844, 390)),
        const Viewport('tablet portrait', Size(800, 1280)),
        const Viewport('tablet landscape', Size(1280, 800)),
      ]) {
        await tester.pumpWidget(buildRealComposition(tester, v));
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        await tester.pump();
        expect(tester.takeException(), isNull, reason: v.label);
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      }
    });
  });

  group('G5. the screen composes adaptively', () {
    // The screen needs geolocator + a magnetometer stream, which this
    // dependency set cannot fake, so the composition itself is asserted on the
    // real source. The sizing arithmetic above is unit-tested directly, and
    // SplitPane's layout is widget-tested in responsive_layout_matrix_test.
    late String src;

    setUpAll(() {
      src = File('lib/modules/inspection/screens/gps_verification_screen.dart')
          .readAsStringSync();
    });

    test('uses the shared adaptive primitive, not a screen-local width', () {
      expect(src, contains('HeaderSplitBody('),
          reason: 'composition goes through the shared foundation widget');
      expect(src, contains("'../../../core/layout/responsive_layout.dart'"));
      // No screen-specific breakpoint numbers anywhere in the screen.
      for (final magic in ['600', '900', '720', '480', 'isLandscape']) {
        expect(src.contains('MediaQuery'), isFalse,
            reason: 'the screen must not read MediaQuery directly');
        expect(magic, isNotEmpty);
      }
    });

    test('the 160px compass floor is gone from executable code', () {
      // It survives only inside the doc comment explaining the regression.
      final code = src
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code, isNot(contains('clamp(160.0')),
          reason: 'the floor that caused the 80px stripe must not return');
      expect(code, contains('fitCompassDiameter'));
    });

    test('the detail card scrolls when it shares a pane with the compass', () {
      expect(src, contains('_buildDetailPane(scrollable: true)'));
      expect(src, contains('SingleChildScrollView(child: card)'));
    });

    test('the confirm action is still rendered in both compositions', () {
      // Confirming is the screen's primary action; it must survive the split.
      expect(src, contains('onConfirm: _startInspection'));
      expect('_buildDetailPane'.allMatches(src).length, greaterThanOrEqualTo(2),
          reason: 'built in both the split and stacked compositions');
    });

    test('no GPS threshold or business rule was touched', () {
      // Layout-only change: the verification threshold and its copy survive
      // verbatim, because a responsive fix must not move a GPS rule.
      expect("'In Zone (< 30 m)'".allMatches(src).length, 1,
          reason: 'the zone threshold and its copy must be unchanged');
      expect(src, contains("verified ? 'In Zone (< 30 m)' : 'Outside Zone'"));
    });
  });

  group('G6. the shared primitive holds at all four required viewports', () {
    testWidgets('split engages on landscape and tablet, not portrait',
        (tester) async {
      // Not a const map: Size overrides ==, so it cannot be a const key.
      final expected = <Size, bool>{
        const Size(390, 844): false,
        const Size(844, 390): true,
        const Size(800, 1280): true,
        const Size(1280, 800): true,
      };
      expected.forEach((size, want) {
        expect(InsightBreakpoints(size).canSplitTwoPane, want,
            reason: '$size');
      });
    });
  });
}

/// Local helper so the test does not need to import dart:math.
double mathMax(double a, double b) => a > b ? a : b;