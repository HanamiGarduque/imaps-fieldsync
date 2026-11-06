import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:imaps_fieldsync/core/navigation/main_shell_screen.dart';
import 'package:imaps_fieldsync/modules/analytics_dashboard/screens/home_dashboard_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/inspection_progress.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_coordinator.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_host.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_overlay.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_preferences.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_script.dart';
import 'package:imaps_fieldsync/modules/offline_sync/screens/updates_screen.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/offline_reliability_fixture.dart';

void main() {
  final fixture = OfflineReliabilityFixture();
  setUpAll(fixture.initialize);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await fixture.reset();
    // Normal Home's initial unread-count read must finish before the snapshot,
    // rather than leave PostgREST's ordinary transport retries in flight.
    fixture.mode = 'success';
  });
  tearDown(fixture.closeCase);
  tearDownAll(fixture.dispose);
  final profile = UserProfile.fromMap(offlineProfile);

  Future<void> settle(WidgetTester tester) async {
    await fixture.flush(tester);
    await tester.pump(const Duration(seconds: 2));
    await fixture.flush(tester);
    await tester.pumpAndSettle();
  }

  fixture.widgetTest(
    'shell guide enters only passive actual pages and retains normal Home',
    (tester) async {
      await fixture.mount(
        tester,
        MainShellScreen(profile: profile, offlineSession: true),
      );
      await settle(tester);
      final home = tester.state(find.byType(HomeDashboardScreen));
      final guide = tester
          .widget<GuideHost>(find.byType(GuideHost))
          .coordinator;
      expect(guide.phase, GuidePhase.invitation);
      Future<String> business() async => jsonEncode({
        for (final table in [
          'local_jobs',
          'local_inspections',
          'local_photos',
          'pending_actions',
          'local_report_queue',
        ])
          table: await fixture.db.query(table),
      });
      final before = await tester.runAsync(business);
      final secure = Map<String, String>.from(fixture.secure);
      final progress = InspectionProgress.instance;
      final steps = [
        progress.currentStep,
        progress.highestCompleted,
        Map<int, String>.from(progress.stepCompletedAt),
      ];
      fixture.requests.clear();
      await tester.tap(find.byKey(const ValueKey('guide-start')));
      await settle(tester);
      for (var index = 0; index < guideStops.length; index++) {
        expect(guide.stopIndex, index);
        for (final page in tester.widgetList<TasksScreen>(find.byType(TasksScreen))) {
          expect(page.walkthrough, isNotNull);
        }
        for (final page in tester.widgetList<UpdatesScreen>(find.byType(UpdatesScreen))) {
          expect(page.walkthrough, isNotNull);
        }
        expect(find.byType(MainShellScreen), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('guide-next')));
        await tester.pumpAndSettle();
      }
      expect(guide.phase, GuidePhase.idle);
      expect(tester.state(find.byType(HomeDashboardScreen)), same(home));
      expect(await tester.runAsync(business), before);
      expect(fixture.secure, secure);
      expect([
        progress.currentStep,
        progress.highestCompleted,
        progress.stepCompletedAt,
      ], steps);
      expect(fixture.requests, isEmpty);
      expect(
        (await GuidePreferences().read(offlineInspector))?.status,
        GuideStatus.completed,
      );
      for (var i = 0; i < 2; i++) {
        await guide.start(GuideLanguage.english, replay: true);
        await tester.pumpAndSettle();
        expect(find.byType(GuideHost), findsOneWidget);
        expect(find.byType(GuideOverlay), findsOneWidget);
        await guide.skip();
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    },
  );

  fixture.widgetTest(
    'automatic offer waits for Home rather than interrupting normal Tasks',
    (tester) async {
      await fixture.mount(
        tester,
        MainShellScreen(
          profile: profile,
          initialIndex: 1,
          offlineSession: true,
        ),
      );
      await settle(tester);
      final guide = tester
          .widget<GuideHost>(find.byType(GuideHost))
          .coordinator;
      expect(guide.phase, GuidePhase.idle);
      expect(await GuidePreferences().read(offlineInspector), isNull);
      await tester.tap(find.byIcon(Icons.home_rounded).last);
      await settle(tester);
      expect(guide.phase, GuidePhase.invitation);
      await tester.tap(find.byKey(const ValueKey('guide-not-now')));
      await tester.pumpAndSettle();
      expect(guide.phase, GuidePhase.idle);
    },
  );

  fixture.widgetTest(
    'covered Home defers an offer until the work route returns',
    (tester) async {
      await fixture.mount(
        tester,
        MainShellScreen(profile: profile, offlineSession: true),
      );
      final context = tester.element(find.byType(MainShellScreen));
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Active fieldwork')),
        ),
      );
      await settle(tester);
      final guide = tester
          .widget<GuideHost>(find.byType(GuideHost, skipOffstage: false))
          .coordinator;
      expect(guide.phase, GuidePhase.idle);
      expect(await GuidePreferences().read(offlineInspector), isNull);
      Navigator.of(context).pop();
      await settle(tester);
      expect(guide.phase, GuidePhase.invitation);
      expect(tester.takeException(), isNull);
    },
  );
}
