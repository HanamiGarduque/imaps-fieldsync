import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/models/report_models.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/report_queue_schema.dart';
import 'package:imaps_fieldsync/core/services/report_submission_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _technical = <String, dynamic>{
  'title': 'Screen did not respond',
  'module': 'My Tasks',
  'summary': 'The task list stopped responding.',
};
const _application = <String, dynamic>{
  'field_job_id': 'exact-job',
  'supabase_application_id': 'exact-application',
  'bridge_source_id': 'exact-source',
  'support_category': 'clarification_request',
  'summary': 'Please confirm the land use.',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  var remoteCalls = 0;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await ReportQueueSchema.createTable(db);
    DBHelper.useDatabaseForTesting(db);
    ReportQueueService.resetTestHooks();
    ReportQueueService.inspectorIdOverride = () => 'inspector';
    ReportQueueService.connectivityOverride = () async => false;
    remoteCalls = 0;
    ReportQueueService.remoteInsertOverride = (_) async {
      remoteCalls++;
      return {'id': 'remote-$remoteCalls', 'reference_code': 'DR-test'};
    };
  });

  tearDown(() async {
    ReportQueueService.resetTestHooks();
    DBHelper.useDatabaseForTesting(null);
    await db.close();
  });

  Future<String> enqueue(bool technical, Map<String, dynamic> values) =>
      technical
      ? ReportQueueService.enqueueTechnicalIssue(
          TechnicalIssueDraft.fromJson(values),
        )
      : ReportQueueService.enqueueApplicationSupport(
          ApplicationSupportDraft.fromJson(values),
        );

  for (final technical in [true, false]) {
    final base = technical ? _technical : _application;
    final type = technical ? 'Technical Issue' : 'Application Support';
    final required = technical
        ? ['title', 'module', 'summary']
        : [
            'field_job_id',
            'supabase_application_id',
            'bridge_source_id',
            'support_category',
            'summary',
          ];
    for (final field in required) {
      for (final value in [null, '', ' \t\r\n\u00a0 ']) {
        test(
          '$type rejects missing/blank $field (${jsonEncode(value)}) before persistence',
          () async {
            await expectLater(
              enqueue(technical, {...base, field: value}),
              throwsA(isA<ReportSubmissionException>()),
            );
            expect(await ReportQueueService.allRowsOnDevice(), isEmpty);
            expect(remoteCalls, 0);
          },
        );
      }
    }

    // Client resource budgets, not remote schema limits: title 200, narrative
    // 8,000, optional text 4,000 UTF-16 code units. Every field is bounded.
    final bounds = technical
        ? {
            'title': 200,
            'summary': 8000,
            'expected_behavior': 4000,
            'repro_steps': 4000,
          }
        : {'summary': 8000, 'affected_field': 4000, 'requested_change': 4000};
    for (final entry in bounds.entries) {
      test(
        '$type rejects oversized ${entry.key} without modifying content or queue',
        () async {
          for (final length in [entry.value + 1, 1000000]) {
            final pasted = 'x' * length;
            final values = {...base, entry.key: pasted};
            await expectLater(
              enqueue(technical, values),
              throwsA(
                isA<ReportSubmissionException>().having(
                  (e) => e.message,
                  'human-readable error',
                  contains('too long'),
                ),
              ),
            );
            expect(values[entry.key], pasted);
          }
          expect(await ReportQueueService.allRowsOnDevice(), isEmpty);
          expect(remoteCalls, 0);
        },
      );
      test('$type accepts the ${entry.key} boundary', () async {
        final id = await enqueue(technical, {
          ...base,
          entry.key: 'a' * entry.value,
        });
        expect(
          (await ReportQueueService.rowById(id))!.payload[entry.key],
          hasLength(entry.value),
        );
      });
    }

    test(
      '$type trims only outer whitespace; optional blank text is omitted',
      () async {
        final optional = technical ? 'expected_behavior' : 'affected_field';
        final id = await enqueue(technical, {
          ...base,
          'summary': ' \n Unang linya\n\n  Pangalawa\n ',
          optional: ' \t\n ',
        });
        final row = (await ReportQueueService.rowById(id))!;
        expect(row.payload['summary'], 'Unang linya\n\n  Pangalawa');
        expect(row.payload.containsKey(optional), isFalse);
        if (!technical) {
          expect(row.fieldJobId, _application['field_job_id']);
          expect(
            row.supabaseApplicationId,
            _application['supabase_application_id'],
          );
          expect(row.bridgeSourceId, _application['bridge_source_id']);
        }
      },
    );

    for (final text in [
      'Hindi gumagana ang mapa sa barangay. Niño, José, 戶 🧭 👩🏽‍💻 🇵🇭',
      '''O'Brien said: "It's broken!" https://example.test/a?q='x'&y=2''',
      '<script>alert("hello")</script> {"status":"sent"} DROP TABLE local_jobs; --',
      'Una\n\n\nIkalawa\r\n  Panatilihin ang indent.',
      'Multiline pasted text\n' * 300,
    ]) {
      test(
        '$type treats ordinary Unicode / code-looking / multiline text as data (${text.length})',
        () async {
          ReportQueueService.connectivityOverride = () async => true;
          Map<String, dynamic>? dispatched;
          ReportQueueService.remoteInsertOverride = (payload) async {
            expect(await db.query('local_report_queue'), hasLength(1));
            dispatched = payload;
            return {'id': 'remote', 'reference_code': 'DR-test'};
          };
          final id = await enqueue(technical, {...base, 'summary': text});
          final row = (await ReportQueueService.rowById(id))!;
          expect(row.queueState, ReportQueueState.sent);
          expect(row.payload['summary'], text.trim());
          expect(dispatched!['summary'], text.trim());
        },
      );
    }

    test(
      '$type rejects text that PostgreSQL cannot store, without a raw error',
      () async {
        for (final text in [
          'bad\u0000text',
          'bad\uD800text',
          'bad\uDC00text',
        ]) {
          await expectLater(
            enqueue(technical, {...base, 'summary': text}),
            throwsA(isA<ReportSubmissionException>()),
          );
        }
        expect(await ReportQueueService.allRowsOnDevice(), isEmpty);
      },
    );

    test(
      '$type prevents repeated submit while its remote send is in flight',
      () async {
        ReportQueueService.connectivityOverride = () async => true;
        final dispatch = Completer<void>();
        final response = Completer<Map<String, dynamic>>();
        ReportQueueService.remoteInsertOverride = (_) {
          remoteCalls++;
          if (!dispatch.isCompleted) dispatch.complete();
          return response.future;
        };
        final first = enqueue(technical, base);
        await dispatch.future;
        // Release the transport even if the assertion fails; no dangling test IO.
        try {
          expect(ReportQueueService.hasSubmitInProgress, isTrue);
          await expectLater(
            enqueue(technical, base),
            throwsA(isA<ReportSubmissionException>()),
          );
        } finally {
          response.complete({'id': 'remote', 'reference_code': 'DR-test'});
          await first;
        }
        expect(await ReportQueueService.allRowsOnDevice(), hasLength(1));
        expect(remoteCalls, 1);
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );
  }

  test(
    'controlled module and category values cannot be arbitrary display text',
    () async {
      for (final value in ['invented', ' My Tasks ', 'my tasks']) {
        await expectLater(
          enqueue(true, {..._technical, 'module': value}),
          throwsA(isA<ReportSubmissionException>()),
        );
      }
      for (final value in ['Clarification Needed', 'other ', 'invented']) {
        await expectLater(
          enqueue(false, {..._application, 'support_category': value}),
          throwsA(isA<ReportSubmissionException>()),
        );
      }
      expect(await ReportQueueService.allRowsOnDevice(), isEmpty);
    },
  );
}
