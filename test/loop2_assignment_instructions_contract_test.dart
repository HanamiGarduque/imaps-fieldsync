// Loop 2 Part 1 — Phase D contract tests (FieldSync side).
//
// Tests:
//   5. TaskItem.fromJob reads assignment_instructions from the job map.
//   6. TaskItem.fromJob reads inspector_notes independently.
//   7. null assignment_instructions does NOT expose inspector_notes as instructions.
//   8. fetchMyJobs select query includes assignment_instructions column.
//   9. SyncOutboxService / outbox does NOT write assignment_instructions.
//  10. Lifecycle/category behaviour is unchanged (Loop 1 regression guard).
//
// All tests are pure in-process logic — no live Supabase calls.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

void main() {
  // ── shared helper ────────────────────────────────────────────────────────────

  Map<String, dynamic> jobMap({
    String? assignmentInstructions,
    String? inspectorNotes,
    String status = 'assigned',
  }) {
    return {
      'id': 'job-001',
      'local_inspection_id': 1,
      'status': status,
      'scheduled_date': '2026-09-20',
      'deadline_date': null,
      'is_self_scheduled': false,
      'current_step': 0,
      'step_timestamps': null,
      'rework_started_at': null,
      'created_at': '2026-09-01T00:00:00.000Z',
      'updated_at': '2026-09-15T10:00:00.000Z',
      'started_at': null,
      'submitted_at': null,
      'supabase_parcel_id': 'parcel-001',
      'assignment_instructions': assignmentInstructions,
      'inspector_notes': inspectorNotes,
      'supabase_zoning_applications': {
        'reference_number': 'REF-001',
        'applicant_name': 'Juan dela Cruz',
        'barangay': 'Brgy. Poblacion',
        'application_type': 'New Construction',
        'purpose': null,
        'contact_number': null,
        'email': null,
      },
      'supabase_parcels': {
        'lot_area_sqm': 120.0,
        'land_use_class': 'Residential',
        'property_index_number': 'PIN-001',
        'latitude': null,
        'longitude': null,
      },
      'findings': null,
      'observations': null,
      'discrepancies': null,
      'recommendations': null,
      'inspection_result': null,
      'is_compliant': null,
      'photo_paths': null,
      'field_job_photos': null,
      'photo_count': 0,
      'checklist_completed_count': 0,
      'checklist_total_count': 0,
      'checklist_data': null,
      'confirmed_latitude': null,
      'confirmed_longitude': null,
      'gps_accuracy_m': null,
      'gps_confirmed_at': null,
    };
  }

  String readSource(String relativePath) {
    final file = File(relativePath);
    if (!file.existsSync()) fail('Source file not found: $relativePath');
    return file.readAsStringSync();
  }

  // ── 5. job reader parses assignment_instructions ────────────────────────────

  test('TaskItem.fromJob populates assignmentInstructions from job map', () {
    final task = TaskItem.fromJob(
      jobMap(assignmentInstructions: 'Inspect left boundary for encroachment.'),
    );
    expect(task.assignmentInstructions, 'Inspect left boundary for encroachment.');
  });

  test('TaskItem.fromJob sets assignmentInstructions to null when absent', () {
    final task = TaskItem.fromJob(jobMap(assignmentInstructions: null));
    expect(task.assignmentInstructions, isNull);
  });

  // ── 6. inspector_notes remains independent ──────────────────────────────────

  test('inspectorNotes and assignmentInstructions are parsed independently', () {
    final task = TaskItem.fromJob(jobMap(
      assignmentInstructions: 'Check rear setback.',
      inspectorNotes: 'Observed 0.3m encroachment on the north wall.',
    ));
    expect(task.inspectorNotes, 'Observed 0.3m encroachment on the north wall.');
    expect(task.assignmentInstructions, 'Check rear setback.');
    expect(task.assignmentInstructions, isNot(equals(task.inspectorNotes)));
  });

  // ── 7. null assignment_instructions does NOT expose inspector_notes ──────────

  test('null assignmentInstructions does not fall back to inspectorNotes', () {
    final task = TaskItem.fromJob(jobMap(
      assignmentInstructions: null,
      inspectorNotes: 'Site inspector findings are present here.',
    ));
    expect(task.assignmentInstructions, isNull);
  });

  test('empty-string assignmentInstructions is not replaced by inspectorNotes', () {
    final task = TaskItem.fromJob(
      jobMap(assignmentInstructions: '', inspectorNotes: 'Inspector findings.'),
    );
    expect(task.assignmentInstructions, '');
    expect(task.inspectorNotes, 'Inspector findings.');
  });

  // ── 8. fetchMyJobs select query includes assignment_instructions ─────────────

  test('supabase_service select query contains assignment_instructions column', () {
    final src = readSource('lib/core/services/supabase_service.dart');
    expect(
      src,
      contains('assignment_instructions'),
      reason: 'fetchMyJobs must select assignment_instructions',
    );
  });

  // ── 9. Outbox never writes assignment_instructions ───────────────────────────

  test('sync_outbox_service does not write assignment_instructions', () {
    final src = readSource('lib/core/services/sync_outbox_service.dart');
    expect(
      src,
      isNot(contains("'assignment_instructions'")),
      reason: 'FieldSync outbox must never write assignment_instructions',
    );
  });

  // ── 10. Lifecycle/category unaffected (Loop 1 regression guard) ──────────────

  group('lifecycle category unaffected by assignment_instructions', () {
    for (final entry in const {
      'assigned': 'pending',
      'in_progress': 'ongoing',
      'completed': 'completed',
    }.entries) {
      test('status ${entry.key} still maps to ${entry.value}', () {
        final task = TaskItem.fromJob(
          jobMap(status: entry.key, assignmentInstructions: 'Any instruction'),
        );
        expect(task.lifecycleCategory.name, entry.value);
      });
    }

    test('null assignmentInstructions does not alter pending lifecycle', () {
      final task = TaskItem.fromJob(
        jobMap(status: 'assigned', assignmentInstructions: null),
      );
      expect(task.lifecycleCategory, TaskLifecycleCategory.pending);
    });
  });
}
