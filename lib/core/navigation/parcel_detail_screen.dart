import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
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

import '../theme/insight_theme.dart';

class ParcelDetailScreen extends StatefulWidget {
  final TaskItem task;

  const ParcelDetailScreen({super.key, required this.task});

  @override
  State<ParcelDetailScreen> createState() => _ParcelDetailScreenState();
}

class _ParcelDetailScreenState extends State<ParcelDetailScreen> {
  TaskItem get task => widget.task;
  InspectionProgress get progress => InspectionProgress.instance;

  @override
  void initState() {
    super.initState();
    progress.ensureActiveInspection(
      task.id,
      label: task.location,
      initialStep: task.currentStep > 0 ? task.currentStep : task.derivedHighestStep,
    );
    progress.addListener(_onProgressChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (context.read<InspectionProvider>().activeTask?.id != widget.task.id) {
        await context.read<InspectionProvider>().startInspection(widget.task);
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
    final List<String> paths = sessionActive
        ? provider.capturedPhotos
            .map((p) => p['photoPath'] as String? ?? '')
            .where((p) => p.isNotEmpty)
            .toList()
        : (task.photoDetails.isNotEmpty
            ? task.photoDetails
                .map((p) => p['photo_url'] as String? ?? '')
                .where((p) => p.isNotEmpty)
                .toList()
            : task.photoPaths);
    return _sectionShell(
        step: 3,
        title: 'Photos',
        child: paths.isEmpty
            ? Text('No photos on file.', style: InsightTheme.inter(13))
            : SizedBox(
                height: 90,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: paths.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: () => _openFullscreenPhoto(paths, i),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      // AdaptivePhotoImage renders BOTH freshly-captured
                      // local files and already-uploaded Storage URLs.
                      child: SizedBox(
                        width: 90,
                        height: 90,
                        child: AdaptivePhotoImage(path: paths[i]),
                      ),
                    ),
                  ),
                ),
              ),
      );
  }

  void _openFullscreenPhoto(List<String> photoPaths, int startIndex) {
    openFullscreenPhotoViewer(context, photoPaths, startIndex);
  }

  void _goToStep(BuildContext context, int step, WidgetBuilder builder) {
    if (progress.isLocked(step)) {
      HapticFeedback.selectionClick();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Complete "${progress.currentStepTitle}" first.')),
      );
      return;
    }
    HapticFeedback.selectionClick();
    // F2 fix (Task Overview photo refresh): rebuild when control returns
    // from a step so sections backed by live provider state (e.g. Photos)
    // reflect saves made inside the step — mirrors the Completed Summary's
    // reload-on-return behavior without changing any persistence path.
    Navigator.push(context, MaterialPageRoute(builder: builder)).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _handleExitRework() {
    context.read<InspectionProvider>().exitReworkMode();
    Navigator.pop(context);
  }

  void _showSupportSheet(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: InsightTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: InsightTheme.line, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text('Support & Options', style: InsightTheme.poppins(16, w: FontWeight.w700)),
            const SizedBox(height: 16),
            _SupportActionTile(
              icon: Icons.person_off_outlined,
              title: 'Reassign Task',
              subtitle: 'Send this inspection to another available officer.',
              color: InsightTheme.ink,
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Requesting task reassignment...', style: InsightTheme.inter(12, c: Colors.white))));
              },
            ),
            const Divider(color: InsightTheme.line),
            _SupportActionTile(
              icon: Icons.flag_outlined,
              title: 'Report Issue',
              subtitle: 'Flag an operational blocker to the MPDO.',
              color: Colors.red.shade700,
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Flagging issue to monitoring system...', style: InsightTheme.inter(12, c: Colors.white))));
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    final currentStep = progress.currentStep;
    
    int remainingSteps = progress.isComplete ? 0 : (InspectionProgress.totalSteps - currentStep + 1);
    int estTimeMinutes = remainingSteps * 5; 

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
          Positioned(
            top: -40, right: -40,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
              child: Container(
                width: 220, height: 220,
                decoration: BoxDecoration(shape: BoxShape.circle, color: InsightTheme.blue1.withValues(alpha: 0.12)),
              ),
            ),
          ),
          
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      _GlassBackButton(onTap: () => Navigator.pop(context)),
                      const SizedBox(width: 14),
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
                                        widthFactor: progress.isComplete ? 1.0 : (currentStep - 1) / InspectionProgress.totalSteps,
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
                                    progress.isComplete ? '100%' : '${((currentStep - 1) / InspectionProgress.totalSteps * 100).toInt()}%',
                                    style: InsightTheme.jetBrains(11, w: FontWeight.w700, c: InsightTheme.ink),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              
                              _StepsTimelineCard(
                                currentStep: currentStep,
                                isComplete: progress.isComplete,
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

class _SupportActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _SupportActionTile({required this.icon, required this.title, required this.subtitle, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: InsightTheme.poppins(14, w: FontWeight.w600, c: color)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: InsightTheme.inter(12, c: InsightTheme.ink2)),
                ],
              ),
            )
          ],
        ),
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
  // F1 fix: real per-step saved times (step number -> ISO8601). Resolved
  // by the parent: live InspectionProgress entries for the active task,
  // falling back to the task's persisted step_timestamps.
  final Map<int, String> savedTimes;

  const _StepsTimelineCard({
    required this.steps, required this.currentStep, this.isComplete = false,
    this.savedTimes = const <int, String>{},
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(steps.length, (i) {
        final step = steps[i];
        final isLast = i == steps.length - 1;
        final isCurrent = step.index == currentStep && !isComplete;
        final isDone = step.index < currentStep || isComplete;
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 6),
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
            padding: EdgeInsets.all(isCurrent ? 12 : 6),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDone ? InsightTheme.greenTint : (isCurrent ? InsightTheme.blue1 : InsightTheme.surface2),
                        ),
                        child: Icon(
                          isDone ? Icons.check_rounded : (isLocked ? Icons.lock_outline_rounded : step.icon),
                          size: 13,
                          color: isDone ? InsightTheme.greenInk : (isCurrent ? Colors.white : InsightTheme.ink3),
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
                      padding: EdgeInsets.only(bottom: isLast ? 0 : 10, top: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  step.title, 
                                  style: InsightTheme.poppins(13.5, w: FontWeight.w600, c: isLocked ? InsightTheme.ink3 : InsightTheme.ink),
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                ),
                              ),
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
                                     maxLines: 1, overflow: TextOverflow.ellipsis,
                                   ),
                                 ),
                               ],
                             )
                          else
                            Text(
                              step.description,
                              style: InsightTheme.inter(11, w: FontWeight.w400, c: isLocked ? InsightTheme.ink3 : InsightTheme.ink2),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
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

class _GlassBackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _GlassBackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
          boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: const Center(
              child: Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: InsightTheme.ink),
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