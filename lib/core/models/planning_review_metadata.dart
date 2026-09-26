// lib/core/models/planning_review_metadata.dart
//
// Loop 8 — Planning Review Metadata (read-only).
//
// Carries the optional Planning Review outcome for the EXACT inspection round
// that was reviewed, as transported by iMAPS into `field_job_reviews`.
//
// Hard boundaries (Loop 8 contract):
//  - purely presentational. It never influences status, TaskItem category,
//    current_step, progress, completed state, reinspection state, photo evidence
//    or sync ACK state;
//  - it is never joined by reference number, application or parcel — only by the
//    exact field_job_id;
//  - a Completed task with no review row simply has NO metadata, and the UI
//    shows no section at all. Nothing is inferred, and "Awaiting Review" is
//    intentionally NOT part of this MVP.
import 'dart:convert';

class PlanningReviewMetadata {
  /// Canonical iMAPS decision, transported unchanged.
  final String decision;

  /// Reviewer display name (iMAPS Planning Officer), when available.
  final String? reviewedBy;

  /// When the review was recorded, transported unchanged.
  final String? reviewedAt;

  /// Source iMAPS identities, retained for correctness/debugging only. They are
  /// intentionally not promoted to prominent UI fields.
  final int? technicalReviewId;
  final int? reviewedSiteInspectionId;
  final String? fieldJobId;

  const PlanningReviewMetadata({
    required this.decision,
    this.reviewedBy,
    this.reviewedAt,
    this.technicalReviewId,
    this.reviewedSiteInspectionId,
    this.fieldJobId,
  });

  /// iMAPS decision vocabulary -> FieldSync presentation.
  ///
  /// "Needs Site Inspection" is deliberately absent: it is the INITIAL
  /// scheduling decision, has no reviewed round, and is never transported as a
  /// completed-round Planning Review.
  String get displayDecision {
    switch (decision) {
      case 'Approved':
        return 'Approved';
      case 'Declined':
        return 'Declined';
      case 'Requires Reinspection':
        return 'Reinspection Requested';
      default:
        return decision;
    }
  }

  /// Parse one `field_job_reviews` row as delivered by PostgREST.
  static PlanningReviewMetadata? fromRow(Map<String, dynamic> row) {
    final rawDecision = row['decision']?.toString().trim();
    if (rawDecision == null || rawDecision.isEmpty) {
      return null;
    }

    final reviewedBy = row['reviewed_by_name']?.toString().trim();

    return PlanningReviewMetadata(
      decision: rawDecision,
      reviewedBy: (reviewedBy != null && reviewedBy.isNotEmpty) ? reviewedBy : null,
      reviewedAt: row['reviewed_at']?.toString(),
      technicalReviewId: (row['technical_review_id'] as num?)?.toInt(),
      reviewedSiteInspectionId: (row['reviewed_site_inspection_id'] as num?)?.toInt(),
      fieldJobId: row['field_job_id']?.toString(),
    );
  }

  /// Resolve metadata from a job map that may carry either the online embed
  /// (`field_job_reviews`) or the offline cache column (`planning_review` JSON).
  static PlanningReviewMetadata? fromJobRow(Map<String, dynamic> job) {
    final embedded = job['field_job_reviews'];
    if (embedded is List && embedded.isNotEmpty) {
      final first = embedded.first;
      if (first is Map) {
        return fromRow(Map<String, dynamic>.from(first));
      }
    }

    final cached = job['planning_review'];
    if (cached is Map) {
      return fromRow(Map<String, dynamic>.from(cached));
    }
    if (cached is String && cached.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(cached);
        if (decoded is Map) {
          return fromRow(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {
        // A malformed cache value is treated as "no review metadata" — it must
        // never surface partial or invented review information.
        return null;
      }
    }

    return null;
  }

  /// Compact cache form, so previously synced metadata stays readable offline.
  Map<String, dynamic> toJson() => {
        'decision': decision,
        'reviewed_by_name': reviewedBy,
        'reviewed_at': reviewedAt,
        'technical_review_id': technicalReviewId,
        'reviewed_site_inspection_id': reviewedSiteInspectionId,
        'field_job_id': fieldJobId,
      };

  static PlanningReviewMetadata? fromJson(Map<String, dynamic> json) {
    return fromRow(json);
  }
}
