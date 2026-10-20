import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/supabase_service.dart';
import 'package:imaps_fieldsync/core/services/sync_outbox_service.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'inspection_owner_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  const submittedAt = '2026-09-23T01:02:03Z';
  late Database db;
  late Map<String, dynamic> remote;
  var writes = 0;

  Future<void> seed(String type, Map<String, dynamic> payload) async {
    await db.insert('pending_actions', {
      'id': '${type}_loop5',
      'type': type,
      'job_id': 'round-1',
      'payload': jsonEncode({
        'cachedUpdatedAtSnapshot': '2026-09-23T02:00:00Z',
        ...payload,
      }),
      'status': 'syncing',
      'retry_count': 1,
      'created_at': '2026-09-23T01:00:00Z',
      'updated_at': '2026-09-23T02:00:00Z',
      'inspector_id': ownerFixture,
    });
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SyncOutboxService.resetRecoverySessionForTesting();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    final source = File('lib/core/services/db_helper.dart').readAsStringSync();
    for (final match in RegExp(
      r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)',
    ).allMatches(source)) {
      await db.execute(match.group(0)!);
    }
    DBHelper.useDatabaseForTesting(db);
    useOwnerFixture();
    remote = {
      'id': 'round-1',
      'status': 'completed',
      'current_step': 6,
      'submitted_at': submittedAt,
      'updated_at': '2026-09-23T02:00:00Z',
    };
    writes = 0;
    SyncOutboxService.recoveryReadForTesting = (_) async => remote;
    SyncOutboxService.recoveryWriteForTesting = (_, _, _, values) async {
      writes++;
      remote.addAll(values);
      return remote;
    };
  });

  tearDown(() async {
    SyncOutboxService.resetRecoverySessionForTesting();
    clearOwnerFixture();
    DBHelper.useDatabaseForTesting(null);
    await db.close();
  });

  test('completed metadata always classifies as Completed and Step 6', () {
    for (final job in [
      {'id': 'a', 'status': 'completed'},
      {
        'id': 'a',
        'status': 'completed',
        'rework_started_at': '2026-09-23T03:00:00Z',
      },
      {'id': 'a', 'status': 'completed', 'current_step': 6},
    ]) {
      final task = TaskItem.fromJob(job);
      expect(task.category, 'Completed');
      expect(task.derivedHighestStep, 6);
    }
  });

  test(
    'generic evidence update rejects lifecycle progress and submission fields',
    () async {
      for (final field in ['status', 'current_step', 'submitted_at']) {
        await expectLater(
          SupabaseService.updateJobInspectionProgress(
            jobId: 'round-1',
            updateData: {field: null},
          ),
          throwsArgumentError,
        );
      }
    },
  );

  test('late Step 5 outbox update cannot regress completed Step 6', () async {
    await seed('current_step_update', {'currentStep': 5});
    await SyncOutboxService.drain();
    expect((await db.query('pending_actions')).single['status'], 'synced');
    expect(remote['status'], 'completed');
    expect(remote['current_step'], 6);
    expect(remote['submitted_at'], submittedAt);
    expect(writes, 0);
  });

  test(
    'late in-progress outbox update cannot restart completed task',
    () async {
      await seed('mark_ongoing', const {});
      await SyncOutboxService.drain();
      expect((await db.query('pending_actions')).single['status'], 'synced');
      expect(remote['status'], 'completed');
      expect(remote['current_step'], 6);
      expect(remote['submitted_at'], submittedAt);
      expect(writes, 0);
    },
  );

  test(
    'cache refresh preserves completed classification from stale lifecycle',
    () async {
      await DBHelper.cacheJobs([
        {'id': 'round-1', 'status': 'completed'},
        {'id': 'round-2', 'status': 'assigned'},
      ]);
      await DBHelper.cacheJobs([
        {'id': 'round-1', 'status': 'in_progress'},
        {'id': 'round-2', 'status': 'assigned'},
      ]);
      final rows = await DBHelper.getCachedJobs();
      expect(
        rows.firstWhere((row) => row['id'] == 'round-1')['status'],
        'completed',
      );
      expect(
        rows.firstWhere((row) => row['id'] == 'round-2')['status'],
        'assigned',
      );
      expect(
        TaskItem.fromJob({...rows.first, 'is_self_scheduled': false}).category,
        'Completed',
      );
    },
  );

  test('source contract preserves rework lifecycle and evidence-only writes', () {
    final service = File(
      'lib/core/services/supabase_service.dart',
    ).readAsStringSync();
    final provider = File(
      'lib/modules/inspection/providers/inspection_provider.dart',
    ).readAsStringSync();
    final rework = RegExp(
      r'static Future<void> reopenForRework\([\s\S]*?(?=\n  // ─)',
    ).firstMatch(service)!.group(0)!;
    expect(rework, isNot(contains("'status': 'in_progress'")));
    expect(rework, isNot(contains("'current_step'")));
    expect(rework, isNot(contains("'submitted_at'")));
    final outbox = File(
      'lib/core/services/sync_outbox_service.dart',
    ).readAsStringSync();
    // Per-step saves write the local snapshot first and deliver through the
    // durable outbox, so the checklist evidence key lives there; the other
    // evidence keys are still built in the provider.
    expect(outbox, contains("'checklist_data'"));
    for (final evidence in ["'observations'", "'photo_paths'"]) {
      expect(provider, contains(evidence));
    }
    final submit = RegExp(
      r'static Future<InspectionAuthorityResult> submitInspection\([\s\S]*?(?=\n  // ─)',
    ).firstMatch(service)!.group(0)!;
    expect(submit, contains("'current_step': 6"));
    expect(submit, contains('existingSubmittedAt ??'));
    expect(submit, contains("'submitted_at': effectiveSubmittedAt"));
  });
}
