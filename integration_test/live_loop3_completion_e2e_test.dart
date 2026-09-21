// LIVE / MUTATING / LOOP 3 ONLY
// Outside test/: ordinary `flutter test` does not discover this file.
// Run only on the inspector's authenticated device:
// flutter test integration_test/live_loop3_completion_e2e_test.dart -d <id> \
//   --dart-define=RUN_LIVE_LOOP3_COMPLETION=true
// Never add credentials or privileged keys here.

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:imaps_fieldsync/core/services/supabase_service.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

const _enabled = bool.fromEnvironment('RUN_LIVE_LOOP3_COMPLETION');
const _jobId = 'c7315702-a00f-476c-84f6-f1ba268686f7';
const _inspectionId = 35;
const _reference = 'APP-2026-00025';
const _inspectorId = 'ddcebeac-2217-41c5-a6e2-d7f873db9af2';
const _assignedById = 4;
const _assignedByName = 'Jyerine Desunia';
const _accuracyMeters = 5.0;
const _notes = 'Loop 3 controlled E2E completion test.';
const _recommendations = 'Loop 3 controlled test recommendation.';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('LIVE / MUTATING / LOOP 3 ONLY — complete APP-2026-00025', (
    tester,
  ) async {
    await dotenv.load(fileName: '.env');
    await SupabaseService.initialize();
    final client = SupabaseService.client;
    final user = client.auth.currentUser;
    if (user == null) throw StateError('LIVE TEST AUTH SESSION REQUIRED');
    _exact(user.id, _inspectorId, 'authenticated inspector UUID');

    // One inspector-RLS-scoped snapshot supplies every pre-write guard and
    // the production parcel relation used by FieldSync.
    final guarded = await client
        .from('field_jobs')
        .select('''
        *,
        supabase_zoning_applications!field_jobs_supabase_application_id_fkey (
          reference_number
        ),
        supabase_parcels!field_jobs_supabase_parcel_id_fkey (
          id, latitude, longitude, land_use_class
        )
      ''')
        .eq('id', _jobId)
        .eq('assigned_inspector_id', user.id)
        .maybeSingle();
    if (guarded == null) {
      throw StateError('PRE-WRITE GUARD FAILED: exact inspector job not found');
    }
    _assertPreWriteGuards(guarded);

    final parcelId = guarded['supabase_parcel_id'] as String?;
    if (parcelId == null) {
      throw StateError('PRE-WRITE GUARD FAILED: parcel id is null');
    }
    final parcel = await SupabaseService.fetchParcelDetails(parcelId);
    if (parcel == null || parcel['id'] != parcelId) {
      throw StateError('PRE-WRITE GUARD FAILED: production parcel read failed');
    }
    final latitude = (parcel['latitude'] as num?)?.toDouble();
    final longitude = (parcel['longitude'] as num?)?.toDouble();
    final landUse = parcel['land_use_class']?.toString();
    if (latitude == null ||
        longitude == null ||
        landUse == null ||
        landUse.isEmpty) {
      throw StateError(
        'PRE-WRITE GUARD FAILED: target coordinates/land use missing',
      );
    }
    final timestamps = <String, dynamic>{
      ...?guarded['step_timestamps'] as Map<String, dynamic>?,
    };

    // Production GPS persistence receives a controlled on-site coordinate;
    // the app's production 30 m geofence is not changed or bypassed.
    await SupabaseService.confirmGpsOnSite(
      jobId: _jobId,
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: _accuracyMeters,
      locationLabel: 'Loop 3 controlled GPS integration',
    );
    await _persistStep(2, timestamps);

    // Current production Step 3 accepts zero photos. Exercise the real
    // upload helper with that valid payload instead of inventing evidence.
    final photoPaths = await SupabaseService.uploadInspectionPhotos(
      jobId: _jobId,
      photosData: const [],
    );
    _exact(photoPaths.length, 0, 'accepted photo count');
    await SupabaseService.updateJobInspectionProgress(
      jobId: _jobId,
      updateData: const {'photo_paths': <String>[], 'photo_count': 0},
    );
    await _persistStep(3, timestamps);

    const checklist = <Map<String, dynamic>>[
      {'item': 'Structure matches declared use', 'checked': true},
      {'item': 'Setback distances compliant', 'checked': true},
      {'item': 'Accessibility & road frontage', 'checked': true},
      {'item': 'Surrounding developments noted', 'checked': true},
      {'item': 'Signage / commercial activity present', 'checked': true},
    ];
    await SupabaseService.updateJobInspectionProgress(
      jobId: _jobId,
      updateData: const {
        'checklist_data': checklist,
        'checklist_completed_count': 5,
        'checklist_total_count': 5,
      },
    );
    await _persistStep(4, timestamps);

    final observations =
        'Actual land use: $landUse. Boundary status: Verified on-site — 0m from declared location.';
    await SupabaseService.updateJobInspectionProgress(
      jobId: _jobId,
      updateData: {
        'observations': observations,
        'discrepancies': null,
        'recommendations': _recommendations,
        'inspector_notes': _notes,
      },
    );

    // Same active online sequence used by ReviewSubmitScreen.
    final finalPhotoPaths = await SupabaseService.uploadInspectionPhotos(
      jobId: _jobId,
      photosData: const [],
    );
    await SupabaseService.submitInspection(
      jobId: _jobId,
      findings: _notes,
      isCompliant: true,
      inspectionResult: 'Compliant',
      observations: observations,
      discrepancies: null,
      recommendations: _recommendations,
      inspectorNotes: _notes,
      checklistData: checklist,
      checklistCompletedCount: 5,
      checklistTotalCount: 5,
      photoPaths: finalPhotoPaths,
      photoCount: finalPhotoPaths.length,
      locationLabel: _reference,
    );
    await _persistStep(6, timestamps);

    final finalJobs = await SupabaseService.fetchMyJobs();
    final finalJob = finalJobs.singleWhere((job) => job['id'] == _jobId);
    _exact(finalJob['status'], 'completed', 'final status');
    _exact(
      mapTaskStatusToLifecycle(finalJob['status'] as String?),
      TaskLifecycleCategory.completed,
      'FieldSync lifecycle',
    );
    expect(
      mapTaskStatusToLifecycle(finalJob['status'] as String?),
      isNot(TaskLifecycleCategory.ongoing),
    );
    final detail = await SupabaseService.fetchJobDetail(_jobId);
    if (detail == null) throw StateError('Final job detail is unavailable');
    _assertFinal(detail, latitude, longitude, observations, checklist);
  }, skip: !_enabled);
}

