import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tasks_screen.dart'; // Ensure TaskItem is accessible here
import 'site_map_screen.dart';
import 'gps_verification_screen.dart';
import 'inspection_checklist_screen.dart';
import 'capture_photo_screen.dart';
import 'field_findings_screen.dart';
import 'review_submit_screen.dart';
import 'inspection_progress.dart';
import 'package:provider/provider.dart';
import '../providers/inspection_provider.dart';

/// ==================================================================
/// THEME COLORS & TOKENS (InSight Blue Glass & Gradient Theme)
/// ==================================================================
class InsightTheme {
  static const Color bg = Color(0xFFF2F4FB);
  static const Color surface = Colors.white;
  static const Color surface2 = Color(0xFFEEF1FC);
  
  static const Color ink = Color(0xFF12141F);
  static const Color ink2 = Color(0xFF666C82);
  static const Color ink3 = Color(0xFFA2A7BC);
  
  static const Color blue1 = Color(0xFF3D6BFF);
  static const Color blue2 = Color(0xFF0B2FBF);
  static const Color blueTint = Color(0xFFE7EDFF);
  static const Color blueInk = Color(0xFF1A3FC4);
  
  static const Color line = Color(0x12141628); // ~rgba(20,22,40,0.07)
  static const Color lineStrong = Color(0x21141628); // ~rgba(20,22,40,0.13)
  
  static TextStyle poppins(double size, {FontWeight w = FontWeight.w600, Color? c, double? h, double? ls}) => 
      GoogleFonts.poppins(fontSize: size, fontWeight: w, color: c ?? ink, height: h ?? 1.2, letterSpacing: ls);
      
  static TextStyle inter(double size, {FontWeight w = FontWeight.w400, Color? c, double? h}) => 
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: c ?? ink2, height: h ?? 1.5);
      
  static TextStyle jetBrains(double size, {FontWeight w = FontWeight.w500, Color? c, double? ls}) => 
      GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: w, color: c ?? ink3, letterSpacing: ls);
}

