import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'inspection_owner_fixture.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/sync_outbox_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  late Map<String, dynamic> remote;
  var writes = 0;
  var conditionalUpdates = 0;
  const base = '2026-01-01T00:00:00Z';
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SyncOutboxService.resetRecoverySessionForTesting();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    final source = await File(
      'lib/core/services/db_helper.dart',
    ).readAsString();
    for (final match in RegExp(
      r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)',
    ).allMatches(source)) {
      final sql = match
          .group(0)!
          .replaceAll(' IF NOT EXISTS', '')
          .replaceFirst('CREATE TABLE ', 'CREATE TABLE IF NOT EXISTS ');
      await db.execute(sql);
    }
    DBHelper.useDatabaseForTesting(db);
    useOwnerFixture();
    remote = {
      'id': 'a',
      'assigned_inspector_id': ownerFixture,
      'status': 'assigned',
      'current_step': 0,
      'updated_at': base,
      'started_at': null,
    };
    await DBHelper.cacheJobs([remote]);
    writes = 0;
    conditionalUpdates = 0;
    SyncOutboxService.recoveryReadForTesting = (_) async => remote;
    SyncOutboxService.recoveryWriteForTesting =
        (id, version, status, values) async {
          conditionalUpdates++;
          expect(id, 'a');
          expect(version, remote['updated_at']);
          expect(status, remote['status']);
          expect(values.containsKey('updated_at'), isFalse);
          writes++;
          remote = {...remote, ...values, 'updated_at': '2026-01-02T00:00:00Z'};
          return remote;
        };
  });
  tearDown(() async {
    SyncOutboxService.resetRecoverySessionForTesting();
    clearOwnerFixture();
    DBHelper.useDatabaseForTesting(null);
    await db.close();
  });
  Future<void> seed(
    String type,
    Map<String, dynamic> payload, {
    String status = 'syncing',
    String id = 'action',
  }) async {
    await db.insert('pending_actions', {
      'id': id,
      'type': type,
      'job_id': 'a',
      'payload': jsonEncode({'cachedUpdatedAtSnapshot': base, ...payload}),
      'status': status,
      'retry_count': 2,
      'created_at': base,
      'updated_at': base,
      'inspector_id': ownerFixture,
    });
  }

  Future<String> state() async =>
      (await db.query('pending_actions')).first['status'] as String;

  for (final status in ['in_progress', 'completed']) {
    test('mark ongoing $status satisfied/superseded without write', () async {
      remote.addAll({'status': status, 'started_at': base});
      await seed('mark_ongoing', {});
      await SyncOutboxService.drain();
      expect(await state(), 'synced');
      expect(writes, 0);
    });
  }
  test('mark ongoing safe base guarded transition', () async {
    await seed('mark_ongoing', {});
    await SyncOutboxService.drain();
    expect(await state(), 'synced');
    expect(writes, 1);
    expect(remote['status'], 'in_progress');
  });
  test('live claim cannot be stolen by concurrent drain', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    SyncOutboxService.recoveryReadForTesting = (_) async {
      entered.complete();
      await release.future;
      return remote;
    };
    await seed('mark_ongoing', {});
    final a = SyncOutboxService.drain();
    await entered.future;
    expect(await state(), 'syncing');
    await SyncOutboxService.drain();
    expect(await state(), 'syncing');
    release.complete();
    await a;
    expect(writes, 1);
    await SyncOutboxService.drain();
    expect(writes, 1);
  });
  const gps = {'latitude': 1, 'longitude': 2, 'accuracyMeters': 3};
  test('GPS remote success ACK lost is satisfied without mutation', () async {
    remote.addAll({
      'status': 'in_progress',
      'started_at': base,
      'gps_confirmed_at': base,
      'confirmed_latitude': 1,
      'confirmed_longitude': 2,
      'gps_accuracy_m': 3,
    });
    await seed('gps_confirm', gps);
    await SyncOutboxService.drain();
    expect(await state(), 'synced');
    expect(writes, 0);
  });
  test('GPS differing evidence is conflict', () async {
    remote['confirmed_latitude'] = 9;
    await seed('gps_confirm', gps);
    await SyncOutboxService.drain();
    expect(await state(), 'conflict');
    expect(writes, 0);
  });
  test('GPS absent evidence safe base writes once', () async {
    await seed('gps_confirm', gps);
    await SyncOutboxService.drain();
    expect(await state(), 'synced');
    expect(writes, 1);
  });
  test('current step never moves backward', () async {
    remote['current_step'] = 5;
    await seed('current_step_update', {'currentStep': 2});
    await SyncOutboxService.drain();
    expect(await state(), 'conflict');
    expect(writes, 0);
  });
  test('conditional zero rows is conflict', () async {
    SyncOutboxService.recoveryWriteForTesting = (_, _, _, _) async => null;
    await seed('current_step_update', {'currentStep': 2});
    await SyncOutboxService.drain();
    expect(await state(), 'conflict');
  });
  test(
    'empty photo evidence reaches verification and acknowledges without write',
    () async {
      remote.addAll({'photo_paths': <String>[], 'photo_count': 0});
      await seed('photos_update', {'photos': []});
      await SyncOutboxService.drain();
      expect(await state(), 'synced');
      expect(writes, 0);
    },
  );
  const checklist = {
    'checklistData': <dynamic>[],
    'checklistCompletedCount': 0,
    'checklistTotalCount': 0,
  };
  const findings = {
    'observations': 'test',
    'discrepancies': null,
    'recommendations': null,
    'inspectorNotes': 'notes',
  };
  for (final type in ['checklist_update', 'findings_update']) {
    for (final mode in ['satisfied', 'safe', 'newer']) {
      test('$type $mode reconciliation', () async {
        final payload = type == 'checklist_update' ? checklist : findings;
        if (mode == 'satisfied') {
          remote.addAll(
            type == 'checklist_update'
                ? {
                    'checklist_data': [],
                    'checklist_completed_count': 0,
                    'checklist_total_count': 0,
                  }
                : {
                    'observations': 'test',
                    'discrepancies': null,
                    'recommendations': null,
                    'inspector_notes': 'notes',
                  },
          );
        }
        if (mode == 'newer') remote['updated_at'] = '2026-01-03T00:00:00Z';
        await seed(type, payload);
        await SyncOutboxService.drain();
        expect(await state(), mode == 'newer' ? 'conflict' : 'synced');
        expect(writes, mode == 'safe' ? 1 : 0);
      });
    }
  }
  const submit = {
    'findings': 'finding',
    'isCompliant': true,
    'inspectionResult': 'Compliant',
    ...findings,
    ...checklist,
    'photosData': <dynamic>[],
  };
  for (final applied in [true, false]) {
    test(
      'submit empty photos applied=$applied preserves local Completed',
      () async {
        conditionalUpdates = 0;
        await DBHelper.cacheJobs([
          {'id': 'a', 'status': 'completed'},
        ]);
        if (applied) {
          remote.addAll({
            'status': 'completed',
            'current_step': 6,
            'submitted_at': base,
            'rework_started_at': null,
            'findings': 'finding',
            'is_compliant': true,
            'inspection_result': 'Compliant',
            'observations': 'test',
            'discrepancies': null,
            'recommendations': null,
            'inspector_notes': 'notes',
            'checklist_data': [],
            'checklist_completed_count': 0,
            'checklist_total_count': 0,
            'photo_paths': [],
            'photo_count': 0,
          });
        }
        await seed('submit_inspection', submit);
        expect(
          (await DBHelper.projectPendingCompletions([
            {'id': 'a', 'status': 'assigned'},
          ])).single['status'],
          'completed',
        );
        await SyncOutboxService.drain();
        expect(await state(), 'synced');
        expect(conditionalUpdates, applied ? 0 : 1);
        expect(writes, applied ? 0 : 1);
        expect((await DBHelper.getCachedJobs()).single['status'], 'completed');
        expect(
          (await DBHelper.projectPendingCompletions([
            {'id': 'a', 'status': 'assigned'},
          ])).single['status'],
          'assigned',
        );
        await SyncOutboxService.drain();
        expect(conditionalUpdates, applied ? 0 : 1);
        expect(writes, applied ? 0 : 1);
      },
    );
  }
  test('absent durable base never replays', () async {
    await seed('mark_ongoing', {'cachedUpdatedAtSnapshot': null});
    await SyncOutboxService.drain();
    expect(await state(), 'conflict');
    expect(writes, 0);
  });
  test('completed status alone cannot acknowledge submit', () async {
    remote['status'] = 'completed';
    await seed('submit_inspection', submit);
    await SyncOutboxService.drain();
    expect(await state(), 'conflict');
    expect(writes, 0);
  });
  for (final status in ['conflict', 'synced']) {
    test('$status excluded after startup', () async {
      await seed('mark_ongoing', {}, status: status);
      await SyncOutboxService.drain();
      expect(await state(), status);
      expect(writes, 0);
    });
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // LOOP 1D-R4 FINAL CLOSURE PASS VERIFICATIONS
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  test('submit_inspection preserves exact payload submittedAt', () async {
    const customTime = '2026-05-15T10:30:00.000Z';
    await seed('submit_inspection', {...submit, 'submittedAt': customTime});
    await SyncOutboxService.drain();
    expect(await state(), 'synced');
    expect(writes, 1);
    expect(remote['submitted_at'], customTime);
    expect(remote['status'], 'completed');
  });

  test(
    'submit_inspection fallback uses action created_at as durable Final Submit timestamp',
    () async {
      const durableCreatedAt = '2026-03-20T14:15:00.000Z';
      await db.insert('pending_actions', {
        'id': 'submit_with_created_at',
        'type': 'submit_inspection',
        'job_id': 'a',
        'inspector_id': ownerFixture,
        'payload': jsonEncode({'cachedUpdatedAtSnapshot': base, ...submit}),
        'status': 'syncing',
        'retry_count': 1,
        'created_at': durableCreatedAt,
        'updated_at': base,
      });
      await SyncOutboxService.drain();
      final row = (await db.query(
        'pending_actions',
        where: "id = 'submit_with_created_at'",
      )).single;
      expect(row['status'], 'synced');
      expect(writes, 1);
      expect(remote['submitted_at'], durableCreatedAt);
      expect(remote['status'], 'completed');
    },
  );

  test(
    'submit_inspection missing both submittedAt and created_at throws and marks conflict',
    () async {
      await db.insert('pending_actions', {
        'id': 'submit_no_ts',
        'type': 'submit_inspection',
        'job_id': 'a',
        'inspector_id': ownerFixture,
        'payload': jsonEncode({'cachedUpdatedAtSnapshot': base, ...submit}),
        'status': 'syncing',
        'retry_count': 1,
        'created_at': '',
        'updated_at': base,
      });
      await SyncOutboxService.drain();
      final row = (await db.query(
        'pending_actions',
        where: "id = 'submit_no_ts'",
      )).single;
      expect(row['status'], 'conflict');
      expect(
        row['last_error'],
        contains('Original intended submitted_at unavailable'),
      );
      expect(writes, 0);
    },
  );

  test(
    'zero-row conditional update yields conflict without infinite retry loop',
    () async {
      SyncOutboxService
          .recoveryWriteForTesting = (id, version, status, values) async {
        conditionalUpdates++;
        // Return null to simulate 0 rows matched / conditional check failure
        return null;
      };
      await seed('mark_ongoing', {});
      await SyncOutboxService.drain();
      expect(await state(), 'conflict');
      final row = (await db.query('pending_actions')).single;
      expect(
        row['last_error'],
        contains('Conditional recovery affected zero rows'),
      );
      expect(conditionalUpdates, 1);
    },
  );

  test(
    'submit_inspection on remote with rework_started_at yields conflict (deferred to Loop 5)',
    () async {
      remote['rework_started_at'] = '2026-01-01T12:00:00Z';
      await seed('submit_inspection', submit);
      await SyncOutboxService.drain();
      expect(await state(), 'conflict');
      final row = (await db.query('pending_actions')).single;
      expect(
        row['last_error'],
        contains('Submission/rework revision ambiguous'),
      );
      expect(writes, 0);
    },
  );

  test(
    'submit_inspection on completed remote with differing submitted_at yields conflict',
    () async {
      remote.addAll({
        'status': 'completed',
        'submitted_at': '2025-12-31T23:59:59Z',
        'rework_started_at': null,
        'findings': 'different finding',
      });
      await seed('submit_inspection', submit);
      await SyncOutboxService.drain();
      expect(await state(), 'conflict');
      expect(writes, 0);
    },
  );

  test(
    'repeated start() does not resnapshot active live claims or duplicate remote requests',
    () async {
      var reads = 0;
      SyncOutboxService.recoveryReadForTesting = (_) async {
        reads++;
        return remote;
      };
      await seed('mark_ongoing', {});
      // Initial drain executes startup recovery and syncs the row
      SyncOutboxService.start();
      for (
        var attempt = 0;
        attempt < 50 && await state() != 'synced';
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(await state(), 'synced');
      expect(reads, 1);
      expect(writes, 1);

      // Repeated start() within the same active process must no-op (no extra reads/writes)
      SyncOutboxService.start();
      SyncOutboxService.start();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(reads, 1);
      expect(writes, 1);
    },
  );
  test(
    'enqueue-vs-ACK ownership: newer replacement payload during in-flight drain is not marked synced by old execution',
    () async {
      final pauseCompleter = Completer<void>();
      SyncOutboxService.recoveryReadForTesting = (_) async {
        // Pause while in-flight
        await pauseCompleter.future;
        return remote;
      };

      // 1. Seed initial checklist update as an interrupted claim
      await db.insert('pending_actions', {
        'id': 'checklist_update_a',
        'type': 'checklist_update',
        'job_id': 'a',
        'inspector_id': ownerFixture,
        'payload': jsonEncode({
          'cachedUpdatedAtSnapshot': base,
          'checklistData': <dynamic>[],
          'checklistCompletedCount': 1,
          'checklistTotalCount': 5,
          'r4RecoveryRequired': true,
        }),
        'status': 'syncing',
        'retry_count': 1,
        'created_at': base,
        'updated_at': base,
      });

      // 2. Start drain (startup recovery turns syncing -> failed, drain sets syncing and pauses in recoveryRead)
      final drainFuture = SyncOutboxService.drain();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Confirm it transitioned to syncing
      final inFlightRow = (await db.query(
        'pending_actions',
        where: "id = 'checklist_update_a'",
      )).single;
      expect(inFlightRow['status'], 'syncing');

      // 3. User makes another checklist edit while the first is in-flight.
      // The live claim keeps its original payload; the newer edit gets its
      // own pending row instead of overwriting the row being acknowledged.
      const newPayload = {
        'cachedUpdatedAtSnapshot': base,
        'checklistData': <dynamic>[],
        'checklistCompletedCount': 4,
        'checklistTotalCount': 5,
      };
      await DBHelper.enqueueAction(
        id: 'checklist_update_a',
        type: 'checklist_update',
        jobId: 'a',
        payload: newPayload,
      );

      final claimedRow = (await db.query(
        'pending_actions',
        where: "id = 'checklist_update_a'",
      )).single;
      expect(claimedRow['status'], 'syncing');
      expect(
        jsonDecode(claimedRow['payload'] as String)['checklistCompletedCount'],
        1,
      );
      final replacementRows = await db.query(
        'pending_actions',
        where: "type = 'checklist_update' AND status = 'pending'",
      );
      expect(replacementRows, hasLength(1));
      final replacementId = replacementRows.single['id'] as String;
      expect(replacementId, isNot('checklist_update_a'));
      expect(
        jsonDecode(
          replacementRows.single['payload'] as String,
        )['checklistCompletedCount'],
        4,
      );

      // 4. Release the first in-flight execution
      pauseCompleter.complete();
      await drainFuture;

      // 5. The old ACK can only mark the row it claimed; the newer row stays
      // pending for the next drain and keeps its newer payload.
      final afterOldAckRow = (await db.query(
        'pending_actions',
        where: 'id = ?',
        whereArgs: [replacementId],
      )).single;
      expect(afterOldAckRow['status'], 'pending');
      expect(
        jsonDecode(
          afterOldAckRow['payload'] as String,
        )['checklistCompletedCount'],
        4,
      );
      final claimedAfterDrain = (await db.query(
        'pending_actions',
        where: "id = 'checklist_update_a'",
      )).single;
      expect(claimedAfterDrain['status'], isNot('pending'));
      expect(claimedAfterDrain['status'], isNot('syncing'));
    },
  );

  test(
    'same-job historical ordering: stale actions on completed remote state do not regress lifecycle or overwrite evidence',
    () async {
      remote.addAll({
        'status': 'completed',
        'submitted_at': base,
        'rework_started_at': null,
        'findings': 'final findings',
        'is_compliant': true,
        'inspection_result': 'Compliant',
        'checklist_data': [
          {'step': 1, 'done': true},
        ],
        'checklist_completed_count': 1,
        'checklist_total_count': 1,
        'photo_paths': [],
        'photo_count': 0,
      });

      // 1. Stale mark_ongoing on completed remote -> satisfied/superseded, 0 writes, status='synced'
      await seed('mark_ongoing', {}, id: 'stale_mark_ongoing');
      // 2. Stale gps_confirm on completed remote -> conflict, 0 writes, lifecycle never regressed
      await seed('gps_confirm', {
        'latitude': 14.5995,
        'longitude': 120.9842,
        'accuracyMeters': 5.0,
      }, id: 'stale_gps');
      // 3. Stale checklist_update with differing evidence on completed remote -> conflict, 0 writes
      await seed('checklist_update', {
        'checklistData': [
          {'step': 1, 'done': false},
        ],
        'checklistCompletedCount': 0,
        'checklistTotalCount': 1,
      }, id: 'stale_checklist');

      await SyncOutboxService.drain();

      expect(
        (await db.query(
          'pending_actions',
          where: "id = 'stale_mark_ongoing'",
        )).single['status'],
        'synced',
      );
      expect(
        (await db.query(
          'pending_actions',
          where: "id = 'stale_gps'",
        )).single['status'],
        'conflict',
      );
      expect(
        (await db.query(
          'pending_actions',
          where: "id = 'stale_checklist'",
        )).single['status'],
        'conflict',
      );
      expect(writes, 0);
      expect(remote['status'], 'completed');
    },
  );

  test(
    'cross-job isolation: Job A conflict does not block Job B from syncing',
    () async {
      final remoteB = {
        'id': 'b',
        'status': 'assigned',
        'updated_at': base,
        'started_at': null,
      };
      SyncOutboxService.recoveryReadForTesting = (id) async =>
          id == 'a' ? remote : remoteB;
      SyncOutboxService.recoveryWriteForTesting =
          (id, version, status, values) async {
            writes++;
            if (id == 'b') {
              remoteB.addAll({...values, 'updated_at': '2026-01-02T00:00:00Z'});
              return remoteB;
            }
            remote.addAll({...values, 'updated_at': '2026-01-02T00:00:00Z'});
            return remote;
          };

      // Job A has stale/absent snapshot -> conflict
      await db.insert('pending_actions', {
        'id': 'job_a_action',
        'type': 'mark_ongoing',
        'job_id': 'a',
        'inspector_id': ownerFixture,
        'payload': jsonEncode({
          'cachedUpdatedAtSnapshot': null,
          'r4RecoveryRequired': true,
        }),
        'status': 'syncing',
        'retry_count': 1,
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      });

      // Job B has valid snapshot and payload -> should sync
      await db.insert('pending_actions', {
        'id': 'job_b_action',
        'type': 'mark_ongoing',
        'job_id': 'b',
        'inspector_id': ownerFixture,
        'payload': jsonEncode({
          'cachedUpdatedAtSnapshot': base,
          'r4RecoveryRequired': true,
        }),
        'status': 'syncing',
        'retry_count': 1,
        'created_at': '2026-01-01T00:01:00Z',
        'updated_at': '2026-01-01T00:01:00Z',
      });

      await SyncOutboxService.drain();

      final rowA = (await db.query(
        'pending_actions',
        where: "id = 'job_a_action'",
      )).single;
      final rowB = (await db.query(
        'pending_actions',
        where: "id = 'job_b_action'",
      )).single;

      expect(rowA['status'], 'conflict');
      expect(rowB['status'], 'synced');
      expect(remoteB['status'], 'in_progress');
      expect(writes, 1);
    },
  );

  test(
    'r4RecoveryRequired is retained diagnostic payload and inert after synced',
    () async {
      await DBHelper.cacheJobs([
        {'id': 'a', 'status': 'assigned'},
      ]);
      await seed('mark_ongoing', {
        'r4RecoveryRequired': true,
      }, status: 'syncing');
      await SyncOutboxService.drain();

      final row = (await db.query('pending_actions')).single;
      expect(row['status'], 'synced');
      final payload =
          jsonDecode(row['payload'] as String) as Map<String, dynamic>;
      expect(payload['r4RecoveryRequired'], true);

      // Re-draining synced action produces 0 writes
      final writesBefore = writes;
      await SyncOutboxService.drain();
      expect(writes, writesBefore);

      // Newly enqueued action does not inherit r4RecoveryRequired
      await DBHelper.enqueueAction(
        id: 'fresh_action',
        type: 'mark_ongoing',
        jobId: 'a',
        payload: const {},
      );
      final freshRow = (await db.query(
        'pending_actions',
        where: "id = 'fresh_action'",
      )).single;
      final freshPayload =
          jsonDecode(freshRow['payload'] as String) as Map<String, dynamic>;
      expect(freshPayload.containsKey('r4RecoveryRequired'), isFalse);
    },
  );
}