Future<void> _persistStep(int step, Map<String, dynamic> timestamps) async {
  timestamps[step.toString()] = DateTime.now().toUtc().toIso8601String();
  await SupabaseService.updateJobInspectionProgress(
    jobId: _jobId,
    updateData: {
      'current_step': step,
      'step_timestamps': Map<String, dynamic>.from(timestamps),
    },
  );
}

void _assertPreWriteGuards(Map<String, dynamic> job) {
  _exact(job['id'], _jobId, 'id');
  _exact(job['local_inspection_id'], _inspectionId, 'local_inspection_id');
  _exact(
    (job['supabase_zoning_applications'] as Map?)?['reference_number'],
    _reference,
    'reference_number',
  );
  _exact(job['assigned_inspector_id'], _inspectorId, 'assigned_inspector_id');
  _exact(job['status'], 'in_progress', 'status');
  _exact(job['current_step'], 1, 'current_step');
  _exact(
    job['assigned_by_imaps_user_id'],
    _assignedById,
    'assigned_by_imaps_user_id',
  );
  _exact(job['assigned_by_name'], _assignedByName, 'assigned_by_name');
  _exact(job['submitted_at'], null, 'submitted_at');
}

void _assertFinal(
  Map<String, dynamic> job,
  double latitude,
  double longitude,
  String observations,
  List<Map<String, dynamic>> checklist,
) {
  _exact(job['id'], _jobId, 'final id');
  _exact(
    job['local_inspection_id'],
    _inspectionId,
    'final local_inspection_id',
  );
  _exact(job['status'], 'completed', 'final status');
  _exact(job['current_step'], 6, 'final current_step');
  expect(job['submitted_at'], isNotNull);
  _exact(job['inspection_result'], 'Compliant', 'inspection_result');
  _exact(job['is_compliant'], true, 'is_compliant');
  _exact(job['findings'], _notes, 'findings');
  _exact(job['observations'], observations, 'observations');
  _exact(job['discrepancies'], null, 'discrepancies');
  _exact(job['recommendations'], _recommendations, 'recommendations');
  _exact(job['inspector_notes'], _notes, 'inspector_notes');
  expect(
    job['checklist_data'],
    orderedEquals(checklist),
    reason: 'checklist_data must match by structural value',
  );
  _exact(job['checklist_completed_count'], 5, 'checklist_completed_count');
  _exact(job['checklist_total_count'], 5, 'checklist_total_count');
  _exact(job['photo_count'], 0, 'photo_count');
  _exact((job['photo_paths'] as List?)?.length ?? 0, 0, 'photo_paths');
  _exact(job['confirmed_latitude'], latitude, 'confirmed_latitude');
  _exact(job['confirmed_longitude'], longitude, 'confirmed_longitude');
  _exact(job['gps_accuracy_m'], _accuracyMeters, 'gps_accuracy_m');
  expect(job['gps_confirmed_at'], isNotNull);
  _exact(
    job['assigned_inspector_id'],
    _inspectorId,
    'preserved assigned_inspector_id',
  );
  _exact(
    job['assignment_instructions'],
    null,
    'preserved assignment_instructions',
  );
  _exact(
    job['assigned_by_imaps_user_id'],
    _assignedById,
    'preserved assigned_by_imaps_user_id',
  );
  _exact(
    job['assigned_by_name'],
    _assignedByName,
    'preserved assigned_by_name',
  );
}

void _exact(Object? actual, Object? expected, String field) {
  if (actual != expected) {
    throw StateError(
      'GUARD/VERIFY FAILED: $field expected <$expected>, got <$actual>',
    );
  }
}
