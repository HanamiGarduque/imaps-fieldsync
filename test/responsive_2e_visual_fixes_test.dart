import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:imaps_fieldsync/core/layout/responsive_layout.dart';
import 'package:imaps_fieldsync/core/widgets/insight_bottom_nav.dart';
import 'package:imaps_fieldsync/core/widgets/quick_actions_sheet.dart';
import 'package:imaps_fieldsync/modules/inspection/widgets/inspection_step_header.dart';

/// Phase 2E — landscape / tablet cleanup.
///
/// These cover the specific defects reported from real-device landscape review:
/// the GPS overflow that survived the split (a short *stacked* viewport), the
/// quick-actions panel overlapping the nav trigger, and the decorative blue orb
/// backgrounds.

void setViewport(WidgetTester tester, Size size, {double textScale = 1.0}) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  tester.view.padding = FakeViewPadding(top: 42, bottom: 42);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

const matrix = <Size>[
  Size(390, 844),
  Size(844, 390),
  Size(430, 932),
  Size(932, 430),
  Size(800, 1280),
  Size(1280, 800),
];

/// Real production chrome: GPS header ~112, verification card ~274.
const double kGpsHeader = 112;
const double kGpsCard = 274;

void main() {
  group('E1. GPS stacked path cannot overflow at any real size', () {
    // The defect: at a width under the split threshold the layout stacks, and
    // header 112 + card 274 exceed a short body. The compass pane then received
    // zero height and its tip overflowed ("BOTTOM OVERFLOWED BY 44 PIXELS").
    // HeaderSplitBody now bounds the secondary pane instead of trusting its
    // intrinsic height.
    for (final size in matrix) {
      testWidgets('no overflow at ${size.width.toInt()}x${size.height.toInt()}',
          (tester) async {
        setViewport(tester, size);
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: SafeArea(
              child: HeaderSplitBody(
                header: const SizedBox(height: kGpsHeader, key: Key('hdr')),
                primary: const SizedBox.expand(key: Key('compass')),
                secondary: const SizedBox(height: kGpsCard, key: Key('card')),
              ),
            ),
          ),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$size');
      });
    }

    testWidgets('a short stacked viewport bounds the card and scrolls it',
        (tester) async {
      // 640x360: below the split width, so stacked, with the least height a
      // real phone reports in landscape.
      setViewport(tester, const Size(640, 360));
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SafeArea(
            child: HeaderSplitBody(
              header: const SizedBox(height: kGpsHeader),
              primary: const SizedBox.expand(key: Key('compass')),
              secondary: const SizedBox(height: kGpsCard, key: Key('card')),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      // The card must be inside a scroll view, not overflowing.
      expect(
        find.descendant(
          of: find.byType(Flexible),
          matching: find.byType(SingleChildScrollView),
        ),
        findsWidgets,
      );
    });

    testWidgets('the detail card still gets its full height when there is room',
        (tester) async {
      // Portrait is unchanged: the loose Flexible fits lets the card keep its
      // intrinsic height exactly as accepted.
      setViewport(tester, const Size(390, 844));
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SafeArea(
            child: HeaderSplitBody(
              header: const SizedBox(height: kGpsHeader),
              primary: const SizedBox.expand(),
              secondary: const SizedBox(height: kGpsCard, key: Key('card')),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.getRect(find.byKey(const Key('card'))).height, kGpsCard);
    });

    test('the split width threshold still guards the split', () {
      // Under 720 wide it stacks; the stack is now safe, not merely "hopefully".
      expect(InsightBreakpoints(const Size(640, 360)).canSplitTwoPane, isFalse);
      expect(InsightBreakpoints(const Size(844, 390)).canSplitTwoPane, isTrue);
    });
  });

  group('E2. quick actions clears the nav trigger', () {
    test('the host offset is derived from the nav, not guessed', () {
      // 10 padding + 64 rail + 12 gap + 64 trigger band + 12 clearance.
      expect(
        kInsightBottomNavTriggerClearance,
        10 + 64 + 12 + 64 + 64 + 12,
      );
      // The trigger occupies offsets 150..214. The old hardcoded 190 fell
      // inside that band, which is why the panel sat on top of the button.
      expect(kInsightBottomNavTriggerClearance, greaterThan(190));
    });

    testWidgets('the panel bottom sits above the trigger top', (tester) async {
      setViewport(tester, const Size(844, 390));
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Stack(
            children: [
              const Positioned.fill(child: SizedBox()),
              // The nav's trigger, positioned exactly as the nav does.
              Positioned(
                right: 0,
                bottom: 10 + 64 + 12 + 64,
                child: const SizedBox(width: 64, height: 64, key: Key('trigger')),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: kInsightBottomNavTriggerClearance,
                child: QuickActionsSheet(
                  actions: [
                    for (final t in ['Site Map', 'Compass', 'Analytics'])
                      QuickAction(icon: Icons.circle_outlined, title: t, onTap: () {}),
                  ],
                  onClose: () {},
                ),
              ),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final trigger = tester.getRect(find.byKey(const Key('trigger')));
      final panel = tester.getRect(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.padding == const EdgeInsets.fromLTRB(8, 6, 8, 10),
        ),
      );
      expect(panel.bottom, lessThanOrEqualTo(trigger.top),
          reason: 'the panel must not sit on top of the trigger');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the panel is bounded, not full-bleed', (tester) async {
      for (final size in [const Size(844, 390), const Size(1280, 800)]) {
        setViewport(tester, size);
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: Stack(
              children: [
                const Positioned.fill(child: SizedBox()),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: kInsightBottomNavTriggerClearance,
                  child: QuickActionsSheet(
                    actions: [
                      for (final t in ['Site Map', 'Compass'])
                        QuickAction(
                            icon: Icons.circle_outlined, title: t, onTap: () {}),
                    ],
                    onClose: () {},
                  ),
                ),
              ],
            ),
          ),
        ));
        await tester.pumpAndSettle();
        final panel = tester.getRect(
          find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.padding == const EdgeInsets.fromLTRB(8, 6, 8, 10),
          ),
        );
        expect(panel.width, lessThanOrEqualTo(kPanelMaxWidth),
            reason: 'bounded at $size');
        expect(tester.takeException(), isNull, reason: '$size');
      }
    });

    testWidgets('no action is clipped in landscape', (tester) async {
      setViewport(tester, const Size(844, 390));
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Stack(
            children: [
              const Positioned.fill(child: SizedBox()),
              Positioned(
                left: 16,
                right: 16,
                bottom: kInsightBottomNavTriggerClearance,
                child: QuickActionsSheet(
                  actions: [
                    for (final t in [
                      'Site Map',
                      'Compass',
                      'Analytics Overview',
                      'Sync History',
                      'Edit Profile'
                    ])
                      QuickAction(
                          icon: Icons.circle_outlined, title: t, onTap: () {}),
                  ],
                  onClose: () {},
                ),
              ),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
      for (final t in [
        'Site Map',
        'Compass',
        'Analytics Overview',
        'Sync History',
        'Edit Profile'
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('E3. map detail panels are map-first and collapsible', () {
    testWidgets('side pane in landscape, map keeps the primary share',
        (tester) async {
      setViewport(tester, const Size(844, 390));
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Stack(
            children: [
              const Positioned.fill(child: SizedBox(key: Key('map'))),
              Positioned.fill(
                child: MapDetailPanel(
                  child: Container(
                    key: const Key('panel'),
                    height: 200,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ));
      await tester.pump();
      final map = tester.getRect(find.byKey(const Key('map')));
      final panel = tester.getRect(find.byKey(const Key('panel')));
      expect(panel.left, greaterThan(map.width * 0.5),
          reason: 'the panel is a side pane, not a bottom overlay');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the collapse control hides the panel and restores it',
        (tester) async {
      setViewport(tester, const Size(844, 390));
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Stack(
            children: [
              const Positioned.fill(child: SizedBox(key: Key('map'))),
              Positioned.fill(
                child: MapDetailPanel(
                  child: Container(
                    key: const Key('panel'),
                    height: 200,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ));
      await tester.pump();
      expect(find.byKey(const Key('panel')), findsOneWidget);
      // The toggle is always present and reachable.
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('panel')), findsNothing,
          reason: 'hidden so the map is fully visible');
      expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.keyboard_arrow_up_rounded));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('panel')), findsOneWidget);
    });

    testWidgets('the toggle keeps a 48px touch target', (tester) async {
      setViewport(tester, const Size(844, 390));
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Stack(
            children: [
              const Positioned.fill(child: SizedBox()),
              Positioned.fill(
                child: MapDetailPanel(child: Container(height: 100)),
              ),
            ],
          ),
        ),
      ));
      await tester.pump();
      final t = tester.getRect(find.byIcon(Icons.keyboard_arrow_down_rounded));
      expect(t.width, greaterThanOrEqualTo(InsightBreakpoints.minTouchTarget));
      expect(t.height, greaterThanOrEqualTo(InsightBreakpoints.minTouchTarget));
    });

    testWidgets('portrait keeps the floating card and still collapses',
        (tester) async {
      setViewport(tester, const Size(390, 844));
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Stack(
            children: [
              const Positioned.fill(child: SizedBox()),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: MapDetailPanel(
                  child: Container(key: const Key('panel'), height: 120),
                ),
              ),
            ],
          ),
        ),
      ));
      await tester.pump();
      expect(find.byKey(const Key('panel')), findsOneWidget);
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('panel')), findsNothing);
    });

    test('map and quick-action-map use the shared panel', () {
      for (final f in [
        'lib/modules/inspection/screens/site_map_screen.dart',
        'lib/modules/inspection/screens/site_map_preview_screen.dart',
      ]) {
        final src = File(f).readAsStringSync();
        expect(src, contains('MapDetailPanel'), reason: f);
      }
      // The guessed recenter offset is gone from the preview screen.
      final preview =
          File('lib/modules/inspection/screens/site_map_preview_screen.dart')
              .readAsStringSync();
      expect(preview, isNot(contains('bottom: 210')));
      expect(preview, contains('kInsightBottomNavReserve'));
    });

    test('map CTA and routing logic are untouched', () {
      final src =
          File('lib/modules/inspection/screens/site_map_screen.dart')
              .readAsStringSync();
      expect(src, contains('Proceed to Location'));
      expect(src, contains('PolylineLayer'));
      expect(src, contains('_routePoints'));
      expect(src, contains('_distanceMeters'));
      expect(src, contains('markStepComplete(1)'));
      // Content-sized, so no dead space below the CTA.
      expect(src, contains('mainAxisSize: MainAxisSize.min'));
    });
  });

  group('E4. inspection step chrome collapses in landscape', () {
    testWidgets('portrait keeps the full accepted header', (tester) async {
      setViewport(tester, const Size(390, 844));
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: InspectionStepHeader(
            title: 'Zoning Checklist',
            subtitle: 'Step 4 of 6',
            stepNumber: 4,
            stepSubtitle: 'Verify ordinance',
            onBack: () {},
          ),
        ),
      ));
      await tester.pump();
      expect(find.text('Zoning Checklist'), findsOneWidget);
      expect(find.text('Step 4 of 6'), findsOneWidget);
      expect(find.textContaining('STEP 4 OF 6'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
    });

    testWidgets('landscape hides the banner but keeps the back button',
        (tester) async {
      setViewport(tester, const Size(844, 390));
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: InspectionStepHeader(
            title: 'Zoning Checklist',
            subtitle: 'Step 4 of 6',
            stepNumber: 4,
            stepSubtitle: 'Verify ordinance',
            onBack: () {},
          ),
        ),
      ));
      await tester.pump();
      // Essential control survives.
      expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
      // Nonessential chrome is hidden.
      expect(find.text('Zoning Checklist'), findsNothing);
      expect(find.text('Step 4 of 6'), findsNothing);
      expect(find.textContaining('STEP 4 OF 6'), findsNothing);
    });

    testWidgets('the collapsed header is much shorter', (tester) async {
      setViewport(tester, const Size(390, 844));
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: InspectionStepHeader(
            title: 'Zoning Checklist',
            subtitle: 'Step 4 of 6',
            stepNumber: 4,
            stepSubtitle: 'Verify ordinance',
            onBack: () {},
          ),
        ),
      ));
      await tester.pump();
      final tall = tester.getSize(find.byType(InspectionStepHeader)).height;

      setViewport(tester, const Size(844, 390));
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: InspectionStepHeader(
            title: 'Zoning Checklist',
            subtitle: 'Step 4 of 6',
            stepNumber: 4,
            stepSubtitle: 'Verify ordinance',
            onBack: () {},
          ),
        ),
      ));
      await tester.pump();
      final short = tester.getSize(find.byType(InspectionStepHeader)).height;

      expect(short, lessThan(tall));
      // Only the 44px back button plus padding remains.
      expect(short, lessThan(90));
    });

    test('the flag defaults to the viewport, so call sites are unchanged', () {
      final src = File(
        'lib/modules/inspection/widgets/inspection_step_header.dart',
      ).readAsStringSync();
      expect(src, contains('compact ?? context.responsive.isShortHeight'));
      expect(src, contains('this.compact,'));
    });
  });

  group('E5. decorative blue orb backgrounds removed', () {
    const cleaned = {
      'lib/modules/profile_settings/screens/notifications_screen.dart',
      'lib/modules/profile_settings/screens/about_insight_screen.dart',
      'lib/modules/profile_settings/screens/terms_privacy_screen.dart',
      'lib/modules/profile_settings/screens/profile_edit_screen.dart',
      'lib/modules/profile_settings/screens/help_faq_screen.dart',
      'lib/modules/profile_settings/widgets/faq_widgets.dart',
      'lib/modules/inspection/screens/inspection_result_screen.dart',
    };

    test('no large decorative orb remains on the info pages', () {
      for (final f in cleaned) {
        final src = File(f).readAsStringSync();
        // The page-sized blurred circles are gone.
        expect(src, isNot(contains('sigmaX: 40')), reason: f);
        expect(src, isNot(contains('sigmaX: 45')), reason: f);
        expect(src, isNot(contains('sigmaX: 50')), reason: f);
        expect(src, isNot(contains('alpha: 0.20')), reason: f);
        expect(src, isNot(contains('backgroundBlob')), reason: f);
      }
    });

    test('the small legitimate blurs (glass surfaces) are preserved', () {
      // These are functional frosted-glass chrome, not decoration, and must
      // survive: sigma 12/16 on back buttons and pills.
      for (final f in cleaned) {
        final src = File(f).readAsStringSync();
        for (final keep in ['sigmaX: 12', 'sigmaX: 16']) {
          if (src.contains(keep)) {
            expect(src, isNot(contains('width: 260')), reason: '$f $keep');
          }
        }
      }
    });

    test('notification indicators are not background decoration', () {
      final notif = File(cleaned.first).readAsStringSync();
      expect(notif, isNot(contains('ImageFilter.blur(sigmaX: 40')));
    });

    test('the shared shell orbs stay removed', () {
      final shell =
          File('lib/core/navigation/main_shell_screen.dart').readAsStringSync();
      expect(shell, isNot(contains('sigmaX: 60')));
    });
  });
}
