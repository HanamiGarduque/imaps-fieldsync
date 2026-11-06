import '../../core/services/db_helper.dart';
import 'guide_preferences.dart';
import 'guide_read_only_data.dart';

Future<GuideReadOnlyData> loadGuideReadOnlyData({
  required String ownerId,
  required GuideLanguage language,
  String? preferredTaskId,
}) async {
  if (DBHelper.requireInspector() != ownerId) {
    throw StateError('Inspector session changed');
  }
  final unavailable = <GuideDataSection>{};
  Future<T?> read<T>(
    GuideDataSection section,
    Future<T?> Function() action,
  ) async {
    DBHelper.requireSameInspector(ownerId);
    try {
      final value = await action();
      DBHelper.requireSameInspector(ownerId);
      return value;
    } catch (_) {
      // A retired owner is not a recoverable empty/unavailable data section.
      DBHelper.requireSameInspector(ownerId);
      unavailable.add(section);
      return null;
    }
  }

  final snapshot = await read(
    GuideDataSection.tasks,
    DBHelper.getTaskPresentationSnapshot,
  );
  final rawJobs = snapshot?.jobs ?? <Map<String, dynamic>>[];
  final jobs = rawJobs
      .where(
        (row) =>
            row['inspector_id'] == ownerId &&
            row['id'] is String &&
            (row['id'] as String).isNotEmpty,
      )
      .toList();
  if (jobs.length != rawJobs.length) unavailable.add(GuideDataSection.tasks);
  Map<String, dynamic>? selected;
  for (final job in jobs) {
    selected ??= job;
    if (job['id'] == preferredTaskId) {
      selected = job;
      break;
    }
  }
  final pending = await read(
    GuideDataSection.sync,
    DBHelper.getSyncCenterQueueActions,
  );
  final synced = await read(
    GuideDataSection.sync,
    () => DBHelper.getRecentSyncedActions(limit: 20),
  );
  final cacheStats = await read(
    GuideDataSection.storage,
    DBHelper.getCacheStats,
  );
  Map<String, dynamic>? draft, findings, routeRow, gpsRow;
  var photos = <Map<String, dynamic>>[];
  if (selected != null) {
    final id = selected['id'] as String;
    draft = await read(
      GuideDataSection.inspection,
      () => DBHelper.getLocalInspection(id),
    );
    findings = await read(
      GuideDataSection.inspection,
      () => DBHelper.getLocalFindingsIntent(id),
    );
    final savedPhotos = await read(
      GuideDataSection.inspection,
      () => DBHelper.getLocalPhotos(id),
    );
    photos = [
      for (final row in savedPhotos ?? <Map<String, dynamic>>[])
        {
          ...row,
          'photoPath': row['photo_path'],
          'capturedAt': row['captured_at'],
        },
    ];
    final route = await read(
      GuideDataSection.inspection,
      () => DBHelper.getRouteCache(id),
    );
    routeRow = route?.toRow();
    gpsRow = await read(
      GuideDataSection.inspection,
      () => DBHelper.getGpsVerification(id),
    );
  }
  DBHelper.requireSameInspector(ownerId);
  if (selected == null && unavailable.contains(GuideDataSection.tasks)) {
    unavailable.add(GuideDataSection.inspection);
  }
  return GuideReadOnlyData(
    ownerId: ownerId,
    language: language,
    jobs: jobs,
    submissions: snapshot?.submissions ?? const [],
    selectedJob: selected,
    draft: draft,
    findingsIntent: findings,
    photos: photos,
    routeRow: routeRow,
    gpsRow: gpsRow,
    pendingActions: pending ?? const [],
    syncedActions: synced ?? const [],
    cacheStats: cacheStats,
    unavailable: unavailable,
  );
}
