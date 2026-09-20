import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late Database db;
  late String path;

  Future<void> createProductionSchema() async {
    final source = await File('lib/core/services/db_helper.dart').readAsString();
    for (final match in RegExp(
      r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)',
    ).allMatches(source)) {
      await db.execute(match.group(0)!);
    }
  }

  Future<void> reopen() async {
    DBHelper.useDatabaseForTesting(null);
    await db.close();
    db = await databaseFactoryFfi.openDatabase(path);
    DBHelper.useDatabaseForTesting(db);
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('loop3-cache-');
    path = '${tempDir.path}/offline_cache.db';
    db = await databaseFactoryFfi.openDatabase(path);
    await createProductionSchema();
    DBHelper.useDatabaseForTesting(db);
  });

  tearDown(() async {
    DBHelper.useDatabaseForTesting(null);
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('cache persists assignment provenance and reconstructs TaskItem', () async {
    final job = {
      'id': 'loop3-job-1',
      'local_inspection_id': 7,
      'status': 'assigned',
      'scheduled_date': '2026-10-01',
      'deadline_date': null,
      'is_self_scheduled': false,
      'supabase_parcel_id': 'parcel-1',
      'assignment_instructions': 'Verify rear boundary',
      'assigned_by_imaps_user_id': '17',
      'assigned_by_name': ' Engr. Reyes ',
      'supabase_zoning_applications': {
        'applicant_name': 'Maria Santos',
        'barangay': 'Poblacion A',
        'reference_number': 'REF-7',
        'application_type': 'Residential',
      },
      'supabase_parcels': {
        'lot_area_sqm': 120.0,
        'declared_land_use': 'Residential',
        'latitude': null,
        'longitude': null,
      },
      'updated_at': '2026-09-18T00:00:00Z',
      'rework_started_at': null,
    };

    await DBHelper.cacheJobs([job]);
    final cached = (await DBHelper.getCachedJobs()).single;
    expect(cached['assignment_instructions'], 'Verify rear boundary');
    expect(cached['assigned_by_imaps_user_id'], '17');
    expect(cached['assigned_by_name'], 'Engr. Reyes');

    final task = TaskItem.fromJob({
      'id': cached['id'],
      'status': cached['status'],
      'scheduled_date': cached['scheduled_date'],
      'deadline_date': cached['deadline_date'],
      'is_self_scheduled': cached['is_self_scheduled'] == 1,
      'assignment_instructions': cached['assignment_instructions'],
      'assigned_by_imaps_user_id': cached['assigned_by_imaps_user_id'],
      'assigned_by_name': cached['assigned_by_name'],
      'supabase_zoning_applications': {
        'applicant_name': cached['applicant_name'],
        'barangay': cached['barangay'],
        'reference_number': cached['reference_number'],
        'application_type': cached['application_type'],
      },
      'supabase_parcels': {
        'lot_area_sqm': cached['lot_area_sqm'],
        'declared_land_use': cached['declared_land_use'],
      },
    });

    expect(task.assignmentInstructions, 'Verify rear boundary');
    expect(task.assignedByImapsUserId, '17');
    expect(task.assignedByName, 'Engr. Reyes');
  });

  test('latest cached reassignment replaces prior assigning officer and keeps lifecycle intact', () async {
    final earlier = {
      'id': 'loop3-job-2',
      'local_inspection_id': 8,
      'status': 'assigned',
      'scheduled_date': '2026-10-02',
      'is_self_scheduled': false,
      'supabase_parcel_id': 'parcel-2',
      'assignment_instructions': 'Initial assignment',
      'assigned_by_imaps_user_id': '11',
      'assigned_by_name': 'Officer A',
      'supabase_zoning_applications': {
        'applicant_name': 'Ana Cruz',
        'barangay': 'San Jose',
        'reference_number': 'REF-8',
        'application_type': 'Residential',
      },
      'supabase_parcels': {
        'lot_area_sqm': 90.0,
        'declared_land_use': 'Residential',
        'latitude': null,
        'longitude': null,
      },
      'updated_at': '2026-09-18T00:00:00Z',
      'rework_started_at': null,
    };

    final latest = {
      ...earlier,
      'status': 'in_progress',
      'assignment_instructions': 'Reassigned task',
      'assigned_by_imaps_user_id': '42',
      'assigned_by_name': 'Officer B',
      'updated_at': '2026-09-18T01:00:00Z',
    };

    await DBHelper.cacheJobs([earlier]);
    await DBHelper.cacheJobs([latest]);

    final cached = (await DBHelper.getCachedJobs()).single;
    expect(cached['assigned_by_imaps_user_id'], '42');
    expect(cached['assigned_by_name'], 'Officer B');
    expect(cached['status'], 'in_progress');
    expect(cached['assignment_instructions'], 'Reassigned task');
  });

  test('close/reopen cache preserves assignment provenance after SQLite reopen', () async {
    final job = {
      'id': 'loop3-job-3',
      'local_inspection_id': 9,
      'status': 'assigned',
      'scheduled_date': '2026-10-03',
      'is_self_scheduled': false,
      'supabase_parcel_id': 'parcel-3',
      'assignment_instructions': 'Review parcel corner markers',
      'assigned_by_imaps_user_id': '99',
      'assigned_by_name': 'Planner 99',
      'supabase_zoning_applications': {
        'applicant_name': 'R. Lim',
        'barangay': 'Tulos',
        'reference_number': 'REF-9',
        'application_type': 'Commercial',
      },
      'supabase_parcels': {
        'lot_area_sqm': 400.0,
        'declared_land_use': 'Commercial',
        'latitude': null,
        'longitude': null,
      },
      'updated_at': '2026-09-18T00:00:00Z',
      'rework_started_at': null,
    };

    await DBHelper.cacheJobs([job]);
    await reopen();
    final cached = (await DBHelper.getCachedJobs()).single;
    expect(cached['assignment_instructions'], 'Review parcel corner markers');
    expect(cached['assigned_by_imaps_user_id'], '99');
    expect(cached['assigned_by_name'], 'Planner 99');
  });
}
