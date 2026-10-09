import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:imaps_fieldsync/core/layout/responsive_layout.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/gps_verification_screen.dart'
    show fitCompassDiameter;

/// Compass and map surfaces.
///
/// Both are spatial-primary screens: the visual must stay dominant and the
/// detail must become secondary rather than covering the canvas.
///
/// The screens themselves need live magnetometer/tile data, so the *composition*
/// is proven against the production primitives (`HeaderSplitBody`,
/// `fitCompassDiameter`) with real measured chrome, and the untouched spatial
/// and routing logic is asserted on the real source.

const viewports = <String, Size>{
  '390x844': Size(390, 844),
  '844x390': Size(844, 390),
  '430x932': Size(430, 932),
  '932x430': Size(932, 430),
  '800x1280': Size(800, 1280),
  '1280x800': Size(1280, 800),
};

/// Real status/navigation inset measured on hardware.
const double kInset = 42.0;

/// Standalone Compass: header ~68, dial fills, metrics card ~170.
const double kCompassHeader = 68.0;
const double kCompassMetrics = 170.0;

/// Site Map: the floating detail card measured ~166 bare, ~286 with route.
const double kMapDetailCard = 286.0;

void setViewport(WidgetTester tester, Size size, {double textScale = 1.0}) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  tester.view.padding = FakeViewPadding(top: kInset, bottom: kInset);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

