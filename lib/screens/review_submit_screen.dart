import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/inspection_provider.dart';
import '../services/supabase_service.dart';
import '../services/sync_outbox_service.dart';
import 'inspection_progress.dart';
import 'tasks_screen.dart'; 
import '../models/user_profile.dart';
import '../widgets/exit_confirm_dialog.dart';

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
  static const Color green = Color(0xFF12A150);
  static const Color greenTint = Color(0xFFE3F8EC); 
  static const Color greenInk = Color(0xFF0D7A3C); 
  static const Color line = Color(0x1A141628); 
  static const Color lineStrong = Color(0x2A141628); 
  
  static TextStyle poppins(double size, {FontWeight w = FontWeight.w600, Color? c, double? h, double? ls}) => GoogleFonts.poppins(fontSize: size, fontWeight: w, color: c ?? ink, height: h ?? 1.2, letterSpacing: ls);
  static TextStyle inter(double size, {FontWeight w = FontWeight.w400, Color? c, double? h, double? ls}) => GoogleFonts.inter(fontSize: size, fontWeight: w, color: c ?? ink2, height: h ?? 1.5, letterSpacing: ls);
  static TextStyle jetBrains(double size, {FontWeight w = FontWeight.w500, Color? c, double? ls}) => GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: w, color: c ?? ink3, letterSpacing: ls);
}

class ReviewSubmitScreen extends StatefulWidget {
  final TaskItem task;
  final List<Map<String, dynamic>> capturedPhotos;
  final int checklistDone;
  final int checklistTotal;

  const ReviewSubmitScreen({super.key, required this.task, this.capturedPhotos = const [], this.checklistDone = 0, this.checklistTotal = 0});
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
    HapticFeedback.heavyImpact();
    setState(() => _submitting = true);
    final provider = context.read<InspectionProvider>();

    final checklist = <Map<String, dynamic>>[
      ...provider.siteCondition.entries.map((e) => {'item': e.key, 'checked': e.value}),
      ...provider.zoningObservations.entries.map((e) => {'item': e.key, 'checked': e.value}),
    ];
    final checklistCompleted = checklist.where((c) => c['checked'] == true).length;
    final localPhotoPaths = provider.capturedPhotos.map((p) => (p['photoPath'] as String?) ?? '').where((p) => p.isNotEmpty).toList();
    final observations = 'Actual land use: ${provider.actualLandUse}. Boundary status: ${provider.boundaryStatus}.';

    // Try the real thing first — unchanged happy path when online.
    bool queuedOffline = false;
    try {
      final photoPaths = await SupabaseService.uploadInspectionPhotos(jobId: widget.task.id, localPaths: localPhotoPaths);
      await SupabaseService.submitInspection(
        jobId: widget.task.id, findings: provider.notes, isCompliant: _selectedStatus == 'Compliant', inspectionResult: _selectedStatus,
        observations: observations,
        discrepancies: provider.discrepancies.isNotEmpty ? provider.discrepancies : null, recommendations: provider.recommendations.isNotEmpty ? provider.recommendations : null,
        inspectorNotes: provider.notes, checklistData: checklist, checklistCompletedCount: checklistCompleted, checklistTotalCount: checklist.length,
        photoPaths: photoPaths, photoCount: photoPaths.length, locationLabel: widget.task.location,
      );
    } catch (e) {
      // Couldn't reach Supabase (or a photo failed mid-upload) — rather
      // than lose everything the inspector just entered, queue the whole
      // submission (including the still-local photo paths) in the
      // FieldSync outbox and let them finish. It'll upload the photos and
      // submit for real once connectivity returns.
      try {
        await SyncOutboxService.enqueueSubmitInspection(
          jobId: widget.task.id, findings: provider.notes, isCompliant: _selectedStatus == 'Compliant', inspectionResult: _selectedStatus,
          observations: observations,
          discrepancies: provider.discrepancies.isNotEmpty ? provider.discrepancies : null, recommendations: provider.recommendations.isNotEmpty ? provider.recommendations : null,
          inspectorNotes: provider.notes, checklistData: checklist, checklistCompletedCount: checklistCompleted, checklistTotalCount: checklist.length,
          localPhotoPaths: localPhotoPaths, locationLabel: widget.task.location,
        );
        queuedOffline = true;
      } catch (_) {
        // Couldn't even save it locally — nothing more we can do here.
        if (!mounted) return;
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
        return;
      }
    }

