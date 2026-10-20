import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/supabase_service.dart';
import 'package:imaps_fieldsync/core/services/sync_outbox_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const owner = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
const job = 'bbbbbbbb-1111-4111-8111-bbbbbbbbbbbb';
const base = '2026-01-01T00:00:00Z';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  late Map<String, dynamic> remote;
  String? readError;
  String? patchError;
  String? photoError;
  bool loseSubmitResponse = false;
  bool zeroRows = false;
  bool wrongReadId = false;
  int patches = 0;
  int finalPatches = 0;
  final activity = <String, Map<String, dynamic>>{};
  Completer<http.Response>? heldRead;
  bool heldReadStarted = false;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://evaluator-sync.test',
      publishableKey: 'isolated-fixture',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((r) async {
        if (r.url.host != 'evaluator-sync.test') {
          throw StateError('External HTTP is forbidden');
        }
        http.Response reply(Object? value, [int status = 200]) => http.Response(
          jsonEncode(value),
          status,
          request: r,
          headers: {'content-type': 'application/json'},
        );
        http.Response rejected(String code) => reply(
          {'code': code, 'message': 'Private server details must not surface'},
          code == 'PGRST301'
              ? 401
              : code == '42501'
              ? 403
              : code == 'XX000'
              ? 503
              : 400,
        );
        if (r.url.path == '/auth/v1/logout') return reply({});
        if (r.url.path == '/rest/v1/activity_log') {
          final row = Map<String, dynamic>.from(jsonDecode(r.body) as Map);
          final id = row['id'] as String? ?? 'generated-${activity.length}';
          activity.putIfAbsent(id, () => row);
          return reply({}, 201);
        }
        if (r.url.path == '/rest/v1/field_job_photos') {
          if (photoError != null) return rejected(photoError!);
          return reply([]);
        }
        expect(r.url.path, '/rest/v1/field_jobs');
        final q = r.url.queryParameters;
        final objectResponse = r.headers.entries.any(
          (h) => h.key.toLowerCase() == 'accept' && h.value.contains('object'),
        );
        final owned =
            remote['assigned_inspector_id'] == owner &&
            (q['assigned_inspector_id'] == null ||
                q['assigned_inspector_id'] == 'eq.$owner');
        if (r.method == 'GET') {
          if (heldRead != null) {
            heldReadStarted = true;
            return heldRead!.future;
          }
          if (readError != null) return rejected(readError!);
          final row = {...remote, if (wrongReadId) 'id': 'another-round'};
          return reply(
            objectResponse
                ? (owned ? row : null)
                : owned
                ? [row]
                : [],
          );
        }
        expect(r.method, 'PATCH');
        patches++;
        if (patchError != null) return rejected(patchError!);
        var matched = owned && !zeroRows;
        if (q['updated_at'] != null) {
          matched &= q['updated_at'] == 'eq.${remote['updated_at']}';
        }
        if (q['status']?.startsWith('eq.') == true) {
          matched &= q['status'] == 'eq.${remote['status']}';
        }
        if (matched) {
          final values = Map<String, dynamic>.from(jsonDecode(r.body) as Map);
          remote.addAll(values);
          remote['updated_at'] = DateTime.utc(
            2026,
            1,
            1,
            0,
            patches,
          ).toIso8601String();
          if (values['status'] == 'completed') {
            finalPatches++;
            if (loseSubmitResponse) {
              loseSubmitResponse = false;
              throw const SocketException('Isolated lost accepted response');
            }
          }
        }
        if (objectResponse) {
          return reply(matched ? Map.of(remote) : null);
        }
        return reply(matched ? [Map.of(remote)] : []);
      }),
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());

  setUp(() async {
    SyncOutboxService.resetRecoverySessionForTesting();
    SharedPreferences.setMockInitialValues({});
    await SupabaseService.client.auth.setInitialSession(
      jsonEncode({
        'access_token': 'fictional',
        'refresh_token': 'fixture',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': owner,
          'app_metadata': {},
          'user_metadata': {},
          'aud': 'authenticated',
          'created_at': base,
        },
      }),
    );
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    final source = File('lib/core/services/db_helper.dart').readAsStringSync();
    for (final statement in RegExp(
      r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)',
    ).allMatches(source)) {
      await db.execute(statement.group(0)!);
    }
    DBHelper.useDatabaseForTesting(db);
    remote = {
      'id': job,
      'assigned_inspector_id': owner,
      'status': 'in_progress',
      'current_step': 5,
      'updated_at': base,
      'submitted_at': null,
      'rework_started_at': null,
      'findings': 'Old notes',
      'is_compliant': false,
      'inspection_result': 'For Review',
      'observations': 'Old observations',
      'discrepancies': 'Old reason',
      'recommendations': null,
      'inspector_notes': 'Old notes',
      'checklist_data': [],
      'checklist_completed_count': 0,
      'checklist_total_count': 0,
      'photo_paths': [],
      'photo_count': 0,
    };
    await DBHelper.cacheJobs([remote]);
    readError = null;
    patchError = null;
    photoError = null;
    loseSubmitResponse = false;
    zeroRows = false;
    wrongReadId = false;
    patches = 0;
    finalPatches = 0;
    activity.clear();
    heldRead = null;
    heldReadStarted = false;
    SyncOutboxService.hasConnectionOverride = () async => true;
  });
  tearDown(() async {
    if (heldRead != null && !heldRead!.isCompleted) {
      heldRead!.complete(http.Response('[]', 200));
    }
    SyncOutboxService.resetRecoverySessionForTesting();
    SyncOutboxService.hasConnectionOverride = null;
    DBHelper.useDatabaseForTesting(null);
    await db.close();
  });

  Future<Map<String, dynamic>> action(String id) async =>
      Map<String, dynamic>.from(
        (await db.query(
          'pending_actions',
          where: 'id = ?',
          whereArgs: [id],
        )).single,
      );
  Future<Map<String, dynamic>> finalIntent() async {
    await SyncOutboxService.enqueueSubmitInspection(
      jobId: job,
      findings: 'Final notes',
      isCompliant: true,
      inspectionResult: 'Compliant',
      observations: 'Final observations',
      discrepancies: null,
      recommendations: null,
      inspectorNotes: 'Final notes',
      checklistData: const [
        {'item': 'Evidence', 'checked': true},
      ],
      checklistCompletedCount: 1,
      checklistTotalCount: 1,
      photosData: const [],
    );
    return Map<String, dynamic>.from(
      (await db.query(
        'pending_actions',
        where: "type = 'submit_inspection'",
      )).single,
    );
  }

  Future<void> draft(String type) async {
    if (type == 'checklist_update') {
      await SyncOutboxService.enqueueChecklistUpdate(
        jobId: job,
        checklistData: const [
          {'item': 'Evidence', 'checked': false},
        ],
        checklistCompletedCount: 0,
        checklistTotalCount: 1,
      );
    } else {
      await SyncOutboxService.enqueueFindingsUpdate(
        jobId: job,
        observations: 'Stale observations',
        discrepancies: 'Stale reason',
        recommendations: null,
        inspectorNotes: 'Stale notes',
      );
    }
  }

  for (final code in ['42501', '23514', '22P02']) {
    test(
      'known rejection $code is actionable, not a connection failure',
      () async {
        patchError = code;
        await expectLater(
          SupabaseService.updateJobInspectionProgress(
            jobId: job,
            updateData: {'inspector_notes': 'Preserved'},
          ),
          throwsA(
            isA<InspectionAuthorityException>()
                .having((e) => e.result.name, 'result', 'serverRejected')
                .having(
                  (e) => e.toString(),
                  'sanitized message',
                  isNot(contains('Private server')),
                ),
          ),
        );
      },
    );
  }
  test('submission preliminary read preserves permission rejection', () async {
    readError = '42501';
    expect(
      (await SupabaseService.submitInspection(
        jobId: job,
        findings: 'Preserved',
        isCompliant: false,
        inspectionResult: 'For Review',
      )).name,
      'serverRejected',
    );
  });
  test(
    'submission preliminary read preserves expired-session classification',
    () async {
      readError = 'PGRST301';
      expect(
        await SupabaseService.submitInspection(
          jobId: job,
          findings: 'Preserved',
          isCompliant: false,
          inspectionResult: 'For Review',
        ),
        InspectionAuthorityResult.authRequired,
      );
    },
  );
  test(
    'submission preliminary read times out without accepting work',
    () async {
      heldRead = Completer<http.Response>();
      await expectLater(
        SupabaseService.submitInspection(
          jobId: job,
          findings: 'Preserved',
          isCompliant: false,
          inspectionResult: 'For Review',
        ).timeout(const Duration(seconds: 11)),
        completion(InspectionAuthorityResult.offlineOrUnverifiable),
      );
      expect(heldReadStarted, isTrue);
    },
  );
  test(
    'photo permission rejection is not flattened into unknown transport',
    () async {
      photoError = '42501';
      await expectLater(
        SupabaseService.uploadInspectionPhotos(
          jobId: job,
          photosData: const [
            {'photoPath': 'isolated-fictional.jpg'},
          ],
        ),
        throwsA(
          isA<InspectionAuthorityException>().having(
            (e) => e.result.name,
            'result',
            'serverRejected',
          ),
        ),
      );
    },
  );

  for (final type in ['checklist_update', 'findings_update']) {
    test(
      'older $type survives truthfully but cannot overwrite final evidence',
      () async {
        await draft(type);
        final old = await action('${type}_$job');
        final finalRow = await finalIntent();
        await SyncOutboxService.drain(trigger: 'manual');
        await SyncOutboxService.drain(trigger: 'manual');
        expect((await action('${type}_$job'))['status'], 'superseded');
        expect((await action('${type}_$job'))['payload'], old['payload']);
        expect((await action(finalRow['id'] as String))['status'], 'synced');
        expect(remote['inspector_notes'], 'Final notes');
        expect(remote['checklist_data'], [
          {'item': 'Evidence', 'checked': true},
        ]);
        expect(patches, 1);
        final logs = await DBHelper.getSyncLogEntries();
        expect(
          logs.any(
            (e) =>
                e['pending_action_id'] == old['id'] &&
                e['result'] == 'info' &&
                '${e['message']}'.contains('not sent'),
          ),
          isTrue,
        );
      },
    );
    for (final accepted in [false, true]) {
      test(
        'late normal $type enqueue after final accepted=$accepted never replays',
        () async {
          await finalIntent();
          if (accepted) await SyncOutboxService.drain(trigger: 'manual');
          await draft(type);
          await SyncOutboxService.drain(trigger: 'manual');
          expect((await action('${type}_$job'))['status'], 'superseded');
          expect(remote['inspector_notes'], 'Final notes');
          expect(remote['checklist_data'], [
            {'item': 'Evidence', 'checked': true},
          ]);
          expect(patches, 1);
        },
      );
    }
  }

  test(
    'lost accepted submit response reconciles after restart without another business PATCH',
    () async {
      final saved = await finalIntent();
      loseSubmitResponse = true;
      await SyncOutboxService.drain(trigger: 'manual');
      final failed = await action(saved['id'] as String);
      expect(failed['status'], 'failed');
      expect(
        jsonDecode(failed['payload'] as String)['r4RecoveryRequired'],
        isTrue,
      );
      SyncOutboxService.resetRecoverySessionForTesting();
      await SyncOutboxService.drain(trigger: 'manual');
      expect((await action(saved['id'] as String))['status'], 'synced');
      expect(finalPatches, 1);
      expect(activity.length, lessThanOrEqualTo(1));
      expect(
        (await action(saved['id'] as String))['created_at'],
        saved['created_at'],
      );
    },
  );
  test(
    'zero-row completion cannot accept matching verdict with different evidence',
    () async {
      remote.addAll({
        'status': 'completed',
        'current_step': 6,
        'submitted_at': base,
        'findings': 'Final notes',
        'is_compliant': true,
        'inspection_result': 'Compliant',
      });
      zeroRows = true;
      expect(
        await SupabaseService.submitInspection(
          jobId: job,
          findings: 'Final notes',
          isCompliant: true,
          inspectionResult: 'Compliant',
          observations: 'Final observations',
          inspectorNotes: 'Final notes',
          checklistData: const [
            {'item': 'Evidence', 'checked': true},
          ],
          checklistCompletedCount: 1,
          checklistTotalCount: 1,
          photoPaths: const [],
        ),
        isNot(InspectionAuthorityResult.authorized),
      );
    },
  );
  test(
    'authority-wrapped fifth transient failure pauses and warns, without a sixth automatic attempt',
    () async {
      await draft('checklist_update');
      await db.update('pending_actions', {
        'retry_count': 4,
        'updated_at': '2020-01-01T00:00:00Z',
      });
      patchError = 'XX000';
      await SyncOutboxService.drain();
      expect((await action('checklist_update_$job'))['status'], 'paused');
      expect((await action('checklist_update_$job'))['retry_count'], 5);
      await SyncOutboxService.drain();
      expect(patches, 1);
      expect(
        (await db.query(
          'sync_log_entries',
          where: "event_type = 'queue_finished'",
        )).single['result'],
        'warning',
      );
    },
  );
  test(
    'known final rejection pauses with evidence and no automatic retry',
    () async {
      final saved = await finalIntent();
      patchError = '23514';
      await SyncOutboxService.drain();
      final rejected = await action(saved['id'] as String);
      expect(rejected['status'], 'paused');
      expect(rejected['payload'], saved['payload']);
      expect(rejected['last_error'], isNot(contains('Private server')));
      await SyncOutboxService.drain();
      expect(patches, 1);
    },
  );
  test('a pause-only authentication batch is warning, never success', () async {
    await draft('checklist_update');
    patchError = 'PGRST301';
    await SyncOutboxService.drain(trigger: 'manual');
    expect((await action('checklist_update_$job'))['status'], 'paused');
    expect(
      (await db.query(
        'sync_log_entries',
        where: "event_type = 'queue_finished'",
      )).single['result'],
      'warning',
    );
  });
  test(
    'replacement between selection and claim cannot acknowledge the newer unsent payload',
    () async {
      await draft('checklist_update');
      final old = await action('checklist_update_$job');
      final newer =
          Map<String, dynamic>.from(jsonDecode(old['payload'] as String) as Map)
            ..['checklistData'] = [
              {'item': 'Evidence', 'checked': true},
            ]
            ..['checklistCompletedCount'] = 1;
      final escaped = jsonEncode(newer).replaceAll("'", "''");
      await db.execute("""
      CREATE TRIGGER replace_before_claim AFTER INSERT ON sync_log_entries
      WHEN NEW.event_type = 'queue_started' BEGIN
        UPDATE pending_actions SET payload = '$escaped', updated_at = '2026-02-01T00:00:00Z'
        WHERE id = 'checklist_update_$job';
      END
    """);
      await SyncOutboxService.drain(trigger: 'manual');
      expect((await action('checklist_update_$job'))['status'], 'pending');
      expect(
        jsonDecode(
          (await action('checklist_update_$job'))['payload'] as String,
        ),
        newer,
      );
      expect(patches, 0);
    },
  );

  test(
    'an unrelated preliminary receipt never authorizes or mutates this round',
    () async {
      wrongReadId = true;
      expect(
        await SupabaseService.submitInspection(
          jobId: job,
          findings: 'Final notes',
          isCompliant: true,
          inspectionResult: 'Compliant',
        ),
        InspectionAuthorityResult.offlineOrUnverifiable,
      );
      expect(patches, 0);
    },
  );
  test(
    'malformed draft payload does not block a valid queued final submission',
    () async {
      await draft('checklist_update');
      await db.update(
        'pending_actions',
        {'payload': '{'},
        where: 'id = ?',
        whereArgs: ['checklist_update_$job'],
      );
      final saved = await finalIntent();
      await expectLater(SyncOutboxService.drain(trigger: 'manual'), completes);
      expect((await action(saved['id'] as String))['status'], 'synced');
      expect((await action('checklist_update_$job'))['status'], 'failed');
    },
  );
  test(
    'getOwnedAction reads only this inspector and keeps a successful durable receipt',
    () async {
      final saved = await finalIntent();
      expect(
        (await DBHelper.getOwnedAction(saved['id'] as String))!['status'],
        'pending',
      );
      await SyncOutboxService.drain(trigger: 'manual');
      expect(
        (await DBHelper.getOwnedAction(saved['id'] as String))!['status'],
        'synced',
      );
      expect(activity.keys, [saved['id']]);
      DBHelper.inspectorIdForTesting = 'another-inspector';
      try {
        expect(await DBHelper.getOwnedAction(saved['id'] as String), isNull);
      } finally {
        DBHelper.inspectorIdForTesting = null;
      }
      expect(
        (await DBHelper.getOwnedAction(saved['id'] as String))!['created_at'],
        saved['created_at'],
      );
    },
  );
  test(
    'local snapshot rejects a stale expected inspector before writing a fresh job',
    () async {
      DBHelper.inspectorIdForTesting = 'another-inspector';
      try {
        await expectLater(
          Future.sync(
            () => Function.apply(DBHelper.saveInspectionLocally, [], {
              #jobId: 'fresh-job',
              #actualLandUse: 'Fictional',
              #notes: 'Preserved',
              #isCompliant: false,
              #inspectionResult: '',
              #checklist: <String, dynamic>{},
              #boundaryStatus: '',
              #expectedInspectorId: owner,
            }),
          ),
          throwsStateError,
        );
        expect(await db.query('local_inspections'), isEmpty);
      } finally {
        DBHelper.inspectorIdForTesting = null;
      }
    },
  );
  test(
    'supersession preserves an older conflict and its exact evidence',
    () async {
      await draft('checklist_update');
      await db.update('pending_actions', {
        'status': 'conflict',
        'last_error': 'Review required',
      });
      final before = await action('checklist_update_$job');
      await finalIntent();
      await draft('checklist_update');
      expect(await action('checklist_update_$job'), before);
      expect(
        (await db.query('pending_actions', where: "status = 'superseded'")),
        hasLength(1),
      );
    },
  );
  for (final liveStatus in ['syncing', 'conflict']) {
    test(
      'a late autosave cannot replace a $liveStatus draft before final submit',
      () async {
        await draft('checklist_update');
        if (liveStatus == 'syncing') {
          await DBHelper.markActionSyncing('checklist_update_$job');
        } else {
          await db.update('pending_actions', {
            'status': 'conflict',
            'last_error': 'Review required',
          });
        }
        final before = await action('checklist_update_$job');
        expect(before['status'], liveStatus);
        await SyncOutboxService.enqueueChecklistUpdate(
          jobId: job,
          checklistData: const [
            {'item': 'Evidence', 'checked': true},
          ],
          checklistCompletedCount: 1,
          checklistTotalCount: 1,
        );
        expect(await action('checklist_update_$job'), before);
        final pending = await db.query(
          'pending_actions',
          where: "type = 'checklist_update' AND status = 'pending'",
        );
        expect(pending, hasLength(1));
        expect(pending.single['id'], isNot('checklist_update_$job'));
        expect(pending.single['payload'], contains('"checked":true'));
      },
    );
  }
  test(
    'normal autosave stays blocked after capped final history is retired',
    () async {
      final saved = await finalIntent();
      await SyncOutboxService.drain(trigger: 'manual');
      await db.delete(
        'pending_actions',
        where: 'id = ?',
        whereArgs: [saved['id']],
      );
      await draft('findings_update');
      await SyncOutboxService.drain(trigger: 'manual');
      expect((await action('findings_update_$job'))['status'], 'superseded');
      expect(remote['inspector_notes'], 'Final notes');
      expect(patches, 1);
    },
  );
  for (final type in ['checklist_update', 'findings_update']) {
    test(
      'genuinely later $type rework remains deliverable after final acceptance',
      () async {
        await finalIntent();
        await SyncOutboxService.drain(trigger: 'manual');
        if (type == 'checklist_update') {
          await SyncOutboxService.enqueueChecklistUpdate(
            jobId: job,
            isRework: true,
            checklistData: const [
              {'item': 'Evidence', 'checked': false},
            ],
            checklistCompletedCount: 0,
            checklistTotalCount: 1,
          );
        } else {
          await SyncOutboxService.enqueueFindingsUpdate(
            jobId: job,
            isRework: true,
            observations: 'Later rework',
            discrepancies: 'Later explanation',
            recommendations: null,
            inspectorNotes: 'Later rework',
          );
        }
        await SyncOutboxService.drain(trigger: 'manual');
        expect((await action('${type}_$job'))['status'], 'synced');
        expect(remote['status'], 'completed');
        expect(remote['current_step'], 6);
        expect(patches, 2);
        if (type == 'checklist_update') {
          expect(remote['checklist_data'], [
            {'item': 'Evidence', 'checked': false},
          ]);
        } else {
          expect(remote['inspector_notes'], 'Later rework');
        }
      },
    );
  }
}