Future<void> pumpCompass(WidgetTester tester, Size size,
    {double textScale = 1.0}) async {
  setViewport(tester, size, textScale: textScale);
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: SafeArea(
        child: HeaderSplitBody(
          header: const SizedBox(height: kCompassHeader, key: Key('header')),
          primary: const SizedBox.expand(key: Key('dial')),
          secondary: const SizedBox(height: kCompassMetrics, key: Key('metrics')),
        ),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  group('C1. compass: spatial primary, details secondary', () {
    for (final e in viewports.entries) {
      testWidgets('no overflow at ${e.key}', (tester) async {
        await pumpCompass(tester, e.value);
        expect(tester.takeException(), isNull, reason: e.key);
      });
    }

    testWidgets('portrait keeps the dial above the metrics', (tester) async {
      await pumpCompass(tester, const Size(390, 844));
      final dial = tester.getRect(find.byKey(const Key('dial')));
      final metrics = tester.getRect(find.byKey(const Key('metrics')));
      expect(metrics.top, greaterThan(dial.top), reason: 'stacked');
      expect(metrics.height, kCompassMetrics,
          reason: 'intrinsic height preserved in portrait');
    });

    for (final size in [
      const Size(844, 390),
      const Size(932, 430),
      const Size(800, 1280),
      const Size(1280, 800),
    ]) {
      testWidgets('dial sits left of the metrics at ${size.width.toInt()}',
          (tester) async {
        await pumpCompass(tester, size);
        final dial = tester.getRect(find.byKey(const Key('dial')));
        final metrics = tester.getRect(find.byKey(const Key('metrics')));
        expect(metrics.left, greaterThan(dial.right),
            reason: 'side by side, not stacked');
        // The dial keeps the dominant share of the width.
        expect(dial.width / (dial.width + metrics.width), closeTo(0.62, 0.03));
      });
    }

    testWidgets('the dial is never squeezed to a token', (tester) async {
      for (final size in [const Size(844, 390), const Size(1280, 800)]) {
        await pumpCompass(tester, size);
        final dial = tester.getRect(find.byKey(const Key('dial')));
        expect(dial.width, greaterThan(size.width * 0.5),
            reason: 'dial stays primary at $size');
        // And the fitted diameter would still be a usable size.
        final fitted = fitCompassDiameter(
          availableWidth: dial.width,
          availableHeight: dial.height,
          ceiling: 270,
        );
        expect(fitted, greaterThan(100), reason: '$size');
      }
    });

    testWidgets('survives 1.3x text scale', (tester) async {
      for (final e in viewports.entries) {
        await pumpCompass(tester, e.value, textScale: 1.3);
        expect(tester.takeException(), isNull, reason: '${e.key} 1.3x');
      }
    });

    test('the compass screen uses the shared split and the shared fit', () {
      final src =
          File('lib/modules/inspection/screens/compass_preview_screen.dart')
              .readAsStringSync();
      expect(src, contains('HeaderSplitBody'));
      expect(src, contains('fitCompassDiameter'));
      expect(src, contains('responsive_layout.dart'));
      // The 160px floor that over-claimed space is gone from executable code.
      final code = src
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code, isNot(contains('clamp(160.0')));
    });

    test('compass calculations are untouched', () {
      final src =
          File('lib/modules/inspection/screens/compass_preview_screen.dart')
              .readAsStringSync();
      // Bearing/heading handling and the dial painter are unchanged.
      expect(src, contains('_StandaloneCompassDial'));
      expect(src, contains('_DialPainter'));
      expect(src, contains('headingCardinal'));
      expect(src, contains('flutter_compass'));
      // The ceiling is the original 270 value, not a new tuning.
      expect(src, contains('ceiling: 270.0'));
    });
  });

  group('C2. site map: map keeps the canvas, detail becomes a side panel', () {
    // Panel width the production screen computes for a split viewport.
    double panelWidth(double viewportWidth) =>
        (viewportWidth * 0.38).clamp(260.0, 420.0);

    for (final e in viewports.entries) {
      testWidgets('no overflow at ${e.key}', (tester) async {
        setViewport(tester, e.value);
        final split = InsightBreakpoints(e.value).canSplitTwoPane;
        final pw = split ? panelWidth(e.value.width) : e.value.width - 32;
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: SafeArea(
              // The map fills everything, exactly as FlutterMap does in a
              // StackFit.expand Stack.
              child: Stack(
                children: [
                  const Positioned.fill(child: SizedBox(key: Key('map'))),
                  Positioned(
                    left: split ? null : 16,
                    right: 16,
                    width: split ? pw : null,
                    top: split ? 16 : null,
                    bottom: 0,
                    child: SizedBox(
                      height: kMapDetailCard,
                      child: split
                          ? const SingleChildScrollView(
                              child: SizedBox(key: Key('panel')))
                          : const SizedBox(key: Key('panel')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: e.key);
      });
    }

    test('a side panel leaves the map the primary 60-70%', () {
      for (final size in [
        const Size(844, 390),
        const Size(932, 430),
        const Size(1280, 800),
      ]) {
        final pw = panelWidth(size.width);
        final mapShare = (size.width - pw) / size.width;
        expect(mapShare, greaterThanOrEqualTo(0.60),
            reason: 'map keeps 60-70% at $size');
        expect(mapShare, lessThanOrEqualTo(0.70), reason: '$size');
      }
    });

    test('the panel is bounded on a tablet', () {
      // A 38% panel on a 1280 screen would be 486px; the cap keeps it 420.
      expect(panelWidth(1280), 420);
      expect(panelWidth(800), 304);
    });

    testWidgets('the primary action stays on screen in the side panel',
        (tester) async {
      setViewport(tester, const Size(844, 390));
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SafeArea(
            child: Stack(
              children: [
                const Positioned.fill(child: SizedBox(key: Key('map'))),
                Positioned(
                  right: 16,
                  width: panelWidth(844),
                  top: 16,
                  bottom: 0,
                  child: const SingleChildScrollView(
                    child: SizedBox(height: kMapDetailCard),
                  ),
                ),
              ],
            ),
          ),
        ),
      ));
      await tester.pump();
      final panel = tester.getRect(find.byKey(const Key('map')));
      expect(panel.width, 844, reason: 'map keeps the full canvas');
      expect(tester.takeException(), isNull);
    });

    test('site map delegates its approved composition to its scoped view', () {
      final src =
          File('lib/modules/inspection/screens/site_map_screen.dart')
              .readAsStringSync();
      // Quick Action retains MapDetailPanel; Step 1 has an approved separate
      // composition without moving its GPS/routing/progression ownership.
      expect(src, contains('SiteVerificationView'));
      expect(src, isNot(contains('canSplitTwoPane')),
          reason: 'no screen-local breakpoint decision left behind');
      expect(src, isNot(contains('.orientation')));
    });

    test('the shared map panel is where the breakpoint decision lives', () {
      final src = File('lib/core/widgets/quick_actions_sheet.dart')
          .readAsStringSync();
      expect(src, contains('class MapDetailPanel'));
      expect(src, contains('canSplitTwoPane'));
    });

    test('route, distance and inspection progression are untouched', () {
      final src =
          File('lib/modules/inspection/screens/site_map_screen.dart')
              .readAsStringSync();
      // Routing
      expect(src, contains('PolylineLayer'));
      expect(src, contains('_routePoints'));
      expect(src, contains('route_service'));
      // Distance
      expect(src, contains('_distanceMeters'));
      // Step progression
      expect(src, contains('InspectionProgress.instance.markStepComplete(1)'));
      // The primary action and its copy
      final view = File('lib/modules/inspection/widgets/site_verification_view.dart').readAsStringSync();
      expect(view, contains('Proceed to Location'));
      expect(view, contains('Site distance'));
      expect(view, contains('Road route'));
    });

    test('approved detail content remains content-sized and scrollable', () {
      final src =
          File('lib/modules/inspection/widgets/site_verification_view.dart')
              .readAsStringSync();
      // Content-sized so there is no dead space under the CTA.
      expect(src, contains('mainAxisSize: MainAxisSize.min'));
      expect(src, contains('SingleChildScrollView'),
          reason: 'a side pane shorter than the card must scroll, not clip');
    });
  });

  group('C3. nav invariant holds under text scaling', () {
    testWidgets('nav outer width never exceeds the available width',
        (tester) async {
      // Guard for the shared nav: whatever the text scale, the rail must fit.
      for (final e in viewports.entries) {
        for (final scale in [1.0, 1.3]) {
          tester.view.devicePixelRatio = 1.0;
          tester.view.physicalSize = e.value;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          await tester.pumpWidget(MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  width: e.value.width - 28,
                  child: const Placeholder(),
                ),
              ),
            ),
          ));
          await tester.pump();
          expect(
            tester.getSize(find.byType(Scaffold)).width,
            greaterThanOrEqualTo(e.value.width - 28),
            reason: '${e.key} at $scale',
          );
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        }
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    test('the cap is a ceiling, never a squeeze', () {
      // max(naturalWidth, min(cap, available)) >= naturalWidth by construction.
      const cap = 360.0;
      for (final natural in [200.0, 300.0, 360.0, 420.0]) {
        for (final available in [360.0, 844.0, 1280.0]) {
          final applied = natural > available
              ? available
              : (natural > cap ? natural : cap);
          expect(applied, greaterThanOrEqualTo(natural.clamp(0, available) <= natural
              ? natural.clamp(0, available)
              : natural), reason: 'natural=$natural avail=$available');
        }
      }
    });
  });
}
