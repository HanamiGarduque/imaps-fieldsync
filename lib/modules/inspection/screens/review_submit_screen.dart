import 'package:flutter/material.dart';
import '../../../core/widgets/field_form_widgets.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/inspection_provider.dart';
import '../structured_checklist.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/sync_outbox_service.dart';
import '../../../core/services/db_helper.dart';
import '../../../core/services/auth_service.dart';
import 'inspection_progress.dart';
import '../../../core/navigation/main_shell_screen.dart';
import '../../tasks/screens/tasks_screen.dart' show TaskItem;
import '../widgets/exit_confirm_dialog.dart';
import '../../../core/widgets/sensitive_screen.dart';

import '../../../core/theme/insight_theme.dart';
import '../widgets/inspection_step_header.dart';
import '../widgets/structured_checklist_summary.dart';
import '../widgets/photo_viewer.dart';
import '../services/photo_source_resolver.dart';
import '../services/photo_evidence_presentation.dart';

class ReviewSubmitScreen extends StatefulWidget {
  final TaskItem task;
  final List<Map<String, dynamic>> capturedPhotos;
  final int checklistDone;
  final int checklistTotal;

  const ReviewSubmitScreen({
    super.key,
    required this.task,
    this.capturedPhotos = const [],
    this.checklistDone = 0,
    this.checklistTotal = 0,
  });
  @override
  State<ReviewSubmitScreen> createState() => _ReviewSubmitScreenState();
}

class _ReviewSubmitScreenState extends State<ReviewSubmitScreen> {
  static const _statusOptions = [
    (title: 'Compliant', subtitle: 'Matches declared use, no issues'),
    (title: 'With Discrepancy', subtitle: 'Observed use differs from declared'),
    (
      title: 'For Review',
      subtitle: 'Needs Planning Officer review; not a non-compliance finding',
    ),
    (
      title: 'Requires Reinspection',
      subtitle: 'Needs another site visit; not a non-compliance finding',
    ),
  ];

  late String _selectedStatus;
  bool _submitting = false;
  String? _localSaveError;
  late final TextEditingController _explanationController;

  void _localSaveFailure(Object error) {
    if (!mounted) return;
    final message =
        error is StateError &&
            error.message.toString().startsWith('A final submission')
        ? error.message.toString()
        : 'Could not save locally. Your review and photos are still here. Please try again.';
    setState(() {
      _submitting = false;
      _localSaveError = message;
    });
  }

  @override
  void initState() {
    super.initState();
    _selectedStatus = context.read<InspectionProvider>().inspectionResult;
    _explanationController = TextEditingController(
      text: context.read<InspectionProvider>().discrepancies,
    );
  }

  @override
  void dispose() {
    _explanationController.dispose();
    super.dispose();
  }

  Future<bool> _saveReviewDraft() async {
    try {
      return await context.read<InspectionProvider>().saveAllInspectionState(
        syncOnline: false,
      );
    } catch (e) {
      _localSaveFailure(e);
      return false;
    }
  }

