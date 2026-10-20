import 'dart:convert';
import 'dart:io';

import 'package:imaps_fieldsync/core/services/supabase_service.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/models/dashboard_stats.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/sync_outbox_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Offline submission is PRESERVED INTENT, never proof of completion. These
/// tests pin that contract: a queued submit keeps the job's unfinished local
/// lifecycle, keeps retention, and is finalized only by a proven remote
/// acceptance (the drain or the online Review & Submit path).
Future<void> submitFixture(String jobId) =>
    SyncOutboxService.enqueueSubmitInspection(
      jobId: jobId,
      findings: 'Isolated test findings',
      isCompliant: true,
      inspectionResult: 'Compliant',
      observations: 'Isolated observations',
      inspectorNotes: 'Isolated notes',
      checklistData: const [],
      checklistCompletedCount: 0,
      checklistTotalCount: 0,
      photosData: const [],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory temporary;
  late Database db;
  late HttpServer server;
  var remoteJobs = <Map<String, dynamic>>[];
  var patches = 0;
  final requestMethods = <String>[];
  final testHttpOverrides = HttpOverrides.current;

  setUpAll(() async {
    // Allow the explicitly configured loopback server instead of Flutter's
    // default HTTP-400 stub. No .env or deployed Supabase URL is loaded.
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      requestMethods.add(request.method);
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET' && request.uri.path == '/rest/v1/field_jobs') {
        if (request.uri.queryParameters.containsKey('id')) {
          final id = request.uri.queryParameters['id']!.substring(3);
          final matches = remoteJobs.where((job) => job['id'] == id);
          request.response.write(jsonEncode(matches.toList()));
        } else {
          expect(
            request.uri.queryParameters['assigned_inspector_id'],
            'eq.fixture-inspector',
          );
          request.response.write(jsonEncode(remoteJobs));
        }
      } else if (request.method == 'PATCH' &&
          request.uri.path == '/rest/v1/field_jobs') {
        patches++;
        final update = jsonDecode(body) as Map<String, dynamic>;
        final id = request.uri.queryParameters['id']!.substring(3);
        final matches = remoteJobs.where((job) => job['id'] == id);
        if (matches.isEmpty) {
          // Zero rows: no longer visible/owned under this inspector.
          request.response.write('[]');
        } else {
          final job = matches.first;
          job.addAll(update);
          // The writer requires the returned representation to prove the write.
          request.response.write(jsonEncode([job]));
        }
      } else if (request.method == 'POST' &&
          request.uri.path == '/rest/v1/activity_log') {
        request.response.statusCode = 201;
      } else {
        fail(
          'Unexpected isolated request: ${request.method} ${request.uri.path}',
        );
      }
      await request.response.close();
    });
    await Supabase.initialize(
      url: 'http://127.0.0.1:${server.port}',
      publishableKey: 'isolated-fixture-key',
      authOptions: FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
    );
    await SupabaseService.client.auth.setInitialSession(
      jsonEncode({
        'access_token': 'isolated-token',
        'refresh_token': 'isolated-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': 'fixture-inspector',
          'app_metadata': {},
          'user_metadata': {},
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
        },
      }),
    );
  });

  tearDownAll(() async {
    await Supabase.instance.dispose();
    await server.close(force: true);
    HttpOverrides.global = testHttpOverrides;
  });

  setUp(() async {
    patches = 0;
    requestMethods.clear();
    remoteJobs = [
      {'id': 'fixture-A', 'status': 'in_progress', 'assigned_inspector_id': 'fixture-inspector'},
      {'id': 'fixture-B', 'status': 'in_progress', 'assigned_inspector_id': 'fixture-inspector'},
    ];
    temporary = await Directory.systemTemp.createTemp('fieldsync-loop-1dr-');
    db = await databaseFactoryFfi.openDatabase('${temporary.path}/fixture.db');
    // Execute the existing production CREATE TABLE statements, not a second
    // hand-maintained schema. No application database or credentials are used.
    final source = await File(
      'lib/core/services/db_helper.dart',
    ).readAsString();
    for (final match in RegExp(
      r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)',
    ).allMatches(source)) {
      await db.execute(match.group(0)!);
    }
    DBHelper.useDatabaseForTesting(db);
    await DBHelper.cacheJobs([
      {'id': 'fixture-A', 'status': 'in_progress', 'assigned_inspector_id': 'fixture-inspector'},
      {'id': 'fixture-B', 'status': 'in_progress', 'assigned_inspector_id': 'fixture-inspector'},
    ]);
  });

  tearDown(() async {
    DBHelper.useDatabaseForTesting(null);
    await db.close();
    await temporary.delete(recursive: true);
  });

  /// The one legitimate way a local round becomes Completed: a proven remote
  /// acceptance followed by the explicit finalization.
  Future<void> acceptOnline(String jobId) async {
    final result = await SupabaseService.submitInspection(
      jobId: jobId,
      findings: 'Isolated test findings',
      isCompliant: true,
      inspectionResult: 'Compliant',
    );
    expect(result, InspectionAuthorityResult.authorized);
    expect(
      await DBHelper.finalizeAcceptedOnlineInspection(jobId, remoteResult: result),
      isTrue,
    );
  }

  for (final failCleanup in [false, true]) {
    test('R2A loopback online acceptance once, cleanup failure=$failCleanup', () async {
      const id = '11111111-1111-4111-8111-111111111111';
      remoteJobs = [{'id': id, 'status': 'in_progress', 'assigned_inspector_id': 'fixture-inspector'}];
      await DBHelper.retainInspectionJob(id, fetchedJob: remoteJobs.single);
      if (failCleanup) {
        await db.execute("CREATE TRIGGER reject_cleanup BEFORE DELETE ON inspection_job_retention BEGIN SELECT RAISE(ABORT, 'isolated cleanup failure'); END");
      }
      // Actual production submission against loopback only. Like ReviewSubmit,
      // local finalization follows confirmed remote success, outside retry logic.
      final result = await SupabaseService.submitInspection(jobId: id, findings: 'Fixture',
          isCompliant: true, inspectionResult: 'Compliant');
      expect(remoteJobs.single['status'], 'completed');
      expect(
        await DBHelper.finalizeAcceptedOnlineInspection(id, remoteResult: result),
        !failCleanup,
      );
      expect(patches, 1);
      expect(await DBHelper.getActionableActions(), isEmpty);
      expect(await db.query('inspection_job_retention'), hasLength(failCleanup ? 1 : 0));
      if (failCleanup) {
        await db.execute('DROP TRIGGER reject_cleanup');
        await DBHelper.cacheJobs(await SupabaseService.fetchMyJobs());
      }
      expect((await DBHelper.getCachedJobs()).firstWhere((j) => j['id'] == id)['status'], 'completed');
      expect(await db.query('inspection_job_retention'), isEmpty);
      expect(patches, 1); // Cache recovery never resubmits the business action.
    });
  }

  test('offline enqueue preserves lifecycle, retention and exact payload', () async {
    await submitFixture('fixture-A');
    final jobs = await DBHelper.getCachedJobs();
    expect(jobs.firstWhere((j) => j['id'] == 'fixture-A')['status'], 'in_progress');
    expect(jobs.firstWhere((j) => j['id'] == 'fixture-B')['status'], 'in_progress');
    final actions = await DBHelper.getActionableActions();
    expect(actions, hasLength(1));
    expect(actions.single['job_id'], 'fixture-A');
    expect(actions.single['type'], 'submit_inspection');
    expect(actions.single['status'], 'pending');
    expect(
      jsonDecode(actions.single['payload'] as String)['findings'],
      'Isolated test findings',
    );
  });

  test('unproven remote submission never finalizes the local round', () async {
    await submitFixture('fixture-A');
    // Zero visible rows: authority cannot be proven, so nothing may finalize.
    remoteJobs = [{'id': 'fixture-B', 'status': 'in_progress', 'assigned_inspector_id': 'fixture-inspector'}];
    final result = await SupabaseService.submitInspection(jobId: 'fixture-A',
        findings: 'Isolated test findings', isCompliant: true,
        inspectionResult: 'Compliant');
    expect(result, InspectionAuthorityResult.notAssignedOrUnavailable);
    expect(
      await DBHelper.finalizeAcceptedOnlineInspection('fixture-A', remoteResult: result),
      isFalse,
    );
    expect((await DBHelper.getCachedJobs()).first['status'], 'in_progress');
  });

  test('proven remote submission finalizes exactly once', () async {
    await submitFixture('fixture-A');
    await acceptOnline('fixture-A');
    expect((await DBHelper.getCachedJobs()).first['status'], 'completed');
    expect(await db.query('inspection_job_retention'), isEmpty);
    expect(
      (await DBHelper.getActionableActions()).single['status'],
      'pending',
      reason: 'Finalization does not itself acknowledge the queued submission.',
    );
    expect(patches, 1);
  });

  for (final table in ['pending_actions']) {
    test('failure in $table rolls back the queued submission', () async {
      await db.execute(
        'CREATE TRIGGER reject_write BEFORE INSERT ON $table '
        "BEGIN SELECT RAISE(ABORT, 'fixture failure'); END",
      );
      await expectLater(
        submitFixture('fixture-A'),
        throwsA(isA<DatabaseException>()),
      );
      expect(await DBHelper.getActionableActions(), isEmpty);
      expect((await DBHelper.getCachedJobs()).first['status'], 'in_progress');
    });
  }

  test('legacy Pending fixture stays canonical through a queued submit', () async {
    await DBHelper.cacheJobs([
      {'id': 'fixture-A', 'status': 'Pending', 'assigned_inspector_id': 'fixture-inspector'},
    ]);
    // Start transition is a fixture precondition, not a repair to start logic.
    await DBHelper.cacheJobs([
      {'id': 'fixture-A', 'status': 'in_progress', 'assigned_inspector_id': 'fixture-inspector'},
    ]);
    await submitFixture('fixture-A');
    expect((await DBHelper.getCachedJobs()).single['status'], 'in_progress');
  });

  test('queued submission keeps an unfinished round Open, not Completed', () async {
    await DBHelper.cacheJobs([
      {'id': 'fixture-A', 'status': 'in_progress', 'assigned_inspector_id': 'fixture-inspector', 'is_self_scheduled': true},
    ]);
    await submitFixture('fixture-A');
    final before = await DBHelper.getActionableActions();
    await db.close();
    db = await databaseFactoryFfi.openDatabase('${temporary.path}/fixture.db');
    DBHelper.useDatabaseForTesting(db);
    final cached = (await DBHelper.getCachedJobs()).single;
    final task = TaskItem.fromJob({
      ...cached,
      'is_self_scheduled': cached['is_self_scheduled'] == 1,
    });
    expect(task.category, 'Pending');
    expect(task.pendingSection, PendingTaskSection.scheduled);
    expect(task.status, 'in_progress', reason: 'queued final intent is not server acceptance');
    expect(await DBHelper.getActionableActions(), before);
  });

  for (final status in [
    'assigned',
    'Pending',
    'pending',
    'in_progress',
    'in-progress',
    'ongoing',
  ]) {
    test('stale remote $status never rewrites a preserved queued round', () async {
      await submitFixture('fixture-A');
      remoteJobs.first['status'] = status;
      final before = jsonEncode(remoteJobs);
      final fetched = await SupabaseService.fetchMyJobs();
      expect(fetched.first['status'], status);
      expect(TaskItem.fromJob(fetched.first).category, isNot('Completed'));
      expect(TaskItem.fromJob(fetched.last).category, 'Ongoing');
      await DBHelper.cacheJobs(remoteJobs);
      expect((await DBHelper.getCachedJobs()).first['status'], status);
      expect(jsonEncode(remoteJobs), before);
      expect(patches, 0);
    });
  }

  for (final status in ['completed', 'Completed', 'submitted']) {
    test('canonical remote $status classifies Completed', () async {
      remoteJobs.first['status'] = status;
      final fetched = await SupabaseService.fetchMyJobs();
      expect(fetched.first['status'], status);
      expect(TaskItem.fromJob(fetched.first).category, 'Completed');
      await DBHelper.cacheJobs(fetched);
      expect((await DBHelper.getCachedJobs()).first['status'], status);
    });
  }

  for (final state in ['pending', 'failed', 'syncing', 'conflict']) {
    test('unacknowledged $state retains payload and unfinished lifecycle', () async {
      await submitFixture('fixture-A');
      final action = (await DBHelper.getActionableActions()).single;
      final id = action['id'] as String;
      if (state == 'failed') {
        await DBHelper.markActionSyncing(id);
        await DBHelper.markActionFailed(id, 'fixture failure');
      }
      if (state == 'syncing') await DBHelper.markActionSyncing(id);
      if (state == 'conflict') {
        await DBHelper.markActionSyncing(id);
        await DBHelper.markActionConflict(id, 'fixture conflict');
      }
      expect((await SupabaseService.fetchMyJobs()).first['status'], 'in_progress');
      await DBHelper.cacheJobs(remoteJobs);
      final queued = (await DBHelper.getSyncCenterQueueActions()).single;
      expect(queued['status'], state);
      expect(queued['payload'], action['payload']);
      expect((await DBHelper.getCachedJobs()).first['status'], 'in_progress');
    });
  }

  test('mock reconnect drain finalizes the round it actually completed', () async {
    await submitFixture('fixture-A');
    final id = (await DBHelper.getActionableActions()).single['id'];
    await SyncOutboxService.drain(onlyJobId: 'fixture-A');
    final acknowledged = (await DBHelper.getRecentSyncedActions()).single;
    expect(acknowledged['id'], id);
    expect(acknowledged['status'], 'synced');
    expect(remoteJobs.first['status'], 'completed');
    expect(patches, 1);
    await SyncOutboxService.drain(onlyJobId: 'fixture-A');
    expect(patches, 1);
    expect((await DBHelper.getCachedJobs()).first['status'], 'completed');
    expect(await db.query('inspection_job_retention'), isEmpty);
  });

  test('acknowledgement without proven completion never completes locally', () async {
    // Authority loss: the action is preserved as a conflict, never synced.
    await submitFixture('fixture-A');
    remoteJobs = [{'id': 'fixture-B', 'status': 'in_progress', 'assigned_inspector_id': 'fixture-inspector'}];
    await SyncOutboxService.drain(onlyJobId: 'fixture-A');
    final queued = (await DBHelper.getSyncCenterQueueActions()).single;
    expect(queued['status'], 'conflict');
    expect(await DBHelper.getRecentSyncedActions(), isEmpty);
    expect((await DBHelper.getCachedJobs()).first['status'], 'in_progress');
  });

  test('repeated final submit preserves one intent and its first identity', () async {
    await submitFixture('fixture-A');
    final first = (await DBHelper.getActionableActions()).single;
    await submitFixture('fixture-A');
    final actions = await DBHelper.getActionableActions();
    expect(actions, hasLength(1));
    expect(actions.single['id'], first['id']);
    expect(actions.single['payload'], first['payload']);
  });

  test('one acknowledged legacy duplicate does not erase another pending submit', () async {
    await submitFixture('fixture-A');
    // A prior version could persist two UUIDs. Preserve those real disk rows;
    // new final-submit retries must not create another one.
    final first = (await DBHelper.getActionableActions()).single;
    await db.insert('pending_actions', {...first, 'id': 'legacy-duplicate-submit'});
    final actions = await DBHelper.getActionableActions();
    expect(actions, hasLength(2));
    await DBHelper.markActionSynced(actions.first['id'] as String);
    expect((await SupabaseService.fetchMyJobs()).first['status'], 'in_progress');
  });

  test(
    'other action types preserve lifecycle and existing deduplication',
    () async {
      await SyncOutboxService.enqueueMarkOngoing(jobId: 'fixture-A');
      await SyncOutboxService.enqueueMarkOngoing(jobId: 'fixture-A');
      expect(await DBHelper.getActionableActions(), hasLength(1));
      expect((await DBHelper.getCachedJobs()).first['status'], 'in_progress');
    },
  );

  test('remote omission preserves only retained local evidence', () async {
    await DBHelper.retainInspectionJob('fixture-A',
        fetchedJob: remoteJobs.first);
    await submitFixture('fixture-A');
    await DBHelper.cacheJobs([]);
    final cached = await DBHelper.getCachedJobs();
    expect(cached, hasLength(1));
    expect(cached.single['id'], 'fixture-A');
    expect(cached.single['status'], 'in_progress');
    expect(await DBHelper.getActionableActions(), hasLength(1));
  });

  test('unsupported remote values stay excluded and available', () async {
    for (final status in ['onprocess', 'cancelled', 'unknown_value']) {
      remoteJobs = [
        {'id': 'fixture-A', 'status': status, 'assigned_inspector_id': 'fixture-inspector'},
        {'id': 'fixture-B', 'status': 'in_progress', 'assigned_inspector_id': 'fixture-inspector'},
      ];
      final fetched = await SupabaseService.fetchMyJobs();
      expect(fetched.first['status'], status);
      expect(['Pending', 'Ongoing', 'Completed'],
          isNot(contains(TaskItem.fromJob(fetched.first).category)));
      await DBHelper.cacheJobs(fetched);
      expect((await DBHelper.getCachedJobs()).first['status'], status);
      expect(patches, 0);
    }
  });

  test('statistics count only proven completions', () async {
    await submitFixture('fixture-A'); // Intended completion, not proven.
    final stats = InspectorDashboardStats.fromTasks(
      (await SupabaseService.fetchMyJobs()).map(TaskItem.fromJob).toList(),
    );
    expect(stats.totalAssigned, 2);
    expect(stats.completedCount, 0);
    expect(stats.activeWorkloadCount, 2);
    await acceptOnline('fixture-A');
    final proven = InspectorDashboardStats.fromTasks(
      (await SupabaseService.fetchMyJobs()).map(TaskItem.fromJob).toList(),
    );
    expect(proven.completedCount, 1);
    expect(proven.activeWorkloadCount, 1);
    expect(patches, 1);
  });
}
