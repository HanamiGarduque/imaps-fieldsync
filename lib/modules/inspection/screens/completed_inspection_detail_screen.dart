import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../tasks/screens/tasks_screen.dart'; // TaskItem
import '../../../core/models/task_submission.dart';
import '../../../core/services/db_helper.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/sync_outbox_service.dart';
import '../../../core/widgets/offline_banner.dart';
import '../providers/inspection_provider.dart';
import 'inspection_progress.dart';
import '../../../core/theme/insight_theme.dart';

import 'site_map_screen.dart';
import 'gps_verification_screen.dart';
import 'inspection_checklist_screen.dart';
import 'capture_photo_screen.dart';
import 'field_findings_screen.dart';
import 'review_submit_screen.dart';
import '../../../core/widgets/imaps_loading_indicator.dart';
import '../../../core/widgets/sensitive_screen.dart';
import '../widgets/photo_viewer.dart';

/// Test-only seam for the Completed summary's remote detail fetch.
///
/// When set, it replaces `SupabaseService.fetchJobDetail` so the cached
/// fallback can be exercised deterministically without a network. Production
/// always runs the real service path; this is never assigned at runtime.
typedef CompletedDetailFetcher =
    Future<Map<String, dynamic>?> Function(String jobId);
CompletedDetailFetcher? completedDetailFetcherOverride;

class CompletedInspectionDetailScreen extends StatefulWidget {
  final TaskItem task;
  final bool historicalReadOnly;
  final TaskSubmission? submission;
  const CompletedInspectionDetailScreen({
    super.key,
    required this.task,
    this.historicalReadOnly = false,
    this.submission,
  });

  @override
  State<CompletedInspectionDetailScreen> createState() =>
      _CompletedInspectionDetailScreenState();
}