  void _showValidation(String message) {
    setState(() => _localSaveError = message);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirmSubmission(InspectionProvider provider) async {
    final answers = {...provider.siteCondition, ...provider.zoningObservations};
    final evidence = PhotoEvidencePresentation(
      provider.capturedPhotos,
      requireMetadata: provider.isReworkMode,
    );
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            scrollable: true,
            title: const Text('Confirm inspection assessment'),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.task.inspectionNo),
                const SizedBox(height: 8),
                Text(
                  _selectedStatus,
                  style: InsightTheme.inter(16, w: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  provider.discrepancies.trim().isEmpty
                      ? 'No discrepancy / explanation recorded'
                      : provider.discrepancies,
                ),
                const SizedBox(height: 16),
                Text(
                  '${answers.values.where((value) => value).length} of ${answers.length} checked — unchecked is not automatically non-compliant.',
                ),
                for (final answer in answers.entries)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${answer.key}: ${answer.value ? 'Checked' : 'Unchecked'}',
                    ),
                  ),
                const SizedBox(height: 16),
                Text('Site photos: ${evidence.sitePhotoCount}'),
                if (evidence.referenceCount > 0)
                  Text('Site Location Reference: ${evidence.referenceCount}'),
                Text('Total evidence attachments: ${evidence.totalCount}'),
                const SizedBox(height: 16),
                const Text(
                  'This is the inspector’s assessment, not an approval or rejection. The Planning Officer retains decision-making authority.',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Confirm & Submit'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _handleSubmit() async {
    if (_submitting) return;
    final provider = context.read<InspectionProvider>();
    // A generated location reference must never stand in for the required
    // camera evidence.
    if (provider.realPhotoCount == 0) {
      _showValidation('Capture at least one camera photo before submitting.');
      return;
    }
    // Resume can enter Review without revisiting every step. Steps 3, 4 and
    // 5 are independent, but all three must be genuinely complete before an
    // inspection can be submitted, whatever order they were done in. The
    // live progress of this inspection is the record; an inspection that is
    // not loaded in this session is decided by the server.
    final progress = InspectionProgress.instance;
    if (progress.activeTaskId == widget.task.id) {
      final completed = progress.completedSteps;
      final missing = InspectionProgress.flexibleSteps
          .where((step) => !completed.contains(step))
          .toList();
      if (missing.isNotEmpty) {
        _showValidation(
          'Complete the remaining inspection step'
          '${missing.length == 1 ? '' : 's'} before submitting: '
          '${missing.map((step) => 'Step $step').join(', ')}.',
        );
        return;
      }
    }
    final validation = provider.assessmentValidationMessage;
    if (validation != null) {
      _showValidation(validation);
      return;
    }
    // Prove the session BEFORE disabling the button, so a lapsed session
    // leaves the screen usable with an explanation instead of a dead control.
    final String uid;
    try {
      provider.requireOwner();
      if (!AuthService.isLoggedIn) {
        throw StateError('Authenticated inspector required');
      }
      uid = DBHelper.requireInspector();
      if (provider.activeTask?.id != widget.task.id) {
        throw StateError('Review must belong to the active inspection round');
      }
    } on StateError {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(InspectionAuthorityResult.authRequired.message),
          ),
        );
      }
      return;
    }
    HapticFeedback.heavyImpact();
    setState(() {
      _submitting = true;
      _localSaveError = null;
    });
    final confirmed = await _confirmSubmission(provider);
    if (!mounted) return;
    if (!confirmed) {
      setState(() => _submitting = false);
      return;
    }
    try {
      // Local first: even a later enqueue failure cannot discard this review's
      // checklist, findings, photos or previously reached step.
      if (!await provider.saveAllInspectionState(syncOnline: false)) {
        throw StateError('Inspection draft could not be saved');
      }
      DBHelper.requireSameInspector(uid);
    } catch (e) {
      _localSaveFailure(e);
      return;
    }

    final legacy = <String, bool>{
      ...provider.siteCondition,
      ...provider.zoningObservations,
    };
    final checklist = StructuredChecklist.remoteChecklist(
      legacy: legacy,
      answers: provider.structuredAnswers,
    );
    final checklistCompleted = legacy.values.where((value) => value).length;

    // UPDATED: Pass the full Map so SupabaseService has access to coordinates & timestamps
    final photosData = provider.capturedPhotos
        .where((p) => (p['photoPath'] as String?)?.isNotEmpty == true)
        .toList();

    Map<String, dynamic> action;
    try {
      DBHelper.requireSameInspector(uid);
      // Journal one immutable intent BEFORE remote work, online as well as
      // offline. Lost acknowledgements now share the outbox recovery identity.
      await SyncOutboxService.enqueueSubmitInspection(
        jobId: widget.task.id,
        findings: provider.notes,
        isCompliant: _selectedStatus == 'Compliant',
        inspectionResult: _selectedStatus,
        observations: provider.observations,
        discrepancies: provider.discrepancies.trim().isEmpty
            ? null
            : provider.discrepancies,
        recommendations: provider.recommendations.trim().isEmpty
            ? null
            : provider.recommendations,
        inspectorNotes: provider.notes,
        checklistData: checklist,
        checklistCompletedCount: checklistCompleted,
        checklistTotalCount: legacy.length,
        photosData: photosData,
        locationLabel: widget.task.location,
      );
      DBHelper.requireSameInspector(uid);
      final queued = await DBHelper.getSyncCenterQueueActions();
      // A concurrently running reconnect drain can already have acknowledged
      // this intent. Retained owner-scoped receipts are not a missing save.
      final candidates = [
        ...queued,
        ...await DBHelper.getRecentSyncedActions(limit: 50),
      ];
      DBHelper.requireSameInspector(uid);
      action = candidates.firstWhere(
        (row) =>
            row['job_id'] == widget.task.id &&
            row['type'] == 'submit_inspection',
      );
      provider.markPhotosSubmitted();
    } catch (e) {
      _localSaveFailure(e);
      return;
    }

    try {
      // Do not wait for a reconnect or manual tap when delivery can succeed now.
      await SyncOutboxService.drain(onlyJobId: widget.task.id);
    } catch (_) {
      // The exact durable intent above remains recoverable in Sync Center.
    }
    if (DBHelper.currentInspectorId != uid) {
      if (mounted) setState(() => _submitting = false);
      return;
    }
    final Map<String, dynamic>? receipt;
    try {
      receipt = await DBHelper.getOwnedAction(action['id'] as String);
      DBHelper.requireSameInspector(uid);
    } catch (e) {
      _localSaveFailure(e);
      return;
    }
    if (!mounted) return;
    if (receipt == null) {
      _localSaveFailure(StateError('Submission receipt could not be read'));
      return;
    }
    final queuedOffline = receipt['status'] != 'synced';
    final requiresReview = receipt['status'] == 'conflict';
    if (receipt['status'] == 'paused') {
      setState(() => _submitting = false);
      _showValidation(
        'Saved on this device, but not accepted by the server. '
        'Delivery is paused. Review your assessment and assignment in Sync Center, '
        'sign in again if needed, or contact the Planning Office before retrying.',
      );
      return;
    }

    if (!queuedOffline) InspectionProgress.instance.markStepComplete(6);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SubmissionSuccessScreen(
          referenceNo: widget.task.inspectionNo,
          finalStatus: _selectedStatus,
          queuedOffline: queuedOffline,
          requiresReview: requiresReview,
          inspectorId: uid,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    final provider = context.watch<InspectionProvider>();
    final photos = provider.capturedPhotos.isNotEmpty
        ? provider.capturedPhotos
        : widget.capturedPhotos;
    final evidence = PhotoEvidencePresentation(
      photos,
      requireMetadata: provider.isReworkMode,
    );
    final checklistTotal =
        provider.siteCondition.length + provider.zoningObservations.length;
    final checklistDone =
        provider.siteCondition.values.where((v) => v).length +
        provider.zoningObservations.values.where((v) => v).length;
    final checklistAnswers = {
      ...provider.siteCondition,
      ...provider.zoningObservations,
    }.entries.toList(growable: false);
    final effectiveTotal = checklistTotal > 0
        ? checklistTotal
        : widget.checklistTotal;
    final effectiveDone = checklistTotal > 0
        ? checklistDone
        : widget.checklistDone;

    return SensitiveScreen(
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          // Findings/checklist/photos are already persisted by their own
          // steps by the time an inspector reaches Review — nothing new to
          // save here, just confirm and keep the task under Ongoing.
          if (!_submitting) {
            handleInspectionExit(context, onSaveProgress: _saveReviewDraft);
          }
        },
        child: Scaffold(
          backgroundColor: InsightTheme.bg,
          body: FieldFormBody(
            header: InspectionStepHeader(
              formStyle: true,
              title: 'Review & Submit',
              subtitle: widget.task.location,
              stepNumber: 6,
              stepSubtitle: 'FINALIZE REPORT',
              onBack: () => _submitting
                  ? null
                  : handleInspectionExit(
                      context,
                      onSaveProgress: _saveReviewDraft,
                    ),
            ),
            action: FieldPrimaryButton(
              label: 'Submit Inspection',
              busy: _submitting,
              busyLabel: 'Submitting inspection…',
              onPressed: _submitting ? null : _handleSubmit,
            ),
            children: [
              if (_localSaveError != null)
                Semantics(
                  liveRegion: true,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      _localSaveError!,
                      style: InsightTheme.inter(14, c: InsightTheme.redInk),
                    ),
                  ),
                ),
              FieldSectionHeading(
                title: 'Inspection record',
                hint:
                    'Review the evidence before submitting ${widget.task.inspectionNo}.',
              ),
              FieldReadOnlyCard(
                children: [
                  _SummaryRow(label: 'Applicant', value: widget.task.name),
                  _SummaryRow(
                    label: 'Site Location',
                    value: widget.task.location,
                  ),
                  _SummaryRow(
                    label: 'Checklist',
                    value: effectiveTotal > 0
                        ? '$effectiveDone of $effectiveTotal checked'
                        : 'None',
                  ),
                  _SummaryRow(
                    label: 'Site photos',
                    value: '${evidence.sitePhotoCount}',
                  ),
                  if (evidence.referenceCount > 0)
                    _SummaryRow(
                      label: 'Site Location Reference',
                      value: '${evidence.referenceCount}',
                    ),
                  _SummaryRow(
                    label: 'Total evidence attachments',
                    value: '${evidence.totalCount}',
                  ),
                  _SummaryRow(
                    label: 'Assessment',
                    value: _selectedStatus.isEmpty
                        ? 'Not selected'
                        : _selectedStatus,
                    isLast: true,
                  ),
                ],
              ),
              if (provider.capturedPhotos.isNotEmpty) ...[
                const SizedBox(height: 12),
                FieldSectionHeading(
                  title: 'Evidence attachments',
                  hint: 'Tap an attachment to inspect the full image.',
                  bottomSpacing: 8,
                  trailing: Text(
                    '${evidence.totalCount} total attachments',
                    style: InsightTheme.inter(
                      13,
                      w: FontWeight.w600,
                      c: InsightTheme.blueInk,
                    ),
                  ),
                ),
                FieldReadOnlyCard(
                  padding: const EdgeInsets.all(12),
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (
                            var i = 0;
                            i < provider.capturedPhotos.length;
                            i++
                          ) ...[
                            if (i > 0) const SizedBox(width: 12),
                            Builder(
                              builder: (context) {
                                final paths = inspectionDisplayPaths(
                                  provider.capturedPhotos
                                      .map(
                                        (p) => p['photoPath'] as String? ?? '',
                                      )
                                      .toList(),
                                  widget.task.id,
                                  widget.task.photoDetails,
                                  widget.task.photoPaths,
                                );
                                final tileWidth = evidence.isReferenceAt(i)
                                    ? 160.0
                                    : 128.0;
                                return Semantics(
                                  button: true,
                                  label: evidence.semanticsAt(i),
                                  child: SizedBox(
                                    width: tileWidth,
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: InsightTheme.roundedSm,
                                        onTap: () => openFullscreenPhotoViewer(
                                          context,
                                          paths,
                                          i,
                                          photoDetails: provider.capturedPhotos,
                                          jobId: widget.task.id,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            ClipRRect(
                                              borderRadius:
                                                  InsightTheme.roundedSm,
                                              child: SizedBox(
                                                height: 100,
                                                width: tileWidth,
                                                child: AdaptivePhotoImage(
                                                  path: paths[i],
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Row(
                                              children: [
                                                Icon(
                                                  evidence.isReferenceAt(i)
                                                      ? Icons.map_outlined
                                                      : evidence.isSitePhotoAt(
                                                          i,
                                                        )
                                                      ? Icons
                                                            .camera_alt_outlined
                                                      : Icons.attach_file,
                                                  size: 14,
                                                  color: InsightTheme.ink2,
                                                ),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Text(
                                                    evidence.labelAt(i),
                                                    style: InsightTheme.inter(
                                                      12,
                                                      c: InsightTheme.ink2,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ],
              if (widget.task.confirmedLatitude != null &&
                  widget.task.confirmedLongitude != null) ...[
                const SizedBox(height: 16),
                const FieldSectionHeading(
                  title: 'GPS record',
                  bottomSpacing: 8,
                ),
                FieldReadOnlyCard(
                  children: [
                    _SummaryRow(
                      label: 'Coordinates',
                      value:
                          '${widget.task.confirmedLatitude!.toStringAsFixed(6)}, ${widget.task.confirmedLongitude!.toStringAsFixed(6)}',
                      compact: true,
                      isLast: widget.task.gpsAccuracyM == null,
                    ),
                    if (widget.task.gpsAccuracyM != null)
                      _SummaryRow(
                        label: 'Recorded accuracy',
                        value:
                            '${widget.task.gpsAccuracyM!.toStringAsFixed(1)} m',
                        compact: true,
                        isLast: true,
                      ),
                  ],
                ),
              ],
              if (checklistTotal > 0) ...[
                const SizedBox(height: 16),
                FieldSectionHeading(
                  title: 'Checklist answers',
                  bottomSpacing: 8,
                  trailing: Text(
                    '$checklistDone/$checklistTotal checked',
                    style: InsightTheme.inter(
                      13,
                      w: FontWeight.w600,
                      c: InsightTheme.blueInk,
                    ),
                  ),
                ),
                FieldReadOnlyCard(
                  children: [
                    for (final (index, answer) in checklistAnswers.indexed)
                      _SummaryRow(
                        label: answer.key,
                        value: answer.value ? 'Checked' : 'Unchecked',
                        compact: true,
                        checked: answer.value,
                        isLast: index == checklistAnswers.length - 1,
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              StructuredChecklistSummary(
                heading: 'Project status & zoning observations',
                answers: provider.structuredAnswers,
              ),
              const SizedBox(height: 16),
              const FieldSectionHeading(
                title: 'Field findings',
                bottomSpacing: 8,
              ),
              FieldReadOnlyCard(
                children: [
                  _SummaryRow(
                    label: 'Observations',
                    value: provider.notes.isEmpty
                        ? 'No observations recorded'
                        : provider.notes,
                    compact: true,
                  ),
                  _SummaryRow(
                    label: 'Discrepancies / assessment explanation',
                    value: provider.discrepancies.isEmpty
                        ? 'No discrepancies recorded'
                        : provider.discrepancies,
                    compact: true,
                  ),
                  _SummaryRow(
                    label: 'Recommendations',
                    value: provider.recommendations.isEmpty
                        ? 'No recommendations recorded'
                        : provider.recommendations,
                    compact: true,
                    isLast: true,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const FieldSectionHeading(
                title: 'Final assessment',
                hint:
                    'Choose explicitly. This is an inspector assessment, not the Planning Officer’s approval or rejection.',
              ),
              ..._statusOptions.map(
                (o) => _ResultOption(
                  title: o.title,
                  subtitle: o.subtitle,
                  isSelected: _selectedStatus == o.title,
                  onTap: () {
                    if (_submitting) return;
                    HapticFeedback.selectionClick();
                    setState(() => _selectedStatus = o.title);
                    context.read<InspectionProvider>().updateResult(o.title);
                    _saveReviewDraft();
                  },
                ),
              ),
              const SizedBox(height: 8),
              const FieldSectionHeading(
                title: 'Assessment explanation',
                hint:
                    'The same details recorded in Step 5. For any non-Compliant outcome, explain what was observed and why it differs or needs follow-up. Review/reinspection alone does not prove non-compliance.',
                bottomSpacing: 8,
              ),
              TextField(
                key: const ValueKey('assessment-explanation'),
                controller: _explanationController,
                readOnly: _submitting,
                minLines: 3,
                maxLines: 6,
                decoration: InsightTheme.compactFormInput.copyWith(
                  labelText: 'Shared Step 5 explanation',
                  alignLabelWithHint: true,
                ),
                onChanged: (value) {
                  provider.updateFindings(
                    actualLandUse: provider.actualLandUse,
                    notes: provider.notes,
                    discrepancies: value,
                    recommendations: provider.recommendations,
                    boundaryStatus: provider.boundaryStatus,
                  );
                  _saveReviewDraft();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isLast;
  final bool compact;
  final bool? checked;
  const _SummaryRow({
    required this.label,
    required this.value,
    this.isLast = false,
    this.compact = false,
    this.checked,
  });
  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: InsightTheme.inter(
            checked == null ? 13 : 14,
            c: checked == null ? InsightTheme.ink3 : InsightTheme.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: InsightTheme.inter(
            checked == null ? 15 : 12.5,
            w: checked == null ? FontWeight.w500 : FontWeight.w400,
            c: checked == null ? InsightTheme.ink : InsightTheme.ink2,
          ),
        ),
      ],
    );
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: compact ? 8 : 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: InsightTheme.line)),
      ),
      child: checked == null
          ? text
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: checked!
                        ? InsightTheme.blueTint
                        : InsightTheme.surface,
                    border: Border.all(
                      color: checked!
                          ? InsightTheme.blue1.withValues(alpha: 0.2)
                          : InsightTheme.lineStrong,
                    ),
                  ),
                  child: checked!
                      ? const Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: InsightTheme.blue1,
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(child: text),
              ],
            ),
    );
  }
}

class _ResultOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;
  const _ResultOption({
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: isSelected,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: InsightTheme.roundedMd,
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected ? InsightTheme.blueTint : InsightTheme.surface,
              borderRadius: InsightTheme.roundedMd,
              border: Border.all(
                color: isSelected ? InsightTheme.blue1 : InsightTheme.line,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 200),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? InsightTheme.blue1 : Colors.transparent,
                    border: isSelected
                        ? null
                        : Border.all(color: InsightTheme.lineStrong, width: 2),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, color: Colors.white, size: 14)
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: InsightTheme.inter(
                          14,
                          w: FontWeight.w600,
                          c: isSelected
                              ? InsightTheme.blueInk
                              : InsightTheme.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: InsightTheme.inter(12, c: InsightTheme.ink2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SubmissionSuccessScreen extends StatelessWidget {
  final String referenceNo;
  final String finalStatus;
  final bool queuedOffline;
  final bool requiresReview;
  final String? inspectorId;
  const SubmissionSuccessScreen({
    super.key,
    required this.referenceNo,
    required this.finalStatus,
    this.queuedOffline = false,
    this.requiresReview = false,
    this.inspectorId,
  });
  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    return SensitiveScreen(
      child: Scaffold(
        backgroundColor: InsightTheme.bg,
        body: FieldFormBody(
          header: const SizedBox(height: 40),
          action: FieldPrimaryButton(
            label: 'Back to Home',
            onPressed: () async {
              try {
                final uid = inspectorId ?? DBHelper.requireInspector();
                DBHelper.requireSameInspector(uid);
                final profile =
                    await AuthService.getCachedProfileForCurrentInspector();
                DBHelper.requireSameInspector(uid);
                if (profile == null || profile.id != uid) {
                  throw StateError('Authorized local profile unavailable');
                }
                if (!context.mounted) return;
                InspectionProgress.instance.reset();
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => MainShellScreen(
                      profile: profile,
                      offlineSession: queuedOffline,
                    ),
                  ),
                  (route) => false,
                );
              } catch (_) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Your saved submission is preserved. Sign in again to return Home.',
                    ),
                  ),
                );
              }
            },
          ),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: InsightTheme.surface,
                borderRadius: InsightTheme.roundedMd,
                border: Border.all(color: InsightTheme.line),
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: queuedOffline
                        ? InsightTheme.blueTint
                        : InsightTheme.greenTint,
                    child: Icon(
                      queuedOffline
                          ? Icons.cloud_off_rounded
                          : Icons.check_rounded,
                      color: queuedOffline
                          ? InsightTheme.blueInk
                          : InsightTheme.greenInk,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    queuedOffline
                        ? (requiresReview ? 'Saved Locally' : 'Saved Offline')
                        : 'Inspection Submitted',
                    textAlign: TextAlign.center,
                    style: InsightTheme.urbanist(24, w: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    queuedOffline
                        ? (requiresReview
                              ? 'Saved on this device. Delivery needs review in Sync Center; remote completion is not confirmed.'
                              : 'Saved on this device. Pending Sync — remote completion is not confirmed. FieldSync will attempt delivery when connected; check Sync Center for updates.')
                        : 'Received by FieldSync / Supabase. Planning Officer-side iMAPS import is not yet confirmed.',
                    textAlign: TextAlign.center,
                    style: InsightTheme.inter(14, c: InsightTheme.ink2),
                  ),
                  const SizedBox(height: 24),
                  _SummaryRow(
                    label: 'Inspection reference',
                    value: referenceNo,
                  ),
                  _SummaryRow(label: 'Final assessment', value: finalStatus),
                  _SummaryRow(
                    label: 'Synchronization',
                    value: queuedOffline
                        ? (requiresReview ? 'Review needed' : 'Pending Sync')
                        : 'Server accepted',
                    isLast: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
