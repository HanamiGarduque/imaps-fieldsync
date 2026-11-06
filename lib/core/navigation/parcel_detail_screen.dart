import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
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
import '../../modules/inspection/widgets/inspection_protocol_view.dart';
import '../../modules/interactive_guide/guide_read_only_data.dart';
import '../../modules/interactive_guide/guide_examples.dart';
import '../../modules/interactive_guide/guide_targets.dart';

import '../theme/insight_theme.dart';
import '../widgets/field_form_widgets.dart';
import '../services/inspection_start_service.dart';
import '../services/db_helper.dart';
import '../services/sync_outbox_service.dart';

class ParcelDetailScreen extends StatefulWidget {
  final TaskItem task;
  final GuideReadOnlyData? walkthrough;
  final List<TaskItem> relatedRounds;

  // Dashboard supplies the real fetch; Tasks/offline entry uses its cached row.
  final Map<String, dynamic>? fetchedJob;

  const ParcelDetailScreen({super.key, required this.task, this.fetchedJob, this.relatedRounds = const [], this.walkthrough});

  @override
  State<ParcelDetailScreen> createState() => _ParcelDetailScreenState();
}

class _ParcelDetailScreenState extends State<ParcelDetailScreen> {
  TaskItem get task => widget.task;
  InspectionProgress get progress => InspectionProgress.instance;
  bool _enteringStep = false;
  Future<void>? _draftLoad;

  Future<void> _loadDraft() async {
    if (widget.walkthrough != null) return;
    if (task.lifecycleCategory == TaskLifecycleCategory.completed) return;
    final provider = context.read<InspectionProvider>();
    if (provider.activeTask?.id != task.id) {
      await provider.startInspection(task);
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.walkthrough != null) return;
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
    final bool sessionActive = widget.walkthrough == null &&
        provider.activeTask?.id == task.id && provider.capturedPhotos.isNotEmpty;
    final details = widget.walkthrough?.photos.isNotEmpty == true ? widget.walkthrough!.photos : sessionActive
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
                      child: AdaptivePhotoImage(path: displayPaths[i], allowNetwork: widget.walkthrough == null),
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
    if (widget.walkthrough != null) return;
    openFullscreenPhotoViewer(
      context,
      photoPaths,
      startIndex,
      photoDetails: details,
      jobId: task.id,
    );
  }

  Future<void> _goToStep(BuildContext context, int step, WidgetBuilder builder) async {
    if (widget.walkthrough != null) return;
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
    if (widget.walkthrough != null) return;
    context.read<InspectionProvider>().exitReworkMode();
    Navigator.pop(context);
  }

  Set<int> get _walkthroughCompleted => {
    if (task.currentStep >= 1 || task.stepTimestamps.containsKey(1)) 1,
    if (task.currentStep >= 2 || task.stepTimestamps.containsKey(2)) 2,
    ...InspectionProgress.deriveCompletedSteps(task.currentStep, task.stepTimestamps),
    if (task.currentStep >= 6 || task.stepTimestamps.containsKey(6)) 6,
  };

  InspectionProtocolStep _protocolStep({required int index, required String title,
    required String description, required IconData icon, required VoidCallback onTap}) {
    if (widget.walkthrough != null) {
      final saved = task.stepTimestamps[index];
      final completed = _walkthroughCompleted;
      final done = completed.contains(index);
      final current = [1, 2, 3, 4, 5, 6].firstWhere((step) => !completed.contains(step), orElse: () => 6);
      final locked = index <= 2 ? !done && index > current
        : index <= 5 ? !completed.contains(2)
        : ![3, 4, 5].every(completed.contains);
      return InspectionProtocolStep(index: index, title: title, description: description,
        icon: icon, onTap: onTap, done: done, current: !done && index == current, locked: locked, savedAt: saved);
    }
    final done = progress.isDone(index) || progress.isComplete;
    final current = progress.isCurrent(index) && !progress.isComplete;
    return InspectionProtocolStep(index: index, title: title, description: description,
      icon: icon, onTap: onTap, done: done, current: current, locked: !done && !current,
      savedAt: progress.completedAtFor(index) ?? task.stepTimestamps[index]);
  }

