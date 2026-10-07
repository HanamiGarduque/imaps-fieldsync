import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/inspection_start_service.dart';
import 'package:imaps_fieldsync/core/services/supabase_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const ownerA = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
const ownerB = 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb';
const job = '11111111-1111-4111-8111-111111111111';

Future<void> signInInspector(String uid) =>
    SupabaseService.client.auth.setInitialSession(jsonEncode({
      'access_token': 'isolated-token-$uid', 'refresh_token': 'isolated-refresh',
      'token_type': 'bearer', 'expires_in': 3600,
      'user': {'id': uid, 'app_metadata': {}, 'user_metadata': {},
        'aud': 'authenticated', 'created_at': '2026-01-01T00:00:00Z'},
    }));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  late Map<String, dynamic>? remote;
  late int remoteReads;
  Object? remoteError;
  Future<void> Function()? afterRead;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://legacy-assignment.test', publishableKey: 'isolated-test-key',
      authOptions: FlutterAuthClientOptions(autoRefreshToken: false,
        detectSessionInUri: false, localStorage: EmptyLocalStorage()),
      httpClient: MockClient((request) async {
        expect(request.method, 'GET', reason: 'compatibility must never write remote data');
        expect(request.url.path, '/rest/v1/field_jobs');
        expect(request.url.queryParameters['id'], 'eq.$job');
        final uid = request.headers['Authorization']?.split('isolated-token-').last;
        expect(request.url.queryParameters['assigned_inspector_id'], 'eq.$uid');
        remoteReads++;
        if (remoteError != null) throw remoteError!;
        final r = remote;
        final visible = r != null && r['assigned_inspector_id'] == uid;
        if (afterRead != null) await afterRead!();
        return http.Response(jsonEncode(visible ? [r] : []), 200,
          headers: {'content-type': 'application/json'}, request: request);
      }),
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());

  Future<List<Map<String, Object?>>> snapshot() async => [
    for (final t in ['local_jobs', 'local_inspections', 'local_photos', 'pending_actions', 'inspection_job_retention'])
      ...await db.query(t)];

  Future<void> legacyJob({bool retention = false}) async {
    await db.insert('local_jobs', {'id': job, 'status': 'in_progress', 'local_inspection_id': 41,
      'bridge_source_id': 'bridge', 'scheduled_date': '2026-10-01', 'deadline_date': '2026-10-20'});
    if (retention) await db.insert('inspection_job_retention', {'job_id': job, 'retained_at': '2026-10-01T00:00:00Z'});
  }

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    final source = File('lib/core/services/db_helper.dart').readAsStringSync();
    for (final m in RegExp(r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)').allMatches(source)) {
      await db.execute(m.group(0)!);
    }
    DBHelper.useDatabaseForTesting(db);
    await signInInspector(ownerA);
    remoteReads = 0;
    remoteError = null;
    afterRead = null;
    remote = {'id': job, 'assigned_inspector_id': ownerA, 'bridge_source_id': 'bridge', 'local_inspection_id': 41};
  });
  tearDown(() async {
    DBHelper.useDatabaseForTesting(null);
    await db.close();
  });

  Future<void> expectDeniedUnchanged(InspectionStartResult expected) async {
    final before = await snapshot();
    expect(await InspectionStartService.prepareJob(job), expected);
    expect(await snapshot(), before);
  }

  test('metadata-only legacy job assigned remotely is repaired and opens', () async {
    await legacyJob();
    final before = (await db.query('local_jobs')).single;
    expect(await InspectionStartService.prepareJob(job), InspectionStartResult.authorized);
    final after = (await db.query('local_jobs')).single;
    expect(after['inspector_id'], ownerA);
    expect({...after}..remove('inspector_id'), {...before}..remove('inspector_id'),
      reason: 'progress, lifecycle, schedule untouched');
    expect(await DBHelper.classifyJobOwnership(db, job, ownerA), LocalOwnershipResult.current);
    expect(remoteReads, greaterThanOrEqualTo(1));
  });

  test('NULL saved-progress marker is repaired with the task row, timestamps kept', () async {
    await legacyJob(retention: true);
    expect(await InspectionStartService.prepareJob(job), InspectionStartResult.authorized);
    final marker = (await db.query('inspection_job_retention')).single;
    expect(marker['inspector_id'], ownerA);
    expect(marker['retained_at'], '2026-10-01T00:00:00Z');
  });

  test('repair is idempotent and CURRENT jobs never re-enter repair', () async {
    await legacyJob(retention: true);
    expect(await InspectionStartService.prepareJob(job), InspectionStartResult.authorized);
    final once = await snapshot();
    final reads = remoteReads;
    expect(await InspectionStartService.prepareJob(job), InspectionStartResult.authorized);
    expect(await snapshot(), once);
    expect(remoteReads, reads, reason: 'retained CURRENT job needs no repair verification');
  });

  test('remote assignment to another inspector: no repair', () async {
    await legacyJob();
    remote = {...remote!, 'assigned_inspector_id': ownerB};
    await expectDeniedUnchanged(InspectionStartResult.notAssignedOrUnavailable);
  });

  test('remote assignment unavailable: no repair', () async {
    await legacyJob();
    remoteError = const SocketException('offline');
    await expectDeniedUnchanged(InspectionStartResult.offlineOrUnverifiable);
  });

  test('remote identity mismatch: no repair', () async {
    await legacyJob();
    remote = {...remote!, 'local_inspection_id': 99};
    await expectDeniedUnchanged(InspectionStartResult.localOwnershipIncomplete);
  });

  test('foreign local owner: no repair', () async {
    await db.insert('local_jobs', {'id': job, 'status': 'assigned', 'inspector_id': ownerB});
    await expectDeniedUnchanged(InspectionStartResult.notAssignedOrUnavailable);
    expect(remoteReads, 0);
  });

  test('mixed graph: no repair, no foreign overwrite', () async {
    await legacyJob();
    await db.insert('local_photos', {'id': 'p', 'job_id': job, 'photo_path': '/p', 'inspector_id': ownerB});
    await expectDeniedUnchanged(InspectionStartResult.notAssignedOrUnavailable);
  });

  for (final (name, insert) in <(String, Map<String, Object?> Function())>[
    ('unknown-owner inspection draft', () => {'#': 'local_inspections', 'id': job, 'notes': 'n'}),
    ('unknown-owner photo', () => {'#': 'local_photos', 'id': 'p', 'job_id': job, 'photo_path': '/p'}),
    ('unknown-owner queued action', () => {'#': 'pending_actions', 'id': 'a', 'job_id': job, 'type': 't',
      'payload': '{}', 'status': 'pending', 'created_at': 'x', 'updated_at': 'x'}),
  ]) {
    test('$name: no automatic repair', () async {
      await legacyJob();
      final row = insert();
      final table = row.remove('#') as String;
      await db.insert(table, row);
      await expectDeniedUnchanged(InspectionStartResult.localOwnershipIncomplete);
    });
  }

  test('account switch after remote verification rolls back', () async {
    await legacyJob(retention: true);
    afterRead = () => signInInspector(ownerB);
    final before = await snapshot();
    final result = await InspectionStartService.prepareJob(job);
    expect(result, isNot(InspectionStartResult.authorized));
    expect(await snapshot(), before);
  });

  test('same inspector reauthentication during verification aborts repair', () async {
    await legacyJob(retention: true);
    afterRead = () => signInInspector(ownerA);
    await expectDeniedUnchanged(InspectionStartResult.authRequired);
  });

  for (final nextInspector in [ownerA, ownerB]) {
    test('session change after first metadata write rolls back both rows ($nextInspector)', () async {
      await legacyJob(retention: true);
      final before = await snapshot();
      DBHelper.useDatabaseForTesting(_SessionSwitchDatabase(db,
        () => signInInspector(nextInspector)));
      expect(await InspectionStartService.prepareJob(job), InspectionStartResult.authRequired);
      expect(await snapshot(), before, reason: 'first UPDATE must roll back with the marker');
    });
  }

  test('unsafe current-owned pending action blocks repair without replay', () async {
    await legacyJob(retention: true);
    await db.insert('pending_actions', {'id': 'a', 'job_id': job, 'inspector_id': ownerA,
      'type': 'submit_inspection', 'payload': '{"forceSyncAnyway":true}',
      'status': 'conflict', 'created_at': 'x', 'updated_at': 'x'});
    await expectDeniedUnchanged(InspectionStartResult.localOwnershipIncomplete);
  });

  test('wrong fetched job cannot cause a partial metadata repair', () async {
    await legacyJob(retention: true);
    final before = await snapshot();
    expect(await InspectionStartService.prepareJob(job,
      fetchedJob: {'id': '22222222-2222-4222-8222-222222222222'}),
      InspectionStartResult.notAssignedOrUnavailable);
    expect(await snapshot(), before);
    expect(remoteReads, 0);
  });

  test('legacy step entry preserves cached metadata despite a stale fetched payload', () async {
    await legacyJob(retention: true);
    final before = (await db.query('local_jobs')).single;
    expect(await InspectionStartService.prepareJob(job, fetchedJob: {
      'id': job, 'status': 'assigned', 'scheduled_date': '2026-12-01',
      'local_inspection_id': 41, 'bridge_source_id': 'bridge',
    }), InspectionStartResult.authorized);
    final after = (await db.query('local_jobs')).single;
    expect({...after}..remove('inspector_id'), {...before}..remove('inspector_id'));
  });

  test('fetched inspection identity mismatch denies before repair', () async {
    await legacyJob(retention: true);
    final before = await snapshot();
    expect(await InspectionStartService.prepareJob(job, fetchedJob: {
      'id': job, 'local_inspection_id': 99, 'bridge_source_id': 'bridge',
    }), InspectionStartResult.localOwnershipIncomplete);
    expect(await snapshot(), before);
  });

  test('late unknown draft added during remote lookup blocks transaction rescan', () async {
    await legacyJob(retention: true);
    afterRead = () async {
      await db.insert('local_inspections', {'id': job, 'notes': 'late evidence'});
    };
    expect(await InspectionStartService.prepareJob(job), InspectionStartResult.localOwnershipIncomplete);
    expect((await db.query('local_jobs')).single['inspector_id'], isNull);
    expect((await db.query('inspection_job_retention')).single['inspector_id'], isNull);
    expect((await db.query('local_inspections')).single['notes'], 'late evidence');
  });

  test('current non-NULL owner stays unchanged while NULL retention is repaired', () async {
    await legacyJob(retention: true);
    await db.update('local_jobs', {'inspector_id': ownerA});
    final before = (await db.query('local_jobs')).single;
    expect(await InspectionStartService.prepareJob(job), InspectionStartResult.authorized);
    expect((await db.query('local_jobs')).single, before);
    expect((await db.query('inspection_job_retention')).single['inspector_id'], ownerA);
  });

  test('new CURRENT job flow unchanged', () async {
    await db.insert('local_jobs', {'id': job, 'status': 'assigned', 'inspector_id': ownerA});
    expect(await InspectionStartService.prepareJob(job), InspectionStartResult.authorized);
    expect((await db.query('inspection_job_retention')).single['inspector_id'], ownerA);
  });
}

