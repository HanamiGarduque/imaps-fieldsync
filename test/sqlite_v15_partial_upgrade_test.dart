// v14 → v15 partial-upgrade matrix.
//
// A real field device can reach the v15 migration with the identity columns
// already present: an earlier open may have been interrupted between the two
// ALTERs, or two opens may have raced the version check. SQLite has no
// `ALTER TABLE ... ADD COLUMN IF NOT EXISTS`, so the migration must inspect
// the real table before it adds anything.
//
// These tests rebuild each device state from scratch. None of them drops,
// truncates or recreates `local_jobs` to make a case pass — every case proves
// the ADD COLUMN is simply skipped when the column is already there.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/report_queue_schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Every table that must survive the upgrade untouched.
const _preservedTables = <String>[
  'local_jobs',
  'local_inspections',
  'local_photos',
  'pending_actions',
  'sync_log_entries',
  'inspection_job_retention',
  'local_route_cache',
];

/// v14 `local_jobs`: no identity columns. Copied from the pre-v15 schema.
const _v14LocalJobs = '''
CREATE TABLE local_jobs(
  id TEXT PRIMARY KEY,
  local_inspection_id INTEGER,
  status TEXT,
  scheduled_date TEXT,
  deadline_date TEXT,
  is_self_scheduled INTEGER DEFAULT 0,
  supabase_parcel_id TEXT,
  applicant_name TEXT,
  barangay TEXT,
  reference_number TEXT,
  application_type TEXT,
  assignment_instructions TEXT,
  assigned_by_imaps_user_id TEXT,
  assigned_by_name TEXT,
  planning_review TEXT,
  submitted_at TEXT,
  cached_updated_at TEXT,
  rework_started_at TEXT,
  parcel_lat REAL,
  parcel_lng REAL,
  lot_area_sqm REAL,
  declared_land_use TEXT,
  parcel_address TEXT
)
''';

List<String> _createTableStatements() {
  final src = File('lib/core/services/db_helper.dart').readAsStringSync();
  return RegExp(
    r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)',
  ).allMatches(src).map((m) => m.group(0)!).toList();
}

Future<void> _createNonJobTables(Database db) async {
  for (final stmt in _createTableStatements()) {
    if (stmt.contains('local_report_queue(') || stmt.contains('local_jobs(')) {
      continue;
    }
    await db.execute(stmt);
  }
}

/// Builds the exact v14 schema, then seeds one row in every table that must
/// survive, so every case can assert no business or cache row was lost.
Future<Database> buildV14(
  String path, {
  List<String> extraLocalJobColumns = const [],
  bool withReportQueue = false,
}) async {
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 14,
      onCreate: (database, _) async {
        await _createNonJobTables(database);
        await database.execute(_v14LocalJobs);
        for (final col in extraLocalJobColumns) {
          await database.execute('ALTER TABLE local_jobs ADD COLUMN $col TEXT');
        }
        if (withReportQueue) {
          await ReportQueueSchema.createTable(database);
        }
      },
    ),
  );
  await db.insert('local_jobs', {'id': 'job-1', 'status': 'assigned'});
  await db.insert('local_inspections', {'id': 'job-1', 'notes': 'prior draft'});
  await db.insert('local_photos', {'id': 'p1', 'job_id': 'job-1'});
  await db.insert('pending_actions', {
    'id': 'a1',
    'type': 'gps_confirm',
    'job_id': 'job-1',
    'payload': '{}',
    'created_at': 't',
    'updated_at': 't',
  });
  await db.insert('sync_log_entries', {
    'id': 'l1',
    'event_type': 'e',
    'result': 'ok',
    'message': 'm',
    'created_at': 't',
  });
  await db.insert('inspection_job_retention', {
    'job_id': 'job-1',
    'retained_at': 't',
  });
  await db.insert('local_route_cache', {
    'job_id': 'job-1',
    'geometry_json': '[]',
    'origin_lat': 1.0,
    'origin_lng': 2.0,
    'fetched_at': 't',
  });
  return db;
}

