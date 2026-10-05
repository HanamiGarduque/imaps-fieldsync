// Reports & Support queue behaviour: persist-before-send, the five locked
// transport states, error classification, concurrency, and isolation from the
// inspection SyncOutbox.
//
// Runs entirely against isolated temporary databases and stubbed remote
// inserts. No network, no Supabase, no device data.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/models/report_models.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/report_queue_schema.dart';
import 'package:imaps_fieldsync/core/services/report_submission_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _techDraft = TechnicalIssueDraft(
  title: 'App closes when opening a task',
  module: 'My Tasks',
  summary: 'It closed three times this morning.',
  reproSteps: 'Home > My Tasks > tap first card',
);

const _supportDraft = ApplicationSupportDraft(
  fieldJobId: 'job-uuid-1',
  supabaseApplicationId: 'app-uuid-1',
  bridgeSourceId: 'rosario-imaps-local-0921-a',
  supportCategory: 'incorrect_information',
  description: 'The listed land use does not match the signage on site.',
  affectedField: 'Land use',
  requestedChange: 'Please correct to Mixed Residential.',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory dir;
  late Database db;
  late List<Map<String, dynamic>> inserts;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fieldsync-rq-');
    db = await databaseFactoryFfi.openDatabase(
      '${dir.path}/q.db',
      options: OpenDatabaseOptions(
        version: 15,
        onCreate: (d, _) async {
          await ReportQueueSchema.createTable(d);
        },
      ),
    );
    DBHelper.useDatabaseForTesting(db);
    inserts = <Map<String, dynamic>>[];
    ReportQueueService.resetTestHooks();
    ReportQueueService.inspectorIdOverride = () => 'inspector-uuid';
    ReportQueueService.connectivityOverride = () async => false;
    ReportQueueService.remoteInsertOverride = (payload) async {
      inserts.add(payload);
      return {
        'id': 'remote-${inserts.length}',
        'reference_code': 'DR-2026-000${inserts.length}',
      };
    };
  });

  tearDown(() async {
    ReportQueueService.resetTestHooks();
    DBHelper.useDatabaseForTesting(null);
    await db.close();
    if (dir.existsSync()) {
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        // Windows may still hold the handle briefly; harmless for a temp dir.
      }
    }
  });

  Future<LocalReportRow> rowOf(String id) async =>
      (await ReportQueueService.rowById(id))!;

  test(
    'offline Technical Issue is persisted before any send, with no job',
    () async {
      final id = await ReportQueueService.enqueueTechnicalIssue(_techDraft);
      final row = await rowOf(id);
      expect(row.queueState, ReportQueueState.pending);
      expect(row.fieldJobId, isNull);
      expect(row.supabaseApplicationId, isNull);
      expect(row.bridgeSourceId, isNull);
      // Nothing was dispatched: the device reported itself offline.
      expect(inserts, isEmpty);
      // Typed text survived the failed send.
      expect(row.payload['summary'], _techDraft.summary);
      expect(row.payload['repro_steps'], _techDraft.reproSteps);
    },
  );

  test(
    'offline Application Support is persisted with the exact identity triple',
    () async {
      final id = await ReportQueueService.enqueueApplicationSupport(
        _supportDraft,
      );
      final row = await rowOf(id);
      expect(row.queueState, ReportQueueState.pending);
      expect(row.fieldJobId, 'job-uuid-1');
      expect(row.supabaseApplicationId, 'app-uuid-1');
      expect(row.bridgeSourceId, 'rosario-imaps-local-0921-a');
      expect(row.payload['support_category'], 'incorrect_information');
    },
  );

  test('a second report for the same task gets its own local id', () async {
    final a = await ReportQueueService.enqueueApplicationSupport(_supportDraft);
    final b = await ReportQueueService.enqueueApplicationSupport(_supportDraft);
    expect(a, isNot(b));
    expect((await ReportQueueService.allRowsOnDevice()).length, 2);
  });

  test('persisted pending survives an app restart', () async {
    final id = await ReportQueueService.enqueueTechnicalIssue(_techDraft);
    // Re-open the same file with no in-memory state: a cold start.
    DBHelper.useDatabaseForTesting(null);
    await db.close();
    db = await databaseFactoryFfi.openDatabase('${dir.path}/q.db');
    DBHelper.useDatabaseForTesting(db);
    expect((await rowOf(id)).queueState, ReportQueueState.pending);
  });

  test(
    'confirmed remote success records remote id + reference and never retries',
    () async {
      ReportQueueService.connectivityOverride = () async => true;
      final id = await ReportQueueService.enqueueTechnicalIssue(_techDraft);
      final sent = await rowOf(id);
      expect(sent.queueState, ReportQueueState.sent);
      expect(sent.remoteReportId, 'remote-1');
      expect(sent.referenceCode, 'DR-2026-0001');

      // Re-running the processor must not send it again.
      await ReportQueueService.processPending();
      expect(inserts.length, 1);
      expect((await rowOf(id)).queueState, ReportQueueState.sent);
    },
  );

  test('pre-dispatch connectivity failure is retryable, not unknown', () async {
    ReportQueueService.connectivityOverride = () async => true;
    ReportQueueService.remoteInsertOverride = (_) async =>
        throw Exception('Failed host lookup: lookup host.example');
    final id = await ReportQueueService.enqueueTechnicalIssue(_techDraft);
    final row = await rowOf(id);
    expect(row.queueState, ReportQueueState.failedRetryable);
    expect(row.retryCount, 1);
    expect(row.lastError, contains('No connection'));
    expect(row.lastError, contains('retry automatically'));
    expect(
      ReportQueueService.isNonRetryable(row),
      isFalse,
      reason: 'another attempt may genuinely succeed unchanged',
    );
  });

  test('connection refused before dispatch is auto-retry eligible', () async {
    ReportQueueService.connectivityOverride = () async => true;
    ReportQueueService.remoteInsertOverride = (_) async => throw Exception(
      'ClientException with SocketException: Connection refused',
    );
    final id = await ReportQueueService.enqueueTechnicalIssue(_techDraft);
    final row = await rowOf(id);
    expect(row.queueState, ReportQueueState.failedRetryable);
    expect(ReportQueueService.isNonRetryable(row), isFalse);
    expect(
      (await ReportQueueService.autoRetryableRowsOnDevice()).map((r) => r.id),
      contains(id),
    );
  });

  group('deterministic server rejection: known outcome, never automatic', () {
    const rejections = <String, String>{
      'HTTP 400': 'PostgREST: 400 Bad Request',
      'HTTP 409': 'HTTP 409 Conflict',
      'HTTP 422': 'HTTP 422 Unprocessable Entity',
      'CHECK constraint': 'violates check constraint "dr_report_identity_ck"',
      'PostgREST error': 'PGRST202 error: could not find the function',
      'invalid controlled value': 'invalid input value for support_category',
    };

    rejections.forEach((name, errorText) {
      test('$name is preserved and never auto-retried', () async {
        ReportQueueService.connectivityOverride = () async => true;
        ReportQueueService.remoteInsertOverride = (_) async =>
            throw Exception(errorText);
        final id = await ReportQueueService.enqueueTechnicalIssue(_techDraft);
        final row = await rowOf(id);

        // A known failure, deliberately NOT an unknown outcome.
        expect(row.queueState, ReportQueueState.failedRetryable);
        expect(row.queueState, isNot(ReportQueueState.deliveryUnknown));
        // The inspector's text survives.
        expect(row.payload['summary'], _techDraft.summary);
        expect(row.payload['title'], _techDraft.title);
        expect(row.payload['repro_steps'], _techDraft.reproSteps);
        // Explicitly excluded from automatic retry.
        expect(ReportQueueService.isNonRetryable(row), isTrue);
        expect(
          (await ReportQueueService.autoRetryableRowsOnDevice()).map((r) => r.id),
          isNot(contains(id)),
        );
      });
    });

    test('reconnect processing skips it and never resubmits', () async {
      ReportQueueService.connectivityOverride = () async => true;
      ReportQueueService.remoteInsertOverride = (_) async =>
          throw Exception('PostgREST: 400 dr_report_identity_ck');
      final id = await ReportQueueService.enqueueTechnicalIssue(_techDraft);
      final attemptsAfterFirst = (await rowOf(id)).retryCount;

      // Every later reconnect / cold start must be a no-op.
      for (var i = 0; i < 3; i++) {
        await ReportQueueService.processPending();
      }
      final row = await rowOf(id);
      expect(
        row.retryCount,
        attemptsAfterFirst,
        reason:
            'a deterministic rejection must not be resubmitted on reconnect',
      );
      expect(row.payload['summary'], _techDraft.summary);
    });
  });

  test('a deterministic rejection is never confused with delivery_unknown', () {
    expect(
      ReportQueueService.classifySendError(
        Exception('PostgREST: 400 dr_report_identity_ck'),
      ),
      isA<DeterministicRejection>(),
    );
    expect(
      ReportQueueService.classifySendError(
        Exception('ConnectionTimeoutException'),
      ),
      isA<AmbiguousSendOutcome>(),
    );
  });

  test('a deterministic rejection is never called "Retry needed"', () async {
    ReportQueueService.connectivityOverride = () async => true;
    ReportQueueService.remoteInsertOverride = (_) async =>
        throw Exception('HTTP 422');
    final id = await ReportQueueService.enqueueTechnicalIssue(_techDraft);
    final rejected = await rowOf(id);
    expect(ReportQueueService.labelFor(rejected), 'Could not be filed');
    expect(
      ReportQueueService.labelFor(rejected),
      isNot(contains('retry automatically')),
    );

    // A genuinely transient failure keeps the retry wording.
    ReportQueueService.remoteInsertOverride = (_) async =>
        throw Exception('Failed host lookup');
    final id2 = await ReportQueueService.enqueueTechnicalIssue(_techDraft);
    expect(ReportQueueService.labelFor(await rowOf(id2)), 'Retry needed');
  });

  test('auth/RLS rejection is not retried automatically', () async {
    ReportQueueService.connectivityOverride = () async => true;
    ReportQueueService.remoteInsertOverride = (_) async =>
        throw Exception('new row violates row-level security policy');
    final id = await ReportQueueService.enqueueTechnicalIssue(_techDraft);
    expect((await rowOf(id)).queueState, ReportQueueState.failedRetryable);
    expect(ReportQueueService.isNonRetryable(await rowOf(id)), isTrue);

    final before = (await rowOf(id)).retryCount;
    await ReportQueueService.processPending();
    expect(
      (await rowOf(id)).retryCount,
      before,
      reason: 'a deterministic auth rejection must not loop',
    );
  });

  test('a timeout is ambiguous and becomes delivery_unknown', () async {
    ReportQueueService.connectivityOverride = () async => true;
    ReportQueueService.remoteInsertOverride = (_) async =>
        throw Exception('ConnectionTimeoutException after 30s');
    final id = await ReportQueueService.enqueueTechnicalIssue(_techDraft);
    expect((await rowOf(id)).queueState, ReportQueueState.deliveryUnknown);
  });

  test(
    'an unrecognised transport error is ambiguous, never auto-retried',
    () async {
      ReportQueueService.connectivityOverride = () async => true;
      ReportQueueService.remoteInsertOverride = (_) async =>
          throw Exception('some novel transport failure we cannot parse');
      final id = await ReportQueueService.enqueueTechnicalIssue(_techDraft);
      expect((await rowOf(id)).queueState, ReportQueueState.deliveryUnknown);
      await ReportQueueService.processPending();
      expect((await rowOf(id)).queueState, ReportQueueState.deliveryUnknown);
    },
  );

  test('broad "connection" wording is not enough to claim a safe retry', () {
    // Guards against future string-matching widening turning an ambiguous
    // outcome into an automatic retry.
    expect(
      ReportQueueService.classifySendError(Exception('connection lost')),
      isA<AmbiguousSendOutcome>(),
    );
    expect(
      ReportQueueService.classifySendError(Exception('connection timed out')),
      isA<AmbiguousSendOutcome>(),
    );
    expect(
      ReportQueueService.classifySendError(Exception('connection closed')),
      isA<AmbiguousSendOutcome>(),
      reason: 'a closed socket is not proof the request never left the device',
    );
    expect(
      ReportQueueService.classifySendError(Exception('SocketException')),
      isA<TransientSendFailure>(),
    );
    expect(
      ReportQueueService.classifySendError(Exception('jwt expired')),
      isA<AuthOrRlsRejection>(),
    );
    expect(
      ReportQueueService.classifySendError(Exception('failed host lookup')),
      isA<TransientSendFailure>(),
    );
    expect(
      ReportQueueService.classifySendError(Exception('Connection refused')),
      isA<TransientSendFailure>(),
    );
  });

  group('every failure keeps the report text', () {
    const failures = <String, String>{
      'pre-dispatch': 'Failed host lookup',
      'connection refused': 'Connection refused',
      'timeout': 'ConnectionTimeoutException',
      'auth/RLS': 'new row violates row-level security policy',
      'HTTP 400': 'PostgREST: 400 Bad Request',
      'HTTP 422': 'HTTP 422 Unprocessable Entity',
      'CHECK constraint': 'violates check constraint "dr_report_identity_ck"',
      'unclassifiable': 'something we have never seen before',
    };

    failures.forEach((name, errorText) {
      test('$name retains the full report', () async {
        ReportQueueService.connectivityOverride = () async => true;
        ReportQueueService.remoteInsertOverride = (_) async =>
            throw Exception(errorText);
        final id = await ReportQueueService.enqueueTechnicalIssue(_techDraft);
        final row = await rowOf(id);
        expect(row.id, id);
        expect(row.payload['title'], _techDraft.title);
        expect(row.payload['summary'], _techDraft.summary);
        expect(row.payload['module'], _techDraft.module);
        expect(row.payload['repro_steps'], _techDraft.reproSteps);
        expect(row.payload['blocks_field_work'], _techDraft.blocksFieldWork);
      });
    });
  });

  test('a recovered persisted sending row becomes delivery_unknown', () async {
    final id = await ReportQueueService.enqueueTechnicalIssue(_techDraft);
    // Simulate a process killed mid-request.
    await db.update(
      'local_report_queue',
      {'queue_state': 'sending'},
      where: 'id = ?',
      whereArgs: [id],
    );
    ReportQueueService.connectivityOverride = () async => true;
    await ReportQueueService.recoverInterruptedSends();
    final row = await rowOf(id);
    expect(row.queueState, ReportQueueState.deliveryUnknown);

    // And the processor must not resurrect it.
    await ReportQueueService.processPending();
    expect(inserts, isEmpty);
    expect((await rowOf(id)).queueState, ReportQueueState.deliveryUnknown);
  });

  test(
    'delivery_unknown survives automatic processing and needs a manual retry',
    () async {
      ReportQueueService.connectivityOverride = () async => true;
      ReportQueueService.remoteInsertOverride = (_) async =>
          throw Exception('ConnectionTimeoutException');
      final id = await ReportQueueService.enqueueTechnicalIssue(_techDraft);
      expect((await rowOf(id)).queueState, ReportQueueState.deliveryUnknown);

      ReportQueueService.remoteInsertOverride = (payload) async {
        inserts.add(payload);
        return {'id': 'remote-x', 'reference_code': 'DR-2026-9999'};
      };
      await ReportQueueService.processPending();
      expect(inserts, isEmpty, reason: 'never automatic');

      // An explicit inspector-driven retry does send.
      await ReportQueueService.retryManually(id);
      expect(inserts.length, 1);
      expect((await rowOf(id)).queueState, ReportQueueState.sent);
    },
  );

  group('online submission persists locally BEFORE any remote call', () {
    // Direct proof: at the exact moment the remote insert is invoked, the typed
    // report is already readable in local_report_queue.
    test('Technical Issue is durable before the remote call happens', () async {
      ReportQueueService.connectivityOverride = () async => true;
      final persistedAtDispatch = <Map<String, dynamic>>[];

      ReportQueueService.remoteInsertOverride = (payload) async {
        final rows = await (await DBHelper.database).query(
          'local_report_queue',
        );
        persistedAtDispatch.addAll(rows);
        return {'id': 'remote-ti', 'reference_code': 'DR-2026-0001'};
      };

      final id = await ReportQueueService.enqueueTechnicalIssue(_techDraft);
      expect(
        persistedAtDispatch,
        hasLength(1),
        reason: 'the report must be readable locally before dispatch',
      );
      expect(persistedAtDispatch.single['id'], id);
      expect(persistedAtDispatch.single['queue_state'],
          anyOf('pending', 'sending'),
          reason: 'already durable and dispatched, never absent');
      expect(
        persistedAtDispatch.single['payload'],
        contains(_techDraft.summary),
      );

      final row = await rowOf(id);
      expect(row.queueState, ReportQueueState.sent);
      expect(row.remoteReportId, 'remote-ti');
      expect(row.referenceCode, 'DR-2026-0001');
    });

    test(
      'Application Support is durable before the remote call happens',
      () async {
        ReportQueueService.connectivityOverride = () async => true;
        final persistedAtDispatch = <Map<String, dynamic>>[];

        ReportQueueService.remoteInsertOverride = (payload) async {
          final rows = await (await DBHelper.database).query(
            'local_report_queue',
          );
          persistedAtDispatch.addAll(rows);
          return {'id': 'remote-as', 'reference_code': 'DR-2026-0002'};
        };

        final id = await ReportQueueService.enqueueApplicationSupport(
          _supportDraft,
        );
        expect(persistedAtDispatch, hasLength(1));
        expect(persistedAtDispatch.single['id'], id);
        expect(persistedAtDispatch.single['field_job_id'], 'job-uuid-1');
        expect(
          persistedAtDispatch.single['supabase_application_id'],
          'app-uuid-1',
        );
        expect(
          persistedAtDispatch.single['bridge_source_id'],
          'rosario-imaps-local-0921-a',
        );

        final row = await rowOf(id);
        expect(row.queueState, ReportQueueState.sent);
        expect(row.remoteReportId, 'remote-as');
        expect(row.referenceCode, 'DR-2026-0002');
      },
    );
  });

  group('raw exceptions never reach the inspector', () {
    const rawSql =
        'DatabaseException(SqliteException(1)): while compiling: '
        'ALTER TABLE local_jobs ADD COLUMN supabase_application_id TEXT '
        '(code 1)';
    const rawPostgrest =
        'PostgrestException(code: 42501, message: new row '
        'violates row-level security policy)';
    const rawSocket = 'SocketException: Connection refused (OS Error: 111)';

    test('a SQLite failure becomes a concise, non-technical sentence', () {
      final message = ReportQueueService.userFacingMessage(
        Exception(rawSql),
        reportType: 'Technical Issue',
      );
      expect(message, isNot(contains('ALTER TABLE')));
      expect(message, isNot(contains('SqliteException')));
      expect(message, isNot(contains('code 1')));
      expect(message, isNot(contains('DatabaseException')));
      expect(message, contains('could not save your report'));
      expect(message, contains('Nothing was sent'));
    });

    test('an RLS failure stays meaningful without leaking driver text', () {
      final message = ReportQueueService.userFacingMessage(
        AuthOrRlsRejection('You are not allowed to file this report.'),
        reportType: 'Application Support',
      );
      expect(message, contains('Could not be filed'));
      expect(message, isNot(contains('42501')));
      expect(message, isNot(contains('row-level security')));
    });

    test('a raw PostgREST/Socket string is never echoed verbatim', () {
      for (final raw in [rawPostgrest, rawSocket]) {
        final message = ReportQueueService.userFacingMessage(
          Exception(raw),
          reportType: 'Technical Issue',
        );
        expect(message, isNot(contains(raw)));
        expect(message, isNot(contains('Exception')));
        expect(message.length, lessThan(200));
      }
    });

    test('the meaningful categories are preserved', () {
      expect(
        ReportQueueService.userFacingMessage(
          TransientSendFailure('x'),
          reportType: 'Technical Issue',
        ),
        contains('Saved on this device'),
      );
      expect(
        ReportQueueService.userFacingMessage(
          DeterministicRejection('x'),
          reportType: 'Technical Issue',
        ),
        contains('Could not be filed'),
      );
      expect(
        ReportQueueService.userFacingMessage(
          const AmbiguousSendOutcome(),
          reportType: 'Technical Issue',
        ),
        contains('uncertain'),
      );
      expect(
        ReportQueueService.userFacingMessage(
          ReportSubmissionException('Choose a support category.'),
          reportType: 'Application Support',
        ),
        'Choose a support category.',
      );
    });
  });

  test('a double tap cannot create two rows or two sends', () async {
    ReportQueueService.connectivityOverride = () async => true;
    Future<String> attempt() async {
      try {
        return await ReportQueueService.enqueueTechnicalIssue(_techDraft);
      } catch (e) {
        return 'rejected: $e';
      }
    }

    final results = await Future.wait([attempt(), attempt()]);
    expect(results.length, 2);
    expect(
      (await ReportQueueService.allRowsOnDevice()).length,
      1,
      reason: 'concurrent submits must not both persist a row',
    );
    expect(
      results.where((r) => r.startsWith('rejected:')).length,
      1,
      reason: 'the second tap is refused, not queued behind the first',
    );
    expect(inserts.length, 1, reason: 'exactly one remote insert');
  });

  test('one row is never in two simultaneous sends', () async {
    ReportQueueService.connectivityOverride = () async => true;
    var inFlight = 0;
    var maxInFlight = 0;
    ReportQueueService.remoteInsertOverride = (_) async {
      inFlight++;
      maxInFlight = maxInFlight > inFlight ? maxInFlight : inFlight;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      inFlight--;
      return {'id': 'remote-z', 'reference_code': 'DR-2026-0001'};
    };
    final id = await ReportQueueService.enqueueTechnicalIssue(_techDraft);
    final row = await rowOf(id);
    await Future.wait([
      ReportQueueService.sendOnce(row),
      ReportQueueService.sendOnce(row),
    ]);
    expect(maxInFlight, 1);
  });

  test('the inspection SyncOutbox table is never touched', () async {
    // pending_actions has no report column and the report queue never writes
    // to it. A Technical Issue needs no job, which is the structural proof the
    // two transports cannot share a table.
    final pending = (await db.rawQuery(
      'PRAGMA table_info(pending_actions)',
    )).map((r) => r['name'] as String).toList();
    expect(
      pending,
      isEmpty,
      reason: 'fixture DB has no outbox table; reports must never require one',
    );

    await ReportQueueService.enqueueTechnicalIssue(_techDraft);
    expect((await ReportQueueService.allRowsOnDevice()).length, 1);
  });
}
