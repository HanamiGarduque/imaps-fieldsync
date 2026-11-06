import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:imaps_fieldsync/modules/analytics_dashboard/screens/home_dashboard_screen.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_coordinator.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_host.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_overlay.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_preferences.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_script.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/interactive_guide_test_support.dart';
import 'support/offline_reliability_fixture.dart';

void main() {
  final fixture = OfflineReliabilityFixture();
  setUpAll(() async {
    await fixture.initialize();
    await prepareGuideTestFonts();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await fixture.reset();
  });
  tearDown(fixture.closeCase);
  tearDownAll(fixture.dispose);

  Future<GuideCoordinator> mount(
    WidgetTester tester,
    Size size,
    TextScaler scaler,
    GuideLanguage language,
    bool empty, {
    double pixelRatio = 1,
    EdgeInsets gestureInsets = EdgeInsets.zero,
  }) async {
    if (empty) await tester.runAsync(() => fixture.db.delete('local_jobs'));
    final guide = GuideCoordinator(
      inspectorId: offlineInspector,
      preferences: GuidePreferences(),
      canPresent: () => true,
    );
    await fixture.mount(
      tester,
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: scaler,
            disableAnimations: true,
            systemGestureInsets: gestureInsets,
          ),
          child: GuideHost(
            coordinator: guide,
            profile: UserProfile.fromMap(offlineProfile),
            preferredTaskId: offlineRound2,
            child: const Scaffold(body: Text('Retained actual origin')),
          ),
        ),
      ),
      size: size,
      showDebugBanner: false,
    );
    if (pixelRatio != 1) {
      tester.view.devicePixelRatio = pixelRatio;
      tester.view.physicalSize = size * pixelRatio;
      tester.view.padding = FakeViewPadding(
        top: 24 * pixelRatio,
        bottom: 24 * pixelRatio,
      );
      await tester.pump();
    }
    await guide.start(language, replay: true);
    await fixture.flush(tester);
    await tester.pumpAndSettle();
    return guide;
  }

  void visibleTarget(WidgetTester tester, GuideStop stop, Size size) {
    final overlay = tester.widget<GuideOverlay>(find.byType(GuideOverlay));
    final context = overlay.targets.contextFor(stop.targetId);
    expect(
      context,
      isNotNull,
      reason: '${stop.id}: actual feature must be mounted',
    );
    final targetFinder = find.byWidget(context!.widget);
    expect(
      targetFinder,
      findsOneWidget,
      reason: '${stop.id}: registered target must be onstage',
    );
    final target = tester.getRect(targetFinder);
    final clipBox = Scrollable.maybeOf(context)?.context.findRenderObject();
    final clipDebug = clipBox is RenderBox
        ? clipBox.localToGlobal(Offset.zero) & clipBox.size
        : null;
    final navigationContext = overlay.targets.contextFor('guide_navigation');
    final coach = tester.getRect(find.byKey(const ValueKey('guide-coach')));
    final page = tester.getRect(
      find.byKey(const ValueKey('guide-active-page')),
    );
    final scrim =
        tester
                .widget<CustomPaint>(find.byKey(const ValueKey('guide-scrim')))
                .painter!
            as GuideScrimPainter;
    expect(
      scrim.target,
      isNotNull,
      reason:
          '${stop.id}: no null-spotlight success; actual $target, coach $coach, page $page, clip $clipDebug',
    );
    expect(
      coach.overlaps(scrim.target!),
      isFalse,
      reason: '${stop.id}: coach covers the actual feature',
    );
    // Targets now describe whole cards/sections. An unusually tall section is
    // scrolled into the real page's viewport, not reduced to a convenient label.
    // Check the highlighted content (excluding its decorative 6dp halo), while
    // the independent container tests verify the complete registered feature.
    final shown = scrim.target!.deflate(6).intersect(target);
    expect(shown.isEmpty, isFalse, reason: '${stop.id}: unrelated pixels');
    expect(
      shown.height,
      greaterThanOrEqualTo(target.height < 48 ? target.height - 12 : 36),
      reason:
          '${stop.id}: a meaningful part of the actual container must be visible',
    );
    if (navigationContext != null && stop.targetId != 'guide_fingerprint') {
      final rail = tester.getRect(find.byWidget(navigationContext.widget));
      expect(
        shown.bottom,
        lessThanOrEqualTo(rail.top - 6 + .01),
        reason: '${stop.id}: highlighted content covered by navigation',
      );
    }
    final viewport = Rect.fromLTWH(0, 24, size.width, size.height - 48);
    for (final edge in [
      shown.left - viewport.left,
      shown.top - viewport.top,
      viewport.right - shown.right,
      viewport.bottom - shown.bottom,
    ]) {
      expect(
        edge,
        greaterThanOrEqualTo(-.01),
        reason: '${stop.id}: actual target is offscreen: $target',
      );
    }
    var expectedVisible = target.intersect(viewport);
    var scrollable = Scrollable.maybeOf(context);
    while (scrollable != null) {
      final box = scrollable.context.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        final clip = box.localToGlobal(Offset.zero) & box.size;
        expectedVisible = expectedVisible.intersect(clip);
        for (final edge in [
          shown.left - clip.left,
          shown.top - clip.top,
          clip.right - shown.right,
          clip.bottom - shown.bottom,
        ]) {
          expect(
            edge,
            greaterThanOrEqualTo(-.01),
            reason:
                '${stop.id}: target is clipped by its real scroll viewport $clip',
          );
        }
      }
      scrollable = Scrollable.maybeOf(scrollable.context);
    }
    expect(
      scrim.target!.left,
      lessThanOrEqualTo(expectedVisible.left + .01),
      reason:
          '${stop.id}: OS gesture edges must not cut off the feature’s left side',
    );
    expect(
      scrim.target!.right,
      greaterThanOrEqualTo(expectedVisible.right - .01),
      reason:
          '${stop.id}: OS gesture edges must not cut off the feature’s right side',
    );
    expect(
      find.byKey(const ValueKey('guide-arrow')),
      findsOneWidget,
      reason: stop.id,
    );
    final arrow =
        tester
                .widget<CustomPaint>(find.byKey(const ValueKey('guide-arrow')))
                .painter!
            as GuideArrowPainter;
    expect(
      arrow.tip.dx,
      inInclusiveRange(target.left - .01, target.right + .01),
      reason: stop.id,
    );
    expect(
      arrow.tip.dy,
      inInclusiveRange(target.top - .01, target.bottom + .01),
      reason: stop.id,
    );
    for (final key in [
      'guide-back',
      'guide-next',
      'guide-skip',
      'guide-details',
    ]) {
      final control = tester.getRect(find.byKey(ValueKey(key)));
      final controlSize = tester.getSize(find.byKey(ValueKey(key)));
      expect(
        controlSize.width,
        greaterThanOrEqualTo(48),
        reason: '$key ${stop.id}',
      );
      expect(
        controlSize.height,
        greaterThanOrEqualTo(48),
        reason: '$key ${stop.id}',
      );
      expect(
        coach.inflate(.01).contains(control.center),
        isTrue,
        reason: '$key ${stop.id}',
      );
    }
    expect(tester.takeException(), isNull, reason: stop.id);
  }

  for (final scene in const [
    ('phone', Size(390, 844), TextScaler.noScaling),
    ('small-phone', Size(360, 800), TextScaler.noScaling),
    ('small-display', Size(432, 960), TextScaler.linear(.85)),
    ('large-text', Size(320, 568), TextScaler.linear(2)),
    ('landscape', Size(844, 390), TextScaler.noScaling),
    ('tablet', Size(800, 1280), TextScaler.noScaling),
    ('nonlinear', Size(320, 568), GuideAndroid200TextScaler()),
  ]) {
    for (final empty in [false, true]) {
      for (final language in GuideLanguage.values) {
        fixture.widgetTest(
          'reference layout ${scene.$1} ${empty ? 'empty' : 'saved'} ${language.name} keeps actual feature containers visible',
          (tester) async {
            final guide = await mount(
              tester,
              scene.$2,
              scene.$3,
              language,
              empty,
              pixelRatio: scene.$1 == 'small-display' ? 5 / 3 : 1,
              gestureInsets: scene.$1 == 'small-display'
                  ? const EdgeInsets.symmetric(horizontal: 34)
                  : EdgeInsets.zero,
            );
            final before = await tester.runAsync(fixture.guideSafetySnapshot);
            for (final stop in guideStops) {
              if (scene.$1 == 'phone') {
                expect(
                  tester
                      .getSize(find.byKey(const ValueKey('guide-coach')))
                      .height,
                  lessThanOrEqualTo(280),
                  reason: stop.id,
                );
              }
              visibleTarget(tester, stop, scene.$2);
              if (stop.page == GuidePage.home) {
                expect(find.byType(HomeDashboardScreen), findsOneWidget);
                expect(find.text('Fixture Inspector'), findsOneWidget);
                expect(find.text('Sample Inspector — Fictional'), findsNothing);
              }
              if ({
                'G02',
                'G03',
                'G15',
                'G16',
                'G19',
                'G32',
                'G34',
                'G36',
                'G38',
                'G41',
              }.contains(stop.id)) {
                await fixture.capture(
                  tester,
                  'reference-${scene.$1}-${empty ? 'empty' : 'saved'}-${language.name}-${stop.id}',
                );
              }
              guide.next();
              try {
                await tester.pumpAndSettle(
                  const Duration(milliseconds: 100),
                  EnginePhase.sendSemanticsUpdate,
                  const Duration(seconds: 10),
                );
              } catch (error) {
                fail(
                  '${guideStops[guide.stopIndex].id} did not settle: $error',
                );
              }
            }
            await guide.finish();
            await tester.pumpAndSettle();
            expect(await tester.runAsync(fixture.guideSafetySnapshot), before);
            expect(fixture.requests, isEmpty);
            await tester.pumpWidget(const SizedBox.shrink());
            guide.dispose();
          },
        );
      }
    }
  }

  fixture.widgetTest(
    'review selected task after twenty assignments keeps G12-G15 visible',
    (tester) async {
      await tester.runAsync(() async {
        final selected = (await fixture.db.query(
          'local_jobs',
          where: 'id = ?',
          whereArgs: [offlineRound2],
        )).single;
        await fixture.db.delete(
          'local_jobs',
          where: 'id = ?',
          whereArgs: [offlineRound2],
        );
        for (var i = 0; i < 20; i++) {
          await fixture.db.insert('local_jobs', {
            'id': 'earlier-$i',
            'inspector_id': offlineInspector,
            'status': 'in_progress',
            'applicant_name': 'Earlier assignment $i',
            'cached_updated_at': '2030-01-01',
          });
        }
        await fixture.db.insert('local_jobs', {
          ...selected,
          'status': 'in_progress',
          'applicant_name': 'Selected last assignment',
          'is_self_scheduled': 0,
          'scheduled_date': '',
          'deadline_date': '2026-11-10',
        });
      });
      const size = Size(390, 844);
      final guide = await mount(
        tester,
        size,
        TextScaler.noScaling,
        GuideLanguage.english,
        false,
      );
      final before = await tester.runAsync(fixture.guideSafetySnapshot);
      while (guide.stopIndex <
          guideStops.indexWhere((stop) => stop.id == 'G12')) {
        guide.next();
      }
      await tester.pumpAndSettle();
      final saved = tester
          .widget<TasksScreen>(find.byType(TasksScreen))
          .walkthrough!;
      expect(saved.jobs, hasLength(22));
      expect(saved.jobs.last['id'], offlineRound2);
      for (final id in ['G12', 'G13', 'G14', 'G15']) {
        expect(guideStops[guide.stopIndex].id, id);
        visibleTarget(tester, guideStops[guide.stopIndex], size);
        expect(find.text('Selected last assignment'), findsOneWidget);
        if (id != 'G15') {
          guide.next();
          await tester.pumpAndSettle();
        }
      }
      await tester.tap(find.byKey(const ValueKey('guide-task-proxy')));
      await tester.pumpAndSettle();
      expect(guideStops[guide.stopIndex].id, 'G16');
      expect(await tester.runAsync(fixture.guideSafetySnapshot), before);
      expect(fixture.requests, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      guide.dispose();
    },
  );

  for (final language in GuideLanguage.values) {
    fixture.widgetTest(
      'completed-only actual targets remain visible in ${language.name}',
      (tester) async {
        await tester.runAsync(
          () => fixture.db.update('local_jobs', {'status': 'completed'}),
        );
        const size = Size(390, 844);
        final guide = await mount(
          tester,
          size,
          TextScaler.noScaling,
          language,
          false,
        );
        for (final stop in guideStops) {
          if (stop.id == 'G13') {
            expect(
              find.textContaining(
                RegExp('Hindi ligtas|cannot be safely highlighted'),
              ),
              findsNothing,
            );
          } else {
            visibleTarget(tester, stop, size);
          }
          guide.next();
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(const SizedBox.shrink());
        guide.dispose();
      },
    );
  }

  for (final language in GuideLanguage.values) {
    fixture.widgetTest(
      'reference details keeps every full ${language.name} explanation without advancing',
      (tester) async {
        const size = Size(390, 844);
        final guide = await mount(
          tester,
          size,
          TextScaler.noScaling,
          language,
          false,
        );
        for (final stop in guideStops) {
          final index = guide.stopIndex;
          await tester.tap(find.byKey(const ValueKey('guide-details')));
          await tester.pumpAndSettle();
          expect(guide.stopIndex, index);
          expect(find.text(stop.copyFor(language).message), findsOneWidget);
          if (stop.copyFor(language).details != null) {
            expect(find.text(stop.copyFor(language).details!), findsOneWidget);
          }
          visibleTarget(tester, stop, size);
          if ({
            'G02',
            'G19',
            'G23',
            'G34',
            'G39',
            'G39-about',
          }.contains(stop.id)) {
            await fixture.capture(
              tester,
              'details-phone-${language.name}-${stop.id}',
            );
          }
          await tester.tap(find.byKey(const ValueKey('guide-details')));
          await tester.pumpAndSettle();
          expect(guide.stopIndex, index);
          expect(find.text(stop.copyFor(language).summary!), findsOneWidget);
          visibleTarget(tester, stop, size);
          guide.next();
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(const SizedBox.shrink());
        guide.dispose();
      },
    );
  }

  for (final language in GuideLanguage.values) {
    fixture.widgetTest(
      'reference details large-text ${language.name} retains GPS and Sync targets',
      (tester) async {
        const size = Size(320, 568);
        final guide = await mount(
          tester,
          size,
          const TextScaler.linear(2),
          language,
          false,
        );
        final before = await tester.runAsync(fixture.guideSafetySnapshot);
        for (final id in ['G19', 'G32']) {
          final index = guideStops.indexWhere((stop) => stop.id == id);
          while (guide.stopIndex < index) {
            guide.next();
          }
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('guide-details')));
          await tester.pumpAndSettle();
          expect(guide.stopIndex, index);
          expect(
            find.text(guideStops[index].copyFor(language).message),
            findsOneWidget,
          );
          visibleTarget(tester, guideStops[index], size);
          await fixture.capture(
            tester,
            'details-large-text-${language.name}-${guideStops[index].id}',
          );
          await tester.tap(find.byKey(const ValueKey('guide-details')));
          await tester.pumpAndSettle();
          visibleTarget(tester, guideStops[index], size);
        }
        expect(await tester.runAsync(fixture.guideSafetySnapshot), before);
        await tester.pumpWidget(const SizedBox.shrink());
        guide.dispose();
      },
    );
  }

  fixture.widgetTest(
    'reference layout reflows details and rotation without obscuring its target',
    (tester) async {
      final guide = await mount(
        tester,
        const Size(390, 844),
        TextScaler.noScaling,
        GuideLanguage.english,
        false,
      );
      await tester.tap(find.byKey(const ValueKey('guide-details')));
      await tester.pumpAndSettle();
      expect(guide.stopIndex, 0);
      expect(find.text(guideStops.first.english.message), findsOneWidget);
      visibleTarget(tester, guideStops.first, const Size(390, 844));
      tester.view.physicalSize = const Size(844, 390);
      await tester.pumpAndSettle();
      visibleTarget(tester, guideStops.first, const Size(844, 390));
      await tester.tap(find.byKey(const ValueKey('guide-details')));
      await tester.pumpAndSettle();
      expect(guide.stopIndex, 0);
      visibleTarget(tester, guideStops.first, const Size(844, 390));
      await tester.pumpWidget(const SizedBox.shrink());
      guide.dispose();
    },
  );
}
