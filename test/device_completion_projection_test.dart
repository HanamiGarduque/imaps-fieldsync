import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/sync_outbox_service.dart';
import 'package:imaps_fieldsync/core/widgets/offline_banner.dart';
import 'package:imaps_fieldsync/modules/inspection/providers/inspection_provider.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/completed_inspection_detail_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/review_submit_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/widgets/photo_viewer.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

import 'support/offline_reliability_fixture.dart';

const pendingBadge = 'Completed on Device — Pending Sync';
const syncedBadge = 'Completed — Synced';
final profile = UserProfile(id: offlineInspector, fullName: 'Fixture Inspector', role: 'inspector');

Map<String, dynamic> roundJob(String id, int round) => {
  'id': id, 'assigned_inspector_id': offlineInspector, 'status': 'in_progress',
  'local_inspection_id': 100 + round, 'inspection_round_number': round,
  'previous_site_inspection_id': round == 2 ? 101 : null,
  'supabase_application_id': 'fixture-application', 'bridge_source_id': 'fixture-bridge',
  'supabase_zoning_applications': {'applicant_name': 'Fictional Round $round',
    'barangay': 'Fixture Barangay', 'reference_number': 'FS04-PHASE-B'},
};

void main() {
  final fixture = OfflineReliabilityFixture();
  setUpAll(fixture.initialize);
  setUp(() async {
    await fixture.reset();
    await DBHelper.cacheJobs([roundJob(offlineJob, 1), roundJob(offlineRound2, 2)]);
  });
  tearDown(fixture.closeCase);
  tearDown(() => completedDetailFetcherOverride = null);
  tearDownAll(fixture.dispose);

  Future<void> settle(WidgetTester tester) async {
    // Advance entrance frames, not just the delayed controller start frame.
    for (var i = 0; i < 4; i++) {
      await fixture.flush(tester);
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<File> seedDraft() async {
    fixture.provider.updateFindings(actualLandUse: 'Fixture use', notes: 'Saved final findings',
      discrepancies: 'Saved discrepancy', recommendations: 'Saved recommendation',
      boundaryStatus: 'Fixture boundary');
    fixture.provider.setSiteCondition('Structure matches declared use', true);
    final photo = File('${fixture.directory.path}/evidence.png')..writeAsBytesSync(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII='));
    fixture.provider.addPhoto(photoPath: photo.path, photoNotes: 'Saved photo note', latitude: 0, longitude: 0);
    await fixture.provider.saveAllInspectionState(syncOnline: false);
    await DBHelper.saveInspectionStep(offlineJob, 5, {'5': '2026-10-16T00:00:00Z'}, offlineInspector);
    return photo;
  }

  Future<void> submit(WidgetTester tester) async {
    await fixture.mount(tester, ReviewSubmitScreen(task: offlineTask));
    await tester.tap(find.text('Submit Inspection'));
    await settle(tester);
    expect(find.byType(SubmissionSuccessScreen), findsOneWidget);
  }

  Future<void> queue() => SyncOutboxService.enqueueSubmitInspection(
    jobId: offlineJob, findings: 'Saved final findings', isCompliant: true,
    inspectionResult: 'Compliant', observations: 'Saved observations',
    inspectorNotes: 'Saved final findings', checklistData: const [
      {'item': 'Saved checklist', 'checked': true},
    ], checklistCompletedCount: 1, checklistTotalCount: 1, photosData: const []);

  Future<void> showCompleted(WidgetTester tester) async {
    await fixture.mount(tester, TasksScreen(profile: profile, initialTabIndex: TasksScreen.tabCompleted));
    await settle(tester);
  }

  Future<void> openSummary(WidgetTester tester) async {
    await showCompleted(tester);
    await tester.tap(find.text('Fictional Round 1')); await settle(tester);
    await tester.ensureVisible(find.text('Application Details'));
    await tester.tap(find.text('Application Details')); await settle(tester);
    expect(find.byType(CompletedInspectionDetailScreen), findsOneWidget);
  }

  fixture.widgetTest('offline submit restart Completed reconnect sync preserves one final identity and evidence', (tester) async {
    final photo = (await tester.runAsync(seedDraft))!;
    final bytes = photo.readAsBytesSync();
    await submit(tester);
    final action = (await tester.runAsync(DBHelper.getActionableActions))!.single;
    final payload = jsonDecode(action['payload'] as String) as Map<String, dynamic>;
    final retained = await tester.runAsync(() => fixture.db.query('inspection_job_retention'));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      fixture.provider.dispose();
      await fixture.restartDatabase();
      fixture.provider = InspectionProvider(); // No submission state survives in memory.
      SyncOutboxService.resetRecoverySessionForTesting();
    });
    await fixture.mount(tester, TasksScreen(profile: profile, initialTabIndex: TasksScreen.tabCompleted));
    await settle(tester);
    expect(find.text(pendingBadge), findsOneWidget);
    expect(find.byKey(const ValueKey(offlineJob)), findsOneWidget);
    expect(find.byKey(const ValueKey(offlineRound2)), findsNothing);
    await fixture.capture(tester, 'phaseb-pending-completed');
    expect((await tester.runAsync(DBHelper.getCachedJobs))!.firstWhere((r) => r['id'] == offlineJob)['status'], 'in_progress');
    expect(TaskItem.fromCachedJob((await tester.runAsync(DBHelper.getCachedJobs))!.firstWhere((r) => r['id'] == offlineJob)).category, 'Ongoing');
    await tester.tap(find.text('Ongoing').first); await settle(tester);
    expect(find.byKey(const ValueKey(offlineJob)), findsNothing);
    expect(find.byKey(const ValueKey(offlineRound2)), findsOneWidget);
    await tester.tap(find.text('Completed').first); await settle(tester);

    // Fake HTTP implements the actual photo writer + authorized submit/drain.
    final remote = {offlineJob: roundJob(offlineJob, 1), offlineRound2: roundJob(offlineRound2, 2)};
    final objects = <String>{};
    final photos = <String, Map<String, dynamic>>{};
    var patches = 0;
    var uploads = 0;
    fixture.requestOverride = (request) async {
      final path = request.url.path;
      http.Response reply(Object value, [int code = 200]) => http.Response(jsonEncode(value), code,
        request: request, headers: {'content-type': 'application/json'});
      if (path.startsWith('/storage/v1/object/')) {
        if (request.method == 'HEAD') return reply({}, objects.contains(path) ? 200 : 404);
        if (request.method == 'POST') { objects.add(path); uploads++; return reply({'Key': path.split('/object/').last}); }
      }
      if (path == '/rest/v1/field_job_photos') {
        if (request.method == 'GET') return reply(photos.values.toList());
        if (request.method == 'POST') {
          final row = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
          photos[row['id'] as String] = row; return reply({}, 201);
        }
      }
      if (path == '/rest/v1/field_jobs') {
        // The existing revision-only diagnostic read is not a job detail read.
        if (request.url.queryParameters['select'] != 'updated_at') {
          expect(request.url.queryParameters['assigned_inspector_id'], 'eq.$offlineInspector');
        }
        final id = request.url.queryParameters['id']?.substring(3);
        if (request.method == 'PATCH') {
          patches++; remote[id]!.addAll(jsonDecode(request.body) as Map<String, dynamic>);
          return reply([remote[id]]);
        }
        final rows = id == null ? remote.values.toList() : [if (remote[id] != null) remote[id]!];
        return reply(request.headers['accept']?.contains('object') == true ? rows.single : rows);
      }
      if (path == '/rest/v1/activity_log') return reply({}, 201);
      throw StateError('Unexpected fake request: ${request.method} $path');
    };
    fixture.online = true;
    SyncOutboxService.hasConnectionOverride = () async => true;
    await tester.runAsync(() => SyncOutboxService.drain(onlyJobId: offlineJob));
    await settle(tester);
    expect(find.text(syncedBadge), findsOneWidget);
    expect(find.text(pendingBadge), findsNothing);
    await fixture.capture(tester, 'phaseb-synced-completed');
    final synced = (await tester.runAsync(DBHelper.getRecentSyncedActions))!.single;
    expect(synced['id'], action['id']); expect(synced['created_at'], action['created_at']);
    expect(synced['payload'], action['payload']); expect(synced['status'], 'synced');
    expect(remote[offlineJob]!['status'], 'completed');
    expect(remote[offlineJob]!['findings'], payload['findings']);
    expect(remote[offlineJob]!['checklist_data'], payload['checklistData']);
    expect(photos.values.single['notes'], 'Saved photo note');
    expect((await tester.runAsync(() => DBHelper.getLocalPhotos(offlineJob)))!.single['is_synced'], 1);
    expect(photo.readAsBytesSync(), bytes);
    expect(retained, hasLength(1));
    expect(await tester.runAsync(() => fixture.db.query('inspection_job_retention')), isEmpty);
    expect(patches, 1); expect(uploads, 1);
    await tester.runAsync(() => SyncOutboxService.drain(onlyJobId: offlineJob));
    expect(patches, 1); expect(uploads, 1);
    // Capped outbox history is not the durable source of accepted completion.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await fixture.db.delete('pending_actions', where: 'id = ?', whereArgs: [action['id']]);
      await fixture.restartDatabase();
    });
    fixture.online = false;
    await showCompleted(tester);
    expect(find.text(syncedBadge), findsOneWidget);
    expect(find.byKey(const ValueKey(offlineJob)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  fixture.widgetTest('saved draft without durable final submit stays Ongoing', (tester) async {
    await tester.runAsync(seedDraft);
    await fixture.mount(tester, TasksScreen(profile: profile, initialTabIndex: TasksScreen.tabCompleted));
    await settle(tester);
    expect(find.text(pendingBadge), findsNothing);
    expect(find.byKey(const ValueKey(offlineJob)), findsNothing);
    await tester.tap(find.text('Ongoing').first); await settle(tester);
    expect(find.byKey(const ValueKey(offlineJob)), findsOneWidget);
  });

  fixture.widgetTest('pending summary rereads saved evidence instead of remote or provider edits and cannot rework', (tester) async {
    final photo = (await tester.runAsync(seedDraft))!;
    await submit(tester);
    final before = (await tester.runAsync(DBHelper.getActionableActions))!.single;
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.provider.updateFindings(actualLandUse: 'Unsaved use', notes: 'Unsaved notes',
      boundaryStatus: 'Unsaved boundary', discrepancies: 'Unsaved discrepancy', recommendations: 'Unsaved recommendation');
    var remoteReads = 0;
    completedDetailFetcherOverride = (_) async {
      remoteReads++;
      return {...roundJob(offlineJob, 1), 'status': 'completed', 'inspector_notes': 'Stale remote notes'};
    };
    final changes = await tester.runAsync(() => fixture.db.rawQuery('SELECT total_changes() AS n'));
    await openSummary(tester);
    expect(find.text(pendingBadge), findsOneWidget);
    expect(find.text('Saved submission — Read only'), findsOneWidget);
    expect(find.text('Round 1'), findsOneWidget);
    expect(find.text('Reinspection — Round 2'), findsNothing);
    expect(remoteReads, 0);
    await fixture.capture(tester, 'phaseb-pending-summary');
    for (final title in ['Photographic Evidence', 'Checklist', 'Field Findings', 'Review & Submit']) {
      await tester.dragUntilVisible(find.text(title), find.byType(ListView), const Offset(0, -200));
      await tester.tap(find.text(title)); await settle(tester);
      expect(find.text('Rework this step'), findsNothing);
    }
    expect(find.text('Saved final findings'), findsOneWidget);
    expect(find.text('Saved discrepancy'), findsOneWidget);
    expect(find.text('Saved recommendation'), findsOneWidget);
    await tester.dragUntilVisible(find.text('Saved photo note'), find.byType(ListView), const Offset(0, 200));
    expect(find.text('Saved photo note'), findsOneWidget);
    expect(tester.widget<AdaptivePhotoImage>(find.byType(AdaptivePhotoImage)).path, photo.path);
    expect(find.text('Unsaved notes'), findsNothing);
    expect(find.text('Stale remote notes'), findsNothing);
    await tester.dragUntilVisible(find.text('SAVED ON DEVICE AT'), find.byType(ListView), const Offset(0, -200));
    expect(find.text('SAVED ON DEVICE AT'), findsOneWidget);
    expect(find.text('SUBMITTED AT'), findsNothing);
    expect(await tester.runAsync(() => fixture.db.rawQuery('SELECT total_changes() AS n')), changes);
    expect((await tester.runAsync(DBHelper.getActionableActions))!.single, before);
    expect(fixture.remoteWrites, 0);
    expect(tester.takeException(), isNull);
  });

  fixture.widgetTest('pending summary retires evidence immediately when inspector changes', (tester) async {
    await tester.runAsync(queue);
    await openSummary(tester);
    expect(find.text(pendingBadge), findsOneWidget);
    final before = await tester.runAsync(() => fixture.db.query('pending_actions'));
    await tester.runAsync(() => fixture.client.auth.setInitialSession(jsonEncode(fixture.session(owner: otherOfflineInspector))));
    await settle(tester);
    expect(find.text(pendingBadge), findsNothing);
    expect(find.text('Saved final findings'), findsNothing);
    expect(find.text(SavedDataNotice.ownerChanged), findsWidgets);
    expect(await tester.runAsync(() => fixture.db.query('pending_actions')), before);
  });

  fixture.widgetTest('photo-free drain shows durable Syncing while authority read waits then Review Required on refusal', (tester) async {
    await tester.runAsync(queue);
    await showCompleted(tester);
    fixture.online = true;
    final response = Completer<http.Response>();
    fixture.requestOverride = (request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/rest/v1/field_jobs');
      expect(request.url.queryParameters['assigned_inspector_id'], 'eq.$offlineInspector');
      final reply = await response.future;
      return http.Response(reply.body, reply.statusCode, headers: reply.headers, request: request);
    };
    late Future<void> draining;
    await tester.runAsync(() async {
      draining = SyncOutboxService.drain(trigger: 'manual', onlyJobId: offlineJob);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    try {
      await settle(tester);
      expect(find.text('Completed on Device — Syncing'), findsOneWidget);
      expect(find.text(syncedBadge), findsNothing);
    } finally {
      response.complete(http.Response('[]', 200, headers: {'content-type': 'application/json'}));
      await tester.runAsync(() => draining);
    }
    await settle(tester);
    expect(find.text('Completed on Device — Review Required'), findsOneWidget);
    expect(find.textContaining('Rejected'), findsNothing); // Missing authority is not a proven rejection reason.
    expect(find.text(syncedBadge), findsNothing);
    final rows = (await tester.runAsync(DBHelper.getSyncCenterQueueActions))!;
    expect(rows.single['status'], 'conflict');
    expect((await tester.runAsync(DBHelper.getCachedJobs))!.firstWhere((j) => j['id'] == offlineJob)['status'], 'in_progress');
    expect(await tester.runAsync(() => fixture.db.query('inspection_job_retention')), hasLength(1));
  });

  for (final state in {
    'pending': pendingBadge, 'syncing': 'Completed on Device — Syncing',
    'paused': 'Completed on Device — Sync Paused', 'failed': 'Completed on Device — Sync Failed',
    'conflict': 'Completed on Device — Review Required', 'synced': 'Completed on Device — Acceptance Unverified',
  }.entries) {
    fixture.widgetTest('${state.key} final intent never invents server acceptance or permits scheduling', (tester) async {
      await tester.runAsync(() async {
        await queue();
        await fixture.db.update('pending_actions', {'status': state.key});
      });
      await showCompleted(tester);
      expect(find.text(state.value), findsOneWidget);
      expect(find.text(syncedBadge), findsNothing);
      await tester.tap(find.byTooltip('About task details for Fictional Round 1')); await settle(tester);
      expect(find.textContaining('Server acceptance is not confirmed.'), findsOneWidget);
      expect(find.text('The server has confirmed this inspection.'), findsNothing);
      await tester.tap(find.text('Close')); await settle(tester);
      await tester.tap(find.text('Fictional Round 1')); await settle(tester);
      expect(find.textContaining('Schedule Inspection Date'), findsNothing);
      expect(find.textContaining('Reschedule Inspection Date'), findsNothing);
      await tester.tap(find.text('Ongoing').first); await settle(tester);
      expect(find.byKey(const ValueKey(offlineJob)), findsNothing);
      expect(find.byKey(const ValueKey(offlineRound2)), findsOneWidget);
    });
  }

  for (final failure in ['ABORT', 'IGNORE']) {
    fixture.widgetTest('SQLite $failure does not project an unsaved final submit into Completed', (tester) async {
      await tester.runAsync(seedDraft);
      await tester.runAsync(() => fixture.db.execute(
        "CREATE TRIGGER reject_final BEFORE INSERT ON pending_actions BEGIN SELECT RAISE($failure${failure == 'ABORT' ? ",'fixture failure'" : ''}); END"));
      await fixture.mount(tester, ReviewSubmitScreen(task: offlineTask));
      await tester.tap(find.text('Submit Inspection')); await settle(tester);
      expect(find.byType(SubmissionSuccessScreen), findsNothing);
      expect(find.textContaining('Could not save locally'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await showCompleted(tester);
      expect(find.byKey(const ValueKey(offlineJob)), findsNothing);
      expect(find.text(pendingBadge), findsNothing);
      await tester.tap(find.text('Ongoing').first); await settle(tester);
      expect(find.byKey(const ValueKey(offlineJob)), findsOneWidget);
    });
  }

  fixture.widgetTest('unreadable final intent shows recoverable local-read failure without false Ongoing membership', (tester) async {
    await tester.runAsync(() async {
      await queue();
      await fixture.db.update('pending_actions', {'payload': '{broken-json'});
    });
    await showCompleted(tester);
    expect(find.text(SavedDataNotice.cacheReadFailed), findsWidgets);
    expect(find.text(pendingBadge), findsNothing);
    expect(find.byKey(const ValueKey(offlineJob)), findsNothing);
  });

  fixture.widgetTest('stale remote assignment refresh cannot remove retained pending Completed projection', (tester) async {
    await tester.runAsync(queue);
    fixture.online = true; fixture.mode = 'jobs-hold';
    await showCompleted(tester);
    expect(find.text(pendingBadge), findsOneWidget);
    fixture.jobsRows = [roundJob(offlineRound2, 2)];
    fixture.resolveHeld(); await settle(tester);
    expect(find.text(pendingBadge), findsOneWidget);
    expect(find.byTooltip('Task data: up to date'), findsOneWidget);
    expect(find.text(syncedBadge), findsNothing);
    await fixture.capture(tester, 'assignment-fresh-report-still-pending-sync');
    expect(find.byKey(const ValueKey(offlineJob)), findsOneWidget);
    expect((await tester.runAsync(DBHelper.getCachedJobs))!.firstWhere((j) => j['id'] == offlineJob)['status'], 'in_progress');
  });

  fixture.widgetTest('obsolete unreadable synced receipt cannot hide a newer durable final intent', (tester) async {
    await tester.runAsync(() async {
      await queue();
      final action = (await DBHelper.getActionableActions()).single;
      await fixture.db.insert('pending_actions', {...action, 'id': 'obsolete-receipt',
        'status': 'synced', 'payload': '{unreadable'});
    });
    await showCompleted(tester);
    expect(find.text(pendingBadge), findsOneWidget);
    expect(find.byKey(const ValueKey(offlineJob)), findsOneWidget);
  });

  fixture.widgetTest('canonical accepted completion does not depend on parsing old synced receipts', (tester) async {
    await tester.runAsync(() async {
      await queue();
      await fixture.db.update('local_jobs', {'status': 'completed'}, where: 'id = ?', whereArgs: [offlineJob]);
      await fixture.db.update('pending_actions', {'status': 'synced', 'payload': '{obsolete'});
    });
    await showCompleted(tester);
    expect(find.text(syncedBadge), findsOneWidget);
    expect(find.byKey(const ValueKey(offlineJob)), findsOneWidget);
  });

  for (final refused in [false, true]) {
    fixture.widgetTest('real drain ${refused ? 'server refusal' : 'transport failure'} preserves final evidence and reports Sync Failed', (tester) async {
      await tester.runAsync(queue);
      final action = (await tester.runAsync(DBHelper.getActionableActions))!.single;
      await showCompleted(tester);
      fixture.requestOverride = (request) async {
        if (!refused) throw const SocketException('Isolated unavailable transport');
        return http.Response(jsonEncode(request.method == 'GET'
          ? [roundJob(offlineJob, 1)] : {'code': '42501', 'message': 'Fictional permission refusal'}),
          request.method == 'GET' ? 200 : 403, request: request,
          headers: {'content-type': 'application/json'});
      };
      await tester.runAsync(() => SyncOutboxService.drain(trigger: 'manual', onlyJobId: offlineJob));
      await settle(tester);
      expect(find.text('Completed on Device — Sync Failed'), findsOneWidget);
      expect(find.text(syncedBadge), findsNothing);
      final failed = (await tester.runAsync(DBHelper.getSyncCenterQueueActions))!.single;
      expect(failed['id'], action['id']); expect(failed['payload'], action['payload']);
      expect(failed['status'], 'failed');
      expect((await tester.runAsync(DBHelper.getCachedJobs))!.firstWhere((j) => j['id'] == offlineJob)['status'], 'in_progress');
      expect(await tester.runAsync(() => fixture.db.query('inspection_job_retention')), hasLength(1));
    });
  }

  test('presentation snapshot is read-only and owner-scoped across session changes', () async {
    await queue();
    final action = (await DBHelper.getActionableActions()).single;
    final before = await fixture.db.rawQuery('SELECT total_changes() AS n');
    final snapshot = await DBHelper.getTaskPresentationSnapshot();
    expect(snapshot.jobs.map((r) => r['id']), containsAll([offlineJob, offlineRound2]));
    expect(snapshot.submissions.single['id'], action['id']);
    expect(await fixture.db.rawQuery('SELECT total_changes() AS n'), before);
    await fixture.client.auth.setInitialSession(jsonEncode(fixture.session(owner: otherOfflineInspector)));
    final foreign = await DBHelper.getTaskPresentationSnapshot();
    expect(foreign.jobs, isEmpty); expect(foreign.submissions, isEmpty);
    expect((await fixture.db.query('pending_actions')).single, action);
  });

  fixture.widgetTest('pending Completed badge and saved summary fit a narrow phone with enlarged text', (tester) async {
    await tester.runAsync(queue);
    await fixture.mount(tester, TasksScreen(profile: profile, initialTabIndex: TasksScreen.tabCompleted),
      size: const Size(320, 844), textScale: 1.3);
    await settle(tester);
    final badge = find.text(pendingBadge);
    expect(badge.hitTestable(), findsOneWidget);
    expect(tester.getRect(badge).left, greaterThan(0));
    expect(tester.getRect(badge).right, lessThan(320));
    final selectedTab = tester.getRect(find.text('Completed'));
    expect(selectedTab.left, greaterThanOrEqualTo(20));
    expect(selectedTab.right, lessThanOrEqualTo(300));
    expect(tester.takeException(), isNull);
    await fixture.capture(tester, 'phaseb-pending-narrow-large-text');
    await tester.tap(find.text('Fictional Round 1')); await settle(tester);
    await tester.ensureVisible(find.text('Application Details'));
    await tester.tap(find.text('Application Details')); await settle(tester);
    expect(find.text(pendingBadge).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await fixture.capture(tester, 'phaseb-summary-narrow-large-text');
  });
}
