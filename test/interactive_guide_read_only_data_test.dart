import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_data_loader.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_preferences.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_read_only_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/offline_reliability_fixture.dart';

void main() {
  final fixture = OfflineReliabilityFixture();
  setUpAll(fixture.initialize);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await fixture.reset();
  });
  tearDown(() async {
    DBHelper.inspectorIdForTesting = null;
    await fixture.closeCase();
  });
  tearDownAll(fixture.dispose);

  test(
    'snapshot prefers the selected owned job without changing real work',
    () async {
      final before = await fixture.guideSafetySnapshot();
      final data = await loadGuideReadOnlyData(
        ownerId: offlineInspector,
        language: GuideLanguage.tagalog,
        preferredTaskId: offlineRound2,
      );
      expect(data.selectedJob?['id'], offlineRound2);
      expect(data.language, GuideLanguage.tagalog);
      expect(data.hasRealTask, isTrue);
      expect(data.canShowTaskExample, isFalse);
      expect(data.unavailable, isEmpty);
      expect(await fixture.guideSafetySnapshot(), before);
      expect(fixture.requests, isEmpty);
      expect(() => data.jobs.add({}), throwsUnsupportedError);
      expect(
        () => data.jobs.first['status'] = 'tampered',
        throwsUnsupportedError,
      );
    },
  );

  test(
    'snapshot falls back to the first owned job, never a foreign selection',
    () async {
      await fixture.db.insert('local_jobs', {
        'id': 'foreign-job',
        'inspector_id': otherOfflineInspector,
        'status': 'assigned',
      });
      final data = await loadGuideReadOnlyData(
        ownerId: offlineInspector,
        language: GuideLanguage.english,
        preferredTaskId: 'foreign-job',
      );
      expect(data.selectedJob?['id'], offlineJob);
      expect(data.jobs.map((row) => row['id']), [offlineJob, offlineRound2]);
      expect(
        data.jobs.every((row) => row['inspector_id'] == offlineInspector),
        isTrue,
      );
    },
  );

  test(
    'snapshot keeps saved evidence values and excludes another owner photos',
    () async {
      await fixture.db.insert('local_inspections', {
        'id': offlineJob,
        'inspector_id': offlineInspector,
        'notes': 'Existing saved finding',
      });
      await fixture.db.insert('local_photos', {
        'id': 'saved-photo',
        'job_id': offlineJob,
        'inspector_id': offlineInspector,
        'photo_path': 'saved-camera.png',
        'notes': 'Existing saved evidence',
        'captured_at': '2026-11-02T00:00:00Z',
      });
      await fixture.db.insert('local_photos', {
        'id': 'foreign-photo',
        'job_id': offlineJob,
        'inspector_id': otherOfflineInspector,
        'photo_path': 'foreign-camera.png',
      });
      final before = await fixture.guideSafetySnapshot();
      final data = await loadGuideReadOnlyData(
        ownerId: offlineInspector,
        language: GuideLanguage.english,
        preferredTaskId: offlineJob,
      );
      expect(data.photos, hasLength(1));
      expect(data.photos.single['photoPath'], 'saved-camera.png');
      expect(data.photos.single['notes'], 'Existing saved evidence');
      expect(data.draft?['id'], offlineJob);
      expect(data.draft?['notes'], 'Existing saved finding');
      expect(await fixture.guideSafetySnapshot(), before);
    },
  );

  test('only a confirmed empty snapshot permits an example', () async {
    await fixture.db.delete('local_jobs');
    final data = await loadGuideReadOnlyData(
      ownerId: offlineInspector,
      language: GuideLanguage.english,
    );
    expect(data.jobs, isEmpty);
    expect(data.selectedJob, isNull);
    expect(data.canShowTaskExample, isTrue);
    expect(data.unavailable, isEmpty);
  });

  test(
    'unreadable saved data never becomes an empty account example',
    () async {
      await fixture.db.execute(
        'ALTER TABLE local_jobs RENAME TO unreadable_jobs',
      );
      final data = await loadGuideReadOnlyData(
        ownerId: offlineInspector,
        language: GuideLanguage.english,
      );
      expect(data.unavailable, contains(GuideDataSection.tasks));
      expect(data.canShowTaskExample, isFalse);
    },
  );

  test('snapshot rejects an owner change across reads', () async {
    final pending = loadGuideReadOnlyData(
      ownerId: offlineInspector,
      language: GuideLanguage.english,
    );
    DBHelper.inspectorIdForTesting = otherOfflineInspector;
    await expectLater(pending, throwsStateError);
  });
}
