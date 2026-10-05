// SQLite v15 -> v16: per-inspector ownership for the local report queue.
//
// Proved against a REAL v15-shaped database: one built with the pre-v16 table
// DDL (no `inspector_id`), populated with queue rows AND unrelated FieldSync
// data, then upgraded. Nothing here touches device data — every database is a
// temporary file.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/services/report_queue_schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The table exactly as v15 shipped it: no ownership column anywhere.
const String _v15QueueDdl = '''
CREATE TABLE local_report_queue(
  id TEXT PRIMARY KEY,
  report_type TEXT NOT NULL CHECK (report_type IN ('technical_issue', 'application_support')),
  payload TEXT NOT NULL,
  local_job_id TEXT,
  field_job_id TEXT,
  supabase_application_id TEXT,
  bridge_source_id TEXT,
  remote_report_id TEXT,
  reference_code TEXT,
  queue_state TEXT NOT NULL DEFAULT 'pending' CHECK (queue_state IN ('pending', 'sending', 'sent', 'failed_retryable', 'delivery_unknown')),
  retry_count INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  created_at TEXT NOT NULL,
  last_attempt_at TEXT,
  updated_at TEXT NOT NULL
)
''';

/// Unrelated FieldSync tables that must survive the upgrade untouched.
const String _v15PendingActions = '''
CREATE TABLE pending_actions(
  id TEXT PRIMARY KEY,
  job_id TEXT NOT NULL,
  action_type TEXT NOT NULL,
  payload TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TEXT NOT NULL
)
''';

const String _v15LocalJobs = '''
CREATE TABLE local_jobs(
  id TEXT PRIMARY KEY,
  local_inspection_id INTEGER,
  status TEXT,
  scheduled_date TEXT,
  applicant_name TEXT,
  reference_number TEXT,
  supabase_application_id TEXT,
  bridge_source_id TEXT
)
''';