  @override
  Widget build(BuildContext context) {
    if (task.lifecycleCategory == TaskLifecycleCategory.completed) {
      return CompletedInspectionDetailScreen(task: task, historicalReadOnly: true, walkthrough: widget.walkthrough);
    }
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    final isReworkMode = widget.walkthrough == null && context.watch<InspectionProvider>().isReworkMode;

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
                      FieldBackButton(onPressed: () { if (widget.walkthrough == null) Navigator.pop(context); }),
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
                    // ponytail: 12k passive document cache; add explicit section
                    // navigation if it grows. Infinite caches break semantics.
                    scrollCacheExtent: widget.walkthrough == null ? null : const ScrollCacheExtent.pixels(12000),
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 40),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      widget.walkthrough?.canShowTaskExample == true
                        ? GuideSample(language: widget.walkthrough!.language, child: RoundContextCard(task: task))
                        : RoundContextCard(task: task),
                      const SizedBox(height: 12),
                      if (task.isReinspection) ...[
                        ReinspectionContextCard(task: task, rounds: widget.relatedRounds),
                        const SizedBox(height: 12),
                      ],
                      
                      InspectionProtocolView(
                        completedCount: widget.walkthrough == null ? progress.completedStepCount : _walkthroughCompleted.length,
                        isComplete: widget.walkthrough == null ? progress.isComplete : _walkthroughCompleted.length == 6,
                        steps: [
                          _protocolStep(index: 1, title: 'Site Verification', icon: Icons.map_rounded,
                            description: 'Pinpoint the exact application site.',
                            onTap: () => _goToStep(context, 1, (_) => SiteMapScreen(task: task))),
                          _protocolStep(index: 2, title: 'GPS Verification', icon: Icons.gps_fixed_rounded,
                            description: 'Confirm live location matches target.',
                            onTap: () => _goToStep(context, 2, (_) => GpsVerificationScreen(task: task))),
                          _protocolStep(index: 3, title: 'Photographic Evidence', icon: Icons.photo_camera_rounded,
                            description: 'Capture comprehensive site photos.',
                            onTap: () => _goToStep(context, 3, (_) => CapturePhotoScreen(task: task))),
                          _protocolStep(index: 4, title: 'Zoning Checklist', icon: Icons.checklist_rounded,
                            description: 'Evaluate standard compliance metrics.',
                            onTap: () => _goToStep(context, 4, (_) => InspectionChecklistScreen(task: task))),
                          _protocolStep(index: 5, title: 'Field Findings', icon: Icons.fact_check_rounded,
                            description: 'Log specific operational observations.',
                            onTap: () => _goToStep(context, 5, (_) => FieldFindingsScreen(task: task))),
                          _protocolStep(index: 6, title: 'Review & Submit', icon: Icons.cloud_upload_rounded,
                            description: 'Finalize and push the active report.',
                            onTap: () => _goToStep(context, 6, (_) => ReviewSubmitScreen(task: task))),
                        ],
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

                      GuideTarget(id: 'evidence_details', child: _GlassCard(
                        child: _photoStepSection(task),
                      )),

                      const SizedBox(height: 16),

                      Builder(builder: (context) {
                        final application = _GlassCard(
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
                                  Expanded(child: Text('Application Details', style: InsightTheme.poppins(13, w: FontWeight.w700, c: InsightTheme.ink))),
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
                        );
                        return widget.walkthrough?.canShowTaskExample == true
                          ? GuideSample(language: widget.walkthrough!.language, child: application) : application;
                      }),
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


// Fullscreen photo viewer moved to lib/modules/inspection/widgets/photo_viewer.dart
// (FullscreenPhotoViewer) so it's shared across every screen with task
// photos, not duplicated per-screen.
