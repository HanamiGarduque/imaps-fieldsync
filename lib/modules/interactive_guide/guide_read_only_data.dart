import 'dart:convert';
import 'dart:math' as math;
import '../inspection/inspection_constants.dart';
import '../inspection/screens/inspection_progress.dart';
import 'guide_preferences.dart';

enum GuideDataSection { tasks, inspection, sync, storage }

/// Saved display values only. This object cannot start or save real work.
class GuideReadOnlyData {
  GuideReadOnlyData({
    required this.ownerId,
    required this.language,
    List<Map<String, dynamic>> jobs = const [],
    List<Map<String, dynamic>> submissions = const [],
    List<Map<String, dynamic>> photos = const [],
    List<Map<String, dynamic>> pendingActions = const [],
    List<Map<String, dynamic>> syncedActions = const [],
    Map<String, dynamic>? selectedJob,
    Map<String, dynamic>? draft,
    Map<String, dynamic>? findingsIntent,
    Map<String, dynamic>? routeRow,
    Map<String, dynamic>? gpsRow,
    Map<String, dynamic>? cacheStats,
    Set<GuideDataSection> unavailable = const {},
  }) : jobs = _rows(jobs),
       submissions = _rows(submissions),
       photos = _rows(photos),
       pendingActions = _rows(pendingActions),
       syncedActions = _rows(syncedActions),
       selectedJob = _row(selectedJob),
       draft = _row(draft),
       findingsIntent = _row(findingsIntent),
       routeRow = _row(routeRow),
       gpsRow = _row(gpsRow),
       cacheStats = _row(cacheStats),
       unavailable = Set.unmodifiable(unavailable);

  final String ownerId;
  final GuideLanguage language;
  final List<Map<String, dynamic>> jobs,
      submissions,
      photos,
      pendingActions,
      syncedActions;
  final Map<String, dynamic>? selectedJob,
      draft,
      findingsIntent,
      routeRow,
      gpsRow,
      cacheStats;
  final Set<GuideDataSection> unavailable;

  bool get hasRealTask => selectedJob != null;
  bool get inspectionUnavailable =>
      unavailable.contains(GuideDataSection.inspection);
  String get inspectionUnavailableLabel => language == GuideLanguage.tagalog
      ? 'Hindi mabasa ang naka-save na datos ng inspeksiyon'
      : 'Saved inspection data unavailable';
  bool get canShowTaskExample =>
      !unavailable.contains(GuideDataSection.tasks) && jobs.isEmpty;

  Map<String, dynamic> get _checklistDraft {
    try {
      return Map<String, dynamic>.from(
        jsonDecode(draft?['checklist_json'] as String? ?? '{}') as Map,
      );
    } catch (_) {
      return const {};
    }
  }

  Map<String, bool> get savedChecklist => {
    for (final row in selectedJob?['checklist_data'] as List? ?? const [])
      if (row is Map && row['item'] is String && row['checked'] is bool)
        row['item'] as String: row['checked'] as bool,
    for (final entry in _checklistDraft.entries)
      if (entry.value is bool) entry.key: entry.value as bool,
  };

  /// Project the selected inspection's saved components onto its normal detail
  /// model. Counters/metadata remain display-only; no active provider is loaded.
  Map<String, dynamic> get savedInspectionFields {
    final findings = savedFindings;
    final answers = {
      ...defaultSiteCondition,
      ...defaultZoningObservations,
      ...savedChecklist,
    };
    return {
      if (draft != null) ...{
        'current_step': math.max(
          (selectedJob?['current_step'] as num?)?.toInt() ?? 0,
          (draft!['current_step'] as num?)?.toInt() ?? 0,
        ),
        'step_timestamps': {
          if (selectedJob?['step_timestamps'] is Map)
            ...Map<String, dynamic>.from(
              selectedJob!['step_timestamps'] as Map,
            ),
          ...InspectionProgress.decodeStepTimestamps(
            draft!['step_timestamps'],
          ).map((step, time) => MapEntry(step.toString(), time)),
        },
      },
      if (draft != null || findingsIntent != null) ...{
        'inspector_notes': findings['notes'],
        'discrepancies': findings['discrepancies'],
        'recommendations': findings['recommendations'],
        'inspection_result': findings['inspectionResult'],
      },
      if (photos.isNotEmpty) ...{
        'photo_count': photos.length,
        'photo_paths': [for (final photo in photos) photo['photoPath']],
        'field_job_photos': [
          for (final photo in photos)
            {...photo, 'photo_url': photo['photoPath']},
        ],
      },
      if (savedChecklist.isNotEmpty) ...{
        'checklist_completed_count': answers.values
            .where((value) => value)
            .length,
        'checklist_total_count': answers.length,
        'checklist_data': [
          for (final entry in answers.entries)
            {'item': entry.key, 'checked': entry.value},
        ],
      },
      if (gpsRow != null) ...{
        'confirmed_latitude': gpsRow!['latitude'],
        'confirmed_longitude': gpsRow!['longitude'],
        'gps_accuracy_m': gpsRow!['accuracy_meters'],
        'gps_confirmed_at': gpsRow!['verified_at'],
      },
    };
  }

  /// Same saved-draft/intent precedence as normal inspection recovery, without
  /// hydrating (or otherwise changing) the inspector's active provider.
  Map<String, String> get savedFindings {
    final local = _checklistDraft['_draft_findings'];
    final findings = <String, String>{
      'notes':
          draft?['notes'] as String? ??
          selectedJob?['inspector_notes'] as String? ??
          '',
      'discrepancies': local is Map
          ? local['discrepancies'] as String? ?? ''
          : selectedJob?['discrepancies'] as String? ?? '',
      'recommendations': local is Map
          ? local['recommendations'] as String? ?? ''
          : selectedJob?['recommendations'] as String? ?? '',
      'inspectionResult':
          draft?['inspection_result'] as String? ??
          selectedJob?['inspection_result'] as String? ??
          '',
    };
    final queuedAt = DateTime.tryParse(
      findingsIntent?['localCreatedAt'] as String? ?? '',
    );
    final draftAt = DateTime.tryParse(draft?['updated_at'] as String? ?? '');
    if (findingsIntent != null &&
        (local is! Map ||
            (queuedAt != null &&
                draftAt != null &&
                queuedAt.isAfter(draftAt)))) {
      findings['notes'] =
          findingsIntent!['inspectorNotes'] as String? ?? findings['notes']!;
      findings['discrepancies'] =
          findingsIntent!['discrepancies'] as String? ?? '';
      findings['recommendations'] =
          findingsIntent!['recommendations'] as String? ?? '';
      findings['inspectionResult'] =
          findingsIntent!['inspectionResult'] as String? ??
          findings['inspectionResult']!;
    }
    return Map.unmodifiable(findings);
  }

  static Map<String, dynamic>? _row(Map<String, dynamic>? value) =>
      value == null ? null : Map.unmodifiable(value);
  static List<Map<String, dynamic>> _rows(List<Map<String, dynamic>> values) =>
      List.unmodifiable(
        values.map((value) => Map<String, dynamic>.unmodifiable(value)),
      );
}
