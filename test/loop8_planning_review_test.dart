// test/loop8_planning_review_test.dart
//
// Loop 8 — Planning Review Metadata (read-only, round-safe).
//
// Covers the Loop 8 contract without touching any live fixture, remote job,
// or task lifecycle state. APP-2026-00026 is modeled synthetically only:
// inspection 36 completed and reviewed -> Requires Reinspection -> a separate
// new inspection 37, with review metadata attached to 36 and never to 37.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/models/planning_review_metadata.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

/// Synthetic job maps mirroring the shape the live PostgREST query returns.
Map<String, dynamic> jobWithReview({
  required String id,
  required int localInspectionId,
  String status = 'completed',
  int currentStep = 6,
  List<Map<String, dynamic>>? reviews,
}) {
  final job = <String, dynamic>{
    'id': id,
    'local_inspection_id': localInspectionId,
    'status': status,
    'current_step': currentStep,
    'submitted_at': '2026-09-22T11:38:54.944788+00:00',
    'inspection_result': 'Requires Reinspection',
    'is_compliant': false,
    'checklist_completed_count': 3,
    'checklist_total_count': 5,
    'photo_count': 0,
    'field_job_photos': <Map<String, dynamic>>[],
  };
  if (reviews != null) {
    job['field_job_reviews'] = reviews;
  }
  return job;
}

Map<String, dynamic> reviewRow({
  int technicalReviewId = 76,
  int reviewedSiteInspectionId = 36,
  String decision = 'Requires Reinspection',
  String? reviewedByName = 'Jyerine Desunia',
  String reviewedAt = '2026-09-22T21:47:57+00:00',
  String fieldJobId = 'job-36',
}) {
  return {
    'id': 'review-row-1',
    'technical_review_id': technicalReviewId,
    'reviewed_site_inspection_id': reviewedSiteInspectionId,
    'decision': decision,
    'reviewed_by': 4,
    'reviewed_by_name': reviewedByName,
    'reviewed_at': reviewedAt,
    'field_job_id': fieldJobId,
  };
}

