import 'package:flutter/material.dart';
import '../../../core/widgets/field_form_widgets.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/inspection_provider.dart';
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
import '../widgets/photo_viewer.dart';
import '../services/photo_source_resolver.dart';

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
    (title: 'For Review', subtitle: 'Needs supervisor sign-off'),
    (title: 'Requires Reinspection', subtitle: 'Site conditions incomplete'),
  ];

  late String _selectedStatus;
  bool _submitting = false;
  String? _localSaveError;

  void _localSaveFailure(Object error) {
    if (!mounted) return;
    final message = error is StateError &&
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
  }

  Future<void> _handleSubmit() async {
    if (_submitting) return;
    final provider = context.read<InspectionProvider>();
    // Prove the session BEFORE disabling the button, so a lapsed session
    // leaves the screen usable with an explanation instead of a dead control.
    final String uid;
    try {
      provider.requireOwner();
      if (!AuthService.isLoggedIn) throw StateError('Authenticated inspector required');
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

    final checklist = <Map<String, dynamic>>[
      ...provider.siteCondition.entries.map(
        (e) => {'item': e.key, 'checked': e.value},
      ),
      ...provider.zoningObservations.entries.map(
        (e) => {'item': e.key, 'checked': e.value},
      ),
    ];
    final checklistCompleted = checklist
        .where((c) => c['checked'] == true)
        .length;

    // UPDATED: Pass the full Map so SupabaseService has access to coordinates & timestamps
    final photosData = provider.capturedPhotos
        .where((p) => (p['photoPath'] as String?)?.isNotEmpty == true)
        .toList();

    final observations =
        'Actual land use: ${provider.actualLandUse}. Boundary status: ${provider.boundaryStatus}.';

    // Mark before the first remote attempt. Even if the upload or queue write
    // fails, the delete path must not treat this photo as safely local-only.
    provider.markPhotosSubmitted();

    // Try the real thing first — unchanged happy path when online.
    bool queuedOffline = false;
    bool requiresReview = false;
    var submission = InspectionAuthorityResult.offlineOrUnverifiable;
    try {
      final preserved = await DBHelper.getSyncCenterQueueActions();
      DBHelper.requireSameInspector(uid);
      if (preserved.any((a) => a['job_id'] == widget.task.id &&
          a['type'] == 'submit_inspection')) {
        // Restart/re-entry must recognize durable intent before any upload or
        // business write. Enqueue below checks identical evidence atomically.
        throw const InspectionAuthorityException(
          InspectionAuthorityResult.offlineOrUnverifiable);
      }
      if (!await SyncOutboxService.hasConnection()
          .timeout(const Duration(seconds: 2))) {
        throw const InspectionAuthorityException(
          InspectionAuthorityResult.offlineOrUnverifiable);
      }
      final photoPaths = await SupabaseService.uploadInspectionPhotos(
        jobId: widget.task.id,
        photosData: photosData,
      );
      DBHelper.requireSameInspector(uid);

      submission = await SupabaseService.submitInspection(
        jobId: widget.task.id,
        findings: provider.notes,
        isCompliant: _selectedStatus == 'Compliant',
        inspectionResult: _selectedStatus,
        observations: observations,
        discrepancies: provider.discrepancies.isNotEmpty
            ? provider.discrepancies
            : null,
        recommendations: provider.recommendations.isNotEmpty
            ? provider.recommendations
            : null,
        inspectorNotes: provider.notes,
        checklistData: checklist,
        checklistCompletedCount: checklistCompleted,
        checklistTotalCount: checklist.length,
        photoPaths: photoPaths,
        photoCount: photoPaths.length,
        locationLabel: widget.task.location,
      );
      submission.requireAuthorized();
    } catch (e) {
      // Couldn't reach Supabase (or a photo failed mid-upload) — rather
      // than lose everything the inspector just entered, queue the whole
      // submission (including the still-local photo paths) in the
      // FieldSync outbox and let them finish. It'll upload the photos and
      // submit for real once connectivity returns.
      try {
        DBHelper.requireSameInspector(uid);
        if (e is InspectionAuthorityException) submission = e.result;
        await SyncOutboxService.enqueueSubmitInspection(
          jobId: widget.task.id,
          findings: provider.notes,
          isCompliant: _selectedStatus == 'Compliant',
          inspectionResult: _selectedStatus,
          observations: observations,
          discrepancies: provider.discrepancies.isNotEmpty
              ? provider.discrepancies
              : null,
          recommendations: provider.recommendations.isNotEmpty
              ? provider.recommendations
              : null,
          inspectorNotes: provider.notes,
          checklistData: checklist,
          checklistCompletedCount: checklistCompleted,
          checklistTotalCount: checklist.length,
          photosData: photosData,
          locationLabel: widget.task.location, // UPDATED: Passing photosData
          preserveOnly:
              submission ==
                  InspectionAuthorityResult.notAssignedOrUnavailable ||
              submission == InspectionAuthorityResult.authRequired,
        );
        queuedOffline = true;
        final preserved = await DBHelper.getSyncCenterQueueActions();
        DBHelper.requireSameInspector(uid);
        requiresReview = preserved.any((a) => a['job_id'] == widget.task.id &&
          a['type'] == 'submit_inspection' &&
          const ['conflict', 'paused'].contains(a['status']));
      } catch (saveError) {
        _localSaveFailure(saveError);
        return;
      }
    }

    // Remote acceptance has already succeeded. Local cleanup must never enter
    // the catch above and enqueue/retry that successful business submission.
    if (DBHelper.currentInspectorId != uid) {
      if (mounted) setState(() => _submitting = false);
      return;
    }
    if (!queuedOffline && !provider.isReworkMode) {
      final cleaned = await DBHelper.finalizeAcceptedOnlineInspection(
        widget.task.id,
        remoteResult: submission,
      );
      if (!cleaned && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Inspection submitted. Local cache cleanup will retry on refresh.',
            ),
          ),
        );
      }
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
    final photoCount = provider.capturedPhotos.isNotEmpty
        ? provider.capturedPhotos.length
        : widget.capturedPhotos.length;
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
          handleInspectionExit(context, onSaveProgress: () async => true);
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
              onBack: () => handleInspectionExit(
                context,
                onSaveProgress: () async => true,
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
                    child: Text(_localSaveError!,
                      style: InsightTheme.inter(14, c: InsightTheme.redInk)),
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
                    label: 'Photos',
                    value: photoCount > 0 ? '$photoCount attached' : 'None',
                  ),
                  _SummaryRow(
                    label: 'Assessment',
                    value: _selectedStatus,
                    isLast: true,
                  ),
                ],
              ),
              if (provider.capturedPhotos.isNotEmpty) ...[
                const SizedBox(height: 12),
                FieldSectionHeading(
                  title: 'Attached photos',
                  hint: 'Tap a photo to inspect the full image.',
                  bottomSpacing: 8,
                  trailing: Text('${provider.capturedPhotos.length} photos',
                    style: InsightTheme.inter(13, w: FontWeight.w600, c: InsightTheme.blueInk)),
                ),
                FieldReadOnlyCard(
                  padding: const EdgeInsets.all(12),
                  children: [
                    SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        for (var i = 0; i < provider.capturedPhotos.length; i++) ...[
                          if (i > 0) const SizedBox(width: 12),
                          Builder(builder: (context) {
                          final paths = inspectionDisplayPaths(
                            provider.capturedPhotos
                                .map((p) => p['photoPath'] as String? ?? '')
                                .toList(),
                            widget.task.id,
                            widget.task.photoDetails,
                            widget.task.photoPaths,
                          );
                          return Semantics(
                            button: true,
                            label: 'View photo ${i + 1}',
                            child: SizedBox(width: 128,
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: InsightTheme.roundedSm,
                                  onTap: () => openFullscreenPhotoViewer(
                                    context,
                                    paths,
                                    i,
                                  ),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    ClipRRect(
                                      borderRadius: InsightTheme.roundedSm,
                                      child: SizedBox(height: 100, width: 128,
                                        child: AdaptivePhotoImage(path: paths[i])),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(children: [
                                      const Icon(Icons.camera_alt_outlined, size: 14, color: InsightTheme.ink2),
                                      const SizedBox(width: 6),
                                      Expanded(child: Text('Photo ${i + 1}',
                                        style: InsightTheme.inter(12, c: InsightTheme.ink2))),
                                    ]),
                                  ]),
                                ),
                              ),
                            ),
                          );
                          }),
                        ],
                      ]),
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
                  trailing: Text('$checklistDone/$checklistTotal checked',
                    style: InsightTheme.inter(13, w: FontWeight.w600, c: InsightTheme.blueInk)),
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
                    label: 'Discrepancies',
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
                    'Select the assessment that best reflects your inspection.',
              ),
              ..._statusOptions.map(
                (o) => _ResultOption(
                  title: o.title,
                  subtitle: o.subtitle,
                  isSelected: _selectedStatus == o.title,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedStatus = o.title);
                    context.read<InspectionProvider>().updateResult(o.title);
                  },
                ),
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
        Text(label, style: InsightTheme.inter(checked == null ? 13 : 14,
            c: checked == null ? InsightTheme.ink3 : InsightTheme.ink)),
        const SizedBox(height: 4),
        Text(value, style: InsightTheme.inter(checked == null ? 15 : 12.5,
            w: checked == null ? FontWeight.w500 : FontWeight.w400,
            c: checked == null ? InsightTheme.ink : InsightTheme.ink2)),
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
      child: checked == null ? text : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 20, height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: checked! ? InsightTheme.blueTint : InsightTheme.surface,
            border: Border.all(color: checked! ? InsightTheme.blue1.withValues(alpha: 0.2) : InsightTheme.lineStrong),
          ),
          child: checked! ? const Icon(Icons.check_rounded, size: 14, color: InsightTheme.blue1) : null,
        ),
        const SizedBox(width: 10),
        Expanded(child: text),
      ]),
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
              final profile = await AuthService.getCachedProfileForCurrentInspector();
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
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(
                'Your saved submission is preserved. Sign in again to return Home.',
              )));
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
                  queuedOffline ? (requiresReview ? 'Saved Locally' : 'Saved Offline')
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
                      : 'Your inspection was accepted by the server.',
                  textAlign: TextAlign.center,
                  style: InsightTheme.inter(14, c: InsightTheme.ink2),
                ),
                const SizedBox(height: 24),
                _SummaryRow(label: 'Inspection reference', value: referenceNo),
                _SummaryRow(
                  label: 'Final assessment',
                  value: finalStatus,
                ),
                _SummaryRow(
                  label: 'Synchronization',
                  value: queuedOffline ? (requiresReview ? 'Review needed' : 'Pending Sync')
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
