import 'package:flutter/material.dart';
import '../../../core/widgets/field_form_widgets.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/inspection_provider.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/sync_outbox_service.dart';
import '../../../core/services/db_helper.dart';
import 'inspection_progress.dart';
import '../../../core/navigation/main_shell_screen.dart';
import '../../tasks/screens/tasks_screen.dart' show TaskItem;
import '../../../core/models/user_profile.dart';
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
      uid = DBHelper.requireInspector();
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
    setState(() => _submitting = true);

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
    context.read<InspectionProvider>().markPhotosSubmitted();

    // Try the real thing first — unchanged happy path when online.
    bool queuedOffline = false;
    var submission = InspectionAuthorityResult.offlineOrUnverifiable;
    try {
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
      } catch (_) {
        // Couldn't even save it locally — nothing more we can do here.
        if (!mounted) return;
        setState(() => _submitting = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
        return;
      }
    }

    if (queuedOffline) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${submission.message} Submission is saved locally; remote completion is not confirmed.',
            ),
          ),
        );
      }
      return;
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

    InspectionProgress.instance.markStepComplete(6);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SubmissionSuccessScreen(
          referenceNo: widget.task.inspectionNo,
          finalStatus: _selectedStatus,
          queuedOffline: queuedOffline,
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
                const FieldSectionHeading(
                  title: 'Attached photos',
                  hint: 'Tap a photo to inspect the full image.',
                ),
                FieldReadOnlyCard(
                  padding: EdgeInsets.zero,
                  children: [
                    SizedBox(
                      height: 128,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        itemCount: provider.capturedPhotos.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
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
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: InsightTheme.roundedSm,
                                  onTap: () => openFullscreenPhotoViewer(
                                    context,
                                    paths,
                                    i,
                                  ),
                                  child: ClipRRect(
                                    borderRadius: InsightTheme.roundedSm,
                                    child: SizedBox(
                                      width: 128,
                                      child: AdaptivePhotoImage(path: paths[i]),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
              if (widget.task.confirmedLatitude != null &&
                  widget.task.confirmedLongitude != null) ...[
                const SizedBox(height: 24),
                const FieldSectionHeading(title: 'GPS record'),
                FieldReadOnlyCard(
                  children: [
                    _SummaryRow(
                      label: 'Coordinates',
                      value:
                          '${widget.task.confirmedLatitude!.toStringAsFixed(6)}, ${widget.task.confirmedLongitude!.toStringAsFixed(6)}',
                      isLast: widget.task.gpsAccuracyM == null,
                    ),
                    if (widget.task.gpsAccuracyM != null)
                      _SummaryRow(
                        label: 'Recorded accuracy',
                        value:
                            '${widget.task.gpsAccuracyM!.toStringAsFixed(1)} m',
                        isLast: true,
                      ),
                  ],
                ),
              ],
              if (checklistTotal > 0) ...[
                const SizedBox(height: 24),
                const FieldSectionHeading(title: 'Checklist answers'),
                FieldReadOnlyCard(
                  children: [
                    for (final answer in {
                      ...provider.siteCondition,
                      ...provider.zoningObservations,
                    }.entries)
                      _SummaryRow(
                        label: answer.key,
                        value: answer.value ? 'Checked' : 'Unchecked',
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              const FieldSectionHeading(title: 'Field findings'),
              FieldReadOnlyCard(
                children: [
                  _SummaryRow(
                    label: 'Observations',
                    value: provider.notes.isEmpty
                        ? 'No observations recorded'
                        : provider.notes,
                  ),
                  _SummaryRow(
                    label: 'Discrepancies',
                    value: provider.discrepancies.isEmpty
                        ? 'No discrepancies recorded'
                        : provider.discrepancies,
                  ),
                  _SummaryRow(
                    label: 'Recommendations',
                    value: provider.recommendations.isEmpty
                        ? 'No recommendations recorded'
                        : provider.recommendations,
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
  const _SummaryRow({
    required this.label,
    required this.value,
    this.isLast = false,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: InsightTheme.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: InsightTheme.inter(13, c: InsightTheme.ink3)),
          const SizedBox(height: 4),
          Text(
            value,
            style: InsightTheme.inter(
              15,
              w: FontWeight.w500,
              c: InsightTheme.ink,
            ),
          ),
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
  const SubmissionSuccessScreen({
    super.key,
    required this.referenceNo,
    required this.finalStatus,
    this.queuedOffline = false,
  });
  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    return Scaffold(
      backgroundColor: InsightTheme.bg,
      body: FieldFormBody(
        header: const SizedBox(height: 40),
        action: FieldPrimaryButton(
          label: 'Back to Tasks',
          onPressed: () async {
            InspectionProgress.instance.reset();
            final profileMap = await SupabaseService.fetchMyProfile();
            if (!context.mounted) return;
            if (profileMap != null) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (_) => MainShellScreen(
                    profile: UserProfile.fromMap(profileMap),
                    initialIndex: 1,
                  ),
                ),
                (route) => false,
              );
            } else {
              Navigator.of(context).popUntil((route) => route.isFirst);
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
                  queuedOffline ? 'Saved Offline' : 'Inspection Submitted',
                  textAlign: TextAlign.center,
                  style: InsightTheme.urbanist(24, w: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  queuedOffline
                      ? 'Saved on this device. It will sync automatically once you\'re back online; remote completion is not confirmed.'
                      : 'Your inspection was accepted by the server.',
                  textAlign: TextAlign.center,
                  style: InsightTheme.inter(14, c: InsightTheme.ink2),
                ),
                const SizedBox(height: 24),
                _SummaryRow(label: 'Inspection reference', value: referenceNo),
                _SummaryRow(
                  label: 'Final assessment',
                  value: finalStatus,
                  isLast: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
