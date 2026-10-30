import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../modules/tasks/screens/tasks_screen.dart'; 
import '../../modules/inspection/screens/site_map_screen.dart';
import '../../modules/inspection/screens/gps_verification_screen.dart';
import '../../modules/inspection/screens/inspection_checklist_screen.dart';
import '../../modules/inspection/screens/capture_photo_screen.dart';
import '../../modules/inspection/screens/field_findings_screen.dart';
import '../../modules/inspection/screens/review_submit_screen.dart';
import '../../modules/inspection/screens/inspection_progress.dart';
import '../../modules/inspection/providers/inspection_provider.dart';
import '../../core/widgets/sensitive_screen.dart';
import '../../modules/inspection/widgets/photo_viewer.dart';
import '../../modules/inspection/services/photo_source_resolver.dart';
import '../../modules/inspection/services/photo_evidence_presentation.dart';
import '../../modules/inspection/screens/completed_inspection_detail_screen.dart';
import '../../modules/inspection/widgets/inspection_round_widgets.dart';

import '../theme/insight_theme.dart';
import '../widgets/field_form_widgets.dart';
import '../services/inspection_start_service.dart';
import '../services/db_helper.dart';
import '../services/sync_outbox_service.dart';

class ParcelDetailScreen extends StatefulWidget {
  final TaskItem task;
  final List<TaskItem> relatedRounds;

  // Dashboard supplies the real fetch; Tasks/offline entry uses its cached row.
  final Map<String, dynamic>? fetchedJob;

  const ParcelDetailScreen({super.key, required this.task, this.fetchedJob, this.relatedRounds = const []});

  @override
  State<ParcelDetailScreen> createState() => _ParcelDetailScreenState();
}

class _ParcelDetailScreenState extends State<ParcelDetailScreen> {
  TaskItem get task => widget.task;
  InspectionProgress get progress => InspectionProgress.instance;
  bool _enteringStep = false;
  Future<void>? _draftLoad;

  Future<void> _loadDraft() async {
    if (task.lifecycleCategory == TaskLifecycleCategory.completed) return;
    final provider = context.read<InspectionProvider>();
    if (provider.activeTask?.id != task.id) {
      await provider.startInspection(task);
    }
  }