void main() {
  group('Loop 8 — review identity and presentation', () {
    test('approved review displays as Approved', () {
      final review = PlanningReviewMetadata.fromRow(reviewRow(decision: 'Approved'));
      expect(review, isNotNull);
      expect(review!.displayDecision, 'Approved');
    });

    test('declined review displays as Declined', () {
      final review = PlanningReviewMetadata.fromRow(reviewRow(decision: 'Declined'));
      expect(review!.displayDecision, 'Declined');
    });

    test('Requires Reinspection displays as Reinspection Requested', () {
      final review = PlanningReviewMetadata.fromRow(reviewRow());
      expect(review!.displayDecision, 'Reinspection Requested');
    });

    test('initial Needs Site Inspection is never presented as a completed-round review', () {
      // The transport CHECK excludes it, but the presentation layer must not
      // invent a Completed-round Planning Review if such a value ever arrives.
      final review = PlanningReviewMetadata.fromRow(reviewRow(decision: 'Needs Site Inspection'));
      expect(review!.displayDecision, 'Needs Site Inspection');
      expect(review.displayDecision, isNot('Reinspection Requested'));
    });

    test('reviewer and reviewed_at are carried through', () {
      final review = PlanningReviewMetadata.fromRow(reviewRow())!;
      expect(review.reviewedBy, 'Jyerine Desunia');
      expect(review.reviewedAt, '2026-09-22T21:47:57+00:00');
      // Source identities are retained internally, not promoted to UI.
      expect(review.technicalReviewId, 76);
      expect(review.reviewedSiteInspectionId, 36);
    });

    test('missing metadata resolves to null so the section is hidden', () {
      final job = jobWithReview(id: 'job-36', localInspectionId: 36);
      final item = TaskItem.fromJob(job);
      expect(item.planningReview, isNull);
    });

    test('a row without a decision is ignored', () {
      final review = PlanningReviewMetadata.fromRow({'decision': '  ', 'reviewed_at': 'x'});
      expect(review, isNull);
    });
  });

  group('Loop 8 — round isolation (the key regression guard)', () {
    test('review metadata attaches ONLY to the reviewed round (36), not the new round (37)', () {
      // Round 1 / inspected job 36: completed, reviewed -> Requires Reinspection.
      final job36 = TaskItem.fromJob(jobWithReview(
        id: 'job-36',
        localInspectionId: 36,
        reviews: [reviewRow(fieldJobId: 'job-36')],
      ));

      // Round 2 / new job 37: created by the review decision, no review row.
      final job37 = TaskItem.fromJob(jobWithReview(
        id: 'job-37',
        localInspectionId: 37,
        status: 'assigned',
        currentStep: 0,
        reviews: const <Map<String, dynamic>>[],
      ));

      expect(job36.planningReview, isNotNull);
      expect(job36.planningReview!.reviewedSiteInspectionId, 36);

      // The new reinspection round must not inherit the previous round's review.
      expect(job37.planningReview, isNull);
    });

    test('reviewed round 36 stays Completed and progress is untouched', () {
      final job36 = TaskItem.fromJob(jobWithReview(
        id: 'job-36',
        localInspectionId: 36,
        reviews: [reviewRow(fieldJobId: 'job-36')],
      ));

      // A review requesting reinspection does NOT reopen the reviewed task.
      expect(job36.status, 'completed');
      expect(job36.currentStep, 6);
      expect(job36.checklistCompletedCount, 3);
      expect(job36.checklistTotalCount, 5);
      expect(job36.submittedAt, isNotNull);
    });

    test('new reinspection round keeps its own independent lifecycle', () {
      final job37 = TaskItem.fromJob(jobWithReview(
        id: 'job-37',
        localInspectionId: 37,
        status: 'in_progress',
        currentStep: 1,
        reviews: const <Map<String, dynamic>>[],
      ));

      expect(job37.status, 'in_progress');
      expect(job37.currentStep, 1);
      expect(job37.planningReview, isNull);
    });

    test('review metadata does not change status, category or current_step', () {
      final withoutReview = TaskItem.fromJob(
          jobWithReview(id: 'job-36', localInspectionId: 36));
      final withReview = TaskItem.fromJob(jobWithReview(
        id: 'job-36',
        localInspectionId: 36,
        reviews: [reviewRow(fieldJobId: 'job-36')],
      ));

      expect(withReview.status, withoutReview.status);
      expect(withReview.currentStep, withoutReview.currentStep);
      expect(withReview.category, withoutReview.category);
      expect(withReview.photoCount, withoutReview.photoCount);
      expect(withReview.submittedAt, withoutReview.submittedAt);
    });
  });

  group('Loop 8 — offline cache is presentational only', () {
    test('cached JSON metadata resolves after a simulated offline load', () {
      final cachedJson = jsonEncode(PlanningReviewMetadata.fromRow(reviewRow())!.toJson());
      final job = jobWithReview(id: 'job-36', localInspectionId: 36);
      job['planning_review'] = cachedJson;

      final item = TaskItem.fromJob(job);
      expect(item.planningReview, isNotNull);
      expect(item.planningReview!.displayDecision, 'Reinspection Requested');
      expect(item.planningReview!.reviewedBy, 'Jyerine Desunia');
    });

    test('malformed cached JSON hides the section instead of inventing data', () {
      final job = jobWithReview(id: 'job-36', localInspectionId: 36);
      job['planning_review'] = 'not-json{';
      expect(TaskItem.fromJob(job).planningReview, isNull);
    });

    test('empty cached review list keeps the section hidden', () {
      final job = jobWithReview(id: 'job-36', localInspectionId: 36);
      job['planning_review'] = jsonEncode({'decision': ''});
      expect(TaskItem.fromJob(job).planningReview, isNull);
    });
  });
}
