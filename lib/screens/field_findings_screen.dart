import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'review_submit_screen.dart';
import 'tasks_screen.dart';
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
  
  static const Color redTint = Color(0xFFFDECEE);
  static const Color redInk = Color(0xFFB72A3B);
  
  static const Color green = Color(0xFF12A150);
  
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
/// SCREEN 11 — FIELD FINDINGS
/// ==================================================================
class FieldFindingsScreen extends StatelessWidget {
  final TaskItem task;
  final List<Map<String, dynamic>> capturedPhotos;
  final int checklistDone;
  final int checklistTotal;

  const FieldFindingsScreen({
    super.key,
    required this.task,
    this.capturedPhotos = const [],
    this.checklistDone = 0,
    this.checklistTotal = 0,
  });

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    return Scaffold(
      backgroundColor: InsightTheme.bg,
      body: Stack(
        children: [
          // ----------------------------------------------------
          // BACKGROUND GRADIENT BLOBS
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Field findings',
                              style: InsightTheme.poppins(17, w: FontWeight.w700, c: InsightTheme.ink),
                            ),
                            Text(
                              task.location,
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
                        height: 6,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: InsightTheme.surface2,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: 0.833, // 83.3% Step 5 of 6
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
                          Text('STEP 5 OF 6', style: InsightTheme.jetBrains(10, w: FontWeight.w700, c: InsightTheme.blueInk, ls: 0.5)),
                          Text(' — FINDINGS', style: InsightTheme.jetBrains(10, c: InsightTheme.ink3, ls: 0.5)),
                        ],
                      ),
                    ],
                  ),
                ),

                // SCROLLABLE LIST
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      // OBSERVATIONS SECTION
                      const _SectionLabel(title: 'OBSERVATIONS'),
                      const SizedBox(height: 10),
                      const _TextCard(
                        text: 'Rear portion of the lot shows a small storage structure not reflected in the declared building plan. Main residence otherwise matches submitted layout.',
                      ),
                      
                      // Confirms the evidence gathered in the earlier steps carried
                      // through to this screen, instead of appearing disconnected.
                      if (capturedPhotos.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, size: 14, color: InsightTheme.green),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${capturedPhotos.length} geotagged photo${capturedPhotos.length == 1 ? '' : 's'} attached from capture',
                                style: InsightTheme.inter(11.5, c: InsightTheme.green),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (checklistTotal > 0) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              checklistDone == checklistTotal ? Icons.check_circle_rounded : Icons.info_rounded,
                              size: 14,
                              color: checklistDone == checklistTotal ? InsightTheme.green : InsightTheme.ink3,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Checklist · $checklistDone of $checklistTotal items reviewed',
                                style: InsightTheme.inter(11.5, c: InsightTheme.ink2),
                              ),
                            ),
                          ],
                        ),
                      ],
                      
                      const SizedBox(height: 24),

                      // DISCREPANCIES SECTION
                      const _SectionLabel(title: 'DISCREPANCIES'),
                      const SizedBox(height: 10),
                      // Styled as a clean list row per the HTML spec
                      Row(
                        children: [
                          Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: InsightTheme.redTint,
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: const Icon(Icons.warning_amber_rounded, size: 18, color: InsightTheme.redInk),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Unpermitted accessory structure', style: InsightTheme.inter(13.5, w: FontWeight.w600, c: InsightTheme.ink)),
                                const SizedBox(height: 2),
                                Text('Rear yard, approx. 12 sqm', style: InsightTheme.inter(11.5, c: InsightTheme.ink2)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 24),

                      // RECOMMENDATIONS SECTION
                      const _SectionLabel(title: 'RECOMMENDATIONS'),
                      const SizedBox(height: 10),
                      const _TextCard(
                        text: 'Advise applicant to file supplementary permit for accessory structure prior to final approval.',
                      ),
                    ],
                  ),
                ),

                // BOTTOM ACTION BUTTON
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  child: ElevatedButton(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      context.read<InspectionProvider>().updateFindings(
                        actualLandUse: task.landUseClass,
                        notes: 'Rear portion of the lot shows a small storage structure not reflected in the declared building plan. Main residence otherwise matches submitted layout.',
                        discrepancies: 'Unpermitted accessory structure — Rear yard, approx. 12 sqm',
                        recommendations: 'Advise applicant to file supplementary permit for accessory structure prior to final approval.',
                        boundaryStatus: 'Not yet verified via GPS',
                      );

                      InspectionProgress.instance.markStepComplete(5);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ReviewSubmitScreen(task: task),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      backgroundColor: Colors.transparent, 
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ).copyWith(
                      elevation: WidgetStateProperty.all(0),
                    ),
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [InsightTheme.blue1, InsightTheme.blue2],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: InsightTheme.blue1.withOpacity(0.32), blurRadius: 22, offset: const Offset(0, 10)),
                        ],
                      ),
                      child: Container(
                        alignment: Alignment.center,
                        constraints: const BoxConstraints(minHeight: 50),
                        child: Text(
                          'Continue to review',
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
}

/// ==================================================================
/// COMPONENT WIDGETS
/// ==================================================================

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

class _TextCard extends StatelessWidget {
  final String text;
  
  const _TextCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: InsightTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: InsightTheme.line),
        boxShadow: const [BoxShadow(color: Color(0x0A141628), blurRadius: 2, offset: Offset(0, 1))],
      ),
      child: Text(
        text,
        style: InsightTheme.inter(12.5, c: InsightTheme.ink2, h: 1.6),
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