import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/widgets/imaps_loading_indicator.dart';
import 'package:imaps_fieldsync/core/widgets/offline_banner.dart';
import 'package:imaps_fieldsync/modules/analytics_dashboard/screens/home_dashboard_screen.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

import 'support/offline_reliability_fixture.dart';

// Review probes for acceptance cases missing from the original ten tests.
// Every HTTP request and SQLite database belongs to the isolated fixture.
void main() {
  final fixture = OfflineReliabilityFixture();
  setUpAll(fixture.initialize);
  setUp(fixture.reset);
  tearDown(fixture.closeCase);
  tearDownAll(fixture.dispose);

  final profile = UserProfile.fromMap(offlineProfile);
  const cachedName = 'Review cached fictional applicant';
  const freshName = 'Review fresh fictional applicant';

  Map<String, dynamic> job(String id, String name) => {
    'id': id,
    'assigned_inspector_id': offlineInspector,
    'status': 'in_progress',
    'scheduled_date': '2026-10-20',
    'supabase_zoning_applications': {
      'applicant_name': name,
      'barangay': 'Fictional review site',
      'reference_number': 'FS04-REVIEW',
    },
  };

  Future<void> seed(WidgetTester tester, {bool empty = false}) async {
    await tester.runAsync(() async {
      await fixture.db.delete('inspection_job_retention');
      await DBHelper.cacheJobs(empty ? [] : [job('review-cached', cachedName)]);
    });
  }

  Future<void> settle(WidgetTester tester) async {
    for (var turn = 0; turn < 3; turn++) {
      await fixture.flush(tester);
    }
  }

  Future<void> captureReady(WidgetTester tester, String name) async {
    // Advance entrance animations through real frames; a large single pump
    // starts delayed springs but can still capture zero-opacity content.
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 200));
      await fixture.flush(tester);
    }
    await fixture.capture(tester, name);
  }

  void answer(http.Request request, List<Map<String, dynamic>> rows) {
    final held = fixture.held.singleWhere((item) => identical(item.request, request));
    held.response.complete(http.Response(jsonEncode(rows), 200,
      request: request, headers: {'content-type': 'application/json'}));
  }

  fixture.widgetTest('review: Home empty offline cache is unknown, not no assignments', (tester) async {
    await seed(tester, empty: true);
    await fixture.mount(tester, HomeDashboardScreen(profile: profile));
    await settle(tester);

    await captureReady(tester, 'review-home-empty-offline');
    expect(find.text('No active assignments.'), findsNothing,
      reason: 'no local rows and no remote answer cannot prove there is no work');
    expect(find.byType(SavedDataNotice), findsOneWidget);
  });

  fixture.widgetTest('review: Home empty cache plus failed refresh reports failure', (tester) async {
    await seed(tester, empty: true);
    fixture.online = true;
    fixture.mode = 'jobs-hold';
    await fixture.mount(tester, HomeDashboardScreen(profile: profile));
    await settle(tester);
    await tester.pump(const Duration(seconds: 11));
    await settle(tester);

    await captureReady(tester, 'review-home-empty-timeout');
    expect(find.text('No active assignments.'), findsNothing,
      reason: 'a timeout is not a successful empty assignment response');
    expect(find.byType(SavedDataNotice), findsOneWidget);
  });

  fixture.widgetTest('review: cached Tasks are identified while refresh is pending', (tester) async {
    await seed(tester);
    fixture.online = true;
    fixture.mode = 'jobs-hold';
    await fixture.mount(tester, TasksScreen(profile: profile));
    await settle(tester);

    expect(find.text(cachedName), findsOneWidget);
    await captureReady(tester, 'review-tasks-cached-refresh-pending');
    final cloud = find.byTooltip('Task data: checking for updates');
    expect(cloud, findsOneWidget,
      reason: 'cached rows must be identified before the ten-second refresh ends');
    await tester.tap(cloud);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Your saved tasks are still available.'), findsOneWidget);
    expect(find.textContaining('Last checked:'), findsNothing);
  });

  fixture.widgetTest('review: switched account cannot keep the old inspector cached cards', (tester) async {
    await seed(tester);
    fixture.online = true;
    fixture.mode = 'jobs-hold';
    await fixture.mount(tester, TasksScreen(profile: profile));
    await settle(tester);
    expect(find.text(cachedName), findsOneWidget);

    await tester.runAsync(() => fixture.client.auth.setInitialSession(
      jsonEncode(fixture.session(owner: otherOfflineInspector))));
    fixture.resolveHeld();
    await settle(tester);

    final retained = await tester.runAsync(() => fixture.db.query('local_jobs'));
    expect(retained!.single['inspector_id'], offlineInspector,
      reason: 'hiding previous-owner data must not delete its durable evidence');
    await captureReady(tester, 'review-tasks-previous-owner-still-visible');
    expect(find.text(cachedName), findsNothing,
      reason: 'discarding the late HTTP answer must also retire the previous owner display');
  });

  fixture.widgetTest('review: older Home response cannot erase newer Tasks cache', (tester) async {
    await seed(tester);
    fixture.online = true;
    fixture.mode = 'jobs-hold';
    await fixture.mount(tester, HomeDashboardScreen(profile: profile));
    await settle(tester);
    final homeRead = fixture.held.singleWhere(
      (item) => item.request.url.path == '/rest/v1/field_jobs').request;

    // This is Home's supported standalone navigation shape: pushing Tasks
    // leaves Home mounted below the new route, with its refresh still in flight.
    unawaited(Navigator.of(tester.element(find.byType(HomeDashboardScreen))).push<void>(
      MaterialPageRoute(builder: (_) => TasksScreen(profile: profile))));
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    final tasksRead = fixture.held.singleWhere((item) =>
      item.request.url.path == '/rest/v1/field_jobs' &&
      !identical(item.request, homeRead)).request;

    answer(tasksRead, [job('review-fresh', freshName)]);
    await settle(tester);
    expect(find.text(freshName), findsOneWidget);
    final before = await tester.runAsync(DBHelper.getCachedJobs);
    expect(before!.single['id'], 'review-fresh');

    // The older request completes last with an outdated empty snapshot.
    answer(homeRead, []);
    await settle(tester);
    final after = await tester.runAsync(DBHelper.getCachedJobs);
    expect(after!.map((row) => row['id']), contains('review-fresh'),
      reason: 'per-screen counters cannot protect the shared cache from another screen');
    Navigator.of(tester.element(find.byType(TasksScreen))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    expect(find.byTooltip('Task data: saved tasks, not verified'), findsOneWidget,
      reason: 'a rejected snapshot must never produce a Fresh checkmark');
    await tester.ensureVisible(find.byKey(const ValueKey('task-sync-indicator')));
    await tester.tap(find.byKey(const ValueKey('task-sync-indicator')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Showing saved task data.'), findsOneWidget);
    expect(find.textContaining('Last checked:'), findsNothing);
  });

  fixture.widgetTest('review: failed local cache read reaches a recoverable screen', (tester) async {
    await seed(tester);
    await tester.runAsync(() => fixture.db.execute(
      'ALTER TABLE local_jobs RENAME TO review_unavailable_jobs'));
    try {
      await fixture.mount(tester, TasksScreen(profile: profile));
      await settle(tester);
      await tester.pump(const Duration(seconds: 11));
      await settle(tester);

      expect(tester.takeException(), isNull,
        reason: 'a SQLite read error needs a local recovery state, not an unhandled future');
      expect(find.byType(ImapsLoadingIndicator), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
    } finally {
      await tester.runAsync(() => fixture.db.execute(
        'ALTER TABLE review_unavailable_jobs RENAME TO local_jobs'));
    }
  });
}