  @override
  void initState() {
    super.initState();
    if (task.lifecycleCategory == TaskLifecycleCategory.completed) return;
    progress.ensureActiveInspection(
      task.id,
      label: task.location,
      initialStep: task.currentStep > 0 ? task.currentStep : task.derivedHighestStep,
      // The persisted per-step times are what prove which of the
      // independent steps 3, 4 and 5 are really done.
      stepTimestamps: task.stepTimestamps.map(
        (key, value) => MapEntry(key.toString(), value),
      ),
    );
    progress.addListener(_onProgressChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await (_draftLoad ??= _loadDraft());
      } catch (e) {
        _draftLoad = null;
        debugPrint('Could not restore inspection draft: $e');
      }
    });
  }

  @override
  void dispose() {
    progress.removeListener(_onProgressChanged);
    super.dispose();
  }

  void _onProgressChanged() {
    if (mounted) setState(() {});
  }

  Widget _photoStepSection(TaskItem task) {
    // F2 fix (Task Overview photo refresh): the TaskItem snapshot is only
    // as fresh as the last My Tasks fetch, so photos taken this session
    // never appeared here. While THIS task is the active inspection, the
    // provider's capturedPhotos is the live source (including freshly
    // captured local paths); the task snapshot remains the fallback for
    // previously-uploaded remote photos. Display-only change — the Phase 8
    // persistence/outbox architecture is untouched.
    final provider = context.watch<InspectionProvider>();
    final bool sessionActive =
        provider.activeTask?.id == task.id && provider.capturedPhotos.isNotEmpty;
    final details = sessionActive
        ? provider.capturedPhotos.where((p) => (p['photoPath'] as String?)?.isNotEmpty == true).toList()
        : PhotoSourceResolver.evidence(task.photoDetails, task.photoPaths);
    final paths = details.map((p) => p['photoPath'] as String).toList();
    final displayPaths = inspectionDisplayPaths(
        paths, task.id, task.photoDetails, task.photoPaths);
    final evidence = PhotoEvidencePresentation(
      details,
      requireMetadata: !sessionActive || provider.isReworkMode,
    );
    Widget group(String heading, List<int> indices) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(heading, style: InsightTheme.inter(13, w: FontWeight.w600)),
        const SizedBox(height: 8),
        SizedBox(
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: indices.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, position) {
              final i = indices[position];
              return Semantics(
                button: true,
                label: evidence.semanticsAt(i),
                child: InkWell(
                  onTap: () => _openFullscreenPhoto(displayPaths, i, details),
                  borderRadius: BorderRadius.circular(12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 90,
                      height: 90,
                      child: AdaptivePhotoImage(path: displayPaths[i]),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
    return _sectionShell(
        step: 3,
        title: 'Evidence attachments',
        child: paths.isEmpty
            ? Text('No evidence attachments on file.', style: InsightTheme.inter(13))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (evidence.sitePhotoCount > 0)
                    group('Site photos', [
                      for (var i = 0; i < paths.length; i++)
                        if (evidence.isSitePhotoAt(i)) i,
                    ]),
                  if (evidence.referenceCount > 0) ...[
                    if (evidence.sitePhotoCount > 0) const SizedBox(height: 16),
                    const Icon(Icons.map_outlined, color: InsightTheme.ink2, size: 20),
                    const SizedBox(height: 8),
                    group('Site Location Reference', [
                      for (var i = 0; i < paths.length; i++)
                        if (evidence.isReferenceAt(i)) i,
                    ]),
                  ],
                  if (evidence.unclassifiedCount > 0) ...[
                    if (evidence.sitePhotoCount + evidence.referenceCount > 0)
                      const SizedBox(height: 16),
                    group('Evidence attachments (type unavailable)', [
                      for (var i = 0; i < paths.length; i++)
                        if (!evidence.isSitePhotoAt(i) && !evidence.isReferenceAt(i)) i,
                    ]),
                  ],
                ],
              ),
      );
  }

  void _openFullscreenPhoto(
    List<String> photoPaths,
    int startIndex,
    List<Map<String, dynamic>>? details,
  ) {
    openFullscreenPhotoViewer(
      context,
      photoPaths,
      startIndex,
      photoDetails: details,
      jobId: task.id,
    );
  }

  Future<void> _goToStep(BuildContext context, int step, WidgetBuilder builder) async {
    if (task.lifecycleCategory == TaskLifecycleCategory.completed) return;
    if (_enteringStep) return;
    if (progress.isLocked(step)) {
      HapticFeedback.selectionClick();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Complete "${progress.currentStepTitle}" first.')),
      );
      return;
    }
    _enteringStep = true;
    try {
      final provider = context.read<InspectionProvider>();
      if (!provider.isReworkMode) {
        // Task Overview is passive. The first actual normal step tap is the
        // durable boundary, repeated on resume before any step can proceed.
        final result = await InspectionStartService.prepareJob(
          task.id, fetchedJob: widget.fetchedJob,
        );
        if (!context.mounted) return;
        if (result != InspectionStartResult.authorized) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result.message)),
          );
          return;
        }
        // Task Overview stays passive. A verified, real step entry is the
        // deliberate start boundary. The existing outbox write atomically
        // persists local_jobs.status=in_progress and the owner-scoped
        // mark_ongoing delivery intent; no server receipt is claimed here.
        // Do not duplicate a start when returning to an ongoing inspection.
        final inspectorId = DBHelper.requireInspector();
        final cached = await (await DBHelper.database).query(
          'local_jobs',
          columns: ['status'],
          where: 'id = ? AND inspector_id = ?',
          whereArgs: [task.id, inspectorId],
          limit: 1,
        );
        DBHelper.requireSameInspector(inspectorId);
        if (cached.length != 1) {
          throw StateError('This inspection is unavailable on this device.');
        }
        if (const ['assigned', 'Pending', 'pending']
            .contains(cached.single['status'])) {
          await SyncOutboxService.enqueueMarkOngoing(jobId: task.id);
        }
        await (_draftLoad ??= _loadDraft());
      }
      if (!context.mounted) return;
      HapticFeedback.selectionClick();
      await Navigator.push(context, MaterialPageRoute(builder: builder));
      if (mounted) setState(() {});
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not prepare inspection for offline work: $e'),
      ));
    } finally {
      _enteringStep = false;
    }
  }

  void _handleExitRework() {
    context.read<InspectionProvider>().exitReworkMode();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (task.lifecycleCategory == TaskLifecycleCategory.completed) {
      return CompletedInspectionDetailScreen(task: task, historicalReadOnly: true);
    }
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    final currentStep = progress.currentStep;

    final isReworkMode = context.watch<InspectionProvider>().isReworkMode;

    return SensitiveScreen(child: Scaffold(
      backgroundColor: InsightTheme.bg,
      bottomNavigationBar: isReworkMode
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Rework redesign: no "Save All" — each step already
                    // auto-saves on its own, same as a normal inspection.
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Changes save automatically as you edit each step.',
                        style: InsightTheme.inter(11, c: InsightTheme.ink3),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    SizedBox(
                      height: 52,
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _handleExitRework,
                        style: FilledButton.styleFrom(
                          backgroundColor: InsightTheme.blue1,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Done Editing'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      FieldBackButton(onPressed: () => Navigator.pop(context)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Task Overview',
                          style: InsightTheme.poppins(18, w: FontWeight.w700, c: InsightTheme.ink),
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 40),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      RoundContextCard(task: task),
                      const SizedBox(height: 12),
                      if (task.isReinspection) ...[
                        ReinspectionContextCard(task: task, rounds: widget.relatedRounds),
                        const SizedBox(height: 12),
                      ],
                      
                      _GlassCard(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('INSPECTION PROTOCOL', style: InsightTheme.jetBrains(10, w: FontWeight.w700, c: InsightTheme.ink3, ls: 1.0)),
                              const SizedBox(height: 12),
                              
                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: InsightTheme.surface2,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                      child: FractionallySizedBox(
                                        alignment: Alignment.centerLeft,
                                        widthFactor: progress.isComplete ? 1.0 : progress.completedStepCount / InspectionProgress.totalSteps,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: InsightTheme.blue1,
                                            borderRadius: BorderRadius.circular(2),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    progress.isComplete ? '100%' : '${(progress.completedStepCount / InspectionProgress.totalSteps * 100).toInt()}%',
                                    style: InsightTheme.jetBrains(11, w: FontWeight.w700, c: InsightTheme.ink),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              if (progress.completedStepCount >= 2) ...[
                                Text(
                                  'Steps 3–5 are independent: open them in any '
                                  'order and come back to the rest. Each step '
                                  'keeps its own saved status.',
                                  style: InsightTheme.inter(11, c: InsightTheme.ink3),
                                ),
                                const SizedBox(height: 12),
                              ],

                              _StepsTimelineCard(
                                currentStep: currentStep,
                                isComplete: progress.isComplete,
                                // Each step shows its own real status: the
                                // independent steps 3-5 are never shown as
                                // done just because a later step was reached.
                                isStepDone: progress.isDone,
                                isStepCurrent: progress.isCurrent,
                                isStepLocked: progress.isLocked,
                                // F1 fix: live times recorded this session for
                                // the active task, merged over the persisted
                                // step_timestamps fetched with the task.
                                savedTimes: {
                                  ...task.stepTimestamps,
                                  ...InspectionProgress.instance.stepCompletedAt,
                                },
                                steps: [
                                  _StepInfo(
                                    index: 1, title: 'Site Verification', icon: Icons.map_rounded,
                                    description: 'Pinpoint the exact application site.',
                                    onTap: () => _goToStep(context, 1, (_) => SiteMapScreen(task: task)),
                                  ),
                                  _StepInfo(
                                    index: 2, title: 'GPS Verification', icon: Icons.gps_fixed_rounded,
                                    description: 'Confirm live location matches target.',
                                    onTap: () => _goToStep(context, 2, (_) => GpsVerificationScreen(task: task)),
                                  ),
                                  _StepInfo(
                                    index: 3, title: 'Photographic Evidence', icon: Icons.photo_camera_rounded,
                                    description: 'Capture comprehensive site photos.',
                                    onTap: () => _goToStep(context, 3, (_) => CapturePhotoScreen(task: task)),
                                  ),
                                  _StepInfo(
                                    index: 4, title: 'Zoning Checklist', icon: Icons.checklist_rounded,
                                    description: 'Evaluate standard compliance metrics.',
                                    onTap: () => _goToStep(context, 4, (_) => InspectionChecklistScreen(task: task)),
                                  ),
                                  _StepInfo(
                                    index: 5, title: 'Field Findings', icon: Icons.fact_check_rounded,
                                    description: 'Log specific operational observations.',
                                    onTap: () => _goToStep(context, 5, (_) => FieldFindingsScreen(task: task)),
                                  ),
                                  _StepInfo(
                                    index: 6, title: 'Review & Submit', icon: Icons.cloud_upload_rounded,
                                    description: 'Finalize and push the active report.',
                                    onTap: () => _goToStep(context, 6, (_) => ReviewSubmitScreen(task: task)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      if (task.assignmentInstructions?.trim().isNotEmpty == true ||
                          task.assignedByName?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 16),
                        _GlassCard(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (task.assignmentInstructions?.trim().isNotEmpty == true) ...[
                                  Text('Assignment Instructions', style: InsightTheme.urbanist(18, w: FontWeight.w700)),
                                  const SizedBox(height: 8),
                                  Text(
                                    task.assignmentInstructions!,
                                    style: InsightTheme.inter(13, w: FontWeight.w400, c: InsightTheme.ink),
                                  ),
                                ],
                                if (task.assignmentInstructions?.trim().isNotEmpty == true &&
                                    task.assignedByName?.trim().isNotEmpty == true)
                                  const Divider(height: 17, color: InsightTheme.line),
                                if (task.assignedByName?.trim().isNotEmpty == true) ...[
                                  Text('Assigned by', style: InsightTheme.inter(12, w: FontWeight.w600, c: InsightTheme.ink3)),
                                  const SizedBox(height: 4),
                                  Text(task.assignedByName!, style: InsightTheme.inter(14, w: FontWeight.w500)),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),

                      _GlassCard(
                        child: _photoStepSection(task),
                      ),

                      const SizedBox(height: 16),

                      _GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(color: InsightTheme.surface2, borderRadius: BorderRadius.circular(6)),
                                    child: const Icon(Icons.description_outlined, color: InsightTheme.ink2, size: 16),
                                  ),
                                  const SizedBox(width: 10),
                                  Text('Application Details', style: InsightTheme.poppins(13, w: FontWeight.w700, c: InsightTheme.ink)),
                                ],
                              ),
                            ),
                            Container(color: InsightTheme.line, height: 1),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              child: Column(
                                children: [
                                  _buildDataRow('Applicant', task.name),
                                  _buildDataRow('Inspection ID', task.inspectionNo),
                                  _buildDataRow('Target Location', task.location),
                                  _buildDataRow('Classification', task.applicationType ?? 'Zoning Evaluation'),
                                  _buildDataRow('Land Use Focus', task.landUseClass, isLast: true),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ));
  }

  Widget _sectionShell({required int step, required String title, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: InsightTheme.poppins(13, w: FontWeight.w700, c: InsightTheme.ink)),
              ),
              Text(
                'Step $step',
                style: InsightTheme.jetBrains(10, w: FontWeight.w700, c: InsightTheme.ink3, ls: 0.6),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildDataRow(String label, String value, {bool isLast = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: isLast ? null : const Border(bottom: BorderSide(color: InsightTheme.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: InsightTheme.inter(12, c: InsightTheme.ink2, w: FontWeight.w500)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              value, 
              style: InsightTheme.inter(12, w: FontWeight.w600, c: InsightTheme.ink),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: InsightTheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: kCardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: child,
      ),
    );
  }
}

class _StepInfo {
  final int index;
  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onTap;

  const _StepInfo({
    required this.index, 
    required this.title, 
    required this.description, 
    required this.icon, 
    required this.onTap
  });
}

class _StepsTimelineCard extends StatelessWidget {
  final List<_StepInfo> steps;
  final int currentStep;
  final bool isComplete;
  // Per-step truth from InspectionProgress: the independent steps 3-5 each
  // have their own completion, so a later step never marks an earlier one
  // as done.
  final bool Function(int step) isStepDone;
  final bool Function(int step) isStepCurrent;
  final bool Function(int step) isStepLocked;
  // F1 fix: real per-step saved times (step number -> ISO8601). Resolved
  // by the parent: live InspectionProgress entries for the active task,
  // falling back to the task's persisted step_timestamps.
  final Map<int, String> savedTimes;

  const _StepsTimelineCard({
    required this.steps, required this.currentStep, this.isComplete = false,
    required this.isStepDone, required this.isStepCurrent, required this.isStepLocked,
    this.savedTimes = const <int, String>{},
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(steps.length, (i) {
        final step = steps[i];
        final isLast = i == steps.length - 1;
        final isCurrent = isStepCurrent(step.index) && !isComplete;
        final isDone = isStepDone(step.index) || isComplete;
        final isLocked = !isDone && !isCurrent;
        return _StepRow(
          step: step,
          isLast: isLast,
          isCurrent: isCurrent,
          isDone: isDone,
          isLocked: isLocked,
          savedAt: savedTimes[step.index],
        );
      }),
    );
  }
}

class _StepRow extends StatelessWidget {
  final _StepInfo step;
  final bool isLast;
  final bool isCurrent;
  final bool isDone;
  final bool isLocked;
  // F1 fix: real saved time for this step (ISO8601), resolved by the
  // parent from live InspectionProgress data or the task's stored
  // step_timestamps. Replaces the old simulated "Verified on" text.
  final String? savedAt;

  const _StepRow({
    required this.step, required this.isLast, required this.isCurrent,
    required this.isDone, required this.isLocked, this.savedAt,
  });

  /// Formats a stored UTC ISO timestamp as e.g. "Aug 25, 3:45 PM".
  String _formatSavedAt(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final month = months[dt.month - 1];
      final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
      final amPm = dt.hour >= 12 ? 'PM' : 'AM';
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$month ${dt.day}, $hour:$minute $amPm';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final markerSize = MediaQuery.textScalerOf(context).scale(12) * 2 + 8;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 6),
      constraints: const BoxConstraints(minHeight: 48),
      decoration: BoxDecoration(
        color: isCurrent ? InsightTheme.surface2 : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            HapticFeedback.selectionClick();
            step.onTap();
          },
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    children: [
                      Container(
                        width: markerSize, height: markerSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDone ? InsightTheme.greenTint : (isCurrent ? InsightTheme.blue1 : InsightTheme.surface2),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          step.index.toString().padLeft(2, '0'),
                          style: InsightTheme.inter(12, w: FontWeight.w700,
                              c: isDone ? InsightTheme.greenInk : (isCurrent ? Colors.white : InsightTheme.ink3)),
                        ),
                      ),
                      if (!isLast)
                        Expanded(
                          child: Container(
                            width: 2,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            color: isDone ? InsightTheme.green.withValues(alpha: 0.35) : InsightTheme.line,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: isLast ? 0 : 4, top: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                  step.title, 
                                  style: InsightTheme.poppins(13.5, w: FontWeight.w600, c: isLocked ? InsightTheme.ink3 : InsightTheme.ink),
                              ),
                              if (isLocked)
                                const Icon(Icons.lock_outline_rounded, size: 14, color: InsightTheme.ink3),
                              if (isCurrent)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: InsightTheme.blue1, 
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: const [
                                      BoxShadow(color: Color(0x283563FF), blurRadius: 6, offset: Offset(0, 2))
                                    ],
                                  ),
                                  child: Text('Start Task', style: InsightTheme.inter(10.5, w: FontWeight.w700, c: Colors.white)),
                                )
                            ],
                          ),
                          const SizedBox(height: 2),
                          if (isDone)
                             Row(
                               children: [
                                 const Icon(Icons.verified_rounded, size: 12, color: InsightTheme.greenInk),
                                 const SizedBox(width: 4),
                                 Expanded(
                                   child: Text(
                                     // F1 fix: real per-task, per-step saved
                                     // time (replaces the old simulated text).
                                     savedAt != null
                                         ? 'Saved on ${_formatSavedAt(savedAt!)}'
                                         : 'Completed',
                                     style: InsightTheme.inter(11, w: FontWeight.w500, c: InsightTheme.greenInk),
                                   ),
                                 ),
                               ],
                             )
                          else
                            Text(
                              step.description,
                              style: InsightTheme.inter(11, w: FontWeight.w400, c: isLocked ? InsightTheme.ink3 : InsightTheme.ink2),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


// Fullscreen photo viewer moved to lib/modules/inspection/widgets/photo_viewer.dart
// (FullscreenPhotoViewer) so it's shared across every screen with task
// photos, not duplicated per-screen.
