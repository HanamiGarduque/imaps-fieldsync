import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:imaps_fieldsync/core/navigation/main_shell_screen.dart';
import 'package:imaps_fieldsync/core/widgets/field_form_widgets.dart';
import 'package:imaps_fieldsync/core/widgets/sensitive_screen.dart';
import 'package:imaps_fieldsync/core/widgets/quick_actions_sheet.dart';
import 'package:imaps_fieldsync/modules/offline_sync/widgets/sync_summary_view.dart';
import 'package:imaps_fieldsync/modules/analytics_dashboard/screens/home_dashboard_screen.dart';
import 'package:imaps_fieldsync/modules/analytics_dashboard/widgets/home_guide_sections.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/screen_protection_observer.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/screen_protection_service.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_coordinator.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_host.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_overlay.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_preferences.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_script.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_targets.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/screens/interactive_guide_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/interactive_guide_test_support.dart';
import 'support/offline_reliability_fixture.dart';

void main() {
  final fixture = OfflineReliabilityFixture();
  final profile = UserProfile.fromMap(offlineProfile);
  setUpAll(() async {
    await fixture.initialize();
    await prepareGuideTestFonts();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await fixture.reset();
    fixture.mode = 'success';
  });
  tearDown(fixture.closeCase);
  tearDownAll(fixture.dispose);

  Future<GuideCoordinator> mountGuide(
    WidgetTester tester,
    GuideLanguage language,
  ) async {
    final guide = GuideCoordinator(
      inspectorId: offlineInspector,
      preferences: GuidePreferences(),
      canPresent: () => true,
    );
    addTearDown(guide.dispose);
    await fixture.mount(
      tester,
      GuideHost(
        coordinator: guide,
        profile: profile,
        child: const Scaffold(body: Text('Retained origin')),
      ),
      showDebugBanner: false,
    );
    await guide.start(language);
    await fixture.flush(tester);
    await tester.pumpAndSettle();
    await fixture.capture(tester, 'visual-G02-${language.name}');
    return guide;
  }

  for (final language in GuideLanguage.values) {
    fixture.widgetTest(
      'short guide omits removed lessons and finishes on Profile in ${language.name}',
      (tester) async {
        final guide = await mountGuide(tester, language);
        final before = await tester.runAsync(fixture.guideSafetySnapshot);
        for (final stop in guideStops) {
          expect(find.byType(QuickActionsSheet), findsNothing);
          expect(find.byType(InteractiveGuideScreen), findsNothing);
          expect(
            stop.id,
            isNot(
              isIn([
                'G11',
                'G25',
                'G26',
                'G27',
                'G28',
                'G29',
                'G30',
                'G31',
                'G37-edit',
                'G39-logout',
                'G40',
              ]),
            ),
          );
          expect(
            stop.targetId,
            isNot(isIn(['profile_edit', 'profile_logout', 'guide_replay'])),
          );
          if (stop == guideStops.last) {
            expect(find.byType(ProfileScreen), findsOneWidget);
            expect(stop.targetId, 'profile_identity');
          }
          await tester.tap(find.byKey(const ValueKey('guide-next')));
          await tester.pumpAndSettle();
          if (stop.id == 'G10') {
            expect(guideStops[guide.stopIndex].id, 'G12');
            expect(
              guideStops[guide.stopIndex].progress(language),
              language == GuideLanguage.tagalog
                  ? 'Yugto 3 ng 6 · Paliwanag 3 ng 6'
                  : 'Stage 3 of 6 · Explanation 3 of 6',
            );
            await tester.tap(find.byKey(const ValueKey('guide-back')));
            await tester.pumpAndSettle();
            expect(guideStops[guide.stopIndex].id, 'G10');
            await tester.tap(find.byKey(const ValueKey('guide-next')));
            await tester.pumpAndSettle();
            expect(guideStops[guide.stopIndex].id, 'G12');
          }
        }
        await fixture.flush(tester);
        expect(guide.phase, GuidePhase.idle);
        expect(await tester.runAsync(fixture.guideSafetySnapshot), before);
        expect(fixture.remoteWrites, 0);
        expect(tester.takeException(), isNull);
      },
    );

    fixture.widgetTest(
      'dedicated Guide ${language.name} keeps language and Replay accessible without covering its final copy',
      (tester) async {
        final labels = GuideLabels(language);
        await fixture.mount(
          tester,
          InteractiveGuideScreen(
            initialLanguage: language,
            hasPreviousOffer: true,
          ),
          showDebugBanner: false,
        );
        await tester.pumpAndSettle();
        final start = find.byKey(const ValueKey('interactive-guide-start'));
        expect(start.hitTestable(), findsOneWidget);
        expect(find.text('Filipino (Tagalog)').hitTestable(), findsOneWidget);
        await fixture.capture(tester, 'visual-guide-page-${language.name}-top');
        await Scrollable.ensureVisible(
          tester.element(find.text(labels.safety)),
          alignment: 1,
        );
        await tester.pumpAndSettle();
        final copy = tester.getRect(find.text(labels.safety));
        final scroll = tester.getRect(
          find.byKey(const ValueKey('interactive-guide-copy')),
        );
        expect(scroll.inflate(.01).contains(copy.bottomCenter), isTrue);
        expect(copy.overlaps(tester.getRect(start)), isFalse);
        await fixture.capture(tester, 'visual-guide-page-${language.name}-end');
        await tester.ensureVisible(start);
        await tester.pumpAndSettle();
        expect(start.hitTestable(), findsOneWidget);
        expect(fixture.remoteWrites, 0);
        expect(tester.takeException(), isNull);
      },
    );

    fixture.widgetTest(
      'Guide page header stays at the top and pinned with small display and text in ${language.name}',
      (tester) async {
        for (final scene in const [
          ('small-display', Size(432, 960), .85),
          ('normal', Size(390, 844), 1.0),
          ('large-text', Size(320, 568), 2.0),
        ]) {
          await fixture.mount(
            tester,
            InteractiveGuideScreen(
              initialLanguage: language,
              hasPreviousOffer: true,
            ),
            size: scene.$2,
            textScale: scene.$3,
            showDebugBanner: false,
          );
          await tester.pumpAndSettle();
          final header = find.byType(FieldPageHeader);
          final before = tester.getRect(header);
          expect(before.top, closeTo(36, .01), reason: scene.$1);
          expect(
            before.contains(
              tester.getRect(find.text('FieldSync Interactive Guide')).center,
            ),
            isTrue,
          );
          await fixture.capture(
            tester,
            'guide-page-${scene.$1}-${language.name}-top',
          );
          await tester.drag(
            find.byKey(const ValueKey('interactive-guide-copy')),
            const Offset(0, -400),
          );
          await tester.pumpAndSettle();
          expect(tester.getRect(header), before, reason: scene.$1);
          final start = find.byKey(const ValueKey('interactive-guide-start'));
          await tester.ensureVisible(start);
          await tester.pumpAndSettle();
          expect(start.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );

    fixture.widgetTest(
      'speech bubble stays beside the stationary fingerprint in ${language.name}',
      (tester) async {
        final guide = await mountGuide(tester, language);
        for (var index = 0; index < 7; index++) {
          final overlay = tester.widget<GuideOverlay>(
            find.byType(GuideOverlay),
          );
          final anchor = tester.getRect(
            find.byWidget(
              overlay.targets.contextFor('guide_fingerprint')!.widget,
            ),
          );
          final bubble = tester.getRect(
            find.byKey(const ValueKey('guide-coach')),
          );
          expect(
            anchor.left - bubble.right,
            inInclusiveRange(0, 16),
            reason: guideStops[index].id,
          );
          expect(
            anchor.center.dy,
            inInclusiveRange(bubble.top, bubble.bottom),
            reason: guideStops[index].id,
          );
          expect(
            find.textContaining(
              RegExp('Hindi ligtas|cannot be safely highlighted'),
            ),
            findsNothing,
          );
          guide.next();
          await tester.pumpAndSettle();
        }
      },
    );
  }

  fixture.widgetTest(
    'Home highlights the full chart and Calendar containers, not their headings',
    (tester) async {
      final guide = await mountGuide(tester, GuideLanguage.english);
      for (final entry in [
        ('G05', find.byType(HomeTaskStatusChart)),
        ('G06', find.byKey(const ValueKey('calendar_section'))),
        ('G07', find.byKey(const ValueKey('assignments_section'))),
      ]) {
        while (guideStops[guide.stopIndex].id != entry.$1) {
          guide.next();
        }
        await tester.pumpAndSettle();
        final overlay = tester.widget<GuideOverlay>(find.byType(GuideOverlay));
        final target = tester.getRect(
          find.byWidget(
            overlay.targets
                .contextFor(guideStops[guide.stopIndex].targetId)!
                .widget,
          ),
        );
        final container = tester.getRect(entry.$2);
        expect(
          target.size,
          container.size,
          reason: '${entry.$1} must teach the whole container',
        );
        final scrim =
            tester
                    .widget<CustomPaint>(
                      find.byKey(const ValueKey('guide-scrim')),
                    )
                    .painter!
                as GuideScrimPainter;
        expect(scrim.target, isNotNull);
        expect(scrim.target!.height, greaterThan(100), reason: entry.$1);
        await fixture.capture(tester, 'visual-${entry.$1}-english');
      }
    },
  );

  for (final language in GuideLanguage.values) {
    fixture.widgetTest(
      'Profile teaches every essential section before Done in ${language.name}',
      (tester) async {
        final guide = await mountGuide(tester, language);
        final before = await tester.runAsync(fixture.guideSafetySnapshot);
        while (guideStops[guide.stopIndex].page != GuidePage.profile) {
          guide.next();
        }
        await tester.pumpAndSettle();
        for (final id in const [
          'profile_identity',
          'profile_summary',
          'profile_analytics',
          'profile_security',
          'profile_help',
          'profile_support',
          'profile_policies',
          'profile_about',
          'profile_identity',
        ]) {
          expect(guide.phase, GuidePhase.active);
          expect(guideStops[guide.stopIndex].targetId, id);
          final overlay = tester.widget<GuideOverlay>(
            find.byType(GuideOverlay),
          );
          expect(overlay.targets.contextFor(id), isNotNull, reason: id);
          final scrim =
              tester
                      .widget<CustomPaint>(
                        find.byKey(const ValueKey('guide-scrim')),
                      )
                      .painter!
                  as GuideScrimPainter;
          expect(scrim.target, isNotNull, reason: id);
          expect(
            tester
                .getRect(find.byKey(const ValueKey('guide-coach')))
                .overlaps(scrim.target!),
            isFalse,
            reason: id,
          );
          await fixture.capture(
            tester,
            'visual-${guideStops[guide.stopIndex].id}-${language.name}',
          );
          await tester.tap(find.byKey(const ValueKey('guide-next')));
          await tester.pumpAndSettle();
        }
        await fixture.flush(tester);
        expect(guide.phase, GuidePhase.idle);
        expect(await tester.runAsync(fixture.guideSafetySnapshot), before);
        expect(fixture.remoteWrites, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  fixture.widgetTest(
    'Back and Next remain available while the guide scrolls to a feature',
    (tester) async {
      final guide = await mountGuide(tester, GuideLanguage.english);
      while (guide.stopIndex < 3) {
        guide.next();
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('guide-back')))
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('guide-next')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const ValueKey('guide-next')));
      await tester.pumpAndSettle();
      expect(guide.stopIndex, 4);
      expect(tester.takeException(), isNull);
    },
  );

  for (final feature in const [
    ('G08', 200),
    ('G12', 180),
    ('G16', 100),
    ('G17', 250),
    ('G18', 160),
    ('G19', 160),
    ('G20', 150),
    ('G21', 180),
    ('G22', 100),
    ('G23', 200),
    ('G24', 64),
    ('G32', 120),
    ('G33', 100),
    ('G34', 140),
    ('G35', 64),
  ]) {
    fixture.widgetTest(
      'meaningful container ${feature.$1} includes its content, not just a label',
      (tester) async {
        await tester.runAsync(
          () => fixture.db.update('local_jobs', {
            'parcel_lat': 13.84,
            'parcel_lng': 121.20,
          }),
        );
        final guide = await mountGuide(tester, GuideLanguage.english);
        while (guideStops[guide.stopIndex].id != feature.$1) {
          guide.next();
        }
        await tester.pumpAndSettle();
        final overlay = tester.widget<GuideOverlay>(find.byType(GuideOverlay));
        final context = overlay.targets.contextFor(
          guideStops[guide.stopIndex].targetId,
        )!;
        expect(
          tester.getSize(find.byWidget(context.widget)).height,
          greaterThanOrEqualTo(feature.$2),
          reason: feature.$1,
        );
        final scrim =
            tester
                    .widget<CustomPaint>(
                      find.byKey(const ValueKey('guide-scrim')),
                    )
                    .painter!
                as GuideScrimPainter;
        expect(scrim.target, isNotNull, reason: feature.$1);
        await fixture.capture(tester, 'visual-${feature.$1}-english');
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final unavailable in [false, true]) {
    fixture.widgetTest(
      'walkthrough storage ${unavailable ? 'unknown' : 'saved'} values never use initialized zeros',
      (tester) async {
        await tester.runAsync(
          () => fixture.db.insert('local_photos', {
            'id': 'saved-cache-photo',
            'job_id': offlineRound2,
            'inspector_id': offlineInspector,
            'is_synced': 0,
            'photo_path': 'saved-only.png',
          }),
        );
        if (unavailable) {
          await tester.runAsync(
            () => fixture.db.execute(
              'ALTER TABLE local_photos RENAME TO unreadable_photos',
            ),
          );
        }
        final guide = await mountGuide(tester, GuideLanguage.english);
        while (guideStops[guide.stopIndex].id != 'G34') {
          guide.next();
        }
        await tester.pumpAndSettle();
        final stats = {
          for (final item in tester.widgetList<SyncStatItem>(
            find.byType(SyncStatItem),
          ))
            item.label: item.value,
        };
        expect(stats['Cached jobs'], unavailable ? '—' : '2');
        expect(stats['Unsynced files'], unavailable ? '—' : '1');
        expect(stats['Reclaimable'], unavailable ? '—' : '0.00 B');
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final language in GuideLanguage.values) {
    for (final replay in [false, true]) {
      fixture.widgetTest(
        'first Help start ${language.name} replay=$replay waits for protection without losing the request',
        (tester) async {
          if (replay) {
            await GuidePreferences().write(
              offlineInspector,
              const GuideRecord(
                1,
                GuideLanguage.english,
                GuideStatus.completed,
              ),
            );
          }
          Completer<void>? secureReply;
          final protection = ScreenProtectionService(
            applyProtection: (secure) async {
              if (secure && secureReply != null) await secureReply.future;
            },
          );
          addTearDown(protection.dispose);
          await fixture.mount(
            tester,
            ScreenProtectionHost(
              protection: protection,
              child: Navigator(
                observers: [ScreenProtectionObserver(protection)],
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) =>
                      MainShellScreen(profile: profile, initialIndex: 3),
                ),
              ),
            ),
          );
          await fixture.flush(tester);
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text('Help & FAQ'),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.ensureVisible(find.text('Help & FAQ'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Help & FAQ'));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('interactive-guide-entry')),
          );
          await tester.pumpAndSettle();
          if (language == GuideLanguage.tagalog) {
            await tester.tap(find.text('Filipino (Tagalog)'));
            await tester.pumpAndSettle();
          }
          secureReply = Completer<void>();
          await tester.tap(
            find.byKey(const ValueKey('interactive-guide-start')),
          );
          await fixture.flush(tester);
          await tester.pump(const Duration(milliseconds: 400));
          final hiddenUntilAcknowledged = protection.mustObscure;
          secureReply.complete();
          await fixture.flush(tester);
          await tester.pumpAndSettle();
          final guide = tester
              .widget<GuideHost>(find.byType(GuideHost))
              .coordinator;
          expect(hiddenUntilAcknowledged, isTrue);
          expect(guide.phase, GuidePhase.active);
          expect(guide.language, language);
          expect(find.byKey(const ValueKey('guide-coach')), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  fixture.widgetTest(
    'normal Home refresh never replaces a scheduled applicant with an error block',
    (tester) async {
      await tester.runAsync(
        () => fixture.db.update(
          'local_jobs',
          {
            'status': 'assigned',
            'is_self_scheduled': 1,
            'scheduled_date': '2026-11-05',
            'applicant_name': 'Synthetic assignment',
            'barangay': 'Demo site',
          },
          where: 'id = ?',
          whereArgs: [offlineRound2],
        ),
      );
      fixture.online = true;
      fixture.mode = 'jobs-hold';
      final targets = GuideTargetRegistry();
      addTearDown(targets.dispose);
      await fixture.mount(
        tester,
        GuideTargetScope(
          registry: targets,
          child: HomeDashboardScreen(profile: profile),
        ),
      );
      await fixture.flush(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Synthetic assignment'), findsOneWidget);
      fixture.jobsRows = [
        {
          'id': offlineRound2,
          'assigned_inspector_id': offlineInspector,
          'status': 'assigned',
          'is_self_scheduled': true,
          'scheduled_date': '2026-11-06',
          'supabase_zoning_applications': {
            'applicant_name': 'Synthetic assignment',
            'barangay': 'Demo site',
            'reference_number': 'SAMPLE-ONLY',
          },
        },
      ];
      fixture.resolveHeld();
      await fixture.flush(tester);
      expect(tester.takeException(), isNull);
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          tester.takeException(),
          isNull,
          reason: 'Assignment refresh frame $frame',
        );
        expect(find.byType(ErrorWidget), findsNothing);
      }
      await tester.pumpAndSettle();
      expect(find.byType(ErrorWidget), findsNothing);
      expect(find.text('Synthetic assignment'), findsOneWidget);
      await fixture.capture(tester, 'short-guide-normal-assignment-refreshed');
    },
  );

  for (final language in GuideLanguage.values) {
    fixture.widgetTest(
      'every Next keeps a compact coach through all ${language.name} transitions',
      (tester) async {
        final guide = await mountGuide(tester, language);
        for (var step = 0; step < guideStops.length - 1; step++) {
          await tester.tap(find.byKey(const ValueKey('guide-next')));
          for (var frame = 0; frame < 20; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            expect(
              tester.getSize(find.byKey(const ValueKey('guide-coach'))).height,
              lessThanOrEqualTo(280),
              reason: 'Next $step, rendered frame $frame must remain compact',
            );
            expect(
              tester.takeException(),
              isNull,
              reason: '${guideStops[guide.stopIndex].id}, frame $frame',
            );
            expect(find.byType(ErrorWidget), findsNothing);
          }
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
