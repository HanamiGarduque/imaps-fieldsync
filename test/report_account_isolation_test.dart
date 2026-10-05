// Cross-account isolation for the local report queue (SQLite v16).
//
// The defect this pins: `local_report_queue` stored no author, so a single
// `allRows()` read returned every report on the device and My Reports rendered
// provisional cards — report type, category and message text — that a DIFFERENT
// inspector account had typed on the same physical device. A second defect rode
// along: the remote `inspector_id` was stamped from the live session at send
// time, so a report written by inspector A could be sent while inspector B was
// signed in and become attributed to B.
//
// Every test below runs against the real schema and the real queue service.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:imaps_fieldsync/core/models/report_models.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/report_queue_schema.dart';
import 'package:imaps_fieldsync/core/services/report_submission_service.dart';
import 'package:imaps_fieldsync/modules/profile_settings/services/diagnostics_service.dart';

/// The two inspectors on one shared device.
const inspectorA = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
const inspectorB = 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb';

const _techDraft = TechnicalIssueDraft(
  title: 'Sync button does nothing',
  module: 'Home',
  summary: 'Tapping Sync twice produced no new state either time.',
);

ApplicationSupportDraft _supportDraft() => const ApplicationSupportDraft(
  fieldJobId: 'job-uuid-1',
  supabaseApplicationId: 'app-uuid-1',
  bridgeSourceId: 'rosario-imaps-local-0921-a',
  supportCategory: 'incorrect_information',
  description: 'The listed land use does not match the signage on site.',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory dir;
  late Database db;
  late List<Map<String, dynamic>> inserts;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fieldsync-iso-');
    db = await databaseFactoryFfi.openDatabase(
      '${dir.path}/iso.db',
      options: OpenDatabaseOptions(
        version: 16,
        onCreate: (d, _) async {
          await ReportQueueSchema.createTable(d);
        },
      ),
    );
    DBHelper.useDatabaseForTesting(db);
    inserts = <Map<String, dynamic>>[];
    ReportQueueService.resetTestHooks();
    ReportQueueService.inspectorIdOverride = () => inspectorA;
    ReportQueueService.connectivityOverride = () async => false;
    ReportQueueService.remoteInsertOverride = (payload) async {
      inserts.add(payload);
      return {
        'id': 'remote-${inserts.length}',
        'reference_code': 'DR-2026-9${inserts.length.toString().padLeft(3, '0')}',
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

  /// Switches which account the device is signed in as.
  void signInAs(String? uid) => ReportQueueService.inspectorIdOverride = () => uid;

  Future<LocalReportRow> rowOf(String id) async =>
      (await ReportQueueService.rowById(id))!;

  /// Writes a pre-v16 shaped row: no `inspector_id` key at all, exactly what a
  /// device that never ran the v16 ALTER already contains.
  Future<String> insertLegacyUnownedRow({
    required String title,
    required String summary,
    String reportType = 'technical_issue',
  }) async {
    final id = 'rq-legacy-$title';
    await db.insert('local_report_queue', {
      'id': id,
      'report_type': reportType,
      'payload': '{"report_type":"$reportType","title":"$title",'
          '"module":"Home","summary":"$summary"}',
      'queue_state': 'pending',
      'retry_count': 0,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      // deliberately NO inspector_id: the legacy shape
    });
    return id;
  }

  group('enqueue records an authoritative owner', () {
    test('Technical Issue is stored with the authenticated inspector', () async {
      signInAs(inspectorA);
      final id = await ReportQueueService.enqueueTechnicalIssue(_techDraft);

      final row = await rowOf(id);
      expect(row.inspectorId, inspectorA);
      expect(await db.query(
        'local_report_queue',
        columns: ['inspector_id'],
        where: 'id = ?',
        whereArgs: [id],
      ), hasLength(1));
    });

    test('Application Support is stored with the authenticated inspector', () async {
      signInAs(inspectorA);
      final id = await ReportQueueService.enqueueApplicationSupport(_supportDraft());

      final row = await rowOf(id);
      expect(row.inspectorId, inspectorA);
    });

    test('no authenticated inspector -> refused, and no row is created', () async {
      signInAs(null);

      await expectLater(
        ReportQueueService.enqueueTechnicalIssue(_techDraft),
        throwsA(isA<ReportSubmissionException>()),
      );
      await expectLater(
        ReportQueueService.enqueueApplicationSupport(_supportDraft()),
        throwsA(isA<ReportSubmissionException>()),
      );

      // Nothing was persisted: no unattributable row may ever be created.
      expect(await ReportQueueService.allRowsOnDevice(), isEmpty);
    });

    test('empty inspector id is treated as unauthenticated', () async {
      signInAs('');
      await expectLater(
        ReportQueueService.enqueueTechnicalIssue(_techDraft),
        throwsA(isA<ReportSubmissionException>()),
      );
      expect(await ReportQueueService.allRowsOnDevice(), isEmpty);
    });
  });

  group('read scoping — My Reports', () {
    test("A's provisional reports are visible to A", () async {
      signInAs(inspectorA);
      await ReportQueueService.enqueueTechnicalIssue(_techDraft);
      await ReportQueueService.enqueueApplicationSupport(_supportDraft());

      final mine = await ReportQueueService.allRowsForInspector(inspectorA);
      expect(mine, hasLength(2));
      expect(
        mine.map((r) => r.reportType),
        containsAll(<ReportType>[
          ReportType.technicalIssue,
          ReportType.applicationSupport,
        ]),
      );
    });

    test("A's provisional reports are invisible to B on the same device", () async {
      signInAs(inspectorA);
      await ReportQueueService.enqueueTechnicalIssue(_techDraft);
      await ReportQueueService.enqueueApplicationSupport(_supportDraft());

      signInAs(inspectorB);
      expect(await ReportQueueService.allRowsForInspector(inspectorB), isEmpty);
      // The UI default resolves the signed-in user, so it must also be empty.
      expect(await ReportQueueService.myRows(), isEmpty);
    });

    test('A and B each see only their own report text', () async {
      signInAs(inspectorA);
      await ReportQueueService.enqueueTechnicalIssue(_techDraft);
      signInAs(inspectorB);
      final bDraft = TechnicalIssueDraft(
        title: 'B only title',
        module: 'My Tasks',
        summary: 'B only summary text.',
      );
      await ReportQueueService.enqueueTechnicalIssue(bDraft);

      final bRows = await ReportQueueService.allRowsForInspector(inspectorB);
      expect(bRows, hasLength(1));
      expect(bRows.single.payload['summary'], 'B only summary text.');

      signInAs(inspectorA);
      final aRows = await ReportQueueService.allRowsForInspector(inspectorA);
      expect(aRows, hasLength(1));
      expect(aRows.single.payload['summary'], isNot(contains('B only')));
    });

    test('switching back to A restores A rows and hides B rows', () async {
      signInAs(inspectorA);
      await ReportQueueService.enqueueTechnicalIssue(_techDraft);
      signInAs(inspectorB);
      await ReportQueueService.enqueueTechnicalIssue(
        const TechnicalIssueDraft(
          title: 'B report',
          module: 'My Tasks',
          summary: 'B summary.',
        ),
      );

      expect(await ReportQueueService.myRows(), hasLength(1));

      signInAs(inspectorA);
      final back = await ReportQueueService.myRows();
      expect(back, hasLength(1));
      expect(back.single.payload['summary'], contains('Tapping Sync twice'));
    });

    test('with no authenticated user, nobody sees anything', () async {
      signInAs(inspectorA);
      await ReportQueueService.enqueueTechnicalIssue(_techDraft);

      signInAs(null);
      expect(await ReportQueueService.myRows(), isEmpty);
    });
  });

  group('legacy NULL-owner rows are owned by nobody', () {
    test('hidden from A', () async {
      await insertLegacyUnownedRow(title: 'Legacy A-ish', summary: 'Old text.');
      signInAs(inspectorA);
      expect(await ReportQueueService.myRows(), isEmpty);
    });

    test('hidden from B', () async {
      await insertLegacyUnownedRow(title: 'Legacy B-ish', summary: 'Old text.');
      signInAs(inspectorB);
      expect(await ReportQueueService.myRows(), isEmpty);
    });

    test('still physically stored, never deleted', () async {
      final id = await insertLegacyUnownedRow(
        title: 'Legacy',
        summary: 'Old text.',
      );
      signInAs(inspectorA);

      expect(await ReportQueueService.myRows(), isEmpty);
      // Preserved on disk, owner unknown, awaiting an explicit recovery pass.
      final row = await rowOf(id);
      expect(row.inspectorId, isNull);
      expect(row.payload['summary'], 'Old text.');
    });

    test('excluded from the retry set for every inspector', () async {
      final id = await insertLegacyUnownedRow(
        title: 'Legacy',
        summary: 'Old text.',
      );
      signInAs(inspectorA);
      ReportQueueService.connectivityOverride = () async => true;

      await ReportQueueService.processPending();

      expect(inserts, isEmpty, reason: 'a legacy row must never be sent');
      final row = await rowOf(id);
      expect(row.queueState, ReportQueueState.pending);
    });

    test('excluded from an explicit per-inspector retry query', () async {
      await insertLegacyUnownedRow(title: 'Legacy', summary: 'Old text.');
      expect(
        await ReportQueueService.retryableRowsForInspector(inspectorA),
        isEmpty,
      );
      expect(
        await ReportQueueService.retryableRowsForInspector(inspectorB),
        isEmpty,
      );
      // ...and is not silently absent from the device either: it is visible to
      // the maintenance read, which is how a future recovery pass would find it.
      expect(await ReportQueueService.allRowsOnDevice(), hasLength(1));
    });

    test('manual retry of a legacy row is refused', () async {
      final id = await insertLegacyUnownedRow(
        title: 'Legacy',
        summary: 'Old text.',
      );
      signInAs(inspectorA);
      ReportQueueService.connectivityOverride = () async => true;

      await ReportQueueService.retryManually(id);

      expect(inserts, isEmpty);
    });
  });

  group('retry is scoped to the signed-in inspector', () {
    test("A's pending rows are retry-eligible while A is signed in", () async {
      signInAs(inspectorA);
      final id = await ReportQueueService.enqueueTechnicalIssue(_techDraft);
      ReportQueueService.connectivityOverride = () async => true;

      final eligible = await ReportQueueService.retryableRowsForInspector(inspectorA);
      expect(eligible.map((r) => r.id), contains(id));
    });

    test("A's pending rows are NOT retried while B is signed in", () async {
      signInAs(inspectorA);
      await ReportQueueService.enqueueTechnicalIssue(_techDraft);
      ReportQueueService.connectivityOverride = () async => true;

      signInAs(inspectorB);
      await ReportQueueService.processPending();

      expect(inserts, isEmpty, reason: 'B must not send A report');
      expect(
        await ReportQueueService.retryableRowsForInspector(inspectorB),
        isEmpty,
      );
    });

    test('no authenticated user -> nothing is retried', () async {
      signInAs(inspectorA);
      await ReportQueueService.enqueueTechnicalIssue(_techDraft);
      ReportQueueService.connectivityOverride = () async => true;

      signInAs(null);
      await ReportQueueService.processPending();

      expect(inserts, isEmpty);
    });

    test("B's manual retry of A's row id is refused", () async {
      signInAs(inspectorA);
      final id = await ReportQueueService.enqueueTechnicalIssue(_techDraft);
      ReportQueueService.connectivityOverride = () async => true;

      signInAs(inspectorB);
      await ReportQueueService.retryManually(id);

      expect(inserts, isEmpty);
      final row = await rowOf(id);
      expect(row.queueState, ReportQueueState.pending);
    });

    test("A's blocked row is untouched and sends once A returns", () async {
      signInAs(inspectorA);
      final id = await ReportQueueService.enqueueTechnicalIssue(_techDraft);
      ReportQueueService.connectivityOverride = () async => true;

      // B is briefly signed in: the row must survive untouched, not be
      // consumed, failed or deleted.
      signInAs(inspectorB);
      await ReportQueueService.processPending();
      expect(inserts, isEmpty);
      expect((await rowOf(id)).queueState, ReportQueueState.pending);

      signInAs(inspectorA);
      await ReportQueueService.processPending();

      expect(inserts, hasLength(1));
      expect((await rowOf(id)).queueState, ReportQueueState.sent);
    });

    test('logout/login does not destroy another inspector queued rows', () async {
      signInAs(inspectorA);
      final id = await ReportQueueService.enqueueTechnicalIssue(_techDraft);

      // "Logout A" then "login B": nothing about the queue is wiped.
      signInAs(null);
      signInAs(inspectorB);

      final row = await rowOf(id);
      expect(row.inspectorId, inspectorA);
      expect(row.payload['summary'], contains('Tapping Sync twice'));
    });
  });

  group('remote insert ownership guard', () {
    test('remote inspector_id is the ROW owner, not the live session', () async {
      signInAs(inspectorA);
      final id = await ReportQueueService.enqueueTechnicalIssue(_techDraft);
      ReportQueueService.connectivityOverride = () async => true;
      await ReportQueueService.processPending();

      expect(inserts, hasLength(1));
      expect(inserts.single['inspector_id'], inspectorA);
      // And the stored row still agrees.
      expect((await rowOf(id)).inspectorId, inspectorA);
    });

    test(
      'SECURITY: A pending report can never be created remotely under B',
      () async {
        signInAs(inspectorA);
        await ReportQueueService.enqueueTechnicalIssue(_techDraft);
        ReportQueueService.connectivityOverride = () async => true;

        // Network returns while B is signed in.
        signInAs(inspectorB);
        await ReportQueueService.processPending();

        // BLOCKED BEFORE ANY REMOTE WRITE.
        expect(inserts, isEmpty);
      },
    );

    test(
      'SECURITY: even a direct sendOnce of a foreign row is refused',
      () async {
        signInAs(inspectorA);
        final id = await ReportQueueService.enqueueTechnicalIssue(_techDraft);
        ReportQueueService.connectivityOverride = () async => true;

        signInAs(inspectorB);
        final row = await rowOf(id);
        await ReportQueueService.sendOnce(row);

        expect(inserts, isEmpty);
        expect((await rowOf(id)).queueState, ReportQueueState.pending);
      },
    );

    test(
      'SECURITY: sending with no authenticated user is refused',
      () async {
        signInAs(inspectorA);
        final id = await ReportQueueService.enqueueTechnicalIssue(_techDraft);
        ReportQueueService.connectivityOverride = () async => true;

        signInAs(null);
        final row = await rowOf(id);
        await ReportQueueService.sendOnce(row);

        expect(inserts, isEmpty);
      },
    );

    test('the send succeeds only when auth matches the row owner', () async {
      signInAs(inspectorB);
      final id = await ReportQueueService.enqueueApplicationSupport(_supportDraft());
      ReportQueueService.connectivityOverride = () async => true;

      await ReportQueueService.processPending();

      expect(inserts, hasLength(1));
      expect(inserts.single['inspector_id'], inspectorB);
      expect(inserts.single['support_category'], 'incorrect_information');
      expect((await rowOf(id)).queueState, ReportQueueState.sent);
    });

    test('remoteInsertFor reports a NULL owner as NULL, never the session', () {
      final orphan = LocalReportRow(
        id: 'rq-x',
        reportType: ReportType.technicalIssue,
        payload: _techDraft.toJson(),
        queueState: ReportQueueState.pending,
        retryCount: 0,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      signInAs(inspectorA);

      expect(ReportQueueService.remoteInsertFor(orphan)['inspector_id'], isNull);
    });
  });

  group('reconciliation and unrelated behavior', () {
    test('a confirmed row is not double-listed against its remote twin', () async {
      signInAs(inspectorA);
      final id = await ReportQueueService.enqueueTechnicalIssue(_techDraft);
      ReportQueueService.connectivityOverride = () async => true;
      await ReportQueueService.processPending();

      final row = await rowOf(id);
      expect(row.queueState, ReportQueueState.sent);
      expect(row.remoteReportId, 'remote-1');

      // The local row is `sent` and the server has that exact remote id, so the
      // history screen folds it into the single server-rendered entry.
      final remote = DiagnosticReport(
        id: row.remoteReportId!,
        referenceCode: row.referenceCode!,
        title: _techDraft.title,
        summary: _techDraft.summary,
        status: 'submitted',
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      );
      final unconfirmed =
          DiagnosticsService.unconfirmedLocalRows([row], [remote]);

      expect(unconfirmed, isEmpty);
    });

    test('an unconfirmed row stays visible to its owner', () {
      final pending = LocalReportRow(
        id: 'rq-p',
        reportType: ReportType.technicalIssue,
        payload: _techDraft.toJson(),
        queueState: ReportQueueState.pending,
        retryCount: 0,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        inspectorId: inspectorA,
      );

      expect(
        DiagnosticsService.unconfirmedLocalRows([pending], const []),
        hasLength(1),
      );
    });

    test('ownership survives the model round-trip through SQLite', () async {
      signInAs(inspectorB);
      final id = await ReportQueueService.enqueueApplicationSupport(_supportDraft());
      final raw = await db.query(
        'local_report_queue',
        where: 'id = ?',
        whereArgs: [id],
      );

      expect(raw.single['inspector_id'], inspectorB);
      // copyWith must not orphan a row.
      final row = await rowOf(id);
      expect(row.copyWith(queueState: ReportQueueState.failedRetryable).inspectorId,
          inspectorB);
    });

    test('the v16 owner index exists for the ownership read path', () async {
      await db.execute(ReportQueueSchema.tableDdl);
      await ReportQueueSchema.applyV16(db);
      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='local_report_queue'",
      );
      expect(
        indexes.map((r) => r['name']),
        contains('idx_local_report_queue_inspector'),
      );
    });

    test('applying v16 to an already-v16 table is a no-op', () async {
      await ReportQueueSchema.applyV16(db);
      await ReportQueueSchema.applyV16(db);

      final columns = await ReportQueueSchema.columnsOf(db, 'local_report_queue');
      expect(columns.where((c) => c == 'inspector_id'), hasLength(1));
    });
  });
}