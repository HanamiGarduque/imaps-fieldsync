import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_coordinator.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_overlay.dart';
import 'package:imaps_fieldsync/core/widgets/quick_actions_sheet.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_preferences.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_script.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_targets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/interactive_guide_overlay_harness.dart';
import 'support/interactive_guide_test_support.dart';

void main() {
  setUpAll(prepareGuideTestFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'large Tagalog arrow controls retain full localized spoken labels',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.reset);
      final guide = GuideCoordinator(
        inspectorId: '11111111-1111-4111-8111-111111111111',
        preferences: GuidePreferences(),
        canPresent: () => true,
      );
      final targets = GuideTargetRegistry();
      await guide.start(GuideLanguage.tagalog);
      await tester.pumpWidget(
        guideOverlayHarness(guide, targets, scaler: const TextScaler.linear(2)),
      );
      await tester.pumpAndSettle();
      final semantics = tester.ensureSemantics();
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('guide-next')))
            .tooltip,
        'Susunod',
      );
      expect(find.bySemanticsLabel('Susunod'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('guide-next'))).height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester.widget(find.byKey(const ValueKey('guide-details'))),
        isA<IconButton>(),
      );
      semantics.dispose();
      await disposeGuideOverlay(tester, guide, targets);
    },
  );
  testWidgets(
    'shared Quick Actions has five measured rows and no reduced-motion tickers',
    (tester) async {
      final targets = GuideTargetRegistry();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(800, 600),
              disableAnimations: true,
            ),
            child: Material(
              child: GuideTargetScope(
                registry: targets,
                child: QuickActionsSheet(
                  onClose: () {},
                  actions: [
                    for (final row in const [
                      ('Map', 'quick_map'),
                      ('Compass', 'quick_compass'),
                      ('Analytics overview', 'quick_analytics'),
                      ('Sync history', 'quick_sync'),
                      ('Edit profile', 'quick_profile'),
                    ])
                      QuickAction(
                        icon: Icons.help_outline,
                        title: row.$1,
                        guideTargetId: row.$2,
                        onTap: () {},
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 30));
      expect(tester.hasRunningAnimations, isFalse);
      for (final id in [
        'quick_map',
        'quick_compass',
        'quick_analytics',
        'quick_sync',
        'quick_profile',
      ]) {
        expect(targets.contextFor(id), isNotNull, reason: id);
      }
      await tester.pumpWidget(const SizedBox());
      targets.dispose();
    },
  );
  for (final size in const [
    Size(320, 568),
    Size(390, 844),
    Size(844, 390),
    Size(800, 1280),
    Size(1280, 800),
    Size(640, 320),
  ]) {
    testWidgets('coach and controls stay readable at $size / 2x text', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      final guide = GuideCoordinator(
        inspectorId: '11111111-1111-4111-8111-111111111111',
        preferences: GuidePreferences(),
        canPresent: () => true,
      );
      final targets = GuideTargetRegistry();
      await guide.start(GuideLanguage.tagalog);
      while (guide.stopIndex <
          guideStops.indexWhere((stop) => stop.id == 'G12')) {
        guide.next();
      }
      await tester.pumpWidget(
        guideOverlayHarness(guide, targets, scaler: const TextScaler.linear(2)),
      );
      await tester.pumpAndSettle();
      for (final key in ['guide-back', 'guide-next', 'guide-skip']) {
        final rect = tester.getRect(find.byKey(ValueKey(key)));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(size.height));
        expect(rect.height, greaterThanOrEqualTo(48));
      }
      final paint =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('guide-scrim')),
                  )
                  .painter!
              as GuideScrimPainter;
      final coach = tester.getRect(find.byKey(const ValueKey('guide-coach')));
      expect(paint.target == null || !coach.overlaps(paint.target!), isTrue);
      await disposeGuideOverlay(tester, guide, targets);
    });
  }

  testWidgets(
    'missing saved feature keeps its explanation without layout warnings or an unrelated cutout',
    (tester) async {
      final guide = GuideCoordinator(
        inspectorId: '11111111-1111-4111-8111-111111111111',
        preferences: GuidePreferences(),
        canPresent: () => true,
      );
      final targets = GuideTargetRegistry();
      await guide.start(GuideLanguage.english);
      guide.next();
      await tester.pumpWidget(
        guideOverlayHarness(guide, targets, content: const SizedBox()),
      );
      await tester.pumpAndSettle();
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('guide-scrim')),
                  )
                  .painter!
              as GuideScrimPainter;
      expect(painter.target, isNull);
      expect(find.textContaining('cannot be safely highlighted'), findsNothing);
      expect(
        find.text(guideStops[guide.stopIndex].english.summary!),
        findsOneWidget,
      );
      await disposeGuideOverlay(tester, guide, targets);
    },
  );

  testWidgets(
    'Android nonlinear text scaling retains readable controls without shrinking text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.reset);
      final guide = GuideCoordinator(
        inspectorId: '11111111-1111-4111-8111-111111111111',
        preferences: GuidePreferences(),
        canPresent: () => true,
      );
      final targets = GuideTargetRegistry();
      await guide.start(GuideLanguage.tagalog);
      await tester.pumpWidget(
        guideOverlayHarness(
          guide,
          targets,
          scaler: const GuideAndroid200TextScaler(),
        ),
      );
      await tester.pumpAndSettle();
      final next = find.byKey(const ValueKey('guide-next'));
      expect(
        MediaQuery.textScalerOf(tester.element(next)),
        isA<GuideAndroid200TextScaler>(),
      );
      expect(tester.getRect(next).bottom, lessThanOrEqualTo(568));
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(guide.stopIndex, 1);
      await disposeGuideOverlay(tester, guide, targets);
    },
  );
}
