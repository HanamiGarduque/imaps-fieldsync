import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/inspection_provider.dart';
import '../services/supabase_service.dart';
import 'inspection_progress.dart';
import 'tasks_screen.dart'; // TaskItem
import '../models/user_profile.dart';

import '../theme/insight_theme.dart';

/// ==================================================================
/// SCREEN 14 — REVIEW & SUBMIT
/// ==================================================================
/// Accepts the same params FieldFindingsScreen passes (task, photos,
/// checklist counts) so that call site keeps working, but ParcelDetailScreen's
/// "jump straight to step 6" shortcut (which only passes `task`) also works —
/// the other 3 are optional and, when omitted, we fall back to whatever is
/// already tracked in the shared InspectionProvider for this active task.
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
  // Same 4 options used by the (now legacy/standalone) InspectionResultScreen —
  // kept here since this is where final-status selection actually lives now.
  static const _statusOptions = [
    (title: 'Compliant', subtitle: 'Matches declared use, no issues'),
    (title: 'With Discrepancy', subtitle: 'Observed use differs from declared'),
    (title: 'For Review', subtitle: 'Needs supervisor sign-off'),
    (title: 'Requires Reinspection', subtitle: 'Site access or conditions incomplete'),
  ];

  late String _selectedStatus;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // Carry over whatever result was already picked back in the Findings step.
    final provider = context.read<InspectionProvider>();
    _selectedStatus = provider.inspectionResult;
  }

  Future<void> _handleSubmit() async {
    if (_submitting) return;
    HapticFeedback.heavyImpact();
    setState(() => _submitting = true);

    final provider = context.read<InspectionProvider>();

    try {
      // Merge both checklist sections into one flat list for the backend.
      final checklist = <Map<String, dynamic>>[
        ...provider.siteCondition.entries.map((e) => {'item': e.key, 'checked': e.value}),
        ...provider.zoningObservations.entries.map((e) => {'item': e.key, 'checked': e.value}),
      ];
      final checklistCompleted = checklist.where((c) => c['checked'] == true).length;

      final photoPaths = provider.capturedPhotos
          .map((p) => (p['photoPath'] as String?) ?? '')
          .where((p) => p.isNotEmpty)
          .toList();

      await SupabaseService.submitInspection(
        jobId: widget.task.id,
        findings: provider.notes,
        isCompliant: _selectedStatus == 'Compliant',
        inspectionResult: _selectedStatus,
        observations: 'Actual land use: ${provider.actualLandUse}. Boundary status: ${provider.boundaryStatus}.',
        discrepancies: provider.discrepancies.isNotEmpty ? provider.discrepancies : null,
        recommendations: provider.recommendations.isNotEmpty ? provider.recommendations : null,
        inspectorNotes: provider.notes,
        checklistData: checklist,
        checklistCompletedCount: checklistCompleted,
        checklistTotalCount: checklist.length,
        photoPaths: photoPaths,
        photoCount: photoPaths.length,
      );

      InspectionProgress.instance.markStepComplete(6);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SubmissionSuccessScreen(
            referenceNo: widget.task.inspectionNo,
            finalStatus: _selectedStatus,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit inspection: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    // Prefer the live provider state (source of truth for the whole
    // 6-step flow); fall back to whatever was passed in via constructor
    // for the "jump straight here" shortcut where the provider might not
    // have been freshly populated for this session.
    final provider = context.watch<InspectionProvider>();
    final photoCount = provider.capturedPhotos.isNotEmpty
        ? provider.capturedPhotos.length
        : widget.capturedPhotos.length;
    final checklistTotal = provider.siteCondition.length + provider.zoningObservations.length;
    final checklistDone = provider.siteCondition.values.where((v) => v).length +
        provider.zoningObservations.values.where((v) => v).length;
    final effectiveChecklistTotal = checklistTotal > 0 ? checklistTotal : widget.checklistTotal;
    final effectiveChecklistDone = checklistTotal > 0 ? checklistDone : widget.checklistDone;

    return Scaffold(
      backgroundColor: InsightTheme.bg,
      body: Stack(
        children: [
          // ----------------------------------------------------
          // BACKGROUND GRADIENT BLOBS
          // ----------------------------------------------------
          Positioned(
            top: -60, right: -60,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                width: 260, height: 260,
                decoration: BoxDecoration(shape: BoxShape.circle, color: InsightTheme.blue1.withOpacity(0.20)),
              ),
            ),
          ),
          Positioned(
            bottom: -80, left: -80,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                width: 220, height: 220,
                decoration: BoxDecoration(shape: BoxShape.circle, color: InsightTheme.blue1.withOpacity(0.10)),
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Review & submit', style: InsightTheme.poppins(17, w: FontWeight.w700)),
                            Text(
                              widget.task.location,
                              style: InsightTheme.inter(11.5, c: InsightTheme.ink2),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // PROGRESS BAR
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 6, width: double.infinity,
                        decoration: BoxDecoration(color: InsightTheme.surface2, borderRadius: BorderRadius.circular(4)),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: 1.0, // 100% Step 6 of 6
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [InsightTheme.blue1, InsightTheme.blue2]),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text('STEP 6 OF 6', style: InsightTheme.jetBrains(10, w: FontWeight.w700, c: InsightTheme.blueInk, ls: 0.5)),
                          Text(' — REVIEW & SUBMIT', style: InsightTheme.jetBrains(10, c: InsightTheme.ink3, ls: 0.5)),
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
                      // SUMMARY CARD — now reflects real data from InspectionProvider
                      // instead of hardcoded numbers unrelated to this inspection.
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                          children: [
                            _SummaryRow(label: 'Site', value: widget.task.location),
                            _SummaryRow(
                              label: 'Checklist',
                              value: effectiveChecklistTotal > 0
                                  ? '$effectiveChecklistDone of $effectiveChecklistTotal items reviewed'
                                  : 'No checklist items recorded',
                            ),
                            _SummaryRow(
                              label: 'Photos',
                              value: photoCount > 0 ? '$photoCount geotagged photo${photoCount == 1 ? '' : 's'}' : 'No photos attached',
                            ),
                            _SummaryRow(label: 'Result', value: _selectedStatus, isLast: true),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // FINAL STATUS SECTION
                      const _SectionLabel(title: 'FINAL STATUS'),
                      const SizedBox(height: 10),
                      ..._statusOptions.map((o) => _ResultOption(
                            title: o.title,
                            subtitle: o.subtitle,
                            isSelected: _selectedStatus == o.title,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _selectedStatus = o.title);
                              context.read<InspectionProvider>().updateResult(o.title);
                            },
                          )),

                      const SizedBox(height: 24),

                      // SIGNATURE SECTION
                      const _SectionLabel(title: 'INSPECTOR SIGNATURE'),
                      const SizedBox(height: 10),
                      Container(
                        height: 120,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: InsightTheme.surface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: InsightTheme.lineStrong, width: 1.5),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 130, height: 44,
                              child: CustomPaint(painter: _SignaturePainter()),
                            ),
                            Positioned(
                              bottom: 10,
                              child: Text(
                                'Signed by ${widget.task.name}',
                                style: InsightTheme.jetBrains(10, c: InsightTheme.ink3),
                              ),
                            )
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // BOTTOM ACTION BUTTON
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _handleSubmit,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      disabledBackgroundColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ).copyWith(elevation: WidgetStateProperty.all(0)),
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _submitting
                              ? [InsightTheme.blue1.withOpacity(0.5), InsightTheme.blue2.withOpacity(0.5)]
                              : [InsightTheme.blue1, InsightTheme.blue2],
                          begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: _submitting ? [] : [
                          BoxShadow(color: InsightTheme.blue1.withOpacity(0.32), blurRadius: 22, offset: const Offset(0, 10)),
                        ],
                      ),
                      child: Container(
                        alignment: Alignment.center,
                        constraints: const BoxConstraints(minHeight: 50),
                        child: _submitting
                            ? const SizedBox(
                                width: 22, height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                              )
                            : Text('Submit inspection', style: InsightTheme.poppins(14.5, w: FontWeight.w600, c: Colors.white)),
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
}

/// ==================================================================
/// SCREEN 15 — SUBMISSION SUCCESS
/// ==================================================================
class SubmissionSuccessScreen extends StatelessWidget {
  final String referenceNo;
  final String finalStatus;
  const SubmissionSuccessScreen({super.key, required this.referenceNo, required this.finalStatus});

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    return Scaffold(
      backgroundColor: InsightTheme.bg,
      body: Stack(
        children: [
          Positioned(
            top: -60, right: -60,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                width: 260, height: 260,
                decoration: BoxDecoration(shape: BoxShape.circle, color: InsightTheme.blue1.withOpacity(0.20)),
              ),
            ),
          ),
          Positioned(
            bottom: -80, left: -80,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                width: 220, height: 220,
                decoration: BoxDecoration(shape: BoxShape.circle, color: InsightTheme.blue1.withOpacity(0.10)),
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 88, height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [InsightTheme.green, Color(0xFF0D7A3C)],
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(color: InsightTheme.green.withOpacity(0.35), blurRadius: 28, offset: const Offset(0, 14))
                        ],
                      ),
                      child: const Icon(Icons.check_rounded, color: Colors.white, size: 38),
                    ),
                    const SizedBox(height: 22),
                    Text('Inspection submitted', style: InsightTheme.poppins(19, w: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(
                      'Reference no. $referenceNo has been recorded as "$finalStatus" and sent for review.',
                      textAlign: TextAlign.center,
                      style: InsightTheme.inter(12.5, c: InsightTheme.ink2, h: 1.6),
                    ),
                    const SizedBox(height: 24),

                    SizedBox(
                      width: 220,
                      child: ElevatedButton(
                        onPressed: () async {
                          HapticFeedback.lightImpact();
                          InspectionProgress.instance.reset();
                          final profileMap = await SupabaseService.fetchMyProfile();
                          if (!context.mounted) return;

                          if (profileMap != null) {
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(
                                builder: (_) => TasksScreen(profile: UserProfile.fromMap(profileMap)),
                              ),
                              (route) => false,
                            );
                          } else {
                            // Fallback lang kung sakaling di makuha ang profile
                            Navigator.of(context).popUntil((route) => route.isFirst);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ).copyWith(elevation: WidgetStateProperty.all(0)),
                        child: Ink(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [InsightTheme.blue1, InsightTheme.blue2],
                              begin: Alignment.topCenter, end: Alignment.bottomCenter,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(color: InsightTheme.blue1.withOpacity(0.32), blurRadius: 22, offset: const Offset(0, 10)),
                            ],
                          ),
                          child: Container(
                            alignment: Alignment.center,
                            constraints: const BoxConstraints(minHeight: 50),
                            child: Text('Back to home', style: InsightTheme.poppins(14.5, w: FontWeight.w600, c: Colors.white)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ==================================================================
/// COMPONENT WIDGETS
/// ==================================================================

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isLast;

  const _SummaryRow({required this.label, required this.value, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: isLast ? null : const Border(bottom: BorderSide(color: InsightTheme.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: InsightTheme.inter(11.5, c: InsightTheme.ink2)),
                const SizedBox(height: 3),
                Text(value, style: InsightTheme.inter(13.5, w: FontWeight.w600, c: InsightTheme.ink)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String title;
  const _SectionLabel({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 10, height: 2,
          decoration: BoxDecoration(color: InsightTheme.blue1, borderRadius: BorderRadius.circular(1)),
        ),
        const SizedBox(width: 7),
        Text(title, style: InsightTheme.jetBrains(10, w: FontWeight.w500, ls: 1.2)),
      ],
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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: isSelected
              ? const LinearGradient(
                  colors: [InsightTheme.blue1, InsightTheme.blue2],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isSelected ? null : InsightTheme.surface,
          border: isSelected ? null : Border.all(color: InsightTheme.line, width: 1.5),
          boxShadow: isSelected
              ? [BoxShadow(color: InsightTheme.blue1.withOpacity(0.3), blurRadius: 22, offset: const Offset(0, 10))]
              : [const BoxShadow(color: Color(0x0A141628), blurRadius: 2, offset: Offset(0, 1))],
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22, height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? Colors.white.withOpacity(0.9) : Colors.transparent,
                border: Border.all(
                  color: isSelected ? Colors.white : InsightTheme.lineStrong,
                  width: isSelected ? 5 : 2,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: InsightTheme.inter(13.5, w: FontWeight.w600, c: isSelected ? Colors.white : InsightTheme.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: InsightTheme.inter(11.5, c: isSelected ? Colors.white.withOpacity(0.85) : InsightTheme.ink2),
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

/// Custom painter to replicate the HTML SVG signature curve
class _SignaturePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = InsightTheme.blue1
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    path.moveTo(size.width * 0.07, size.height * 0.7);
    path.quadraticBezierTo(size.width * 0.18, size.height * 0.2, size.width * 0.28, size.height * 0.64);
    path.quadraticBezierTo(size.width * 0.38, size.height * 1.08, size.width * 0.50, size.height * 0.60);
    path.quadraticBezierTo(size.width * 0.60, size.height * 0.3, size.width * 0.71, size.height * 0.64);
    path.quadraticBezierTo(size.width * 0.82, size.height * 0.98, size.width * 0.92, size.height * 0.56);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}