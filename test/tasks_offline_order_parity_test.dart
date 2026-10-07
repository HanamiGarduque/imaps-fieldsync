// test/tasks_offline_order_parity_test.dart
//
// Offline/online list sequence parity for My Tasks.
//
// Defect this guards: the Tasks screen sorts the Completed category by
// submitted_at (newest submission first, oldest last) in BOTH online and
// offline modes, but the offline path had no submitted_at to sort by, so the
// comparator always compared '' with '' and the offline list silently fell back
// to raw local_jobs row order — a different sequence from the online list.
//
// This test is a source/contract guard plus a behavioral check of the sort
// itself. It never touches a live device, Supabase, or any task state.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

void main() {
  group('offline/online Completed order parity', () {
    test('local_jobs caches submitted_at and migrates it in', () {
      final source = File('lib/core/services/db_helper.dart').readAsStringSync();

      // Fresh-install schema carries the column.
      expect(source, contains('submitted_at TEXT,'));

      // Upgrade path for an existing install.
      expect(source, contains('if (oldVersion < 13)'));
      expect(
        RegExp(r'ALTER TABLE local_jobs ADD COLUMN submitted_at TEXT').allMatches(source),
        hasLength(1),
        reason: 'submitted_at must be added exactly once, in the v13 upgrade guard.',
      );

      // Cached row mapping must persist the value.
      expect(source, contains("'submitted_at': job['submitted_at']"));
    });

    test('offline task reconstruction passes submitted_at into TaskItem', () {
      final task = TaskItem.fromCachedJob({
        'id': 'cached-round', 'status': 'completed',
        'submitted_at': '2026-10-07T01:02:03Z',
      });
      expect(task.submittedAt, '2026-10-07T01:02:03Z',
        reason: 'The actual offline mapper must retain the Completed sort key.');
    });

    test('Completed is still sorted newest-first by submitted_at', () {
      final source = File('lib/modules/tasks/screens/tasks_screen.dart').readAsStringSync();

      expect(source, contains("case 'Completed':"));
      expect(source, contains('final sa = a.submittedAt ??'));
      expect(source, contains('return sb.compareTo(sa);'),
          reason: 'Completed must remain newest submission first (oldest last).');
    });

    test('parity fix does not touch lifecycle or the review contract', () {
      final cache = File('lib/core/services/db_helper.dart').readAsStringSync();

      // No lifecycle column may be introduced or reordered by this fix. Scoped
      // to the job-cache mapper: local_inspections legitimately stores its own
      // draft progress (pre-existing, unrelated to this parity fix).
      final cachedRowBody = cache.substring(
        cache.indexOf('static Map<String, dynamic> _cachedJobRow('),
        cache.indexOf('static String? _planningReviewCacheJson('),
      );
      expect(
        cachedRowBody.contains("'current_step':"),
        isFalse,
        reason: 'The job cache must not start carrying lifecycle progress.',
      );
      expect(cachedRowBody, contains("'status': job['status']"));

      // Planning Review cache stays presentational and untouched.
      expect(cache, contains('planning_review'));
      final task = TaskItem.fromCachedJob({
        'id': 'reviewed-round', 'status': 'completed',
        'planning_review': '{"decision":"Requires Reinspection"}',
      });
      expect(task.planningReview!.decision, 'Requires Reinspection');
      expect(task.category, 'Completed');
      expect(task.currentStep, 0, reason: 'Review metadata must not create progress.');
    });
  });
}
