// Loop 3 Part 1 — Phase A–D contract tests (FieldSync side).
//
// Tests covering the FieldSync read-only contract for the Assigning Planning
// Officer fields (assigned_by_imaps_user_id, assigned_by_name).
//
// APPROVAL STATUS:
//   ✅  Tests 7–12 — implementable now (FieldSync read paths).
//   🚫  Tests 1–6 (iMAPS actor capture, persistence, push, retry) — BLOCKED
//       pending Team Leader approval for iMAPS Controller modification and
//       shared Supabase schema mutation. Reported as BLOCKED, not passed.
//
// Contract coverage (see canonical FIELDSYNC_BRIDGE_ARCHITECTURE.md):
//   Contract  7 — FieldSync reads assigned_by_imaps_user_id
//   Contract  8 — FieldSync reads assigned_by_name
//   Contract  9 — null assigned_by_name does not display Admin
//   Contract 10 — FieldSync writers never write assigned_by fields
//   Contract 11 — Loop 1 lifecycle/status unchanged
//   Contract 12 — Loop 2 assignment_instructions/inspector_notes unchanged
//
// All tests are pure in-process logic — no live Supabase calls.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

void main() {
  // ── shared helper ────────────────────────────────────────────────────────────

  Map<String, dynamic> jobMap({
    String? assignedByImapsUserId,
    String? assignedByName,
    String? assignmentInstructions,
    String? inspectorNotes,
    String status = 'assigned',
  }) {
    return {
      'id': 'job-loop3-001',
      'local_inspection_id': 42,
      'status': status,
      'scheduled_date': '2026-10-01',
      'deadline_date': null,
      'is_self_scheduled': false,
      'current_step': 0,
      'step_timestamps': null,
      'rework_started_at': null,
      'created_at': '2026-09-18T00:00:00.000Z',
      'updated_at': '2026-09-18T10:00:00.000Z',
      'started_at': null,
      'submitted_at': null,
      'supabase_parcel_id': 'parcel-loop3-001',
      'assignment_instructions': assignmentInstructions,
      'assigned_by_imaps_user_id': assignedByImapsUserId,
      'assigned_by_name': assignedByName,
      'inspector_notes': inspectorNotes,
      'supabase_zoning_applications': {
        'reference_number': 'REF-LOOP3-001',
        'applicant_name': 'Maria Santos',
        'barangay': 'Brgy. Poblacion A',
        'application_type': 'New Construction',
        'purpose': null,
        'contact_number': null,
        'email': null,
      },
      'supabase_parcels': {
        'lot_area_sqm': 200.0,
        'land_use_class': 'Commercial',
        'property_index_number': 'PIN-LOOP3-001',
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

  // ── BLOCKED (1–6): iMAPS Controller + shared schema — Team Leader approval required ──
  // Test 1 BLOCKED: Planning Officer user ID captured at assignment time.
  // Test 2 BLOCKED: Planning Officer name snapshot captured.
  // Test 3 BLOCKED: queue/retry uses persisted actor, not runtime auth().
  // ── 7. FieldSync reads assigned_by_imaps_user_id ────────────────────────────

  test('TaskItem.fromJob reads assigned_by_imaps_user_id from job map', () {
    final task = TaskItem.fromJob(jobMap(assignedByImapsUserId: '17'));
    expect(task.assignedByImapsUserId, '17');
  });

  test('TaskItem.fromJob sets assignedByImapsUserId to null when absent', () {
    final task = TaskItem.fromJob(jobMap(assignedByImapsUserId: null));
    expect(task.assignedByImapsUserId, isNull);
  });

  // ── 8. FieldSync reads assigned_by_name ─────────────────────────────────────

  test('TaskItem.fromJob reads assigned_by_name from job map', () {
    final task = TaskItem.fromJob(jobMap(assignedByName: 'Engr. Reyes'));
    expect(task.assignedByName, 'Engr. Reyes');
  });

  test('TaskItem.fromJob sets assignedByName to null when absent', () {
    final task = TaskItem.fromJob(jobMap(assignedByName: null));
    expect(task.assignedByName, isNull);
  });

  // ── 9. null assigned_by_name does NOT display Admin ─────────────────────────

  test('null assignedByName does not resolve to Admin', () {
    final task = TaskItem.fromJob(jobMap(assignedByName: null));
    expect(task.assignedByName, isNull);
    expect(task.assignedByName, isNot('Admin'));
  });

  test('empty assignedByName is not replaced with Admin', () {
    final task = TaskItem.fromJob(jobMap(assignedByName: ''));
    expect(task.assignedByName, '');
    expect(task.assignedByName, isNot('Admin'));
  });

  test('parcel_detail_screen guards assigned-by display; never hard-codes Admin', () {
    final src = readSource('lib/core/navigation/parcel_detail_screen.dart');
    expect(
      src,
      contains("task.assignedByName?.trim().isNotEmpty == true"),
      reason: 'Assigned-by card must guard on assignedByName?.trim().isNotEmpty',
    );
    expect(src, isNot(contains("'Admin'")),
        reason: 'parcel_detail_screen must not hard-code Admin as assigned-by');
  });

  test('completed_inspection_detail_screen guards assigned-by; never hard-codes Admin', () {
    final src = readSource(
        'lib/modules/inspection/screens/completed_inspection_detail_screen.dart');
    expect(
      src,
      contains("task.assignedByName?.trim().isNotEmpty == true"),
      reason: 'Assigned-by card must guard on assignedByName?.trim().isNotEmpty',
    );
    expect(src, isNot(contains("'Admin'")),
        reason: 'completed_inspection_detail_screen must not hard-code Admin');
  });

  // ── 10. FieldSync writers never write assigned_by fields ─────────────────────

  test('sync_outbox_service does not write assigned_by_imaps_user_id', () {
    final src = readSource('lib/core/services/sync_outbox_service.dart');
    expect(src, isNot(contains("'assigned_by_imaps_user_id'")));
    expect(src, isNot(contains('"assigned_by_imaps_user_id"')));
  });

  test('sync_outbox_service does not write assigned_by_name', () {
    final src = readSource('lib/core/services/sync_outbox_service.dart');
    expect(src, isNot(contains("'assigned_by_name'")));
    expect(src, isNot(contains('"assigned_by_name"')));
  });

  test('fetchMyJobs selects assigned_by_imaps_user_id and assigned_by_name', () {
    final src = readSource('lib/core/services/supabase_service.dart');
    expect(src, contains('assigned_by_imaps_user_id'),
        reason: 'fetchMyJobs must SELECT assigned_by_imaps_user_id');
    expect(src, contains('assigned_by_name'),
        reason: 'fetchMyJobs must SELECT assigned_by_name');
  });

  // ── 11. Loop 1 lifecycle/category unaffected ─────────────────────────────────

  group('Loop 1 lifecycle unaffected by Loop 3 fields', () {
    for (final entry in const {
      'assigned': 'pending',
      'in_progress': 'ongoing',
      'completed': 'completed',
    }.entries) {
      test('status ${entry.key} maps to ${entry.value} with assigned_by_name set', () {
        final task = TaskItem.fromJob(jobMap(
          status: entry.key,
          assignedByName: 'Engr. Reyes',
        ));
        expect(task.lifecycleCategory.name, entry.value);
      });
    }

    test('null assignedByName does not alter pending lifecycle', () {
      final task = TaskItem.fromJob(jobMap(status: 'assigned', assignedByName: null));
      expect(task.lifecycleCategory, TaskLifecycleCategory.pending);
    });
  });

  // ── 12. Loop 2 ownership unchanged ───────────────────────────────────────────

  test('assignmentInstructions, assignedByName, inspectorNotes are independently parsed', () {
    final task = TaskItem.fromJob(jobMap(
      assignmentInstructions: 'Verify left boundary.',
      assignedByName: 'Engr. Reyes',
      inspectorNotes: 'Inspector field note.',
    ));
    expect(task.assignmentInstructions, 'Verify left boundary.');
    expect(task.assignedByName, 'Engr. Reyes');
    expect(task.inspectorNotes, 'Inspector field note.');
    expect(task.assignmentInstructions, isNot(equals(task.inspectorNotes)));
    expect(task.assignedByName, isNot(equals(task.inspectorNotes)));
  });

  test('null assignmentInstructions does not affect assignedByName', () {
    final task = TaskItem.fromJob(
        jobMap(assignmentInstructions: null, assignedByName: 'Engr. Reyes'));
    expect(task.assignmentInstructions, isNull);
    expect(task.assignedByName, 'Engr. Reyes');
  });

  // Loop 2 regression guard: assignment_instructions still selected
  test('fetchMyJobs still selects assignment_instructions (Loop 2 regression)', () {
    final src = readSource('lib/core/services/supabase_service.dart');
    expect(src, contains('assignment_instructions'),
        reason: 'fetchMyJobs must still select assignment_instructions');
  });

  // Test 4 BLOCKED: no Admin fallback in iMAPS persistence or push.
  // Test 5 BLOCKED: iMAPS payload includes assigned_by_imaps_user_id.
  // Test 6 BLOCKED: iMAPS payload includes assigned_by_name.
  // ────────────────────────────────────────────────────────────────────────────
}