class _CompletedInspectionDetailScreenState
    extends State<CompletedInspectionDetailScreen> {
  TaskItem? _fullTask;
  bool _isLoading = true;
  String? _error;
  TaskSubmission? _submission;
  StreamSubscription<AuthState>? _authSubscription;
  int _detailRequestId = 0;
  bool _retired = false;
  bool get _savedSubmissionMode => widget.submission != null;
  bool get _awaitingAcceptance =>
      _submission?.isSynced == false || _fullTask?.category != 'Completed';
  bool get _readOnly =>
      _savedSubmissionMode ||
      widget.historicalReadOnly ||
      widget.task.planningReview?.decision == 'Requires Reinspection' ||
      _fullTask?.planningReview?.decision == 'Requires Reinspection';

  /// True when the full remote detail is unavailable and the already-cached
  /// task handed in by the caller is being shown instead. This is a read-only
  /// degradation: nothing is fetched, invented, or persisted, and no status,
  /// category or step value is ever changed by viewing.
  bool _isCachedFallback = false;

  /// A refresh that failed while the device still had connectivity. The saved
  /// data is still shown, but the failure stays visible so a genuine backend
  /// problem is never silently presented as a normal offline view.
  bool _refreshFailedWhileOnline = false;

  @override
  void initState() {
    super.initState();
    if (_savedSubmissionMode) {
      _authSubscription = SupabaseService.client.auth.onAuthStateChange.listen(
        (_) => _retireIfOwnerChanged(),
        onError: (Object _) => _retireIfOwnerChanged(),
      );
      SyncOutboxService.drainCompleted.addListener(_loadFullDetail);
      SyncOutboxService.progress.addListener(_loadFullDetail);
    }
    _loadFullDetail();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    SyncOutboxService.drainCompleted.removeListener(_loadFullDetail);
    SyncOutboxService.progress.removeListener(_loadFullDetail);
    super.dispose();
  }

  bool _retireIfOwnerChanged() {
    if (!_savedSubmissionMode) return false;
    if (!_retired &&
        DBHelper.currentInspectorId == widget.submission!.inspectorId) {
      return false;
    }
    if (mounted) {
      setState(() {
        _retired = true;
        _fullTask = null;
        _submission = null;
        _isLoading = false;
        _error = SavedDataNotice.ownerChanged;
      });
    }
    return true;
  }

  /// A pending final submission is an immutable saved snapshot, not a rework
  /// session. Re-read SQLite so a stale route/provider/remote response cannot
  /// substitute different evidence or manufacture acceptance.
  Future<void> _loadSavedSubmission() async {
    final requestId = ++_detailRequestId;
    if (_retireIfOwnerChanged()) return;
    try {
      final snapshot = await DBHelper.getTaskPresentationSnapshot();
      final row = snapshot.jobs.singleWhere((r) => r['id'] == widget.task.id);
      final actions = snapshot.submissions.where(
        (r) => r['job_id'] == widget.task.id,
      );
      final submission = actions.isEmpty
          ? null
          : TaskSubmission.fromRow(actions.first);
      final task = TaskItem.fromCachedJob({
        ...row,
        ...?submission?.evidenceFields,
      });
      if (submission == null && task.category != 'Completed') {
        throw StateError('Saved final submission is unavailable');
      }
      if (!mounted ||
          requestId != _detailRequestId ||
          _retireIfOwnerChanged()) {
        return;
      }
      setState(() {
        _fullTask = task;
        _submission = submission;
        _isLoading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted ||
          requestId != _detailRequestId ||
          _retireIfOwnerChanged()) {
        return;
      }
      setState(() {
        _fullTask = null;
        _isLoading = false;
        _error =
            'Could not read the saved submission. Try again from My Tasks.';
      });
    }
  }

  Future<void> _loadFullDetail() async {
    if (_savedSubmissionMode) return _loadSavedSubmission();
    Map<String, dynamic>? job;
    Object? failure;

    try {
      final override = completedDetailFetcherOverride;
      job = override != null
          ? await override(widget.task.id)
          : await SupabaseService.fetchJobDetail(widget.task.id);
    } catch (e) {
      failure = e;
    }

    // Remote-first: a successful fetch always wins.
    if (job != null) {
      if (!mounted) return;
      setState(() {
        _fullTask = TaskItem.fromJob(job!);
        _isLoading = false;
        _error = null;
        _isCachedFallback = false;
        _refreshFailedWhileOnline = false;
      });
      return;
    }

    await _applyCachedFallback(failure);
  }

  /// Fallback contract: a Completed task is already listed from the local
  /// cache, so opening its summary must still work when the full remote detail
  /// cannot be fetched. Only data that is genuinely cached is displayed; no
  /// field is invented, no lifecycle value is altered, and nothing is written.
  Future<void> _applyCachedFallback(Object? failure) async {
    final cached = widget.task;
    final hasCachedTask =
        cached.id.isNotEmpty && (cached.status?.isNotEmpty ?? false);

    // Case B: neither a remote detail nor a usable cached task. Keep the
    // existing safe error state.
    if (!hasCachedTask) {
      if (!mounted) return;
      setState(() {
        _error = failure == null
            ? 'Could not load this inspection.'
            : 'Failed to load: $failure';
        _isLoading = false;
      });
      return;
    }

    // Connectivity only refines the wording of an already-decided fallback; it
    // must never gate rendering, so it is bounded and treated as unknown.
    final online = await _hasConnectivity().timeout(
      const Duration(milliseconds: 500),
      onTimeout: () => false,
    );

    if (!mounted) return;
    setState(() {
      _fullTask = cached;
      _isLoading = false;
      _error = null;
      _isCachedFallback = true;
      _refreshFailedWhileOnline = online;
    });
  }

  /// Smallest existing connectivity pattern in the app. An unknown result is
  /// treated as not-online, so a failure is never labelled a normal offline
  /// view and a real backend error is never hidden as one.
  Future<bool> _hasConnectivity() async {
    try {
      final dynamic result = await Connectivity().checkConnectivity();
      return result is ConnectivityResult
          ? result != ConnectivityResult.none
          : (result as List).any((s) => s != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  Future<void> _reworkStep(int step) async {
    if (_readOnly) return;
    final task = _fullTask;
    if (task == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: InsightTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Rework this step?',
          style: InsightTheme.poppins(18, w: FontWeight.w600),
        ),
        content: Text(
          'Only "${InspectionProgress.stepTitles[step - 1]}" needs to be '
          'redone. The rest of the submitted inspection stays as-is until '
          'you resubmit.',
          style: InsightTheme.inter(14, c: InsightTheme.ink2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: InsightTheme.inter(
                14,
                w: FontWeight.w600,
                c: InsightTheme.ink3,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: InsightTheme.blue1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Rework',
              style: InsightTheme.inter(
                14,
                w: FontWeight.w600,
                c: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || _readOnly) return;

    HapticFeedback.mediumImpact();

    try {
      await SupabaseService.reopenForRework(
        jobId: task.id,
        locationLabel: task.location,
      );

      // FIXED: Moved mounted check above the context usage across the async gap
      if (!mounted) return;

      final inspectionProvider = context.read<InspectionProvider>();
      inspectionProvider.hydrateForRework(task);
      await inspectionProvider.restoreStructuredChecklist();
      await inspectionProvider.restorePendingFindings();
      if (!mounted) return;
      InspectionProgress.instance.unlockAllForReview(
        task.id,
        label: task.location,
      );

      _navigateToStep(step, task);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not reopen: $e')));
    }
  }

  void _navigateToStep(int step, TaskItem task) {
    if (_readOnly) return;
    final Widget target;
    switch (step) {
      case 1:
        // Issue 1 fix (Completed Category enhancement, reported by user):
        // ParcelDetailScreen is NOT the Site Verification step — it's the
        // general task-overview/landing hub shown before an inspection is
        // even started (hardcoded title 'Task Overview', read-only
        // application info + the 6-step list). The actual Site
        // Verification screen is SiteMapScreen (see its own doc comment:
        // "Site Verification (Step 1)"). Reworking Step 1 was silently
        // landing on the wrong screen entirely.
        target = SiteMapScreen(task: task);
        break;
      case 2:
        target = GpsVerificationScreen(task: task);
        break;
      case 3:
        target = CapturePhotoScreen(task: task);
        break;
      case 4:
        target = InspectionChecklistScreen(task: task);
        break;
      case 5:
        target = FieldFindingsScreen(task: task);
        break;
      default:
        target = ReviewSubmitScreen(task: task);
    }
    // Enhancement (Inspection Summary, 2026-07): re-fetch when control
    // returns from the step screen, so an edit saved during rework shows
    // up in the summary immediately without the inspector having to back
    // out of this screen and reopen it. A Field Findings Save is already
    // persisted by the time Navigator pops back here — this call just
    // reflects it. Leaving that step WITHOUT pressing Save persists nothing;
    // that text is shown from _draftFindings instead, so the summary never
    // claims unsaved evidence is on file.
    Navigator.push(context, MaterialPageRoute(builder: (_) => target)).then((
      _,
    ) {
      if (mounted) _loadFullDetail();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SensitiveScreen(
      child: Scaffold(
        backgroundColor: InsightTheme.bg,
        appBar: AppBar(
          backgroundColor: InsightTheme.surface,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          iconTheme: const IconThemeData(color: InsightTheme.ink),
          title: Text(
            'Inspection Summary',
            style: InsightTheme.poppins(16, w: FontWeight.w600),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1.0),
            child: Container(color: InsightTheme.line, height: 1.0),
          ),
        ),
        body: _isLoading
            ? const Center(child: ImapsLoadingIndicator(size: 60))
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _error!,
                    style: InsightTheme.inter(14, c: InsightTheme.ink2),
                  ),
                ),
              )
            : _buildBody(_fullTask!),
      ),
    );
  }

  Widget _buildBody(TaskItem task) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      children: [
        if (_savedSubmissionMode) ...[
          Text(
            'Saved submission — Read only',
            style: InsightTheme.inter(13, w: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: InsightTheme.surface2,
              border: Border.all(color: InsightTheme.line),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _submission?.badge(
                        canonicalCompleted: task.category == 'Completed',
                      ) ??
                      'Completed — Synced',
                  style: InsightTheme.inter(
                    13,
                    w: FontWeight.w700,
                    c: _awaitingAcceptance
                        ? InsightTheme.orangeInk
                        : InsightTheme.green,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _awaitingAcceptance
                      ? 'Your final submission is saved on this device. Server acceptance is not confirmed. Check Sync Center for delivery or review actions.'
                      : 'The server has confirmed this inspection.',
                  style: InsightTheme.inter(12, c: InsightTheme.ink2),
                ),
              ],
            ),
          ),
        ] else if (_readOnly) ...[
          Text(
            'Historical inspection — Read only',
            style: InsightTheme.inter(13, w: FontWeight.w700),
          ),
          const SizedBox(height: 12),
        ],
        if (_isCachedFallback) _buildSavedDataNotice(),
        _buildHeaderCard(task),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'INSPECTION DATA',
            style: InsightTheme.inter(
              11,
              w: FontWeight.w700,
              c: InsightTheme.ink3,
              ls: 1.2,
            ),
          ),
        ),
        if (task.assignmentInstructions?.trim().isNotEmpty == true) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: InsightTheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF000000).withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.assignment_ind_outlined,
                        size: 20,
                        color: InsightTheme.ink2,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Assignment Instructions',
                        style: InsightTheme.poppins(
                          14,
                          w: FontWeight.w600,
                          c: InsightTheme.ink,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: InsightTheme.surface2,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      task.assignmentInstructions!,
                      style: InsightTheme.inter(
                        13,
                        w: FontWeight.w400,
                        c: InsightTheme.ink2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        // Loop 3 — Assigning Planning Officer (read-only).
        // Never shows "Admin" — null/missing renders nothing.
        if (task.assignedByName?.trim().isNotEmpty == true) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: InsightTheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF000000).withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  const Icon(
                    Icons.person_outline_rounded,
                    size: 20,
                    color: InsightTheme.ink2,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Assigned by',
                          style: InsightTheme.inter(
                            11,
                            w: FontWeight.w600,
                            c: InsightTheme.ink3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          task.assignedByName!,
                          style: InsightTheme.poppins(
                            14,
                            w: FontWeight.w600,
                            c: InsightTheme.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        _CollapsibleStepCard(
          step: 1,
          title: 'Site Verification',
          icon: Icons.location_on_outlined,
          onRework: _readOnly ? null : () => _reworkStep(1),
          content: _buildDetailRows({
            'Land use class': task.landUseClass,
            'Lot area (sqm)': task.lotAreaSqm?.toStringAsFixed(2) ?? '—',
            'Property index no.': task.propertyIndexNumber ?? '—',
          }),
        ),
        _CollapsibleStepCard(
          step: 2,
          title: 'GPS Verification',
          icon: Icons.satellite_alt_outlined,
          onRework: _readOnly ? null : () => _reworkStep(2),
          content: _buildDetailRows({
            'Confirmed latitude':
                task.confirmedLatitude?.toStringAsFixed(6) ?? '—',
            'Confirmed longitude':
                task.confirmedLongitude?.toStringAsFixed(6) ?? '—',
            'Accuracy (m)': task.gpsAccuracyM?.toStringAsFixed(1) ?? '—',
            'Confirmed at': task.gpsConfirmedAt ?? '—',
          }),
        ),
        _CollapsibleStepCard(
          step: 3,
          title: 'Photographic Evidence',
          icon: Icons.camera_alt_outlined,
          onRework: _readOnly ? null : () => _reworkStep(3),
          content: _buildPhotoGrid(task),
        ),
        _CollapsibleStepCard(
          step: 4,
          title: 'Checklist',
          icon: Icons.checklist_rtl_rounded,
          onRework: _readOnly ? null : () => _reworkStep(4),
          content: _buildDetailRows({
            'Completed':
                '${task.checklistCompletedCount} of ${task.checklistTotalCount} verified',
          }),
        ),
        _CollapsibleStepCard(
          step: 5,
          title: 'Field Findings',
          icon: Icons.edit_document,
          onRework: _readOnly ? null : () => _reworkStep(5),
          content: _buildDetailRows({
            'Observations': task.observations?.isNotEmpty == true
                ? task.observations!
                : 'None recorded',
            'Discrepancies': task.discrepancies?.isNotEmpty == true
                ? task.discrepancies!
                : 'None recorded',
            'Recommendations': task.recommendations?.isNotEmpty == true
                ? task.recommendations!
                : 'None recorded',
            'Inspector notes': task.inspectorNotes?.isNotEmpty == true
                ? task.inspectorNotes!
                : 'None recorded',
            // Leaving a rework step with unsaved text used to persist it on the
            // way out. It is now a draft only, so the summary shows it while
            // the rework session is open instead of claiming it is on file.
            ..._draftFindings(task),
          }),
        ),
        _CollapsibleStepCard(
          step: 6,
          title: 'Review & Submit',
          icon: Icons.verified_outlined,
          onRework: _readOnly ? null : () => _reworkStep(6),
          content: _buildDetailRows({
            // The four-state assessment is the authoritative reading. The
            // legacy boolean cannot separate a procedural For Review /
            // Requires Reinspection from a non-compliance finding, so it is
            // never rendered as a verdict here.
            'Inspector assessment': task.inspectionResult?.isNotEmpty == true
                ? task.inspectionResult!
                : 'Not recorded',
            'Assessment explanation': task.discrepancies?.isNotEmpty == true
                ? task.discrepancies!
                : 'None recorded',
            if (_savedSubmissionMode && _awaitingAcceptance)
              'Saved on device at': _submission?.savedAt ?? '—'
            else
              'Submitted at': task.submittedAt ?? '—',
          }),
        ),
        // Loop 8 — read-only Planning Review metadata for THIS exact round.
        // Rendered only when an explicit review row exists; a Completed task
        // with no review simply shows nothing. No buttons, no editing, and no
        // effect on status, category, current_step, progress or completed state.
        if (task.planningReview != null) ...[
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              'PLANNING REVIEW',
              style: InsightTheme.inter(
                11,
                w: FontWeight.w700,
                c: InsightTheme.ink3,
                ls: 1.2,
              ),
            ),
          ),
          _buildPlanningReviewCard(task),
        ],
      ],
    );
  }

  /// Loop 8 — small, strictly read-only Planning Review card. Reuses the
  /// existing card styling of this screen; genuinely null values are omitted
  /// rather than shown as placeholders.
  Widget _buildPlanningReviewCard(TaskItem task) {
    final review = task.planningReview!;
    final rows = <String, String>{
      'Decision': review.displayDecision,
      if (review.decisionReason?.trim().isNotEmpty == true)
        'Reason': review.decisionReason!,
      if (review.reviewedBy != null && review.reviewedBy!.isNotEmpty)
        'Reviewed by': review.reviewedBy!,
      if (review.reviewedAt != null && review.reviewedAt!.isNotEmpty)
        'Reviewed at': _formatPlanningReviewTimestamp(review.reviewedAt!),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: InsightTheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.rate_review_outlined,
                  size: 20,
                  color: InsightTheme.ink2,
                ),
                const SizedBox(width: 8),
                Text(
                  'Planning Review',
                  style: InsightTheme.poppins(
                    14,
                    w: FontWeight.w600,
                    c: InsightTheme.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildDetailRows(rows),
            const SizedBox(height: 4),
            Text(
              'Read-only record from the City Planning Office.',
              style: InsightTheme.inter(11, c: InsightTheme.ink3),
            ),
          ],
        ),
      ),
    );
  }

  /// Format a transported review timestamp for display; falls back to the raw
  /// value when it cannot be parsed, so a review is never hidden by formatting.
  String _formatPlanningReviewTimestamp(String raw) {
    final formatted = _formatTimestamp(raw);
    return formatted == '—' ? raw : formatted;
  }

  /// Non-blocking notice shown only when this summary is rendered from cached
  /// data. It never blocks the screen and it never claims detail is complete.
  Widget _buildSavedDataNotice() {
    final message = _refreshFailedWhileOnline
        ? 'Could not refresh from the server. Showing saved task data.'
        : 'Offline. Showing saved task data. Some details are not available.';
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: InsightTheme.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: InsightTheme.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.cloud_off_rounded, size: 16, color: InsightTheme.ink3),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: InsightTheme.inter(12, c: InsightTheme.ink2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(TaskItem task) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: InsightTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: InsightTheme.line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x04000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _savedSubmissionMode && _awaitingAcceptance
                  ? InsightTheme.orangeTint
                  : InsightTheme.greenTint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _savedSubmissionMode && _awaitingAcceptance
                  ? Icons.cloud_upload_outlined
                  : Icons.check_circle_rounded,
              color: _savedSubmissionMode && _awaitingAcceptance
                  ? InsightTheme.orangeInk
                  : InsightTheme.green,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      task.inspectionNo,
                      style: InsightTheme.inter(
                        11,
                        w: FontWeight.w700,
                        c: InsightTheme.ink3,
                      ),
                    ),
                    // Enhancement (Inspection Summary, 2026-07): surfaces
                    // the same signal already used by the Completed list
                    // (tasks_screen.dart) — reworkStartedAt non-null means
                    // an unfinished rework edit exists. status itself is
                    // untouched and stays 'completed' the whole time, so
                    // showing this badge here never implies a category
                    // change. Cleared back to null on Review & Submit.
                    if (task.reworkStartedAt != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: InsightTheme.orangeTint,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Modified',
                          style: InsightTheme.inter(
                            9.5,
                            w: FontWeight.w700,
                            c: const Color(0xFFB45309),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (task.roundLabel != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    task.roundLabel!,
                    style: InsightTheme.inter(13, w: FontWeight.w700),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  task.location,
                  style: InsightTheme.poppins(
                    15,
                    w: FontWeight.w600,
                    c: InsightTheme.ink,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  task.name,
                  style: InsightTheme.inter(13, c: InsightTheme.ink2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                // Enhancement (Inspection Summary, 2026-07): "last saved"
                // timestamp. Prefers updated_at (auto-maintained by the
                // trg_field_jobs_set_updated_at DB trigger on every write,
                // so it reflects rework edits too) and falls back to
                // submitted_at for older rows fetched before this field
                // existed on the client.
                if (!_savedSubmissionMode &&
                    (task.updatedAt ?? task.submittedAt) != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Last saved: ${_formatTimestamp(task.updatedAt ?? task.submittedAt)}',
                    style: InsightTheme.inter(
                      11,
                      w: FontWeight.w500,
                      c: InsightTheme.ink3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Enhancement (Inspection Summary, 2026-07): plain, dependency-free
  /// timestamp formatting — intentionally not pulling in `intl` since it's
  /// not already used elsewhere in this codebase and this task is scoped
  /// to enhancing the summary, not adding new dependencies.
  String _formatTimestamp(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '—';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} · $hour12:$minute $ampm';
  }

  /// Field Findings text left in memory by leaving a completed task's rework
  /// screen without pressing Save. It exists only while that rework session is
  /// open for this exact job; at any other time the summary shows what is
  /// actually persisted. The task-level Modified badge is what tells the
  /// inspector this text is not on file yet.
  Map<String, String> _draftFindings(TaskItem task) {
    if (_savedSubmissionMode) return const {};
    // Read defensively: this screen is also rendered in read-only/historical
    // contexts, where no live InspectionProvider exists and there is no draft
    // by definition — the persisted row is the only truth to show.
    InspectionProvider? provider;
    try {
      provider = context.read<InspectionProvider?>();
    } on ProviderNotFoundException {
      return const {};
    }
    if (provider == null ||
        !provider.hasReworkFindings ||
        provider.activeTask?.id != task.id) {
      return const {};
    }
    String shown(String value) => value.isEmpty ? 'None recorded' : value;
    return {
      'Observations': shown(provider.observations),
      'Discrepancies': shown(provider.discrepancies),
      'Recommendations': shown(provider.recommendations),
      'Inspector notes': shown(provider.notes),
    };
  }

  Widget _buildDetailRows(Map<String, String> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows.entries.map((e) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                e.key.toUpperCase(),
                style: InsightTheme.inter(
                  10,
                  w: FontWeight.w700,
                  c: InsightTheme.ink3,
                  ls: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                e.value,
                style: InsightTheme.inter(
                  13,
                  w: FontWeight.w500,
                  c: InsightTheme.ink,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPhotoGrid(TaskItem task) {
    // Fix (Step 3 / photo-notes audit, 2026-07): prefer the richer
    // field_job_photos join (photoDetails — has notes) over the flat
    // field_jobs.photo_paths URL list (photoPaths — never had notes).
    // Falls back to photoPaths so older cached job data (fetched before
    // this fix) still renders photos, just without a note caption.
    final hasDetails = task.photoDetails.isNotEmpty;
    final int count = hasDetails
        ? task.photoDetails.length
        : task.photoPaths.length;
    if (count == 0) {
      // Loop 7 rule: never render a stale signed URL or an invented grid.
      // Signed URLs are deliberately never cached, so on the cached fallback
      // there is simply no photo data to show - say so plainly instead of
      // implying the inspection had no photos.
      return Text(
        _isCachedFallback
            ? 'Photo evidence is not available offline.'
            : 'No photos attached to this report.',
        style: InsightTheme.inter(13, c: InsightTheme.ink2),
      );
    }
    final urls = hasDetails
        ? task.photoDetails
              .map((p) => (p['photo_url'] as String?) ?? '')
              .toList()
        : task.photoPaths;

    // Redesign (photo-notes clarity pass, 2026-07): each photo + its note
    // is its own bordered card with an explicit "Photo N of Count" label,
    // so which note belongs to which picture is unambiguous even with
    // several photos, rather than a plain unbounded row/strip.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(count, (i) {
        final url = urls[i];
        final note = hasDetails
            ? (task.photoDetails[i]['notes'] as String?)
            : null;
        final hasNote = note != null && note.trim().isNotEmpty;
        return Padding(
          padding: EdgeInsets.only(bottom: i == count - 1 ? 0 : 10),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: InsightTheme.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: InsightTheme.line),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => openFullscreenPhotoViewer(
                    context,
                    urls,
                    i,
                    photoDetails: hasDetails ? task.photoDetails : null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 80,
                      height: 80,
                      child: AdaptivePhotoImage(
                        path: url,
                        fit: BoxFit.cover,
                        errorBuilder: (context) => Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: InsightTheme.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: InsightTheme.line),
                          ),
                          child: const Icon(
                            Icons.broken_image_outlined,
                            size: 22,
                            color: InsightTheme.ink3,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.photo_camera_outlined,
                            size: 12,
                            color: InsightTheme.ink3,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Photo ${i + 1} of $count',
                            style: InsightTheme.inter(
                              9.5,
                              w: FontWeight.w700,
                              c: InsightTheme.ink3,
                              ls: 0.4,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasNote ? note : 'No inspection note for this photo.',
                        style: InsightTheme.inter(
                          12.5,
                          c: hasNote ? InsightTheme.ink2 : InsightTheme.ink3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// A collapsible card mimicking the _CompactTaskCard from tasks_screen.dart
class _CollapsibleStepCard extends StatefulWidget {
  final int step;
  final String title;
  final IconData icon;
  final Widget content;
  final VoidCallback? onRework;

  const _CollapsibleStepCard({
    required this.step,
    required this.title,
    required this.icon,
    required this.content,
    required this.onRework,
  });

  @override
  State<_CollapsibleStepCard> createState() => _CollapsibleStepCardState();
}

class _CollapsibleStepCardState extends State<_CollapsibleStepCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: InsightTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: InsightTheme.line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x04000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              onTap: () {
                setState(() => _isExpanded = !_isExpanded);
                HapticFeedback.selectionClick();
              },
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: InsightTheme.bg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: InsightTheme.line),
                      ),
                      child: Center(
                        child: Text(
                          '${widget.step}',
                          style: InsightTheme.inter(
                            11,
                            w: FontWeight.w700,
                            c: InsightTheme.ink,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: InsightTheme.inter(
                          14,
                          w: FontWeight.w600,
                          c: InsightTheme.ink,
                        ),
                      ),
                    ),
                    // Enhancement (Inspection Summary, 2026-07): per-step
                    // status indicator. Deliberately just "Saved" (not a
                    // per-step "Modified") — the data model only tracks a
                    // single task-level rework_started_at, not which
                    // individual step it belongs to, so labeling one step
                    // as "Modified" over another would be a guess, not a
                    // fact. The task-level Modified badge already lives on
                    // the header above for that reason.
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: InsightTheme.greenTint,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 11,
                            color: InsightTheme.green,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            'Saved',
                            style: InsightTheme.inter(
                              9.5,
                              w: FontWeight.w700,
                              c: InsightTheme.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      _isExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: InsightTheme.ink3,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            if (_isExpanded) ...[
              Container(color: InsightTheme.line, height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    widget.content,
                    const SizedBox(height: 16),
                    if (widget.onRework != null)
                      GestureDetector(
                        onTap: widget.onRework,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: InsightTheme.blueTint,
                            // FIXED: Replaced  with 8)
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: InsightTheme.blue1.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.refresh_rounded,
                                color: InsightTheme.blue2,
                                size: 16,
                              ),
                              // FIXED: Replaced  with 8)
                              const SizedBox(width: 8),
                              Text(
                                'Rework this step',
                                style: InsightTheme.inter(
                                  12,
                                  w: FontWeight.w600,
                                  c: InsightTheme.blue2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
