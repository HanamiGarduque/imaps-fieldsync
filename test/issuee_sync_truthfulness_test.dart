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

/// Applies the `status` filter the request actually carries, so the lifecycle
/// predicate is genuinely exercised: a request that only allows `assigned`
/// must NOT match a remote row sitting at `pending`.
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
  var transportOffline = false;
  var rejectWithServerError = false;
  var patchCount = 0;

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
        if (transportOffline) throw const SocketException('isolated offline');
        final q = r.url.queryParameters;
        final uid = r.headers['Authorization']?.split('issuee-token-').last;
        final mine = remote['assigned_inspector_id'] == uid;
        if (r.method == 'PATCH') {
          patchCount++;
          if (rejectWithServerError) {
            return http.Response(
              jsonEncode({'message': 'server rejected', 'code': 'P0001'}),
              400,
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
    // The live device shape that produced the audit: a self-scheduled job
    // whose remote status is `pending`, not `assigned`.
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
    transportOffline = false;
    rejectWithServerError = false;
    patchCount = 0;
    SyncOutboxService.hasConnectionOverride = () async => !transportOffline;
  });
  tearDown(() async {
    SyncOutboxService.hasConnectionOverride = null;
    DBHelper.useDatabaseForTesting(null);
    await db.close();
  });

  Future<String?> lastError() async =>
      (await db.query('pending_actions', columns: ['last_error'])).single['last_error'] as String?;

  Future<Map<String, Object?>> row() async =>
      (await db.query('pending_actions')).single;

  /// Every user-facing line the Sync Center can show for this action.
  Future<List<String>> surfacedText() async {
    final logs = await db.query('sync_log_entries',
        columns: ['message'], where: 'pending_action_id = ?', whereArgs: ['mark_ongoing_$job']);
    return <String>[?await lastError(), ...logs.map((l) => l['message'] as String)];
  }

  test('1. online + successful mark_ongoing acknowledges the row exactly once', () async {
    await SyncOutboxService.enqueueMarkOngoing(jobId: job);
    await SyncOutboxService.drain(trigger: 'test');
    final r = await row();
    expect(r['status'], 'synced', reason: 'last_error=${await lastError()}');
    expect(r['retry_count'], 0);
    expect(remote['status'], 'in_progress');
    expect(patchCount, 1, reason: 'no duplicate remote mutation after acknowledgement');
  });

  test('2. true offline makes no attempt and counts no failure', () async {
    await SyncOutboxService.enqueueMarkOngoing(jobId: job);
    transportOffline = true;
    await SyncOutboxService.drain(trigger: 'test');
    final r = await row();
    expect(r['status'], 'pending', reason: 'waiting for connection');
    expect(r['retry_count'], 0, reason: 'no remote attempt means no failed attempt');
    expect(remote['status'], 'pending');
  });

  test('3. online server refusal is not reported as a lost connection', () async {
    await SyncOutboxService.enqueueMarkOngoing(jobId: job);
    rejectWithServerError = true;
    await SyncOutboxService.drain(trigger: 'test');
    expect((await row())['status'], 'failed');
    final text = (await surfacedText()).join(' | ');
    expect(text, isNot(contains('Network connection lost')));
    expect(text, isNot(contains('Connection timed out')));
  });

  test('5. repeated enqueue keeps one active equivalent action', () async {
    await SyncOutboxService.enqueueMarkOngoing(jobId: job);
    await SyncOutboxService.enqueueMarkOngoing(jobId: job);
    await SyncOutboxService.enqueueMarkOngoing(jobId: job);
    expect((await db.query('pending_actions')).length, 1);
  });

  test('6. remote assigned transitions normally', () async {
    remote['status'] = 'assigned';
    await SyncOutboxService.enqueueMarkOngoing(jobId: job);
    await SyncOutboxService.drain(trigger: 'test');
    expect((await row())['status'], 'synced', reason: 'last_error=${await lastError()}');
    expect(remote['status'], 'in_progress');
  });

  test('7. remote already in_progress for same job and inspector reconciles as satisfied', () async {
    remote.addAll({'status': 'in_progress', 'started_at': '2026-10-01T00:00:00Z'});
    await SyncOutboxService.enqueueMarkOngoing(jobId: job);
    await SyncOutboxService.drain(trigger: 'test');
    expect((await row())['status'], 'synced');
    expect(remote['started_at'], '2026-10-01T00:00:00Z', reason: 'start is not rewritten');
  });

  test('8. remote in_progress for a different inspector is never acknowledged', () async {
    remote.addAll({
      'status': 'in_progress', 'started_at': '2026-10-01T00:00:00Z',
      'assigned_inspector_id': other,
    });
    await SyncOutboxService.enqueueMarkOngoing(jobId: job);
    await SyncOutboxService.drain(trigger: 'test');
    expect((await row())['status'], isNot('synced'));
    expect(patchCount, 0, reason: 'no remote write for a job this session cannot see');
  });

  test('10. an acknowledged action does not reappear on a later drain', () async {
    await SyncOutboxService.enqueueMarkOngoing(jobId: job);
    await SyncOutboxService.drain(trigger: 'test');
    await SyncOutboxService.drain(trigger: 'test');
    await SyncOutboxService.drain(trigger: 'test');
    expect(
      (await DBHelper.getActionableActions()).where((a) => a['id'] == 'mark_ongoing_$job'),
      isEmpty,
    );
    expect(patchCount, 1);
  });

  test('11. a paused/failed row still acknowledges on a later successful drain', () async {
    await SyncOutboxService.enqueueMarkOngoing(jobId: job);
    rejectWithServerError = true;
    await SyncOutboxService.drain(trigger: 'test');
    expect((await row())['status'], 'failed');
    expect((await row())['retry_count'], 1);
    rejectWithServerError = false;
    await SyncOutboxService.drain(trigger: 'manual');
    expect((await row())['status'], 'synced');
  });

  test('12. Problem A ownership denial still holds: another inspector is a conflict', () async {
    remote['assigned_inspector_id'] = other;
    await SyncOutboxService.enqueueMarkOngoing(jobId: job);
    await SyncOutboxService.drain(trigger: 'test');
    expect((await row())['status'], 'conflict',
        reason: 'a job owned by another inspector needs review, never silent success');
  });
}
