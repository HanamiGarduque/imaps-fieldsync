import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/sync_outbox_service.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'inspection_owner_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  const a = '11111111-1111-4111-8111-111111111111';
  const b = '22222222-2222-4222-8222-222222222222';
  late Directory directory;
  late Database db;
  late String path;

  Future<void> enqueue(String type, {double latitude = 0}) => type == 'gps_confirm'
      ? SyncOutboxService.enqueueGpsConfirm(
          jobId: a, latitude: latitude, longitude: 0, accuracyMeters: 1)
      : SyncOutboxService.enqueueMarkOngoing(jobId: a);

  Future<void> seed(String? status) => DBHelper.cacheJobs([
    {'id': a, 'status': status, 'is_self_scheduled': true},
    {'id': b, 'status': 'assigned'},
  ]);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fieldsync-r3-');
    path = '${directory.path}/fixture.db';
    db = await databaseFactoryFfi.openDatabase(path);
    final source = await File('lib/core/services/db_helper.dart').readAsString();
    for (final match in RegExp(
      r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)',
    ).allMatches(source)) {
      await db.execute(match.group(0)!);
    }
    DBHelper.useDatabaseForTesting(db);
    useOwnerFixture();
  });

  tearDown(() async {
    clearOwnerFixture();
    DBHelper.useDatabaseForTesting(null);
    await db.close();
    await directory.delete(recursive: true);
  });

  for (final type in ['gps_confirm', 'mark_ongoing']) {
    for (final status in ['assigned', 'Pending', 'pending', 'in_progress', 'in-progress', 'ongoing']) {
      test('$type canonicalizes $status, preserves retention and isolates UUID', () async {
        await seed(status);
        await DBHelper.retainInspectionJob(a);
        expect((await DBHelper.getCachedJobs()).first['status'], status);
        expect(await DBHelper.getActionableActions(), isEmpty);
        await enqueue(type);
        await enqueue(type, latitude: 1);
        DBHelper.useDatabaseForTesting(null);
        await db.close();
        db = await databaseFactoryFfi.openDatabase(path);
        DBHelper.useDatabaseForTesting(db);
        final rows = await DBHelper.getCachedJobs();
        final row = rows.firstWhere((r) => r['id'] == a);
        expect(row['status'], 'in_progress');
        expect(row['is_self_scheduled'], 1);
        final task = TaskItem.fromJob({...row, 'is_self_scheduled': true});
        expect(task.category, 'Pending');
        expect(task.pendingSection, PendingTaskSection.scheduled);
        expect(task.status, 'in_progress');
        expect(task.isSelfScheduled, isTrue);
        expect(rows.firstWhere((r) => r['id'] == b)['status'], 'assigned');
        expect((await db.query('inspection_job_retention')).single['job_id'], a);
        final action = (await DBHelper.getActionableActions()).single;
        expect(action['id'], '${type}_$a');
        expect(action['job_id'], a);
        expect(action['type'], type);
        expect(action['status'], 'pending');
        expect(action['retry_count'], 0);
        final payload = jsonDecode(action['payload'] as String);
        if (type == 'gps_confirm') {
          expect(payload['latitude'], 1);
        } else {
          expect(payload, isEmpty);
        }
      });
    }

    for (final failure in ['insert', 'update', 'ignored_update', 'missing']) {
      test('$type rolls back queue replacement on $failure', () async {
        await seed('Pending');
        await DBHelper.retainInspectionJob(a);
        // Existing action must survive a failed deterministic replacement too.
        await db.insert('pending_actions', {
          'id': '${type}_$a', 'type': type, 'job_id': a,
          'inspector_id': ownerFixture,
          'payload': '{"old":true}', 'status': 'failed', 'retry_count': 2,
          'created_at': '2026-01-01T00:00:00.000',
          'updated_at': '2026-01-01T00:00:00.000',
        });
        final before = await db.query('pending_actions');
        if (failure == 'missing') {
          await db.delete('local_jobs', where: 'id = ?', whereArgs: [a]);
        } else {
          final table = failure == 'insert' ? 'pending_actions' : 'local_jobs';
          final operation = failure == 'insert' ? 'INSERT' : 'UPDATE';
          final raise = failure == 'ignored_update'
              ? 'RAISE(IGNORE)' : "RAISE(ABORT, 'fixture failure')";
          await db.execute('CREATE TRIGGER reject_start BEFORE $operation ON $table '
              'BEGIN SELECT $raise; END');
        }
        await expectLater(enqueue(type), throwsA(
          failure == 'missing' || failure == 'ignored_update'
              ? isA<StateError>() : isA<DatabaseException>(),
        ));
        expect(await db.query('pending_actions'), before);
        final rows = await DBHelper.getCachedJobs();
        if (failure == 'missing') {
          expect(rows.where((r) => r['id'] == a), isEmpty);
        } else {
          expect(rows.firstWhere((r) => r['id'] == a)['status'], 'Pending');
        }
        expect(rows.firstWhere((r) => r['id'] == b)['status'], 'assigned');
        expect((await db.query('inspection_job_retention')).single['job_id'], a);
      });
    }

    test('$type missing row rejects new action without a fake task', () async {
      await expectLater(enqueue(type), throwsStateError);
      expect(await DBHelper.getActionableActions(), isEmpty);
      expect(await DBHelper.getCachedJobs(), isEmpty);
    });

    for (final status in ['completed', 'Completed', 'submitted', 'cancelled', 'onprocess', null, '', '   ', 'unknown']) {
      test('$type preserves local $status and existing action semantics', () async {
        await seed(status);
        await enqueue(type);
        expect((await DBHelper.getCachedJobs()).first['status'], status);
        expect((await DBHelper.getActionableActions()).single['type'], type);
      });
    }
  }
}
