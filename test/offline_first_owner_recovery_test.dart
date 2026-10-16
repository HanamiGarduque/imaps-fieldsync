import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:imaps_fieldsync/core/navigation/parcel_detail_screen.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/widgets/imaps_loading_indicator.dart';
import 'package:imaps_fieldsync/core/widgets/offline_banner.dart';
import 'package:imaps_fieldsync/modules/analytics_dashboard/screens/home_dashboard_screen.dart';
import 'package:imaps_fieldsync/modules/analytics_dashboard/widgets/active_assignments_folder_card.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

import 'support/offline_reliability_fixture.dart';

// Breaks caught: auth transitions must invalidate display AND already-bound
// navigation callbacks; unreadable local data must recover without being erased.
void main() {
  final fixture = OfflineReliabilityFixture();
  setUpAll(fixture.initialize);
  setUp(fixture.reset);
  tearDown(fixture.closeCase);
  tearDownAll(fixture.dispose);
  final ownerA = UserProfile.fromMap(offlineProfile);
  final ownerB = UserProfile.fromMap({...offlineProfile, 'id': otherOfflineInspector});

  Future<void> flush(WidgetTester tester) async {
    for (var turn = 0; turn < 4; turn++) {
      await fixture.flush(tester);
    }
  }

  Widget screen(bool home, UserProfile profile) => home
      ? HomeDashboardScreen(profile: profile)
      : TasksScreen(profile: profile);

  Future<void> switchTo(WidgetTester tester, String owner) async {
    await tester.runAsync(() => fixture.client.auth.setInitialSession(
        jsonEncode(fixture.session(owner: owner))));
    expect(fixture.client.auth.currentSession!.user.id, owner);
    expect(DBHelper.currentInspectorId, owner);
    expect(DBHelper.inspectorIdForTesting, isNull,
        reason: 'this is an auth-client transition, never a namespace override');
  }

  for (final home in [false, true]) {
    final page = home ? 'Home' : 'Tasks';
    fixture.widgetTest('$page authenticated A→B retires cards and bound navigation, preserves exact A evidence', (tester) async {
      await tester.runAsync(() async {
        await fixture.db.update('local_jobs', {'applicant_name': 'Applicant of inspector A'},
            where: 'id = ?', whereArgs: [offlineJob]);
        await fixture.db.insert('local_inspections', {
          'id': offlineJob, 'inspector_id': offlineInspector,
          'notes': 'Fictional A findings', 'current_step': 5,
        });
        await fixture.db.insert('local_photos', {
          'id': 'owner-A-photo', 'job_id': offlineRound2,
          'inspector_id': offlineInspector, 'photo_path': 'fixture-only-R2.jpg',
          'notes': 'Fictional A round two evidence',
        });
      });
      final before = await tester.runAsync(() async => {
        for (final table in ['local_jobs', 'local_inspections', 'local_photos', 'inspection_job_retention'])
          table: await fixture.db.query(table),
      });
      await fixture.mount(tester, screen(home, ownerA));
      await flush(tester);
      expect(find.text('Applicant of inspector A'), findsWidgets);
      final VoidCallback boundNavigation;
      if (home) {
        boundNavigation = tester.widget<ActiveAssignmentsFolderCard>(
            find.byType(ActiveAssignmentsFolderCard).first).onTap;
      } else {
        boundNavigation = tester.widget<GestureDetector>(find.ancestor(
          of: find.text('Application Details', skipOffstage: false).first,
          matching: find.byType(GestureDetector, skipOffstage: false),
        ).first).onTap!;
      }

      await switchTo(tester, otherOfflineInspector);
      boundNavigation(); // The callback was created under A, before the event.
      await tester.pump();
      await flush(tester);
      expect(find.byType(ParcelDetailScreen, skipOffstage: false), findsNothing);
      expect(find.text('Applicant of inspector A', skipOffstage: false), findsNothing);
      final after = await tester.runAsync(() async => {
        for (final table in before!.keys) table: await fixture.db.query(table),
      });
      expect(after, before, reason: 'retiring UI must not mutate either round or evidence');
      await fixture.capture(tester, 'area2-${page.toLowerCase()}-owner-A-retired');

      await tester.runAsync(() => DBHelper.cacheJobs([{
        'id': 'owner-B-assignment', 'status': 'in_progress',
        'inspection_round_number': 2, 'local_inspection_id': 702,
        'supabase_zoning_applications': {'applicant_name': 'Applicant of inspector B'},
      }]));
      await tester.pumpWidget(const SizedBox.shrink());
      await fixture.mount(tester, screen(home, ownerB));
      await flush(tester);
      expect(find.text('Applicant of inspector B'), findsWidgets);
      expect(find.text('Applicant of inspector A', skipOffstage: false), findsNothing);
      final visible = await tester.runAsync(DBHelper.getCachedJobs);
      expect(visible!.single['id'], 'owner-B-assignment');
      expect(visible.single['inspector_id'], otherOfflineInspector);
      expect(visible.single['inspection_round_number'], 2);
      await fixture.capture(tester, 'area2-${page.toLowerCase()}-owner-B-only');
    });

    fixture.widgetTest('$page malformed cached row exits loading and retries without deleting it', (tester) async {
      await tester.runAsync(() => fixture.db.update('local_jobs', {
        'inspection_round_number': 'unreadable',
        'applicant_name': 'Recovered cached applicant',
      }, where: 'id = ?', whereArgs: [offlineJob]));
      await fixture.mount(tester, screen(home, ownerA));
      await flush(tester);
      expect(tester.takeException(), isNull);
      if (!home) expect(find.byType(ImapsLoadingIndicator), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      final kept = await tester.runAsync(() => fixture.db.query('local_jobs',
          where: 'id = ?', whereArgs: [offlineJob]));
      expect(kept!.single['inspection_round_number'], 'unreadable');
      await tester.runAsync(() => fixture.db.update('local_jobs', {'inspection_round_number': 1},
          where: 'id = ?', whereArgs: [offlineJob]));
      await tester.tap(find.text('Retry'));
      await flush(tester);
      expect(find.text('Recovered cached applicant'), findsWidgets);
    });
  }

  fixture.widgetTest('Home SQLite read error is recoverable and distinct from server-empty', (tester) async {
    await tester.runAsync(() async {
      await fixture.db.update('local_jobs', {'applicant_name': 'Recovered cached applicant'},
          where: 'id = ?', whereArgs: [offlineJob]);
      await fixture.db.execute('ALTER TABLE local_jobs RENAME TO temporarily_unreadable_jobs');
    });
    try {
      await fixture.mount(tester, screen(true, ownerA));
      await flush(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('No active assignments.'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
    } finally {
      await tester.runAsync(() => fixture.db.execute('ALTER TABLE temporarily_unreadable_jobs RENAME TO local_jobs'));
    }
    await tester.tap(find.text('Retry'));
    await flush(tester);
    expect(find.text('Recovered cached applicant'), findsWidgets);
  });

  fixture.widgetTest('Home timeout retries to a verified authoritative empty result', (tester) async {
    await tester.runAsync(() async {
      await fixture.db.delete('inspection_job_retention');
      await DBHelper.cacheJobs([]);
    });
    fixture.online = true;
    fixture.mode = 'jobs-hold';
    await fixture.mount(tester, screen(true, ownerA));
    await flush(tester);
    await tester.pump(const Duration(seconds: 11));
    await flush(tester);
    expect(find.text('No active assignments.'), findsNothing);
    expect(find.byType(SavedDataNotice), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    fixture.mode = 'success';
    await tester.tap(find.text('Retry'));
    await flush(tester);
    expect(find.text('No active assignments.'), findsOneWidget);
    expect(find.byType(SavedDataNotice), findsNothing);
  });
}
