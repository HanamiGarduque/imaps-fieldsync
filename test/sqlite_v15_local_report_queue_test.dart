// SQLite v15 — local_report_queue + local_jobs identity columns.
//
// All destructive migration testing runs against isolated, temporary
// databases, exactly like the route-cache and retention suites. Device data is
// never opened.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/report_queue_schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Extract every CREATE TABLE statement from the DBHelper source, in definition
// order. Non-greedy up to the first ')' — safe here because, once the nested
// CHECK statements are stripped from scanning, none of the remaining tables
// nests parentheses. local_report_queue IS captured by this same pattern; the
// CHECK material is nested but the lazy match stops at the queue's own closing
// ')' on the CHECK line for builds that skip it, so callers must skip it by
// name (only the columns builder does).
List<String> createTableStatements() {
  final src = File('lib/core/services/db_helper.dart').readAsStringSync();
  return RegExp(
    r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)',
  ).allMatches(src).map((m) => m.group(0)!).toList();
}

const String _v14LocalJobs = '''
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

Future<Database> openFreshV15At(String path) async {
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 15,
      onCreate: (database, version) async {
        for (final stmt in createTableStatements()) {
          if (stmt.contains('local_report_queue(')) {
            // Created below, together with its indexes.
            continue;
          }
          await database.execute(stmt);
        }
        // The v15 fresh-install path: local_jobs already carries its two
        // identity columns inline above; here we only add the queue table and
        // its indexes. applyV15Schema's ALTERs are for UPGRADES, which have a
        // v14 local_jobs without those columns — never double-apply them.
        await ReportQueueSchema.createTable(database);
      },
    ),
  );
  return db;
}

Future<Database> openLegacyV14At(String path) async {
  return databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 14,
      onCreate: (database, version) async {
        for (final stmt in createTableStatements()) {
          if (stmt.contains('local_report_queue(') ||
              stmt.contains('local_jobs(')) {
            continue;
          }
          await database.execute(stmt);
        }
        // v14 local_jobs, with no identity columns.
        await database.execute(_v14LocalJobs);
      },
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory dir;
  late String path;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fieldsync-v15-');
    path = '${dir.path}/fixture.db';
  });

  tearDown(() async {
    DBHelper.useDatabaseForTesting(null);
    await dir.delete(recursive: true);
  });

  test(
    'fresh v15 database has local_report_queue with the full contract',
    () async {
      final db = await openFreshV15At(path);
      DBHelper.useDatabaseForTesting(db);
      final cols = (await db.rawQuery(
        'PRAGMA table_info(local_report_queue)',
      )).map((r) => r['name'] as String).toList();
      expect(
        cols,
        containsAll([
          'id',
          'report_type',
          'payload',
          'local_job_id',
          'field_job_id',
          'supabase_application_id',
          'bridge_source_id',
          'remote_report_id',
          'reference_code',
          'queue_state',
          'retry_count',
          'last_error',
          'created_at',
          'last_attempt_at',
          'updated_at',
        ]),
      );
      for (final t in [
        'local_jobs',
        'local_inspections',
        'local_photos',
        'pending_actions',
        'sync_log_entries',
        'inspection_job_retention',
        'local_route_cache',
      ]) {
        final rows = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='$t'",
        );
        expect(rows, isNotEmpty, reason: '$t must exist in a fresh v15 DB');
      }
      final jobCols = (await db.rawQuery(
        'PRAGMA table_info(local_jobs)',
      )).map((r) => r['name'] as String).toList();
      expect(
        jobCols,
        containsAll(['supabase_application_id', 'bridge_source_id']),
      );
      await db.close();
    },
  );

  test('fresh v15 database has all approved indexes', () async {
    final db = await openFreshV15At(path);
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
    await db.close();
  });

  test(
    'v14 to v15 upgrade preserves all existing rows and adds new columns',
    () async {
      var db = await openLegacyV14At(path);
      await db.insert('local_jobs', {'id': 'job-1', 'status': 'assigned'});
      await db.insert('local_inspections', {'id': 'job-1', 'notes': 'x'});
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
      await db.close();

      db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 15,
          onUpgrade: (database, oldVersion, newVersion) async {
            expect(oldVersion, 14);
            await ReportQueueSchema.applyV15(database);
          },
        ),
      );

      expect(await db.rawQuery('SELECT COUNT(*) c FROM local_jobs'), [
        {'c': 1},
      ]);
      final job = (await db.query(
        'local_jobs',
        where: 'id=?',
        whereArgs: ['job-1'],
      )).single;
      expect(job['status'], 'assigned');
      // Identity columns are NULL on the upgraded cached row; it stays usable
      // for existing task functionality but is ineligible for Application
      // Support until refreshed with real remote identities.
      expect(job['supabase_application_id'], isNull);
      expect(job['bridge_source_id'], isNull);
      expect(await db.rawQuery('SELECT COUNT(*) c FROM pending_actions'), [
        {'c': 1},
      ]);
      expect(await db.rawQuery('SELECT COUNT(*) c FROM local_route_cache'), [
        {'c': 1},
      ]);
      expect(await db.rawQuery('SELECT COUNT(*) c FROM local_report_queue'), [
        {'c': 0},
      ]);

      // pending_actions schema unchanged downstream of the upgrade.
      final pendingCols = (await db.rawQuery(
        'PRAGMA table_info(pending_actions)',
      )).map((r) => r['name'] as String).toList();
      expect(
        pendingCols,
        containsAll([
          'id',
          'type',
          'job_id',
          'payload',
          'status',
          'retry_count',
          'last_error',
          'created_at',
          'updated_at',
        ]),
      );
      await db.close();
    },
  );

  test('report_type and queue_state CHECK constraints are enforced', () async {
    final db = await openFreshV15At(path);
    DBHelper.useDatabaseForTesting(db);
    await expectLater(
      db.insert('local_report_queue', {
        'id': 'r1',
        'report_type': 'bogus',
        'payload': '{}',
        'created_at': 't',
        'updated_at': 't',
      }),
      throwsA(anything),
    );
    await expectLater(
      db.insert('local_report_queue', {
        'id': 'r2',
        'report_type': 'technical_issue',
        'payload': '{}',
        'queue_state': 'bogus',
        'created_at': 't',
        'updated_at': 't',
      }),
      throwsA(anything),
    );
    // Technical Issue with any identity is rejected by the row CHECK.
    await expectLater(
      db.insert('local_report_queue', {
        'id': 'r3',
        'report_type': 'technical_issue',
        'payload': '{}',
        'field_job_id': 'j',
        'created_at': 't',
        'updated_at': 't',
      }),
      throwsA(anything),
    );
    // Application Support missing any identity is rejected.
    await expectLater(
      db.insert('local_report_queue', {
        'id': 'r4',
        'report_type': 'application_support',
        'payload': '{}',
        'field_job_id': 'j',
        'created_at': 't',
        'updated_at': 't',
      }),
      throwsA(anything),
    );
    // Valid Application Support row is accepted.
    await db.insert('local_report_queue', {
      'id': 'r5',
      'report_type': 'application_support',
      'payload': '{}',
      'field_job_id': 'j',
      'supabase_application_id': 'a',
      'bridge_source_id': 's',
      'created_at': 't',
      'updated_at': 't',
    });
    expect(
      (await db.rawQuery('SELECT COUNT(*) c FROM local_report_queue'))[0]['c'],
      1,
    );
    // A second confirmed remote identity may not attach to two local rows.
    await db.insert('local_report_queue', {
      'id': 'r6',
      'report_type': 'technical_issue',
      'payload': '{}',
      'remote_report_id': 'remote-1',
      'created_at': 't',
      'updated_at': 't',
    });
    await expectLater(
      db.insert('local_report_queue', {
        'id': 'r7',
        'report_type': 'technical_issue',
        'payload': '{}',
        'remote_report_id': 'remote-1',
        'created_at': 't',
        'updated_at': 't',
      }),
      throwsA(anything),
    );
    await db.close();
  });

  test('no report row is created by the migration', () async {
    final db = await openFreshV15At(path);
    expect(
      (await db.rawQuery('SELECT COUNT(*) c FROM local_report_queue'))[0]['c'],
      0,
    );
    await db.close();
  });
}