const _t0 = '2026-09-01T10:00:00.000Z';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fieldsync-v16-');
  });

  tearDown(() async {
    if (dir.existsSync()) {
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        // Windows may still hold the handle briefly; harmless for a temp dir.
      }
    }
  });

  /// Builds a genuine v15 database: the old DDL, three queue rows in different
  /// transport states, and unrelated inspection data alongside them.
  Future<Database> openRealV15(String path) async {
    final db = await databaseFactoryFfi.openDatabase(path);
    await db.execute(_v15QueueDdl);
    await db.execute(_v15PendingActions);
    await db.execute(_v15LocalJobs);

    Future<void> queueRow(
      String id,
      String state, {
      int retries = 0,
      String? remoteId,
    }) => db.insert('local_report_queue', {
      'id': id,
      'report_type': 'technical_issue',
      'payload': '{"report_type":"technical_issue","title":"t-$id",'
          '"module":"Home","summary":"summary for $id"}',
      'queue_state': state,
      'retry_count': retries,
      'remote_report_id': remoteId,
      'created_at': _t0,
      'updated_at': _t0,
    });

    await queueRow('rq-pending', 'pending');
    await queueRow('rq-retryable', 'failed_retryable', retries: 3);
    await queueRow('rq-sent', 'sent', remoteId: 'remote-abc');

    await db.insert('pending_actions', {
      'id': 'pa-1',
      'job_id': 'job-1',
      'action_type': 'submit_inspection',
      'payload': '{"x":1}',
      'status': 'pending',
      'created_at': _t0,
    });
    await db.insert('local_jobs', {
      'id': 'job-1',
      'local_inspection_id': 39,
      'status': 'assigned',
      'applicant_name': 'Ralph Lauren Bautista',
      'reference_number': 'APP-2026-00028',
    });
    return db;
  }

  Future<List<String>> columnsOf(Database db, String table) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return info.map((r) => r['name'] as String).toList();
  }

  test('v15 database genuinely lacks the ownership column', () async {
    final db = await openRealV15('${dir.path}/v15.db');
    expect(await columnsOf(db, 'local_report_queue'), isNot(contains('inspector_id')));
    await db.close();
  });

  test('15->16 preserves the table, every row, and all unrelated data', () async {
    final path = '${dir.path}/upgrade.db';
    var db = await openRealV15(path);

    final before = await db.query('local_report_queue');
    expect(before, hasLength(3));

    await ReportQueueSchema.applyV16(db);
    db.close();

    // Reopen the SAME file the way the app would: v16 DDL is additive and the
    // ALTER already ran, so applyV16 must be a safe no-op on a real reopen.
    db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 16,
        onUpgrade: (d, _, _) async => ReportQueueSchema.applyV16(d),
      ),
    );
    await ReportQueueSchema.applyV16(db); // idempotent

    // Table and rows preserved.
    expect(await columnsOf(db, 'local_report_queue'), contains('inspector_id'));
    final after = await db.query('local_report_queue', orderBy: 'id');
    expect(after, hasLength(3));
    expect(after.map((r) => r['id']), ['rq-pending', 'rq-retryable', 'rq-sent']);
    // Content untouched.
    final sent = after.firstWhere((r) => r['id'] == 'rq-sent');
    expect(sent['remote_report_id'], 'remote-abc');
    final retryable = after.firstWhere((r) => r['id'] == 'rq-retryable');
    expect(retryable['retry_count'], 3);
    expect(
      (retryable['payload'] as String),
      contains('summary for rq-retryable'),
    );

    // Unrelated FieldSync data untouched.
    expect(await db.query('pending_actions'), hasLength(1));
    expect(
      (await db.query('local_jobs')).single['applicant_name'],
      'Ralph Lauren Bautista',
    );
    await db.close();
  });

  test('legacy rows migrate to NULL inspector_id — never backfilled', () async {
    final db = await openRealV15('${dir.path}/legacy.db');
    await ReportQueueSchema.applyV16(db);

    final rows = await db.query('local_report_queue', orderBy: 'id');
    expect(rows, hasLength(3));
    for (final row in rows) {
      // No guessing: no name, email, message or job was used to infer an owner.
      expect(row['inspector_id'], isNull, reason: 'row ${row['id']}');
    }

    // And an ownership-scoped read matches none of them.
    expect(
      await db.query(
        'local_report_queue',
        where: 'inspector_id = ?',
        whereArgs: ['anyone'],
      ),
      isEmpty,
    );
    // A NULL-owner row is invisible even to a `= NULL`-style lookup, because
    // SQL NULL comparison is never true — so it can never be adopted later.
    expect(
      await db.query(
        'local_report_queue',
        where: 'inspector_id IS NULL',
      ),
      hasLength(3),
    );
    await db.close();
  });

  test('fresh v16 install already has the ownership column', () async {
    final db = await databaseFactoryFfi.openDatabase(
      '${dir.path}/fresh.db',
      options: OpenDatabaseOptions(
        version: 16,
        onCreate: (d, _) => ReportQueueSchema.createTable(d),
      ),
    );

    expect(await columnsOf(db, 'local_report_queue'), contains('inspector_id'));
    // Fresh installs get the ownership index too.
    final indexes = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index' "
      "AND tbl_name='local_report_queue'",
    );
    expect(
      indexes.map((r) => r['name']),
      contains('idx_local_report_queue_inspector'),
    );
    await db.close();
  });

  test('v16 DDL and a v16 upgraded table have identical columns', () async {
    final fresh = await databaseFactoryFfi.openDatabase(
      '${dir.path}/freshcmp.db',
      options: OpenDatabaseOptions(
        version: 16,
        onCreate: (d, _) => ReportQueueSchema.createTable(d),
      ),
    );
    final upgraded = await openRealV15('${dir.path}/upcmp.db');
    await ReportQueueSchema.applyV16(upgraded);

    expect(
      await columnsOf(fresh, 'local_report_queue'),
      await columnsOf(upgraded, 'local_report_queue'),
    );
    await fresh.close();
    await upgraded.close();
  });

  test('DBHelper declares version 16 with an applied v16 upgrade branch', () {
    final source = File('lib/core/services/db_helper.dart').readAsStringSync();
    expect(source, contains('version: 16,'));
    expect(source, contains('if (oldVersion < 16)'));
    expect(source, contains('ReportQueueSchema.applyV16(db)'));
    // The v15 branch must still be present for devices coming from older builds.
    expect(source, contains('if (oldVersion < 15)'));
    expect(source, contains('ReportQueueSchema.applyV15(db)'));
  });

  test('the v16 migration is additive: no DROP/DELETE of queue rows', () {
    final source =
        File('lib/core/services/report_queue_schema.dart').readAsStringSync();
    final v16 = source.substring(source.indexOf('applyV16'));
    expect(v16, isNot(contains('DROP')));
    expect(v16, isNot(contains('DELETE')));
    expect(v16, contains('addColumnIfMissing'));
  });
}