// Intercept the real SQLite transaction solely to exercise a session change
// after the first UPDATE. All graph queries, writes and rollback are real.
class _SessionSwitchDatabase implements Database {
  _SessionSwitchDatabase(this.db, this.switchSession);
  final Database db;
  final Future<void> Function() switchSession;
  @override
  Future<T> transaction<T>(Future<T> Function(Transaction) action, {bool? exclusive}) =>
      db.transaction((txn) => action(_SessionSwitchTransaction(txn, switchSession)), exclusive: exclusive);
  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct,
    List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy,
    String? having, String? orderBy, int? limit, int? offset}) =>
      db.query(table, distinct: distinct, columns: columns, where: where, whereArgs: whereArgs,
        groupBy: groupBy, having: having, orderBy: orderBy, limit: limit, offset: offset);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SessionSwitchTransaction implements Transaction {
  _SessionSwitchTransaction(this.txn, this.switchSession);
  final Transaction txn;
  final Future<void> Function() switchSession;
  @override
  Future<int> update(String table, Map<String, Object?> values, {String? where,
    List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) async {
    final n = await txn.update(table, values, where: where, whereArgs: whereArgs,
      conflictAlgorithm: conflictAlgorithm);
    if (table == 'local_jobs') await switchSession();
    return n;
  }
  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct,
    List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy,
    String? having, String? orderBy, int? limit, int? offset}) =>
      txn.query(table, distinct: distinct, columns: columns, where: where, whereArgs: whereArgs,
        groupBy: groupBy, having: having, orderBy: orderBy, limit: limit, offset: offset);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
