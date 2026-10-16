import 'dart:convert';

/// Presentation of a final-submit row read from owner-scoped SQLite.
/// This is never a field_jobs lifecycle value or permission to replay a write.
class TaskSubmission {
  final String actionId;
  final String jobId;
  final String inspectorId;
  final String savedAt;
  final String state;
  final Map<String, dynamic> payload;

  TaskSubmission.fromRow(Map<String, dynamic> row)
      : actionId = row['id'] as String,
        jobId = row['job_id'] as String,
        inspectorId = row['inspector_id'] as String,
        savedAt = row['created_at'] as String,
        state = row['status'] as String,
        payload = Map<String, dynamic>.unmodifiable(
            jsonDecode(row['payload'] as String) as Map<String, dynamic>) {
    if (row['type'] != 'submit_inspection' || actionId.isEmpty ||
        jobId.isEmpty || inspectorId.isEmpty || DateTime.tryParse(savedAt) == null ||
        !const {'pending', 'syncing', 'paused', 'failed', 'conflict', 'synced'}.contains(state) ||
        payload['findings'] is! String || payload['isCompliant'] is! bool ||
        payload['inspectionResult'] is! String || payload['checklistData'] is! List ||
        payload['checklistCompletedCount'] is! int || payload['checklistTotalCount'] is! int ||
        (payload['photosData'] is! List && payload['localPhotoPaths'] is! List)) {
      throw const FormatException('Saved final submission is unreadable');
    }
  }

  bool get isSynced => state == 'synced';

  String badge({required bool canonicalCompleted}) {
    if (isSynced && canonicalCompleted) return 'Completed — Synced';
    final label = switch (state) {
      'pending' => 'Pending Sync',
      'syncing' => 'Syncing',
      'paused' => 'Sync Paused',
      'failed' => 'Sync Failed',
      'conflict' => 'Review Required',
      _ => 'Acceptance Unverified',
    };
    return 'Completed on Device — $label';
  }

  /// Only saved evidence is overlaid. Status, round identity and server
  /// submitted_at remain the cached job's values, never invented here.
  Map<String, dynamic> get evidenceFields {
    final photos = payload['photosData'] as List? ?? [
      for (final path in payload['localPhotoPaths'] as List) {'photoPath': path},
    ];
    return {
      'findings': payload['findings'], 'is_compliant': payload['isCompliant'],
      'inspection_result': payload['inspectionResult'],
      'observations': payload['observations'], 'discrepancies': payload['discrepancies'],
      'recommendations': payload['recommendations'], 'inspector_notes': payload['inspectorNotes'],
      'checklist_data': payload['checklistData'],
      'checklist_completed_count': payload['checklistCompletedCount'],
      'checklist_total_count': payload['checklistTotalCount'],
      'photo_count': photos.length,
      'field_job_photos': [for (final photo in photos) {
        'photo_url': photo['photoPath'], 'notes': photo['notes'],
        'latitude': photo['latitude'], 'longitude': photo['longitude'],
        'captured_at': photo['capturedAt'],
      }],
    };
  }
}
