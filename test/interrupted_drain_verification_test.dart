import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/sync_outbox_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'inspection_owner_fixture.dart';

/// V1 defect reproduction, not a passing recovery regression.
/// Reopens file-backed SQLite; does not simulate OS process death or remote ACK.
/// No Supabase initialization, credentials, or remote writes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  const jobA = '11111111-1111-4111-8111-111111111111';
  late Directory temporary;
  late Database db;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('fieldsync-v1-');
    db = await databaseFactoryFfi.openDatabase('${temporary.path}/fixture.db');
    final source = await File('lib/core/services/db_helper.dart').readAsString();
    for (final match in RegExp(
      r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)',
    ).allMatches(source)) {
      await db.execute(match.group(0)!);
    }
    DBHelper.useDatabaseForTesting(db);
    useOwnerFixture();
    await DBHelper.cacheJobs([{'id': jobA, 'status': 'in_progress'}]);
  });

  tearDown(() async {
    clearOwnerFixture();
    DBHelper.useDatabaseForTesting(null);
    await db.close();
    await temporary.delete(recursive: true);
  });

  Future<void> seedAction(String type, String status, {String jobId = jobA}) async {
    await db.insert('pending_actions', {
      'id': '${type}_$jobId',
      'type': type,
      'job_id': jobId,
      'payload': '{}',
      'status': status,
      'retry_count': 0,
      'last_error': null,
      'created_at': '2026-01-01T00:00:00.000',
      'updated_at': '2026-01-01T00:00:00.000',
      'inspector_id': ownerFixture,
    });
  }

  Future<void> restart() async {
    DBHelper.useDatabaseForTesting(null);
    await db.close();
    db = await databaseFactoryFfi.openDatabase('${temporary.path}/fixture.db');
    DBHelper.useDatabaseForTesting(db);
  }

  test('CASE C: interrupted syncing must recover after database reopen', () async {
    await seedAction('mark_ongoing', 'pending');
    expect((await DBHelper.getActionableActions()).single['status'], 'pending');
    await DBHelper.markActionSyncing('mark_ongoing_$jobA');
    // Model a committed claim left by an interrupted drain, well past any lease.
    await db.update('pending_actions', {
      'updated_at': '2026-01-01T00:00:00.000',
    });
    await restart();
    expect((await db.query('pending_actions')).single['status'], 'syncing');
    await SyncOutboxService.drain(trigger: 'automatic');
    await SyncOutboxService.drain(trigger: 'manual');
    await SyncOutboxService.drain(trigger: 'manual', onlyJobId: jobA);
    final persisted = (await db.query('pending_actions')).single;
    final actionable = await DBHelper.getActionableActions();
    // Accept either successful delivery or durable eligibility for retry.
    expect(
      persisted['status'] == 'synced' || actionable.any((a) => a['id'] == persisted['id']),
      isTrue,
      reason: 'Interrupted action remains ${persisted['status']}; '
          '${actionable.length} eligible rows after automatic/manual/per-job drain.',
    );
  });
}
