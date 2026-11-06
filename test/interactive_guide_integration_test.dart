import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:imaps_fieldsync/core/navigation/main_shell_screen.dart';
import 'package:imaps_fieldsync/core/widgets/insight_bottom_nav.dart';
import 'package:imaps_fieldsync/core/widgets/quick_actions_sheet.dart';
import 'package:imaps_fieldsync/modules/analytics_dashboard/screens/home_dashboard_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/providers/inspection_provider.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/inspection_progress.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_coordinator.dart';
import 'package:imaps_fieldsync/core/navigation/parcel_detail_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/site_map_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/gps_verification_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/capture_photo_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/inspection_checklist_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/field_findings_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/review_submit_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/completed_inspection_detail_screen.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/secure_prefs_service.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_host.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_overlay.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_preferences.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_script.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_targets.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/screens/interactive_guide_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/help_faq_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/interactive_guide_test_support.dart';
import 'support/offline_reliability_fixture.dart';

// Host integration: real shell, screens, SQLite and SDK session handling with
// isolated platform/HTTP boundaries. This is not installed-device/auth proof.
void main() {
  final fixture = OfflineReliabilityFixture();
  final hardware = <String>[];
  setUpAll(() async {
    await fixture.initialize();
    await prepareGuideTestFonts();
    for (final weight in [
      FontWeight.w400,
      FontWeight.w500,
      FontWeight.w600,
      FontWeight.w700,
      FontWeight.w800,
    ]) {
      GoogleFonts.inter(fontWeight: weight);
      GoogleFonts.urbanist(fontWeight: weight);
      GoogleFonts.openSans(fontWeight: weight);
    }
    await GoogleFonts.pendingFonts();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await fixture.reset();
    fixture.mode = 'success';
    hardware.clear();
    for (final channel in [
      'plugins.flutter.io/camera',
      'flutter.baseflow.com/geolocator',
      'flutter_compass',
    ]) {
      fixture.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(channel),
        (call) async {
          hardware.add('$channel/${call.method}');
          throw StateError('Guide requested hardware');
        },
      );
    }
  });
  tearDown(fixture.closeCase);
  tearDownAll(fixture.dispose);

  Future<void> settle(WidgetTester tester) async {
    await fixture.flush(tester);
    await tester.pump(const Duration(seconds: 2));
    await fixture.flush(tester);
    await tester.pumpAndSettle();
    await fixture.flush(tester);
    await tester.pumpAndSettle();
  }

  Future<GuideCoordinator> mount(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    TextScaler scaler = TextScaler.noScaling,
    bool reducedMotion = true,
    int initialIndex = 0,
  }) async {
    await fixture.mount(
      tester,
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: scaler, disableAnimations: reducedMotion),
            child: MainShellScreen(
              profile: UserProfile.fromMap(offlineProfile),
              offlineSession: true,
              initialIndex: initialIndex,
            ),
          ),
        ),
      ),
      size: size,
      showDebugBanner: false,
    );
    await settle(tester);
    return tester.widget<GuideHost>(find.byType(GuideHost)).coordinator;
  }

  Future<String> snapshot() => fixture.guideSafetySnapshot();

  void denyGuideIo() {
    fixture.requests.clear();
    fixture.requestOverride = (request) async => throw StateError(
      'Guide attempted ${request.method} ${request.url.path}',
    );
  }

  for (final accountState in [
    'empty',
    'populated',
    'completed-only',
    'partial',
  ]) {
    for (final language in GuideLanguage.values) {
      fixture.widgetTest(
        '$accountState account completes the full ${language.name} guide without business effects',
        (tester) async {
          if (accountState == 'empty') {
            fixture.provider.dispose();
            fixture.provider = InspectionProvider();
            InspectionProgress.instance.reset();
            for (final table in [
              'local_jobs',
              'local_inspections',
              'local_photos',
              'pending_actions',
            ]) {
              await fixture.db.delete(table);
            }
          } else {
            await tester.runAsync(() async {
              await fixture.db.update('local_jobs', {
                'status': accountState == 'completed-only'
                    ? 'completed'
                    : 'assigned',
                'applicant_name': 'Saved tour applicant',
                'reference_number': 'REAL-TOUR-42',
                'barangay': 'Saved tour barangay',
                'is_self_scheduled': 1,
                'scheduled_date': '2026-11-04',
                'deadline_date': '2026-11-10',
                if (accountState == 'populated') 'parcel_lat': 13.5,
                if (accountState == 'populated') 'parcel_lng': 121.25,
              });
              await fixture.db.insert('local_inspections', {
                'id': offlineJob,
                'inspector_id': offlineInspector,
                'notes': 'Saved tour finding',
                'inspection_result': 'For Review',
                'updated_at': '2026-11-02T00:00:00Z',
                'checklist_json': jsonEncode({
                  'Structure matches declared use': true,
                  '_draft_findings': {
                    'discrepancies': 'Saved tour explanation',
                    'recommendations': 'Saved tour recommendation',
                  },
                }),
              });
              if (accountState != 'partial') {
                await fixture.db.insert('local_photos', {
                  'id': 'tour-photo',
                  'job_id': offlineJob,
                  'inspector_id': offlineInspector,
                  'photo_path': File('assets/icon/app_icon.png').absolute.path,
                  'notes': 'Saved tour photo',
                  'captured_at': '2026-11-02T00:00:00Z',
                });
              }
            });
          }
          final guide = await mount(tester);
          final home = tester.state(find.byType(HomeDashboardScreen));
          expect(guide.phase, GuidePhase.invitation);
          await fixture.capture(
            tester,
            '$accountState-A-invitation-${language.name}',
          );
          if (language == GuideLanguage.tagalog) {
            await tester.tap(find.text('Filipino (Tagalog)'));
            await tester.pumpAndSettle();
            await fixture.capture(tester, '$accountState-A-invitation-tagalog');
          }
          final before = await tester.runAsync(snapshot);
          final session = fixture.client.auth.currentSession;
          denyGuideIo();
          await tester.tap(find.byKey(const ValueKey('guide-start')));
          await settle(tester);
          final stages = <int>{}, previews = <int>{};
          const scenes = {
            'G02': 'B-fingerprint',
            'G03': 'B-home',
            'G06': 'B-calendar',
            'G07': 'B-assignments',
            'G08': 'B-assignment-card',
            'G09': 'C-tasks',
            'G15': 'C-sample',
            'G16': 'D-overview',
            'G17': 'D-protocol',
            'G18': 'D-step-1',
            'G19': 'D-step-2',
            'G20': 'D-step-3',
            'G21': 'D-step-4',
            'G22': 'D-step-5',
            'G23': 'D-step-6',
            'G32': 'F-sync',
            'G35': 'F-received',
            'G36': 'G-profile',
            'G39': 'G-help',
            'G39-support': 'G-support',
            'G39-policies': 'G-policies',
            'G39-about': 'G-about',
            'G41': 'G-done',
          };
          for (var index = 0; index < guideStops.length; index++) {
            expect(guide.stopIndex, index);
            expect(guide.language, language);
            final stop = guideStops[index];
            final active = find.byKey(const ValueKey('guide-active-page'));
            if (stop.page == GuidePage.home) {
              expect(
                find.descendant(
                  of: active,
                  matching: find.byType(HomeDashboardScreen),
                ),
                findsOneWidget,
              );
              expect(find.text('Fixture Inspector'), findsOneWidget);
              expect(find.text('Sample Inspector — Fictional'), findsNothing);
            }
            if (stop.page == GuidePage.tasks) {
              final tasks = tester.widget<TasksScreen>(
                find.descendant(of: active, matching: find.byType(TasksScreen)),
              );
              expect(tasks.walkthrough, isNotNull);
              if (accountState != 'empty') {
                expect(find.text('Saved tour applicant'), findsWidgets);
              }
            }
            if ({'G16', 'G17', 'G24'}.contains(stop.id)) {
              expect(
                find.descendant(
                  of: active,
                  matching: find.byType(
                    accountState == 'completed-only'
                        ? CompletedInspectionDetailScreen
                        : ParcelDetailScreen,
                  ),
                ),
                findsOneWidget,
              );
            }
            if (stop.id == 'G22' && accountState != 'empty') {
              expect(find.text('Saved tour finding'), findsOneWidget);
            }
            if (stop.id == 'G20' &&
                accountState != 'empty' &&
                accountState != 'partial') {
              expect(
                tester
                    .widget<CapturePhotoScreen>(find.byType(CapturePhotoScreen))
                    .walkthrough!
                    .photos,
                hasLength(1),
              );
            }
            expect(find.byType(QuickActionsSheet), findsNothing);
            expect(tester.takeException(), isNull, reason: stop.id);
            stages.add(stop.stage);
            final coach = find.byKey(const ValueKey('guide-coach'));
            expect(
              find.descendant(
                of: coach,
                matching: find.text(stop.copyFor(language).title),
              ),
              findsOneWidget,
            );
            if (accountState == 'completed-only' &&
                {'G16', 'G17', 'G24'}.contains(stop.id)) {
              final completed = tester.widget<CompletedInspectionDetailScreen>(
                find.byType(CompletedInspectionDetailScreen),
              );
              expect(completed.task.inspectorNotes, 'Saved tour finding');
              expect(completed.task.photoDetails, hasLength(1));
            }
            const screens = {
              'G18': (1, SiteMapScreen),
              'G19': (2, GpsVerificationScreen),
              'G20': (3, CapturePhotoScreen),
              'G21': (4, InspectionChecklistScreen),
              'G22': (5, FieldFindingsScreen),
              'G23': (6, ReviewSubmitScreen),
            };
            final screen = screens[stop.id];
            if (screen != null) {
              expect(
                find.descendant(
                  of: find.byKey(const ValueKey('guide-active-page')),
                  matching: find.byType(screen.$2),
                ),
                findsOneWidget,
              );
              previews.add(screen.$1);
              final preview = tester.getRect(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is GuideTarget && widget.id == 'step_${screen.$1}',
                ),
              );
              expect(preview.top, greaterThanOrEqualTo(0));
              expect(
                preview.bottom,
                lessThanOrEqualTo(844),
                reason: 'The actual read-only preview must be brought onscreen',
              );
            }
            final paint =
                tester
                        .widget<CustomPaint>(
                          find.byKey(const ValueKey('guide-scrim')),
                        )
                        .painter!
                    as GuideScrimPainter;
            expect(
              paint.target == null ||
                  !tester.getRect(coach).overlaps(paint.target!),
              isTrue,
              reason: stop.id,
            );
            if (scenes[stop.id] != null) {
              await fixture.capture(
                tester,
                '$accountState-${scenes[stop.id]}-${language.name}',
              );
            }
            final proxy = find.byKey(const ValueKey('guide-task-proxy'));
            if (stop.id == 'G15' && proxy.evaluate().isNotEmpty) {
              await tester.tap(proxy);
            } else {
              if (stop.id == 'G15') {
                expect(
                  paint.target,
                  isNull,
                  reason:
                      'An unfit card uses the explicit overview and Next, never a wrong hit region',
                );
              }
              await tester.tap(find.byKey(const ValueKey('guide-next')));
            }
            await tester.pumpAndSettle();
          }
          await fixture.flush(tester);
          expect(stages, {1, 2, 3, 4, 5, 6});
          expect(previews, {1, 2, 3, 4, 5, 6});
          expect(guide.phase, GuidePhase.idle);
          expect(find.byKey(const ValueKey('guide-active-page')), findsNothing);
          expect(tester.state(find.byType(HomeDashboardScreen)), same(home));
          expect(fixture.client.auth.currentSession, same(session));
          expect(await tester.runAsync(snapshot), before);
          expect(fixture.requests, isEmpty);
          expect(hardware, isEmpty);
          expect(
            (await GuidePreferences().read(offlineInspector))?.status,
            GuideStatus.completed,
          );
          expect(tester.takeException(), isNull);

          // Normal actions are usable again, and Help replays through this shell.
          fixture.requestOverride = null;
          if (accountState == 'populated' || accountState == 'partial') {
            tester
                .widget<InsightBottomNav>(find.byType(InsightBottomNav))
                .onTap(1);
            await settle(tester);
            expect(
              await SecurePrefsService.getAcknowledgedTaskIds(offlineInspector),
              contains(offlineJob),
            );
          }
          await tester.tap(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics &&
                  widget.properties.label == 'Quick actions',
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(QuickActionsSheet), findsOneWidget);
          expect(
            tester
                .widget<QuickActionsSheet>(find.byType(QuickActionsSheet))
                .actions
                .map((action) => action.title),
            [
              'Map',
              'Compass',
              'Analytics overview',
              'Sync history',
              'Edit profile',
            ],
          );
          await fixture.capture(
            tester,
            '$accountState-E-normal-five-shortcuts-${language.name}',
          );
          await tester.tap(find.text('Analytics overview'));
          await settle(tester);
          expect(find.byType(ProfileScreen), findsOneWidget);
          expect(
            tester
                .widget<InsightBottomNav>(find.byType(InsightBottomNav))
                .currentIndex,
            3,
          );
          final help = find.text('Help & FAQ');
          await tester.scrollUntilVisible(
            help,
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.ensureVisible(help);
          await tester.pumpAndSettle();
          await tester.tap(help);
          await tester.pumpAndSettle();
          expect(find.byType(HelpFaqScreen), findsOneWidget);
          await fixture.capture(
            tester,
            '$accountState-G-real-help-${language.name}',
          );
          await tester.tap(
            find.byKey(const ValueKey('interactive-guide-entry')),
          );
          await tester.pumpAndSettle();
          expect(find.byType(InteractiveGuideScreen), findsOneWidget);
          await fixture.capture(
            tester,
            '$accountState-G-replay-page-${language.name}',
          );
          await tester.tap(
            find.byKey(const ValueKey('interactive-guide-start')),
          );
          await settle(tester);
          expect(guide.phase, GuidePhase.active);
          expect(guide.stopIndex, 0);
          await tester.binding.handlePopRoute();
          await settle(tester);
          expect(find.byType(InteractiveGuideScreen), findsOneWidget);
          expect(
            (await GuidePreferences().read(offlineInspector))?.status,
            GuideStatus.completed,
          );
        },
      );
    }
  }

  for (final exit in ['not-now', 'skip', 'android-back']) {
    fixture.widgetTest(
      '$exit restores real shell without changing business or security state',
      (tester) async {
        final guide = await mount(tester);
        final before = await tester.runAsync(snapshot);
        denyGuideIo();
        if (exit == 'not-now') {
          await tester.tap(find.byKey(const ValueKey('guide-not-now')));
        } else {
          await tester.tap(find.byKey(const ValueKey('guide-start')));
          await settle(tester);
          while (guide.stopIndex <
              guideStops.indexWhere((stop) => stop.id == 'G20')) {
            guide.next();
          }
          await tester.pumpAndSettle();
          if (exit == 'skip') {
            await tester.tap(find.byKey(const ValueKey('guide-skip')));
          } else {
            await tester.binding.handlePopRoute();
          }
        }
        await settle(tester);
        expect(guide.phase, GuidePhase.idle);
        expect(find.byKey(const ValueKey('guide-active-page')), findsNothing);
        expect(await tester.runAsync(snapshot), before);
        expect(fixture.requests, isEmpty);
        expect(hardware, isEmpty);
        expect(
          (await GuidePreferences().read(offlineInspector))?.status,
          GuideStatus.skipped,
        );
      },
    );
  }

  fixture.widgetTest(
    'a fitting integrated sample card opens only the read-only overview',
    (tester) async {
      final guide = await mount(tester, size: const Size(800, 1280));
      await guide.start(GuideLanguage.english);
      while (guide.stopIndex <
          guideStops.indexWhere((stop) => stop.id == 'G15')) {
        guide.next();
      }
      await tester.pumpAndSettle();
      final before = await tester.runAsync(snapshot);
      denyGuideIo();
      await tester.tap(find.byKey(const ValueKey('guide-task-proxy')));
      await tester.pumpAndSettle();
      expect(guideStops[guide.stopIndex].id, 'G16');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('guide-active-page')),
          matching: find.byType(ParcelDetailScreen),
        ),
        findsOneWidget,
      );
      expect(await tester.runAsync(snapshot), before);
      expect(fixture.requests, isEmpty);
      expect(hardware, isEmpty);
    },
  );

  fixture.widgetTest(
    'integrated welcome beacon is one-shot and its fingerprint never moves',
    (tester) async {
      final guide = await mount(tester, reducedMotion: false);
      await guide.skip();
      await settle(tester);
      await guide.start(GuideLanguage.english, replay: true);
      await tester.pump();
      final fingerprint = find.byWidgetPredicate(
        (widget) => widget is GuideTarget && widget.id == 'guide_fingerprint',
      );
      final anchor = tester.getRect(fingerprint);
      for (var frame = 0; frame <= 6; frame++) {
        if (frame > 0) await tester.pump(const Duration(milliseconds: 150));
        expect(tester.getRect(fingerprint), anchor);
        await fixture.capture(tester, 'beacon-$frame');
      }
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
      expect(guide.stopIndex, 0);
      await guide.skip();
      await tester.pumpAndSettle();
    },
  );

  for (final scene in [
    ('small-2x', const Size(320, 568), const TextScaler.linear(2)),
    ('portrait', const Size(390, 844), TextScaler.noScaling),
    ('landscape', const Size(844, 390), TextScaler.noScaling),
    ('tablet-portrait', const Size(800, 1280), TextScaler.noScaling),
    ('tablet-landscape', const Size(1280, 800), TextScaler.noScaling),
    ('nonlinear', const Size(320, 568), const GuideAndroid200TextScaler()),
  ]) {
    fixture.widgetTest(
      'integrated coach fits ${scene.$1} with reduced motion',
      (tester) async {
        final guide = await mount(tester, size: scene.$2, scaler: scene.$3);
        await guide.start(GuideLanguage.tagalog);
        while (guide.stopIndex <
            guideStops.indexWhere((stop) => stop.id == 'G15')) {
          guide.next();
        }
        await fixture.flush(tester);
        await tester.pumpAndSettle();
        for (final key in ['guide-back', 'guide-next', 'guide-skip']) {
          final rect = tester.getRect(find.byKey(ValueKey(key)));
          expect(rect.height, greaterThanOrEqualTo(48));
          expect(rect.top, greaterThanOrEqualTo(24));
          expect(rect.bottom, lessThanOrEqualTo(scene.$2.height - 24));
        }
        final paint =
            tester
                    .widget<CustomPaint>(
                      find.byKey(const ValueKey('guide-scrim')),
                    )
                    .painter!
                as GuideScrimPainter;
        expect(paint.pulse, isNull);
        expect(
          paint.target == null ||
              !tester
                  .getRect(find.byKey(const ValueKey('guide-coach')))
                  .overlaps(paint.target!),
          isTrue,
        );
        await fixture.capture(tester, 'responsive-${scene.$1}');
        await guide.skip();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
