import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_coordinator.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_overlay.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_preferences.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_script.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_targets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/interactive_guide_overlay_harness.dart';
import 'support/interactive_guide_test_support.dart';

void main() {
  setUpAll(prepareGuideTestFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  GuideCoordinator coordinator() => GuideCoordinator(
    inspectorId: '11111111-1111-4111-8111-111111111111',
    preferences: GuidePreferences(),
    canPresent: () => true,
  );

  testWidgets(
    'portrait invitation is complete and active explanations open through details',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      final guide = coordinator();
      final targets = GuideTargetRegistry();
      await guide.offerIfEligible();
      await tester.pumpWidget(guideOverlayHarness(guide, targets));
      await tester.pumpAndSettle();
      void wholeMessage(String id, String message) {
        final viewport = tester.getRect(
          find.byKey(ValueKey('guide-copy-$id-english')),
        );
        final text = tester.getRect(find.text(message));
        expect(
          viewport.intersect(text),
          text,
          reason:
              'Normal portrait has room; do not force-scroll the main explanation',
        );
      }

      wholeMessage('invitation', guideInvitationEnglish.message);
      await guide.start(GuideLanguage.english);
      final stop = guideStops.singleWhere((stop) => stop.id == 'G15');
      while (guide.stopIndex < guideStops.indexOf(stop)) {
        guide.next();
      }
      await tester.pumpAndSettle();
      wholeMessage('G15', stop.english.summary!);
      expect(find.text(stop.english.message), findsNothing);
      await tester.tap(find.byKey(const ValueKey('guide-details')));
      await tester.pumpAndSettle();
      expect(find.text(stop.english.message), findsOneWidget);
      expect(guideStops[guide.stopIndex].id, 'G15');
      await disposeGuideOverlay(tester, guide, targets);
    },
  );

  testWidgets(
    'offscreen targets scroll safely and Skip restores the real scroll offset',
    (tester) async {
      final guide = coordinator();
      final targets = GuideTargetRegistry();
      final scroll = ScrollController();
      await guide.start(GuideLanguage.english);
      guide.next();
      await tester.pumpWidget(
        guideOverlayHarness(
          guide,
          targets,
          content: SingleChildScrollView(
            controller: scroll,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: const Column(
              children: [
                SizedBox(height: 550),
                GuideTarget(
                  id: 'home_content',
                  child: SizedBox(height: 60, child: Text('Offscreen target')),
                ),
                SizedBox(height: 700),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      await tester.tap(find.byKey(const ValueKey('guide-skip')));
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      await disposeGuideOverlay(tester, guide, targets);
      scroll.dispose();
    },
  );

  testWidgets(
    'a resize between sample pointer-down and pointer-up cannot use old bounds',
    (tester) async {
      final guide = coordinator();
      final targets = GuideTargetRegistry();
      await guide.start(GuideLanguage.english);
      while (guide.stopIndex <
          guideStops.indexWhere((stop) => stop.id == 'G15')) {
        guide.next();
      }
      await tester.pumpWidget(guideOverlayHarness(guide, targets));
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('guide-task-proxy'))),
      );
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(guideStops[guide.stopIndex].id, 'G15');
      await disposeGuideOverlay(tester, guide, targets);
    },
  );

  testWidgets(
    'invitation exposes both languages and Not Now immediately dismisses it',
    (tester) async {
      final guide = coordinator();
      final targets = GuideTargetRegistry();
      await guide.offerIfEligible();
      await tester.pumpWidget(guideOverlayHarness(guide, targets));
      await tester.pumpAndSettle();
      expect(find.text('Filipino (Tagalog)'), findsOneWidget);
      expect(find.text('English'), findsAtLeastNWidgets(1));
      await tester.tap(find.text('Filipino (Tagalog)'));
      await tester.pumpAndSettle();
      expect(find.text('Simulan ang Gabay'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('guide-not-now')));
      await tester.pumpAndSettle();
      expect(guide.phase, GuidePhase.idle);
      expect(find.byKey(const ValueKey('guide-coach')), findsNothing);
      expect(
        (await GuidePreferences().read(guide.inspectorId))?.status,
        GuideStatus.skipped,
      );
      await disposeGuideOverlay(tester, guide, targets);
    },
  );

  testWidgets(
    'coach controls and body win priority; cutout never activates the app',
    (tester) async {
      final guide = coordinator();
      final targets = GuideTargetRegistry();
      var realActions = 0;
      await guide.start(GuideLanguage.english);
      await tester.pumpWidget(
        guideOverlayHarness(guide, targets, realAction: () => realActions++),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('guide-back')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text(guideStops.first.english.summary!));
      expect(guide.stopIndex, 0);
      await tester.tap(find.byKey(const ValueKey('guide-next')));
      await tester.pumpAndSettle();
      expect(guide.stopIndex, 1);
      await tester.tapAt(const Offset(80, 68));
      await tester.pumpAndSettle();
      expect(realActions, 0);
      await tester.tap(find.byKey(const ValueKey('guide-skip')));
      await tester.pumpAndSettle();
      expect(guide.phase, GuidePhase.idle);
      expect(tester.hasRunningAnimations, isFalse);
      await disposeGuideOverlay(tester, guide, targets);
    },
  );

  testWidgets(
    'spotlight equals actual rendered bounds and stays disjoint from coach',
    (tester) async {
      final guide = coordinator();
      final targets = GuideTargetRegistry();
      await guide.start(GuideLanguage.english);
      guide.next();
      await tester.pumpWidget(guideOverlayHarness(guide, targets));
      await tester.pumpAndSettle();
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('guide-scrim')),
                  )
                  .painter!
              as GuideScrimPainter;
      final target = tester.getRect(
        find.widgetWithText(FilledButton, 'Real control'),
      );
      expect(painter.target, target.inflate(6));
      expect(
        tester
            .getRect(find.byKey(const ValueKey('guide-coach')))
            .overlaps(painter.target!),
        isFalse,
      );
      await disposeGuideOverlay(tester, guide, targets);
    },
  );

  testWidgets('sample proxy and Next use the same tutorial transition', (
    tester,
  ) async {
    for (final tapSample in [true, false]) {
      final guide = coordinator();
      final targets = GuideTargetRegistry();
      var sampleOpens = 0;
      await guide.start(GuideLanguage.english, replay: true);
      while (guide.stopIndex <
          guideStops.indexWhere((stop) => stop.id == 'G15')) {
        guide.next();
      }
      await tester.pumpWidget(
        guideOverlayHarness(
          guide,
          targets,
          openSample: () {
            sampleOpens++;
            guide.next();
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        tapSample
            ? find.byKey(const ValueKey('guide-task-proxy'))
            : find.byKey(const ValueKey('guide-next')),
      );
      await tester.pumpAndSettle();
      expect(sampleOpens, 1);
      expect(guideStops[guide.stopIndex].id, 'G16');
      await disposeGuideOverlay(tester, guide, targets);
    }
  });

  testWidgets('background zones protect the OS edge and clamp the first stop', (
    tester,
  ) async {
    final guide = coordinator();
    final targets = GuideTargetRegistry();
    await guide.start(GuideLanguage.english);
    await tester.pumpWidget(
      guideOverlayHarness(
        guide,
        targets,
        gestureInsets: const EdgeInsets.symmetric(horizontal: 24),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(8, 100));
    await tester.tapAt(const Offset(50, 100));
    expect(guide.stopIndex, 0);
    final coach = tester.getRect(find.byKey(const ValueKey('guide-coach')));
    final background = Offset(750, coach.top > 36 ? 24 : coach.bottom + 16);
    expect(coach.contains(background), isFalse);
    await tester.tapAt(background);
    await tester.pumpAndSettle();
    expect(guide.stopIndex, 1);
    await disposeGuideOverlay(tester, guide, targets);
  });

  testWidgets(
    'OS gesture edges never activate a fully highlighted sample card',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(432, 960);
      addTearDown(tester.view.reset);
      final guide = coordinator();
      final targets = GuideTargetRegistry();
      await guide.start(GuideLanguage.english);
      while (guide.stopIndex <
          guideStops.indexWhere((stop) => stop.id == 'G15')) {
        guide.next();
      }
      await tester.pumpWidget(
        guideOverlayHarness(
          guide,
          targets,
          scaler: const TextScaler.linear(.85),
          gestureInsets: const EdgeInsets.symmetric(horizontal: 34),
          content: const Positioned(
            left: 20,
            right: 20,
            top: 40,
            child: GuideTarget(
              id: 'guide_task_card',
              child: SizedBox(height: 200),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scrim =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('guide-scrim')),
                  )
                  .painter!
              as GuideScrimPainter;
      expect(scrim.target!.left, lessThanOrEqualTo(20));
      expect(scrim.target!.right, greaterThanOrEqualTo(412));
      for (final x in [24.0, 408.0]) {
        await tester.tapAt(Offset(x, 80));
        await tester.pumpAndSettle();
        expect(guideStops[guide.stopIndex].id, 'G15');
      }
      await tester.tap(find.byKey(const ValueKey('guide-task-proxy')));
      await tester.pumpAndSettle();
      expect(guideStops[guide.stopIndex].id, 'G16');
      await disposeGuideOverlay(tester, guide, targets);
    },
  );

  testWidgets(
    'Android Back ends only the guide and Done completes the last stop',
    (tester) async {
      final guide = coordinator();
      final targets = GuideTargetRegistry();
      await guide.start(GuideLanguage.english);
      await tester.pumpWidget(guideOverlayHarness(guide, targets));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(guide.phase, GuidePhase.idle);
      expect(find.byType(Scaffold), findsOneWidget);
      await guide.start(GuideLanguage.english, replay: true);
      for (var i = 0; i < guideStops.length - 1; i++) {
        guide.next();
      }
      await tester.pumpAndSettle();
      expect(find.text('Done'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('guide-next')));
      await tester.pumpAndSettle();
      expect(
        (await GuidePreferences().read(guide.inspectorId))?.status,
        GuideStatus.completed,
      );
      await disposeGuideOverlay(tester, guide, targets);
    },
  );

  testWidgets(
    'reduced motion is static and keyboard focus cannot reach the app',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final guide = coordinator();
      final targets = GuideTargetRegistry();
      await guide.start(GuideLanguage.english);
      await tester.pumpWidget(guideOverlayHarness(guide, targets));
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.bySemanticsLabel('Real Quick Actions'), findsNothing);
      for (var i = 0; i < 10; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<GuideOverlay>(),
          isNotNull,
        );
      }
      await disposeGuideOverlay(tester, guide, targets);
      semantics.dispose();
    },
  );

  testWidgets(
    'welcome and stage beacons run once and Skip cancels an active pulse',
    (tester) async {
      final guide = coordinator();
      final targets = GuideTargetRegistry();
      await guide.start(GuideLanguage.english);
      await tester.pumpWidget(
        guideOverlayHarness(guide, targets, reducedMotion: false),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
      expect(guide.stopIndex, 0);
      expect(tester.hasRunningAnimations, isFalse);
      for (var i = 0; i < 4; i++) {
        guide.next();
      }
      await tester.pump();
      expect(tester.hasRunningAnimations, isTrue);
      await guide.skip();
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
      await disposeGuideOverlay(tester, guide, targets);
    },
  );

  testWidgets('Skip restores keyboard focus to the retained launch control', (
    tester,
  ) async {
    final guide = coordinator();
    final targets = GuideTargetRegistry();
    final launchFocus = FocusNode();
    await tester.pumpWidget(
      guideOverlayHarness(
        guide,
        targets,
        content: TextButton(
          focusNode: launchFocus,
          onPressed: () {},
          child: const Text('Launch entry'),
        ),
      ),
    );
    launchFocus.requestFocus();
    await tester.pump();
    await guide.start(GuideLanguage.english);
    await tester.pumpAndSettle();
    expect(launchFocus.hasFocus, isFalse);
    await guide.skip();
    await tester.pumpAndSettle();
    expect(launchFocus.hasFocus, isTrue);
    await disposeGuideOverlay(tester, guide, targets);
    launchFocus.dispose();
  });
}
