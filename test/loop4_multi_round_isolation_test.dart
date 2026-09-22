import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/sync_outbox_service.dart';
import 'package:imaps_fieldsync/modules/inspection/providers/inspection_provider.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/inspection_progress.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  const roundOneId = '11111111-1111-4111-8111-111111111111';
  const roundTwoId = '22222222-2222-4222-8222-222222222222';
  late Directory temporary;
  late Database db;

  Map<String, dynamic> roundJob({
    required String id,
    required int localId,
    required String status,
    required String officerId,
    required String officerName,
    required String instructions,
  }) => {
    'id': id,
    'local_inspection_id': localId,
    'status': status,
    'scheduled_date': '2026-09-25',
    'deadline_date': '2026-09-27',
    'is_self_scheduled': false,
    'current_step': status == 'completed' ? 6 : 0,
    'step_timestamps': status == 'completed'
        ? {'1': '2026-09-21T01:00:00Z'}
        : null,
    'submitted_at': status == 'completed' ? '2026-09-21T06:00:00Z' : null,
    'supabase_parcel_id': 'parcel-shared',
    'assignment_instructions': instructions,
    'assigned_by_imaps_user_id': officerId,
    'assigned_by_name': officerName,
    'findings': status == 'completed' ? 'Round 1 findings' : null,
    'observations': status == 'completed' ? 'Round 1 observations' : null,
    'discrepancies': status == 'completed' ? 'Round 1 discrepancy' : null,
    'recommendations': status == 'completed' ? 'Round 1 recommendation' : null,
    'inspector_notes': status == 'completed' ? 'Round 1 inspector notes' : null,
    'inspection_result': status == 'completed' ? 'Requires Reinspection' : null,
    'checklist_data': status == 'completed'
        ? [
            {'item': 'setback', 'passed': false},
          ]
        : null,
    'photo_paths': status == 'completed'
        ? ['https://example.test/round-1.jpg']
        : null,
    'photo_count': status == 'completed' ? 1 : 0,
    'checklist_completed_count': status == 'completed' ? 1 : 0,
    'checklist_total_count': status == 'completed' ? 1 : 0,
    'updated_at': '2026-09-21T06:00:00Z',
    'supabase_zoning_applications': {
      'reference_number': 'APP-LOOP4-SHARED',
      'applicant_name': 'Loop 4 Applicant',
      'barangay': 'Poblacion A',
      'application_type': 'Locational Clearance',
    },
    'supabase_parcels': {
      'latitude': 13.845,
      'longitude': 121.206,
      'lot_area_sqm': 200.0,
      'land_use_class': 'Residential',
    },
  };

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('fieldsync-loop4-');
    db = await databaseFactoryFfi.openDatabase('${temporary.path}/loop4.db');
    final source = File('lib/core/services/db_helper.dart').readAsStringSync();
    for (final match in RegExp(
      r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)',
    ).allMatches(source)) {
      await db.execute(match.group(0)!);
    }
    DBHelper.useDatabaseForTesting(db);
    InspectionProgress.instance.reset();
  });

  tearDown(() async {
    DBHelper.useDatabaseForTesting(null);
    await db.close();
    await temporary.delete(recursive: true);
  });

  test(
    'same application rounds coexist with independent lifecycle and evidence',
    () async {
      final roundOne = TaskItem.fromJob(
        roundJob(
          id: roundOneId,
          localId: 35,
          status: 'completed',
          officerId: '4',
          officerName: 'Officer A',
          instructions: 'Round 1 instructions',
        ),
      );
      final roundTwo = TaskItem.fromJob(
        roundJob(
          id: roundTwoId,
          localId: 36,
          status: 'assigned',
          officerId: '12',
          officerName: 'Officer B',
          instructions: 'Round 2 instructions',
        ),
      );

      expect(roundOne.id, isNot(roundTwo.id));
      expect(roundOne.inspectionNo, roundTwo.inspectionNo);
      expect(roundOne.category, 'Completed');
      expect(roundTwo.category, 'Pending');
      expect(roundOne.currentStep, 6);
      expect(roundTwo.currentStep, 0);
      expect(roundOne.checklistData, isNotEmpty);
      expect(roundTwo.checklistData, isEmpty);
      expect(roundOne.photoPaths, isNotEmpty);
      expect(roundTwo.photoPaths, isEmpty);
      expect(roundOne.findings, 'Round 1 findings');
      expect(roundTwo.findings, isNull);
      expect(roundOne.assignedByName, 'Officer A');
      expect(roundTwo.assignedByName, 'Officer B');
      expect(roundOne.assignmentInstructions, 'Round 1 instructions');
      expect(roundTwo.assignmentInstructions, 'Round 2 instructions');
    },
  );

  test(
    'SQLite drafts, photos, progress and outbox isolate by field job UUID',
    () async {
      final jobOne = roundJob(
        id: roundOneId,
        localId: 35,
        status: 'completed',
        officerId: '4',
        officerName: 'Officer A',
        instructions: 'Round 1 instructions',
      );
      final jobTwo = roundJob(
        id: roundTwoId,
        localId: 36,
        status: 'assigned',
        officerId: '12',
        officerName: 'Officer B',
        instructions: 'Round 2 instructions',
      );
      await DBHelper.cacheJobs([jobOne, jobTwo]);
      expect(await DBHelper.getCachedJobs(), hasLength(2));

      await db.insert('local_inspections', {
        'id': roundOneId,
        'notes': 'Round 1 findings',
        'checklist_json': jsonEncode({'old': true}),
        'current_step': 6,
        'is_synced': 1,
      });
      await DBHelper.savePhotoLocally(
        photoId: 'photo-round-1',
        jobId: roundOneId,
        photoPath: 'round-1.jpg',
        notes: 'old',
        latitude: 1,
        longitude: 2,
      );
      await SyncOutboxService.enqueueCurrentStepUpdate(
        jobId: roundTwoId,
        step: 1,
      );

      final provider = InspectionProvider();
      await provider.startInspection(TaskItem.fromJob(jobTwo));
      expect(provider.currentStep, 1);
      expect(provider.capturedPhotos, isEmpty);
      expect(provider.notes, isEmpty);
      expect(provider.siteCondition, isNot(containsPair('old', true)));

      InspectionProgress.instance.ensureActiveInspection(
        roundOneId,
        initialStep: 6,
      );
      InspectionProgress.instance.ensureActiveInspection(
        roundTwoId,
        initialStep: 0,
      );
      expect(InspectionProgress.instance.highestCompleted, 0);

      expect((await db.query('local_photos')).single['job_id'], roundOneId);
      final action = (await db.query('pending_actions')).single;
      expect(action['job_id'], roundTwoId);
      expect(action['id'], contains(roundTwoId));
    },
  );

  test('active writers and deterministic IDs are keyed by field job id', () {
    final dbSource = File(
      'lib/core/services/db_helper.dart',
    ).readAsStringSync();
    final progress = File(
      'lib/modules/inspection/screens/inspection_progress.dart',
    ).readAsStringSync();
    final outbox = File(
      'lib/core/services/sync_outbox_service.dart',
    ).readAsStringSync();
    final supabase = File(
      'lib/core/services/supabase_service.dart',
    ).readAsStringSync();

    expect(dbSource, contains('id TEXT PRIMARY KEY'));
    expect(dbSource, contains('job_id TEXT NOT NULL'));
    expect(progress, contains('_activeTaskId != taskId'));
    expect(outbox, contains("'current_step_update_\$jobId'"));
    expect(supabase, contains("'inspections/\$jobId/photo_"));
  });
}
