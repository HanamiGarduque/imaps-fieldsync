import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/models/task_submission.dart';

TaskSubmission submission(String state) => TaskSubmission.fromRow({
  'id': 'fixture-submit',
  'type': 'submit_inspection',
  'job_id': 'fixture-job',
  'inspector_id': 'fixture-inspector',
  'created_at': '2026-10-22T08:00:00Z',
  'status': state,
  'payload': jsonEncode({
    'findings': 'Fictional findings',
    'isCompliant': true,
    'inspectionResult': 'Compliant',
    'checklistData': const [],
    'checklistCompletedCount': 0,
    'checklistTotalCount': 0,
    'photosData': const [],
  }),
});

void main() {
  test('a verified server receipt is the only Synced badge', () {
    expect(
      TaskSubmission.badgeOrUnverified(
        submission('synced'),
        canonicalCompleted: true,
      ),
      'Completed — Synced',
    );
  });

  test('a local submission awaiting delivery stays on Device', () {
    expect(
      TaskSubmission.badgeOrUnverified(
        submission('pending'),
        canonicalCompleted: true,
      ),
      'Completed on Device — Pending Sync',
    );
  });

  test('a paused local submission is not presented as accepted', () {
    expect(
      TaskSubmission.badgeOrUnverified(
        submission('paused'),
        canonicalCompleted: true,
      ),
      'Completed on Device — Sync Paused',
    );
  });

  test('a failed local submission is not presented as accepted', () {
    expect(
      TaskSubmission.badgeOrUnverified(
        submission('failed'),
        canonicalCompleted: true,
      ),
      'Completed on Device — Sync Failed',
    );
  });

  test('a completed task without a readable receipt is Unverified', () {
    expect(
      TaskSubmission.badgeOrUnverified(null, canonicalCompleted: true),
      'Completed — Sync Unverified',
    );
    expect(TaskSubmission.syncUnverifiedBadge, 'Completed — Sync Unverified');
  });

  test('a synced receipt on a non-canonical completion is still unverified', () {
    expect(
      TaskSubmission.badgeOrUnverified(
        submission('synced'),
        canonicalCompleted: false,
      ),
      'Completed on Device — Acceptance Unverified',
    );
  });

  test('an unknown receipt state never claims acceptance', () {
    expect(
      TaskSubmission.badgeOrUnverified(
        submission('syncing'),
        canonicalCompleted: true,
      ),
      'Completed on Device — Syncing',
    );
  });
}