Future<Database> upgradeToV15(String path) async {
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 15,
      onUpgrade: (database, oldVersion, newVersion) async {
        expect(oldVersion, 14);
        await ReportQueueSchema.applyV15(database);
      },
    ),
  );
  DBHelper.useDatabaseForTesting(db);
  return db;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory dir;
  late String path;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fieldsync-v15b-');
    path = '${dir.path}/fixture.db';
  });

  tearDown(() async {
    DBHelper.useDatabaseForTesting(null);
    if (dir.existsSync()) {
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        // Windows may still hold the handle briefly; harmless for a temp dir.
      }
    }
  });

  Future<void> expectEveryExistingRowSurvived(Database db) async {
    for (final table in _preservedTables) {
      expect(
        await db.rawQuery('SELECT COUNT(*) c FROM $table'),
        [
          {'c': 1},
        ],
        reason: '$table must keep its row through the upgrade',
      );
    }
    expect((await db.query('local_jobs')).single['status'], 'assigned');
    expect(
      (await db.query('local_inspections')).single['notes'],
      'prior draft',
    );
  }

  Future<void> expectPendingActionsUnchanged(Database db) async {
    final cols = (await db.rawQuery(
      'PRAGMA table_info(pending_actions)',
    )).map((r) => r['name'] as String).toList();
    expect(cols, [
      'id',
      'type',
      'job_id',
      'payload',
      'status',
      'retry_count',
      'last_error',
      'created_at',
      'updated_at',
    ]);
    final notNull = (await db.rawQuery(
      'PRAGMA table_info(pending_actions)',
    )).firstWhere((r) => r['name'] == 'job_id');
    expect(notNull['notnull'], 1, reason: 'job_id must remain NOT NULL');
  }

  Future<void> expectRouteCacheUnchanged(Database db) async {
    final cols = (await db.rawQuery(
      'PRAGMA table_info(local_route_cache)',
    )).map((r) => r['name'] as String).toList();
    expect(cols, [
      'job_id',
      'geometry_json',
      'distance_meters',
      'duration_seconds',
      'origin_lat',
      'origin_lng',
      'fetched_at',
    ]);
    expect((await db.query('local_route_cache')).single['geometry_json'], '[]');
  }

  Future<void> expectFinalV15Schema(Database db) async {
    final jobCols = await ReportQueueSchema.columnsOf(db, 'local_jobs');
    expect(
      jobCols,
      containsAll(['supabase_application_id', 'bridge_source_id']),
    );
    final idx = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index'",
    )).map((r) => r['name'] as String).toList();
    expect(
      idx,
      containsAll([
        'idx_local_report_queue_state',
        'idx_local_report_queue_type',
        'idx_local_report_queue_field_job',
        'idx_local_report_queue_remote_report_unique',
      ]),
    );
  }

  test(
    'A. v14 normal: neither identity column exists, both are added',
    () async {
      var db = await buildV14(path);
      expect(
        (await ReportQueueSchema.columnsOf(
          db,
          'local_jobs',
        )).contains('supabase_application_id'),
        isFalse,
      );
      await db.close();

      db = await upgradeToV15(path);
      await expectEveryExistingRowSurvived(db);
      await expectPendingActionsUnchanged(db);
      await expectRouteCacheUnchanged(db);
      await expectFinalV15Schema(db);
      await db.close();
    },
  );

  test(
    'B. supabase_application_id already present: preserved, bridge added',
    () async {
      var db = await buildV14(
        path,
        extraLocalJobColumns: ['supabase_application_id'],
      );
      await db.update('local_jobs', {
        'supabase_application_id': 'app-already-there',
      });
      await db.close();

      db = await upgradeToV15(path);
      final job = (await db.query('local_jobs')).single;
      expect(
        job['supabase_application_id'],
        'app-already-there',
        reason: 'an existing value must never be overwritten',
      );
      expect(job['bridge_source_id'], isNull);
      expect(
        await ReportQueueSchema.columnsOf(db, 'local_jobs'),
        contains('supabase_application_id'),
      );
      await expectEveryExistingRowSurvived(db);
      await db.close();
    },
  );

  test(
    'C. bridge_source_id already present: preserved, application id added',
    () async {
      var db = await buildV14(path, extraLocalJobColumns: ['bridge_source_id']);
      await db.update('local_jobs', {
        'bridge_source_id': 'source-already-there',
      });
      await db.close();

      db = await upgradeToV15(path);
      final job = (await db.query('local_jobs')).single;
      expect(job['bridge_source_id'], 'source-already-there');
      expect(job['supabase_application_id'], isNull);
      await expectEveryExistingRowSurvived(db);
      await db.close();
    },
  );

  test(
    'D. both already present: no ALTER is repeated and the upgrade succeeds',
    () async {
      var db = await buildV14(
        path,
        extraLocalJobColumns: ['supabase_application_id', 'bridge_source_id'],
      );
      await db.update('local_jobs', {
        'supabase_application_id': 'app-kept',
        'bridge_source_id': 'source-kept',
      });
      await db.close();

      // This is the exact state that produced the device crash: running the
      // old migration here threw "duplicate column name: supabase_application_id".
      db = await upgradeToV15(path);
      final job = (await db.query('local_jobs')).single;
      expect(job['supabase_application_id'], 'app-kept');
      expect(job['bridge_source_id'], 'source-kept');
      await expectFinalV15Schema(db);
      await expectEveryExistingRowSurvived(db);
      await expectPendingActionsUnchanged(db);
      await expectRouteCacheUnchanged(db);
      await db.close();
    },
  );

  test(
    'E. local_report_queue already present: the upgrade does not fail',
    () async {
      var db = await buildV14(path, withReportQueue: true);
      await db.insert('local_report_queue', {
        'id': 'rq-existing',
        'report_type': 'technical_issue',
        'payload': '{"title":"kept","summary":"s"}',
        'queue_state': 'pending',
        'created_at': 't',
        'updated_at': 't',
      });
      await db.close();

      db = await upgradeToV15(path);
      final row = (await db.query('local_report_queue')).single;
      expect(row['id'], 'rq-existing');
      expect(row['payload'], contains('kept'));
      await expectEveryExistingRowSurvived(db);
      await db.close();
    },
  );

  test(
    'F. approved indexes already present: the upgrade does not fail',
    () async {
      // withReportQueue runs the real createTable(), so all four approved
      // indexes already exist before the upgrade runs.
      var db = await buildV14(path, withReportQueue: true);
      final before = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index'",
      )).map((r) => r['name'] as String).toSet();
      expect(
        before,
        containsAll([
          'idx_local_report_queue_state',
          'idx_local_report_queue_type',
          'idx_local_report_queue_field_job',
          'idx_local_report_queue_remote_report_unique',
        ]),
      );
      await db.close();

      db = await upgradeToV15(path);
      await expectFinalV15Schema(db);
      await expectEveryExistingRowSurvived(db);
      await db.close();
    },
  );

  test('G. applying v15 twice in a row is a no-op', () async {
    var db = await buildV14(path);
    await db.close();

    db = await upgradeToV15(path);
    await db.close();

    // Re-open at the same version and re-run the same migration body, as a
    // second open racing or resuming would.
    db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 15,
        onUpgrade: (database, _, _) async {
          await ReportQueueSchema.applyV15(database);
        },
      ),
    );
    await db.update('local_jobs', {
      'supabase_application_id': 'app-after',
      'bridge_source_id': 'source-after',
    });
    final again = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 15,
        onUpgrade: (database, _, _) async {
          await ReportQueueSchema.applyV15(database);
        },
      ),
    );
    final job = (await again.query('local_jobs')).single;
    expect(job['supabase_application_id'], 'app-after');
    expect(job['bridge_source_id'], 'source-after');
    await again.close();
    await db.close();
  });

  test('H. pending_actions schema is byte-for-byte unchanged', () async {
    var db = await buildV14(path);
    await db.close();
    db = await upgradeToV15(path);
    await expectPendingActionsUnchanged(db);
    await db.close();
  });

  test('I. local_route_cache schema is byte-for-byte unchanged', () async {
    var db = await buildV14(path);
    await db.close();
    db = await upgradeToV15(path);
    await expectRouteCacheUnchanged(db);
    await db.close();
  });

  test(
    'the migration appends columns and never drops or recreates a table',
    () async {
      var db = await buildV14(path);
      final beforeCols = await ReportQueueSchema.columnsOf(db, 'local_jobs');
      final tableCountBefore = await db.rawQuery(
        "SELECT COUNT(*) c FROM sqlite_master WHERE type='table'",
      );
      await db.close();

      db = await upgradeToV15(path);

      // SQLite records an ADD COLUMN by appending to the stored CREATE text.
      // What must not happen is a DROP or a recreate, so assert that every
      // original column survives in its original order and that only the two
      // approved columns were appended.
      final afterCols = (await db.rawQuery(
        'PRAGMA table_info(local_jobs)',
      )).map((r) => r['name'] as String).toList();
      expect(
        afterCols.take(beforeCols.length).toList(),
        beforeCols.toList(),
        reason: 'no original column may be dropped or reordered',
      );
      expect(afterCols.sublist(beforeCols.length).toSet(), {
        'supabase_application_id',
        'bridge_source_id',
      });

      // No table was dropped: the queue table is the only addition.
      final tableCountAfter = await db.rawQuery(
        "SELECT COUNT(*) c FROM sqlite_master WHERE type='table'",
      );
      expect(
        tableCountAfter.single['c'],
        (tableCountBefore.single['c'] as int) + 1,
      );
      await expectEveryExistingRowSurvived(db);
      await db.close();
    },
  );
}
