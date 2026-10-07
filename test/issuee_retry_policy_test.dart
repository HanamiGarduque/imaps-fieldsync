import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/supabase_service.dart';
import 'package:imaps_fieldsync/core/services/sync_outbox_service.dart';

const job = '44444444-4444-4444-8444-444444444444';
const owner = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
const other = 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb';

Future<void> signIn(String uid) => SupabaseService.client.auth.setInitialSession(jsonEncode({
      'access_token': 'issuee-token-$uid', 'refresh_token': 'r',
      'token_type': 'bearer', 'expires_in': 3600,
      'user': {
        'id': uid, 'app_metadata': {}, 'user_metadata': {},
        'aud': 'authenticated', 'created_at': '2026-01-01T00:00:00Z',
      },
    }));

bool statusFilterMatches(String? raw, String actual) {
  if (raw == null) return true;
  if (raw.startsWith('in.(')) {
    return raw
        .replaceFirst('in.(', '')
        .replaceFirst(RegExp(r'\)$'), '')
        .split(',')
        .map((v) => v.trim().replaceAll('"', ''))
        .contains(actual);
  }
  if (raw.startsWith('neq.')) return actual != raw.substring(4);
  if (raw.startsWith('eq.')) return actual == raw.substring(3);
  return true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;
  late Map<String, dynamic> remote;
  late bool online;
  late int? failWithStatus;
  late bool transportFails;
  var attempts = 0;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://issuee.test', publishableKey: 'fixture',
      authOptions: FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((r) async {
        if (r.url.path == '/auth/v1/logout') return http.Response('{}', 200, request: r);
        if (r.url.path == '/rest/v1/activity_log') return http.Response('', 201, request: r);
        if (!online) throw const SocketException('isolated offline');
        if (transportFails) throw const SocketException('link dropped mid-request');
        final q = r.url.queryParameters;
        final uid = r.headers['Authorization']?.split('issuee-token-').last;
        final mine = remote['assigned_inspector_id'] == uid;
        if (r.url.path == '/rest/v1/field_jobs') attempts++;
        if (r.method == 'PATCH') {
          if (failWithStatus != null) {
            return http.Response(
              jsonEncode({'message': 'server error', 'code': 'XX000'}),
              failWithStatus!,
              request: r,
            );
          }
          var matched = mine;
          if (q['assigned_inspector_id'] != null) {
            matched = matched && q['assigned_inspector_id'] == 'eq.$uid';
          }
          matched = matched && statusFilterMatches(q['status'], remote['status'] as String);
          if (matched) remote.addAll(jsonDecode(r.body) as Map<String, dynamic>);
          return http.Response(jsonEncode(matched ? [remote] : []), 200, request: r);
        }
        if (failWithStatus != null) {
          return http.Response(
            jsonEncode({'message': 'server error', 'code': 'XX000'}),
            failWithStatus!,
            request: r,
          );
        }
        return http.Response(
          jsonEncode(mine ? [remote] : []),
          200,
          headers: {'content-type': 'application/json'},
          request: r,
        );
      }),
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    final source = File('lib/core/services/db_helper.dart').readAsStringSync();
    for (final m in RegExp(r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)').allMatches(source)) {
      await db.execute(m.group(0)!);
    }
    DBHelper.useDatabaseForTesting(db);
    await signIn(owner);
    remote = {
      'id': job, 'assigned_inspector_id': owner, 'status': 'pending',
      'current_step': 0, 'started_at': null, 'submitted_at': null,
      'local_inspection_id': 44, 'reference_number': 'APP-2026-00033',
      'is_self_scheduled': true,
    };
    await db.insert('local_jobs', {
      'id': job, 'status': 'pending', 'reference_number': 'APP-2026-00033',
      'local_inspection_id': 44, 'inspector_id': owner,
    });
    online = true;
    failWithStatus = null;
    attempts = 0;
    transportFails = false;
    SyncOutboxService.hasConnectionOverride = () async => online;
  });
  tearDown(() async {
    SyncOutboxService.hasConnectionOverride = null;
    DBHelper.useDatabaseForTesting(null);
    await db.close();
  });

  const id = 'mark_ongoing_44444444-4444-4444-8444-444444444444';

  Future<Map<String, Object?>> row() async =>
      (await db.query('pending_actions', where: 'id = ?', whereArgs: [id])).single;

  /// How many times the drain actually began an attempt on this action. The
  /// sync log is the honest record; raw HTTP request counts include the
  /// authority reads that bracket one attempt.
  Future<int> attemptsLogged() async =>
      (await db.query('sync_log_entries',
              where: "pending_action_id = ? AND event_type = 'upload_started'",
              whereArgs: [id]))
          .length;

  /// Queues the action at a given failed-attempt count, with `updated_at`
  /// backdated to `age` so the backoff schedule can be exercised without
  /// waiting for real time to pass.
  Future<void> seed({int retryCount = 0, Duration age = Duration.zero, String status = 'pending'}) async {
    await db.insert('pending_actions', {
      'id': id, 'type': 'mark_ongoing', 'job_id': job, 'payload': '{}',
      'status': status, 'retry_count': retryCount, 'last_error': 'seeded',
      'inspector_id': owner,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().subtract(age).toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  test('1. first transient failure counts once and blocks an automatic retry for 1 minute', () async {
    await seed();
    failWithStatus = 503;
    await SyncOutboxService.drain();
    expect((await row())['status'], 'failed');
    expect((await row())['retry_count'], 1);

    attempts = 0;
    await SyncOutboxService.drain();
    expect(attempts, 0, reason: 'automatic retry before the 1 minute backoff');
    expect((await row())['retry_count'], 1);
  });

  test('2. retry #2 uses the 5 minute backoff', () async {
    await seed(retryCount: 1, age: const Duration(seconds: 59));
    failWithStatus = 503;
    attempts = 0;
    await SyncOutboxService.drain();
    expect(attempts, 0, reason: 'still inside the 1 minute backoff from failure #1');
  });

  test('3. retry #3 uses the 5 minute backoff from failure #2', () async {
    await seed(retryCount: 2, age: const Duration(minutes: 4));
    failWithStatus = 503;
    attempts = 0;
    await SyncOutboxService.drain();
    expect(attempts, 0, reason: 'still inside the 5 minute backoff from failure #2');
  });

  test('4. retry #4 uses the 15 minute backoff from failure #3', () async {
    await seed(retryCount: 3, age: const Duration(minutes: 14));
    failWithStatus = 503;
    attempts = 0;
    await SyncOutboxService.drain();
    expect(attempts, 0, reason: 'still inside the 15 minute backoff from failure #3');
  });

  test('5. failure #5 pauses automatic retries and preserves the row', () async {
    await seed(retryCount: 4, age: const Duration(hours: 1));
    failWithStatus = 503;
    await SyncOutboxService.drain();
    final r = await row();
    expect(r['status'], 'paused');
    expect(r['retry_count'], 5);
    expect(r['last_error'], contains('preserved'));
  });

  test('6. an app-start drain at r5 makes no remote attempt', () async {
    await seed(retryCount: 4, age: const Duration(hours: 1));
    failWithStatus = 503;
    await SyncOutboxService.drain(); // reaches the ceiling
    attempts = 0;
    // `drain()` with the default trigger is exactly what app startup calls.
    for (var i = 0; i < 3; i++) {
      await SyncOutboxService.drain();
    }
    expect(attempts, 0, reason: 'a paused action is never auto-retried');
    expect((await row())['status'], 'paused');
  });

  test('7. a connectivity-change drain at r5 makes no remote attempt', () async {
    await seed(retryCount: 4, age: const Duration(hours: 1));
    failWithStatus = 503;
    await SyncOutboxService.drain();
    attempts = 0;
    online = false;
    await SyncOutboxService.drain();
    online = true;
    await SyncOutboxService.drain();
    expect(attempts, 0);
    expect((await row())['status'], 'paused');
  });

  test('8. a manual retry at the ceiling gets exactly one immediate attempt', () async {
    await seed(retryCount: 5, age: const Duration(hours: 1), status: 'paused');
    failWithStatus = 503;
    await SyncOutboxService.drain(trigger: 'manual');
    expect(await attemptsLogged(), 1, reason: 'the user asked exactly once');
    expect((await row())['status'], 'paused');
  });

  test('9. a failed manual retry stays paused and does not resume the automatic loop', () async {
    await seed(retryCount: 5, age: const Duration(hours: 1), status: 'paused');
    failWithStatus = 503;
    await SyncOutboxService.drain(trigger: 'manual');
    attempts = 0;
    for (var i = 0; i < 3; i++) {
      await SyncOutboxService.drain();
    }
    expect(attempts, 0, reason: 'no infinite automatic retries resume');
    expect((await row())['status'], 'paused');
  });

  test('10. a successful manual retry acknowledges the action exactly once', () async {
    await seed(retryCount: 5, age: const Duration(hours: 1), status: 'paused');
    failWithStatus = null;
    attempts = 0;
    await SyncOutboxService.drain(trigger: 'manual');
    expect((await row())['status'], 'synced');
    expect(remote['status'], 'in_progress');
    expect(await attemptsLogged(), 1);
    await SyncOutboxService.drain(trigger: 'manual');
    expect(await attemptsLogged(), 1,
        reason: 'no duplicate remote mutation after acknowledgement');
  });

  test('11. true offline attempts nothing and never counts a failure', () async {
    await seed(retryCount: 2, age: const Duration(hours: 1));
    online = false;
    attempts = 0;
    await SyncOutboxService.drain();
    final r = await row();
    expect(attempts, 0);
    expect(r['status'], 'pending', reason: 'waiting for connection');
    expect(r['retry_count'], 2, reason: 'no remote attempt means no failed attempt');
  });

  test('12. a transport failure mid-request is transient: counted and backed off', () async {
    await seed();
    failWithStatus = null;
    transportFails = true;
    await SyncOutboxService.drain();
    transportFails = false;
    expect((await row())['status'], 'failed');
    expect((await row())['retry_count'], 1,
        reason: 'a request that was actually made and failed is a failed attempt');
    attempts = 0;
    await SyncOutboxService.drain();
    expect(attempts, 0, reason: 'and it is now inside the 1 minute backoff');
  });

  test('13. a server 5xx is transient and starts the backoff', () async {
    await seed();
    failWithStatus = 500;
    await SyncOutboxService.drain();
    expect((await row())['status'], 'failed');
    expect((await row())['retry_count'], 1);
  });

  test('14. a permanent authority rejection stops automatic retry and is not called offline', () async {
    await seed();
    failWithStatus = null;
    // The row is invisible to this session's authority read: no owner match,
    // no write. That is permanent authority, not a connection problem.
    remote['assigned_inspector_id'] = other;
    await SyncOutboxService.drain();
    final r = await row();
    expect(r['status'], isNot('failed'),
        reason: 'an authority problem must not enter the retry loop');
    expect(r['retry_count'], 0, reason: 'a refused authority write is not a transient failure');
    expect('${r['last_error']}'.toLowerCase(), isNot(contains('connection')));
    attempts = 0;
    await SyncOutboxService.drain();
    await SyncOutboxService.drain();
    expect(attempts, 0, reason: 'no automatic retries for a permanent authority problem');
  });

  test('15. a wrong-inspector job is never acknowledged as success', () async {
    await seed();
    remote['assigned_inspector_id'] = other;
    await SyncOutboxService.drain();
    final r = await row();
    expect(r['status'], isNot('synced'));
    expect(await attemptsLogged(), 1, reason: 'one real attempt was made');
    expect(remote['status'], 'pending', reason: 'nothing was written');
    expect(remote['started_at'], isNull);
  });

  test('16. an already-satisfied mark_ongoing is acknowledged with no duplicate mutation', () async {
    remote.addAll({'status': 'in_progress', 'started_at': '2026-10-01T00:00:00Z'});
    await seed();
    await SyncOutboxService.drain();
    expect((await row())['status'], 'synced');
    expect(remote['status'], 'in_progress');
    expect(remote['started_at'], '2026-10-01T00:00:00Z',
        reason: 'the already-satisfied transition must not be re-applied');
  });

  test('17. already in_progress for a DIFFERENT inspector is not acknowledged', () async {
    remote.addAll({
      'status': 'in_progress', 'started_at': '2026-10-01T00:00:00Z',
      'assigned_inspector_id': other,
    });
    await seed();
    await SyncOutboxService.drain();
    expect((await row())['status'], isNot('synced'));
  });

  test('18. a rescheduled pending task still starts normally', () async {
    await seed();
    await SyncOutboxService.drain();
    expect((await row())['status'], 'synced');
    expect(remote['status'], 'in_progress');
  });

  test('19. remote success then a local acknowledgement interruption reconciles on retry', () async {
    await seed(status: 'syncing', retryCount: 1);
    // The remote write already landed before the app died.
    remote.addAll({'status': 'in_progress', 'started_at': '2026-10-01T00:00:00Z'});
    await SyncOutboxService.drain();
    // An abandoned claim is recovered, then recognised as already satisfied.
    expect(['synced', 'paused', 'failed'], contains((await row())['status']));
    await SyncOutboxService.drain(trigger: 'manual');
    expect((await row())['status'], 'synced');
    expect(remote['started_at'], '2026-10-01T00:00:00Z',
        reason: 'the retry must not repeat the remote mutation');
  });

  test('20. an acknowledged action does not return after a restart', () async {
    await seed();
    await SyncOutboxService.drain();
    expect((await row())['status'], 'synced');
    DBHelper.useDatabaseForTesting(null);
    DBHelper.useDatabaseForTesting(db);
    await SyncOutboxService.drain();
    await SyncOutboxService.drain(trigger: 'manual');
    expect(await attemptsLogged(), 1);
    expect((await DBHelper.getActionableActions()).where((a) => a['id'] == id), isEmpty);
  });

  test('21. duplicate enqueue keeps one active equivalent row', () async {
    await SyncOutboxService.enqueueMarkOngoing(jobId: job);
    await SyncOutboxService.enqueueMarkOngoing(jobId: job);
    await SyncOutboxService.enqueueMarkOngoing(jobId: job);
    expect((await db.query('pending_actions')).length, 1);
  });
}
