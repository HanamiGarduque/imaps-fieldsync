import 'dart:convert';
import 'dart:io';

import 'package:imaps_fieldsync/core/services/supabase_service.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';
import 'package:imaps_fieldsync/modules/analytics_dashboard/screens/home_dashboard_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/models/dashboard_stats.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/sync_outbox_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
      if (request.method == 'GET' &&
          request.uri.path == '/rest/v1/field_jobs') {
        if (request.uri.queryParameters.containsKey('id')) {
          final id = request.uri.queryParameters['id']!.substring(3);
          final job = remoteJobs.firstWhere((job) => job['id'] == id);
          request.response.write(jsonEncode({'updated_at': job['updated_at']}));
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
        remoteJobs.firstWhere((job) => job['id'] == id).addAll(update);
        request.response.statusCode = 204;
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
      {'id': 'fixture-A', 'status': 'in_progress'},
      {'id': 'fixture-B', 'status': 'in_progress'},
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
      {'id': 'fixture-A', 'status': 'in_progress'},
      {'id': 'fixture-B', 'status': 'in_progress'},
    ]);
  });

  tearDown(() async {
    DBHelper.useDatabaseForTesting(null);
    await db.close();
    await temporary.delete(recursive: true);
  });

  for (final failCleanup in [false, true]) {
    test('R2A loopback online acceptance once, cleanup failure=$failCleanup', () async {
      const id = '11111111-1111-4111-8111-111111111111';
      remoteJobs = [{'id': id, 'status': 'in_progress'}];
      await DBHelper.retainInspectionJob(id, fetchedJob: remoteJobs.single);
      if (failCleanup) {
        await db.execute("CREATE TRIGGER reject_cleanup BEFORE DELETE ON inspection_job_retention BEGIN SELECT RAISE(ABORT, 'isolated cleanup failure'); END");
      }
      // Actual production submission against loopback only. Like ReviewSubmit,
      // local finalization follows confirmed remote success, outside retry logic.
      await SupabaseService.submitInspection(jobId: id, findings: 'Fixture',
          isCompliant: true, inspectionResult: 'Compliant');
      expect(remoteJobs.single['status'], 'completed');
      expect(await DBHelper.finalizeAcceptedOnlineInspection(id), !failCleanup);
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

  test(
    'production enqueue commits pending submit and exact local completed',
    () async {
      await submitFixture('fixture-A');
      final jobs = await DBHelper.getCachedJobs();
      expect(
        jobs.firstWhere((j) => j['id'] == 'fixture-A')['status'],
        'completed',
      );
      expect(
        jobs.firstWhere((j) => j['id'] == 'fixture-B')['status'],
        'in_progress',
      );
      final actions = await DBHelper.getActionableActions();
      expect(actions, hasLength(1));
      expect(actions.single['job_id'], 'fixture-A');
      expect(actions.single['type'], 'submit_inspection');
      expect(actions.single['status'], 'pending');
      expect(
        jsonDecode(actions.single['payload'] as String)['findings'],
        'Isolated test findings',
      );
    },
  );

  for (final table in ['pending_actions', 'local_jobs']) {
    test('failure in $table rolls back both required effects', () async {
      final operation = table == 'pending_actions' ? 'INSERT' : 'UPDATE';
      await db.execute(
        'CREATE TRIGGER reject_write BEFORE $operation ON $table '
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

  test('missing exact cache row rejects submission atomically', () async {
    await expectLater(submitFixture('fixture-missing'), throwsStateError);
    expect(await DBHelper.getActionableActions(), isEmpty);
  });

  test('legacy Pending fixture starts canonically then completes', () async {
    await DBHelper.cacheJobs([
      {'id': 'fixture-A', 'status': 'Pending'},
    ]);
    // Start transition is a fixture precondition, not a repair to start logic.
    await DBHelper.cacheJobs([
      {'id': 'fixture-A', 'status': 'in_progress'},
    ]);
    await submitFixture('fixture-A');
    expect((await DBHelper.getCachedJobs()).single['status'], 'completed');
  });

  test('self-scheduled task remains Completed after database reopen', () async {
    await DBHelper.cacheJobs([
      {'id': 'fixture-A', 'status': 'in_progress', 'is_self_scheduled': true},
    ]);
    await submitFixture('fixture-A');
    final before = await DBHelper.getActionableActions();
    await db.close();
    db = await databaseFactoryFfi.openDatabase('${temporary.path}/fixture.db');
    DBHelper.useDatabaseForTesting(db);
    final cached = (await DBHelper.getCachedJobs()).single;
    // Current screens use fromJob with cached status, not fromOfflineCache.
    final task = TaskItem.fromJob({
      ...cached,
      'is_self_scheduled': cached['is_self_scheduled'] == 1,
    });
    expect(task.category, 'Completed');
    expect(task.isSelfScheduled, isTrue);
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
    test('fetch and cache protect stale $status with job isolation', () async {
      await submitFixture('fixture-A');
      remoteJobs.first.addAll({
        'status': status,
        'extra_remote_field': {'retained': true},
        'local_inspection_id': 19,
        'supabase_parcel_id': 'shared-parcel',
      });
      remoteJobs.last.addAll({
        'local_inspection_id': 19,
        'supabase_parcel_id': 'shared-parcel',
      });
      final before = jsonEncode(remoteJobs);
      final fetched = await SupabaseService.fetchMyJobs();
      expect(fetched.first, {...remoteJobs.first, 'status': 'completed'});
      expect(fetched.last, remoteJobs.last);
      expect(TaskItem.fromJob(fetched.first).category, 'Completed');
      expect(
        isHomeDashboardActiveAssignment(TaskItem.fromJob(fetched.first)),
        isFalse,
      );
      expect(TaskItem.fromJob(fetched.last).category, 'Ongoing');
      expect(
        homeDashboardTaskPresentationCategory(TaskItem.fromJob(fetched.first)),
        'Completed',
      );
      expect(
        homeDashboardTaskPresentationCategory(TaskItem.fromJob(fetched.last)),
        'Ongoing',
      );
      await DBHelper.cacheJobs(remoteJobs); // Also exercise raw remote caching.
      expect((await DBHelper.getCachedJobs()).first['status'], 'completed');
      expect(jsonEncode(remoteJobs), before);
      expect(patches, 0);
    });
  }

  for (final status in ['completed', 'Completed', 'submitted']) {
    for (final pending in [false, true]) {
      test(
        'completed equivalent $status unchanged, pending=$pending',
        () async {
          if (pending) await submitFixture('fixture-A');
          remoteJobs.first['status'] = status;
          final fetched = await SupabaseService.fetchMyJobs();
          expect(fetched.first['status'], status);
          expect(TaskItem.fromJob(fetched.first).category, 'Completed');
          // Remote already agrees with completion: no conflict evidence.
          expect(fetched.first.containsKey('_localPendingCompletionConflict'), isFalse);
          expect(fetched.first.containsKey('_remoteStatusSnapshot'), isFalse);
          await DBHelper.cacheJobs(fetched);
          expect((await DBHelper.getCachedJobs()).first['status'], status);
        },
      );
    }
  }

  for (final state in ['pending', 'failed', 'syncing', 'conflict']) {
    test('unacknowledged $state retains completion and payload', () async {
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
      expect(
        (await SupabaseService.fetchMyJobs()).first['status'],
        'completed',
      );
      await DBHelper.cacheJobs(remoteJobs);
      final queued = (await DBHelper.getSyncCenterQueueActions()).single;
      expect(queued['status'], state);
      expect(queued['payload'], action['payload']);
      expect((await DBHelper.getCachedJobs()).first['status'], 'completed');
    });
  }

  test(
    'acknowledgement ends pending-submit projection but cached completion remains terminal',
    () async {
      await submitFixture('fixture-A');
      final action = (await DBHelper.getActionableActions()).single;
      expect(
        (await SupabaseService.fetchMyJobs()).first['status'],
        'completed',
      );
      await DBHelper.markActionSyncing(action['id'] as String);
      await DBHelper.markActionSynced(action['id'] as String);
      expect(
        (await SupabaseService.fetchMyJobs()).first['status'],
        'in_progress',
      );
      await DBHelper.cacheJobs(remoteJobs);
      expect((await DBHelper.getCachedJobs()).first['status'], 'completed');
      remoteJobs.first['status'] = 'completed';
      await DBHelper.cacheJobs(await SupabaseService.fetchMyJobs());
      expect((await DBHelper.getCachedJobs()).first['status'], 'completed');
    },
  );

  test(
    'mock reconnect drain acknowledges same action once and converges',
    () async {
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
      await DBHelper.cacheJobs(await SupabaseService.fetchMyJobs());
      expect((await DBHelper.getCachedJobs()).first['status'], 'completed');
    },
  );

  test(
    'one acknowledged submit does not erase another pending submit',
    () async {
      await submitFixture('fixture-A');
      await submitFixture('fixture-A');
      final actions = await DBHelper.getActionableActions();
      expect(actions, hasLength(2)); // Existing UUID-per-submit contract.
      await DBHelper.markActionSynced(actions.first['id'] as String);
      expect(
        (await SupabaseService.fetchMyJobs()).first['status'],
        'completed',
      );
    },
  );

  test(
    'other action types preserve lifecycle and existing deduplication',
    () async {
      await SyncOutboxService.enqueueMarkOngoing(jobId: 'fixture-A');
      await SyncOutboxService.enqueueMarkOngoing(jobId: 'fixture-A');
      expect(await DBHelper.getActionableActions(), hasLength(1));
      expect((await DBHelper.getCachedJobs()).first['status'], 'in_progress');
      await db.update(
        'local_jobs',
        {'status': 'completed'},
        where: 'id = ?',
        whereArgs: ['fixture-A'],
      );
      expect(
        (await SupabaseService.fetchMyJobs()).first['status'],
        'in_progress',
      );
    },
  );

  test(
    'pending submit alone does not protect unaccepted local lifecycle',
    () async {
      await submitFixture('fixture-A');
      await db.update(
        'local_jobs',
        {'status': 'in_progress'},
        where: 'id = ?',
        whereArgs: ['fixture-A'],
      );
      expect(
        (await SupabaseService.fetchMyJobs()).first['status'],
        'in_progress',
      );
    },
  );

  test(
    'remote omission preserves only pending-completion cache evidence',
    () async {
      await submitFixture('fixture-A');
      await DBHelper.cacheJobs([]);
      final cached = await DBHelper.getCachedJobs();
      expect(cached, hasLength(1));
      expect(cached.single['id'], 'fixture-A');
      expect(cached.single['status'], 'completed');
      expect(await DBHelper.getActionableActions(), hasLength(1));
    },
  );

  for (final status in ['onprocess', 'cancelled', null, '', '   ', 'unknown_value']) {
    test('R2B protected unsupported $status preserves conflict and availability', () async {
      await submitFixture('fixture-A');
      final actions = await DBHelper.getActionableActions();
      remoteJobs.first.addAll({
        'status': status,
        'extra_remote_field': {'retained': true},
      });
      final before = jsonEncode(remoteJobs);
      final expected = {
        ...remoteJobs.first,
        'status': 'completed',
        '_localPendingCompletionConflict': true,
        '_remoteStatusSnapshot': status,
      };
      // Direct projection proves input-map immutability, not just HTTP copying.
      final projected = await DBHelper.projectPendingCompletions(remoteJobs);
      expect(projected.first, expected);
      expect(identical(projected.first, remoteJobs.first), isFalse);
      expect(projected.last, remoteJobs.last);
      final fetched = await SupabaseService.fetchMyJobs();
      expect(fetched, projected);
      expect(TaskItem.fromJob(fetched.first).category, 'Completed');
      await DBHelper.cacheJobs(remoteJobs);
      var cached = await DBHelper.getCachedJobs();
      expect(cached.firstWhere((j) => j['id'] == 'fixture-A')['status'], 'completed');
      expect(cached.firstWhere((j) => j['id'] == 'fixture-B')['status'], 'in_progress');
      await DBHelper.cacheJobs(fetched); // Normal fetch -> cache path too.
      cached = await DBHelper.getCachedJobs();
      expect(cached, hasLength(2));
      expect(cached.firstWhere((j) => j['id'] == 'fixture-A')['status'], 'completed');
      for (final row in cached) {
        expect(row.containsKey('_localPendingCompletionConflict'), isFalse);
        expect(row.containsKey('_remoteStatusSnapshot'), isFalse);
      }
      expect(await DBHelper.getActionableActions(), actions);
      expect(jsonEncode(remoteJobs), before);
      expect(requestMethods, everyElement('GET'));
      expect(patches, 0);
    });

    test('R2B unprotected unsupported $status stays excluded', () async {
      remoteJobs.first['status'] = status;
      final before = jsonEncode(remoteJobs);
      final fetched = await SupabaseService.fetchMyJobs();
      expect(fetched, remoteJobs);
      expect(['Pending', 'Ongoing', 'Completed'],
          isNot(contains(TaskItem.fromJob(fetched.first).category)));
      await DBHelper.cacheJobs(fetched);
      expect((await DBHelper.getCachedJobs()).first['status'], status);
      expect(jsonEncode(remoteJobs), before);
      expect(requestMethods, everyElement('GET'));
    });
  }

  test('R2B one protected conflict keeps the whole fetched list available', () async {
    remoteJobs = [
      {'id': 'fixture-A', 'status': 'cancelled'},
      {'id': 'fixture-B', 'status': 'assigned'},
      {'id': 'fixture-C', 'status': 'in_progress'},
      {'id': 'fixture-D', 'status': 'completed'},
    ];
    await DBHelper.cacheJobs(remoteJobs); // Local rows exist before acceptance.
    await submitFixture('fixture-A');
    final fetched = await SupabaseService.fetchMyJobs();
    expect(fetched, hasLength(4)); // No StateError; unrelated jobs survive.
    expect(fetched[0]['status'], 'completed');
    expect(fetched[0]['_localPendingCompletionConflict'], isTrue);
    expect(fetched[0]['_remoteStatusSnapshot'], 'cancelled');
    expect(fetched[1]['status'], 'assigned');
    expect(fetched[2]['status'], 'in_progress');
    expect(fetched[3]['status'], 'completed');
    expect(
      fetched.skip(1).any((job) => job.containsKey('_localPendingCompletionConflict')),
      isFalse,
    );
    expect(TaskItem.fromJob(fetched[0]).category, 'Completed');
    expect(TaskItem.fromJob(fetched[1]).category, 'Pending');
    expect(TaskItem.fromJob(fetched[2]).category, 'Ongoing');
    expect(TaskItem.fromJob(fetched[3]).category, 'Completed');
    await DBHelper.cacheJobs(remoteJobs); // Raw conflicting row cannot roll back B/C/D.
    final cached = await DBHelper.getCachedJobs();
    expect(cached, hasLength(4));
    expect(cached.firstWhere((j) => j['id'] == 'fixture-A')['status'], 'completed');
    expect(cached.firstWhere((j) => j['id'] == 'fixture-B')['status'], 'assigned');
    expect(cached.firstWhere((j) => j['id'] == 'fixture-C')['status'], 'in_progress');
    expect(cached.firstWhere((j) => j['id'] == 'fixture-D')['status'], 'completed');
    expect(patches, 0);
    expect(requestMethods, everyElement('GET'));
  });

  test('R2B profile statistics survive one protected conflicting job', () async {
    remoteJobs = [
      {'id': 'fixture-A', 'status': 'cancelled'},
      {'id': 'fixture-B', 'status': 'in_progress'},
    ];
    await DBHelper.cacheJobs(remoteJobs);
    await submitFixture('fixture-A');
    // Same shared-boundary sequence as the unchanged Profile screen.
    final jobs = await SupabaseService.fetchMyJobs();
    final stats = InspectorDashboardStats.fromTasks(
      jobs.map(TaskItem.fromJob).toList(),
    );
    expect(stats.totalAssigned, 2);
    expect(stats.completedCount, 1); // Effective local Completed is counted.
    expect(stats.activeWorkloadCount, 1);
    expect(stats.completionRate, closeTo(0.5, 1e-9));
    expect(patches, 0);
  });

  test('R2B conflict metadata clears when remote agrees on completion', () async {
    await submitFixture('fixture-A');
    remoteJobs.first['status'] = 'cancelled';
    expect(
      (await SupabaseService.fetchMyJobs()).first['_localPendingCompletionConflict'],
      isTrue,
    );
    final repeated = await SupabaseService.fetchMyJobs();
    expect(repeated.first['_localPendingCompletionConflict'], isTrue);
    expect(repeated.first['_remoteStatusSnapshot'], 'cancelled');
    remoteJobs.first['status'] = 'completed'; // Next fetch, remote agrees.
    final fetched = await SupabaseService.fetchMyJobs();
    expect(fetched.first['status'], 'completed');
    expect(fetched.first.containsKey('_localPendingCompletionConflict'), isFalse);
    expect(fetched.first.containsKey('_remoteStatusSnapshot'), isFalse);
    await DBHelper.cacheJobs(fetched);
    expect((await DBHelper.getCachedJobs()).first['status'], 'completed');
    expect(patches, 0);
  });

  test('R2B recognized stale remote values never carry conflict metadata', () async {
    await submitFixture('fixture-A');
    for (final status in [
      'assigned',
      'Pending',
      'pending',
      'in_progress',
      'in-progress',
      'ongoing',
    ]) {
      remoteJobs.first['status'] = status;
      final fetched = await SupabaseService.fetchMyJobs();
      expect(fetched.first['status'], 'completed');
      expect(fetched.first.containsKey('_localPendingCompletionConflict'), isFalse);
      expect(fetched.first.containsKey('_remoteStatusSnapshot'), isFalse);
      await DBHelper.cacheJobs(remoteJobs);
      expect((await DBHelper.getCachedJobs()).first['status'], 'completed');
    }
    expect(patches, 0);
  });

  test('R2B protection persists while any same-job submit is unacknowledged', () async {
    await submitFixture('fixture-A');
    await submitFixture('fixture-A'); // Existing UUID-per-submit contract.
    final actions = await DBHelper.getActionableActions();
    expect(actions, hasLength(2));
    await DBHelper.markActionSyncing(actions.first['id'] as String);
    await DBHelper.markActionSynced(actions.first['id'] as String);
    await DBHelper.markActionSyncing(actions.last['id'] as String);
    await DBHelper.markActionFailed(actions.last['id'] as String, 'fixture failure');
    remoteJobs.first['status'] = 'cancelled';
    final stillProtected = await SupabaseService.fetchMyJobs();
    expect(stillProtected.first['status'], 'completed');
    expect(stillProtected.first['_remoteStatusSnapshot'], 'cancelled');
    await DBHelper.markActionSyncing(actions.last['id'] as String);
    await DBHelper.markActionSynced(actions.last['id'] as String);
    final afterAcknowledgement = await SupabaseService.fetchMyJobs();
    expect(afterAcknowledgement, remoteJobs); // Raw unsupported again.
    expect(
      afterAcknowledgement.first.containsKey('_localPendingCompletionConflict'),
      isFalse,
    );
    expect(TaskItem.fromJob(afterAcknowledgement.first).category, isNot('Completed'));
    await DBHelper.cacheJobs(afterAcknowledgement);
    expect((await DBHelper.getCachedJobs()).first['status'], 'cancelled');
    expect(requestMethods, everyElement('GET'));
    expect(patches, 0);
  });
}