    InspectionProgress.instance.markStepComplete(6);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => SubmissionSuccessScreen(referenceNo: widget.task.inspectionNo, finalStatus: _selectedStatus, queuedOffline: queuedOffline),
    ));
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    final provider = context.watch<InspectionProvider>();
    final photoCount = provider.capturedPhotos.isNotEmpty ? provider.capturedPhotos.length : widget.capturedPhotos.length;
    final checklistTotal = provider.siteCondition.length + provider.zoningObservations.length;
    final checklistDone = provider.siteCondition.values.where((v) => v).length + provider.zoningObservations.values.where((v) => v).length;
    final effectiveTotal = checklistTotal > 0 ? checklistTotal : widget.checklistTotal;
    final effectiveDone = checklistTotal > 0 ? checklistDone : widget.checklistDone;

    return PopScope(
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
      body: Stack(
        children: [
          Positioned(top: -60, right: -60, child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40), child: Container(width: 260, height: 260, decoration: BoxDecoration(shape: BoxShape.circle, color: InsightTheme.blue1.withValues(alpha: 0.20))))),
          Positioned(bottom: -80, left: -80, child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40), child: Container(width: 220, height: 220, decoration: BoxDecoration(shape: BoxShape.circle, color: InsightTheme.blue1.withValues(alpha: 0.10))))),

          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      _GlassBackButton(onTap: () => handleInspectionExit(context, onSaveProgress: () async => true)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Review & Submit', style: InsightTheme.poppins(17, w: FontWeight.w700)),
                            Text(widget.task.location, style: InsightTheme.inter(12, c: InsightTheme.ink2), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 6, decoration: BoxDecoration(color: InsightTheme.surface2, borderRadius: BorderRadius.circular(4)),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft, widthFactor: 1.0,
                          child: Container(decoration: BoxDecoration(gradient: const LinearGradient(colors: [InsightTheme.blue1, InsightTheme.blue2]), borderRadius: BorderRadius.circular(4))),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text('STEP 6 OF 6', style: InsightTheme.jetBrains(10, w: FontWeight.w700, c: InsightTheme.blueInk, ls: 0.5)),
                          Text(' — FINALIZE REPORT', style: InsightTheme.jetBrains(10, c: InsightTheme.ink3, ls: 0.5)),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(color: InsightTheme.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: InsightTheme.line), boxShadow: const [BoxShadow(color: Color(0x0A141628), blurRadius: 10, offset: Offset(0, 4))]),
                        child: Column(
                          children: [
                            _SummaryRow(label: 'Site Location', value: widget.task.location),
                            _SummaryRow(label: 'Checklist', value: effectiveTotal > 0 ? '$effectiveDone of $effectiveTotal verified' : 'None'),
                            _SummaryRow(label: 'Photos', value: photoCount > 0 ? '$photoCount attached' : 'None'),
                            _SummaryRow(label: 'Current Status', value: _selectedStatus, isLast: true),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      _SectionLabel(title: 'FINAL ASSESSMENT'),
                      const SizedBox(height: 12),
                      ..._statusOptions.map((o) => _ResultOption(title: o.title, subtitle: o.subtitle, isSelected: _selectedStatus == o.title, onTap: () {
                        HapticFeedback.selectionClick(); setState(() => _selectedStatus = o.title); context.read<InspectionProvider>().updateResult(o.title);
                      })),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _handleSubmit,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                      disabledBackgroundColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ).copyWith(elevation: WidgetStateProperty.all(0)),
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: _submitting ? [InsightTheme.blue1.withValues(alpha: 0.5), InsightTheme.blue2.withValues(alpha: 0.5)] : [InsightTheme.blue1, InsightTheme.blue2], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: _submitting ? [] : [BoxShadow(color: InsightTheme.blue1.withValues(alpha: 0.32), blurRadius: 20, offset: const Offset(0, 8))],
                      ),
                      child: Container(
                        alignment: Alignment.center, constraints: const BoxConstraints(minHeight: 52),
                        child: _submitting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : Text('Submit Inspection', style: InsightTheme.poppins(15, w: FontWeight.w600, c: Colors.white)),
                      ),
                    ),
                  ),
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

class _SummaryRow extends StatelessWidget {
  final String label; final String value; final bool isLast;
  const _SummaryRow({required this.label, required this.value, this.isLast = false});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(border: isLast ? null : const Border(bottom: BorderSide(color: InsightTheme.line))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: InsightTheme.inter(13, c: InsightTheme.ink2)),
          Flexible(child: Text(value, style: InsightTheme.inter(13, w: FontWeight.w600, c: InsightTheme.ink), textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis)),
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
        Container(width: 10, height: 2, decoration: BoxDecoration(color: InsightTheme.blue1, borderRadius: BorderRadius.circular(1))),
        const SizedBox(width: 8),
        Text(title, style: InsightTheme.jetBrains(11, w: FontWeight.w500, ls: 1.2)),
      ],
    );
  }
}