/// ==================================================================
/// SCREEN 6 — INSPECTION DETAILS
/// ==================================================================
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
    // Starting a fresh inspection for this parcel shouldn't carry over
    // progress left behind from a different one.
    progress.ensureActiveInspection(task.id);
    progress.addListener(_onProgressChanged);

    // Reset/init the shared InspectionProvider session for this task so
    // the checklist, photo, and findings screens have something to write
    // into (and Review & Submit has something real to read from).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<InspectionProvider>().startInspection(task);
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

  /// Only lets the inspector open a step that's already done or is the
  /// current one — jumping ahead to a step whose prerequisites haven't
  /// been completed is what made the workflow feel disconnected before.
  void _goToStep(BuildContext context, int step, WidgetBuilder builder) {
    if (progress.isLocked(step)) {
      HapticFeedback.selectionClick();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Complete "${progress.currentStepTitle}" first.')),
      );
      return;
    }
    HapticFeedback.selectionClick();
    Navigator.push(context, MaterialPageRoute(builder: builder));
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    final currentStep = progress.currentStep;

    return Scaffold(
      backgroundColor: InsightTheme.bg,
      body: Stack(
        children: [
          // ----------------------------------------------------
          // BACKGROUND GRADIENT BLOBS (Matching HTML ::before / ::after)
          // ----------------------------------------------------
          Positioned(
            top: -60,
            right: -60,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: InsightTheme.blue1.withOpacity(0.20),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            left: -80,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: InsightTheme.blue1.withOpacity(0.10),
                ),
              ),
            ),
          ),

          // ----------------------------------------------------
          // MAIN CONTENT
          // ----------------------------------------------------
          SafeArea(
            child: Column(
              children: [
                // TOP BAR
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      _GlassBackButton(onTap: () => Navigator.pop(context)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Inspection details',
                          style: InsightTheme.poppins(17, w: FontWeight.w700, c: InsightTheme.ink),
                        ),
                      ),
                    ],
                  ),
                ),

                // PROGRESS BAR
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 6,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: InsightTheme.surface2,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: progress.isComplete ? 1.0 : (currentStep - 1) / InspectionProgress.totalSteps,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [InsightTheme.blue1, InsightTheme.blue2],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            progress.isComplete ? 'SUBMITTED' : 'STEP $currentStep OF ${InspectionProgress.totalSteps}',
                            style: InsightTheme.jetBrains(10, w: FontWeight.w700, c: InsightTheme.blueInk, ls: 0.5),
                          ),
                          Text(
                            progress.isComplete ? ' — READY FOR REVIEW' : ' — ${progress.currentStepTitle.toUpperCase()}',
                            style: InsightTheme.jetBrains(10, c: InsightTheme.ink3, ls: 0.5),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                // SCROLLABLE CONTENT
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      // DETAILS CARD
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: InsightTheme.surface,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: InsightTheme.line),
                          boxShadow: const [
                            BoxShadow(color: Color(0x0A141628), blurRadius: 2, offset: Offset(0, 1)),
                            BoxShadow(color: Color(0x0F141628), blurRadius: 30, offset: Offset(0, 14)),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(task.location, style: InsightTheme.inter(15, w: FontWeight.w600, c: InsightTheme.ink)),
                            const SizedBox(height: 4),
                            Text('Ref. no. ${task.inspectionNo}', style: InsightTheme.inter(11.5, c: InsightTheme.ink2)),
                            const SizedBox(height: 12),
                            
                            _buildListRow('Applicant', task.name),
                            _buildListRow('Project type', 'Residential reclassification'),
                            _buildListRow('Declared land use', 'Single-detached residential', isLast: true),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 18),
                      
                      // LOCATION SECTION LABEL
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 10, height: 2,
                            decoration: BoxDecoration(color: InsightTheme.blue1, borderRadius: BorderRadius.circular(1)),
                          ),
                          const SizedBox(width: 7),
                          Text('LOCATION', style: InsightTheme.jetBrains(10, w: FontWeight.w500, ls: 1.2)),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // LOCATION MAP CARD — tapping it opens Site verification,
                      // the same place Step 1 in the timeline below leads to.
                      GestureDetector(
                        onTap: () => _goToStep(context, 1, (_) => SiteMapScreen(task: task)),
                        child: Container(
                        decoration: BoxDecoration(
                          color: InsightTheme.surface,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: InsightTheme.line),
                          boxShadow: const [
                            BoxShadow(color: Color(0x0A141628), blurRadius: 2, offset: Offset(0, 1)),
                            BoxShadow(color: Color(0x0F141628), blurRadius: 30, offset: Offset(0, 14)),
                          ],
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Gradient Map Placeholder
                            Container(
                              height: 100,
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Color(0xFFE6EAFB), Color(0xFFD5DDF9)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                            ),
                            // Map Details
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Text(
                                'Brgy. Maligaya, Zone 3 · 340m from main road',
                                style: InsightTheme.inter(12, c: InsightTheme.ink2),
                              ),
                            ),
                          ],
                        ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      // INSPECTION STEPS TIMELINE (premium glass card)
                      _StepsTimelineCard(
                        currentStep: currentStep,
                        isComplete: progress.isComplete,
                        steps: [
                          _StepInfo(
                            index: 1,
                            title: 'Site verification',
                            icon: Icons.map_rounded,
                            onTap: () => _goToStep(
                              context,
                              1,
                              (_) => SiteMapScreen(task: task),
                            ),
                          ),
                          _StepInfo(
                            index: 2,
                            title: 'GPS verification',
                            icon: Icons.gps_fixed_rounded,
                            onTap: () => _goToStep(
                              context,
                              2,
                              (_) => GpsVerificationScreen(task: task),
                            ),
                          ),
                          _StepInfo(
                            index: 3,
                            title: 'Photos',
                            icon: Icons.photo_camera_rounded,
                            onTap: () => _goToStep(
                              context,
                              3,
                              (_) => CapturePhotoScreen(task: task),
                            ),
                          ),
                          _StepInfo(
                            index: 4,
                            title: 'Checklist',
                            icon: Icons.checklist_rounded,
                            onTap: () => _goToStep(
                              context,
                              4,
                              (_) => InspectionChecklistScreen(task: task),
                            ),
                          ),
                          _StepInfo(
                            index: 5,
                            title: 'Findings',
                            icon: Icons.fact_check_rounded,
                            onTap: () => _goToStep(
                              context,
                              5,
                              (_) => FieldFindingsScreen(task: task),
                            ),
                          ),
                          _StepInfo(
                            index: 6,
                            title: 'Review & submit',
                            icon: Icons.task_alt_rounded,
                            onTap: () => _goToStep(
                              context,
                              6,
                              (_) => ReviewSubmitScreen(task: task),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // PRIMARY CTA — always points at whatever comes next
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: ElevatedButton(
                    onPressed: progress.isComplete
                        ? null
                        : () => _goToStep(
                              context,
                              currentStep,
                              (_) => _screenForStep(currentStep),
                            ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      disabledBackgroundColor: Colors.transparent,
                    ).copyWith(elevation: WidgetStateProperty.all(0)),
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: progress.isComplete
                              ? [InsightTheme.ink3, InsightTheme.ink3]
                              : const [InsightTheme.blue1, InsightTheme.blue2],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: progress.isComplete
                            ? null
                            : [BoxShadow(color: InsightTheme.blue1.withOpacity(0.32), blurRadius: 22, offset: const Offset(0, 10))],
                      ),
                      child: Container(
                        alignment: Alignment.center,
                        constraints: const BoxConstraints(minHeight: 50),
                        child: Text(
                          progress.isComplete
                              ? 'Inspection submitted'
                              : 'Continue · ${InspectionProgress.stepTitles[currentStep - 1]}',
                          style: InsightTheme.poppins(14.5, w: FontWeight.w600, c: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Maps a step number to the screen that owns it — used by the
  /// "Continue" CTA so it always opens exactly what's next.
  Widget _screenForStep(int step) {
    switch (step) {
      case 1:
        return SiteMapScreen(task: task);
      case 2:
        return GpsVerificationScreen(task: task);
      case 3:
        return CapturePhotoScreen(task: task);
      case 4:
        return InspectionChecklistScreen(task: task);
      case 5:
        return FieldFindingsScreen(task: task);
      default:
        return ReviewSubmitScreen(task: task);
    }
  }

  Widget _buildListRow(String label, String value, {bool isLast = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: isLast ? null : const Border(bottom: BorderSide(color: InsightTheme.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: InsightTheme.inter(11.5, c: InsightTheme.ink2)),
          const SizedBox(height: 2),
          Text(value, style: InsightTheme.inter(13.5, w: FontWeight.w600, c: InsightTheme.ink)),
        ],
      ),
    );
  }
}

/// ==================================================================
/// STEP TIMELINE — premium, clickable inspection workflow tracker
/// ==================================================================
class _StepInfo {
  final int index;
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const _StepInfo({
    required this.index,
    required this.title,
    required this.icon,
    required this.onTap,
  });
}

class _StepsTimelineCard extends StatelessWidget {
  final List<_StepInfo> steps;
  final int currentStep;
  final bool isComplete;

  const _StepsTimelineCard({required this.steps, required this.currentStep, this.isComplete = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: InsightTheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: InsightTheme.line),
        boxShadow: const [
          BoxShadow(color: Color(0x0A141628), blurRadius: 2, offset: Offset(0, 1)),
          BoxShadow(color: Color(0x14141628), blurRadius: 36, offset: Offset(0, 16)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // HEADER
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 4),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [InsightTheme.blue1, InsightTheme.blue2],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(color: InsightTheme.blue1.withOpacity(0.30), blurRadius: 10, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: const Icon(Icons.route_rounded, size: 15, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Inspection workflow', style: InsightTheme.poppins(13.5, w: FontWeight.w700, c: InsightTheme.ink)),
                      const SizedBox(height: 1),
                      Text(
                        isComplete
                            ? 'All steps complete'
                            : 'Up next: Step $currentStep · ${InspectionProgress.stepTitles[currentStep - 1]}',
                        style: InsightTheme.inter(11, c: InsightTheme.ink3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
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
                );
              }),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final _StepInfo step;
  final bool isLast;
  final bool isCurrent;
  final bool isDone;
  final bool isLocked;

  const _StepRow({
    required this.step,
    required this.isLast,
    required this.isCurrent,
    required this.isDone,
    required this.isLocked,
  });

  @override
  Widget build(BuildContext context) {
    final Color labelColor = isLocked ? InsightTheme.ink3 : InsightTheme.ink;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          HapticFeedback.selectionClick();
          step.onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // BADGE + CONNECTOR LINE
                Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: isCurrent || isDone
                            ? const LinearGradient(
                                colors: [InsightTheme.blue1, InsightTheme.blue2],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        color: isCurrent || isDone ? null : InsightTheme.surface2,
                        border: isCurrent || isDone
                            ? null
                            : Border.all(color: InsightTheme.lineStrong, width: 1.4),
                        boxShadow: isCurrent
                            ? [BoxShadow(color: InsightTheme.blue1.withOpacity(0.30), blurRadius: 12, offset: const Offset(0, 5))]
                            : null,
                      ),
                      child: Icon(
                        isLocked ? Icons.lock_outline_rounded : step.icon,
                        size: 15,
                        color: isCurrent || isDone ? Colors.white : InsightTheme.ink3,
                      ),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                (isCurrent || isDone) ? InsightTheme.blue1.withOpacity(0.45) : InsightTheme.line,
                                InsightTheme.line,
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                // LABEL
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: isLast ? 0 : 18, top: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'STEP ${step.index} OF ${InspectionProgress.totalSteps}',
                                style: InsightTheme.jetBrains(9.5, w: FontWeight.w700, c: isCurrent ? InsightTheme.blueInk : InsightTheme.ink3, ls: 0.4),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                step.title,
                                style: InsightTheme.inter(13.5, w: FontWeight.w600, c: labelColor),
                              ),
                            ],
                          ),
                        ),
                        if (isCurrent)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: InsightTheme.blueTint,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Current',
                              style: InsightTheme.inter(10, w: FontWeight.w700, c: InsightTheme.blueInk),
                            ),
                          )
                        else if (isLocked)
                          Icon(Icons.lock_outline_rounded, size: 16, color: InsightTheme.ink3.withOpacity(0.6))
                        else
                          Icon(Icons.chevron_right_rounded, size: 20, color: InsightTheme.ink3.withOpacity(0.7)),
                      ],
                    ),
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

/// Glassmorphic back button matching the prototype
class _GlassBackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _GlassBackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.5),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Colors.white.withOpacity(0.65)),
          boxShadow: const [BoxShadow(color: Color(0x0F141628), blurRadius: 14, offset: Offset(0, 4))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: const Center(
              child: Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: InsightTheme.ink),
            ),
          ),
        ),
      ),
    );
  }
}