class _ResultOption extends StatelessWidget {
  final String title; final String subtitle; final bool isSelected; final VoidCallback onTap;
  const _ResultOption({required this.title, required this.subtitle, required this.isSelected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? InsightTheme.surface : InsightTheme.surface, 
          borderRadius: BorderRadius.circular(18), 
          border: Border.all(color: isSelected ? InsightTheme.blue1 : InsightTheme.line, width: isSelected ? 2 : 1),
          boxShadow: isSelected ? [BoxShadow(color: InsightTheme.blue1.withValues(alpha: 0.15), blurRadius: 12, offset: const Offset(0, 4))] : [const BoxShadow(color: Color(0x0A141628), blurRadius: 2, offset: Offset(0, 1))],
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200), width: 22, height: 22,
              decoration: BoxDecoration(shape: BoxShape.circle, color: isSelected ? InsightTheme.blue1 : Colors.transparent, border: isSelected ? null : Border.all(color: InsightTheme.lineStrong, width: 2)),
              child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 14) : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: InsightTheme.inter(14, w: FontWeight.w600, c: isSelected ? InsightTheme.blueInk : InsightTheme.ink)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: InsightTheme.inter(12, c: InsightTheme.ink2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SubmissionSuccessScreen extends StatelessWidget {
  final String referenceNo; final String finalStatus; final bool queuedOffline;
  const SubmissionSuccessScreen({super.key, required this.referenceNo, required this.finalStatus, this.queuedOffline = false});
  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    return Scaffold(
      backgroundColor: InsightTheme.bg,
      body: Stack(
        children: [
          Positioned(top: -60, right: -60, child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40), child: Container(width: 260, height: 260, decoration: BoxDecoration(shape: BoxShape.circle, color: InsightTheme.blue1.withValues(alpha: 0.20))))),
          Positioned(bottom: -80, left: -80, child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40), child: Container(width: 220, height: 220, decoration: BoxDecoration(shape: BoxShape.circle, color: InsightTheme.blue1.withValues(alpha: 0.10))))),

          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: queuedOffline ? const [InsightTheme.blue1, InsightTheme.blue2] : const [InsightTheme.green, Color(0xFF0D7A3C)],
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                        ),
                        boxShadow: [BoxShadow(color: (queuedOffline ? InsightTheme.blue1 : InsightTheme.green).withValues(alpha: 0.35), blurRadius: 28, offset: const Offset(0, 14))],
                      ),
                      child: Icon(queuedOffline ? Icons.cloud_off_rounded : Icons.check_rounded, color: Colors.white, size: 36),
                    ),
                    const SizedBox(height: 24),
                    Text(queuedOffline ? 'Saved Offline' : 'Inspection Submitted', style: InsightTheme.poppins(20, w: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(
                      queuedOffline
                          ? 'ID $referenceNo recorded as "$finalStatus" — no signal right now, will sync automatically once you\'re back online.'
                          : 'ID $referenceNo recorded as "$finalStatus".',
                      textAlign: TextAlign.center, style: InsightTheme.inter(14, c: InsightTheme.ink2),
                    ),
                    const SizedBox(height: 36),
                    SizedBox(
                      width: 240,
                      child: ElevatedButton(
                        onPressed: () async {
                          InspectionProgress.instance.reset();
                          final profileMap = await SupabaseService.fetchMyProfile();
                          if (!context.mounted) return;
                          if (profileMap != null) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => TasksScreen(profile: UserProfile.fromMap(profileMap))), (route) => false);
                          else Navigator.of(context).popUntil((route) => route.isFirst);
                        },
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))).copyWith(elevation: WidgetStateProperty.all(0)),
                        child: Ink(
                          decoration: BoxDecoration(gradient: const LinearGradient(colors: [InsightTheme.blue1, InsightTheme.blue2], begin: Alignment.topCenter, end: Alignment.bottomCenter), borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: InsightTheme.blue1.withValues(alpha: 0.32), blurRadius: 22, offset: const Offset(0, 10))]),
                          child: Container(alignment: Alignment.center, constraints: const BoxConstraints(minHeight: 52), child: Text('Back to Home', style: InsightTheme.poppins(15, w: FontWeight.w600, c: Colors.white))),
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

class _GlassBackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _GlassBackButton({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42, height: 42,
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withValues(alpha: 0.65)), boxShadow: const [BoxShadow(color: Color(0x0F141628), blurRadius: 10, offset: Offset(0, 4))]),
        child: ClipRRect(borderRadius: BorderRadius.circular(14), child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12), child: const Center(child: Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: InsightTheme.ink))))),
      ),
    );
  }
}