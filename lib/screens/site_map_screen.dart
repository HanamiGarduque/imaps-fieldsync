import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'gps_verification_screen.dart';
import 'tasks_screen.dart';
import 'inspection_progress.dart';

class InsightTheme {
  static const Color bg = Color(0xFFF2F4FB);
  static const Color surface = Colors.white;
  static const Color surface2 = Color(0xFFEEF1FC);
  static const Color ink = Color(0xFF12141F);
  static const Color ink2 = Color(0xFF666C82);
  static const Color ink3 = Color(0xFFA2A7BC);
  static const Color blue1 = Color(0xFF3D6BFF);
  static const Color blue2 = Color(0xFF0B2FBF);
  static const Color blueInk = Color(0xFF1A3FC4);
  static const Color red = Color(0xFFE23B4E);
  static const Color redInk = Color(0xFFB72A3B);
  static const Color line = Color(0x1A141628); 
  
  static TextStyle poppins(double size, {FontWeight w = FontWeight.w600, Color? c, double? h, double? ls}) => GoogleFonts.poppins(fontSize: size, fontWeight: w, color: c ?? ink, height: h ?? 1.2, letterSpacing: ls);
  static TextStyle inter(double size, {FontWeight w = FontWeight.w400, Color? c, double? h, double? ls}) => GoogleFonts.inter(fontSize: size, fontWeight: w, color: c ?? ink2, height: h ?? 1.5, letterSpacing: ls);
  static TextStyle jetBrains(double size, {FontWeight w = FontWeight.w500, Color? c, double? ls}) => GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: w, color: c ?? ink3, letterSpacing: ls);
}

class SiteMapScreen extends StatelessWidget {
  final TaskItem task;
  const SiteMapScreen({super.key, required this.task});

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    return Scaffold(
      backgroundColor: InsightTheme.bg,
      body: Stack(
        children: [
          // Original Blurred Background Blobs
          Positioned(top: -60, right: -60, child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40), child: Container(width: 260, height: 260, decoration: BoxDecoration(shape: BoxShape.circle, color: InsightTheme.blue1.withValues(alpha: 0.20))))),
          Positioned(bottom: -80, left: -80, child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40), child: Container(width: 220, height: 220, decoration: BoxDecoration(shape: BoxShape.circle, color: InsightTheme.blue1.withValues(alpha: 0.10))))),

          SafeArea(
            child: Column(
              children: [
                // Glass Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      _GlassBackButton(onTap: () => Navigator.pop(context)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Site Verification', style: InsightTheme.poppins(17, w: FontWeight.w700)),
                            Text(task.location, style: InsightTheme.inter(12, c: InsightTheme.ink2), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Progress Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 6, decoration: BoxDecoration(color: InsightTheme.surface2, borderRadius: BorderRadius.circular(4)),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft, widthFactor: 1/6,
                          child: Container(decoration: BoxDecoration(gradient: const LinearGradient(colors: [InsightTheme.blue1, InsightTheme.blue2]), borderRadius: BorderRadius.circular(4))),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text('STEP 1 OF 6', style: InsightTheme.jetBrains(10, w: FontWeight.w700, c: InsightTheme.blueInk, ls: 0.5)),
                          Text(' — LOCATE TARGET', style: InsightTheme.jetBrains(10, c: InsightTheme.ink3, ls: 0.5)),
                        ],
                      ),
                    ],
                  ),
                ),

                // Map Content
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: InsightTheme.line),
                      gradient: const LinearGradient(colors: [Color(0xFFEDEFFB), Color(0xFFDCE2F8)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      boxShadow: const [BoxShadow(color: Color(0x0A141628), blurRadius: 10, offset: Offset(0, 4))],
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: Stack(
                      children: [
                        Align(
                          alignment: const Alignment(0.1, -0.16),
                          child: Container(width: 16, height: 16, decoration: BoxDecoration(color: InsightTheme.red, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3))),
                        ),
                        Align(
                          alignment: const Alignment(-0.24, 0.20),
                          child: Container(width: 18, height: 18, decoration: BoxDecoration(color: InsightTheme.blue1, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: [BoxShadow(color: InsightTheme.blue1.withValues(alpha: 0.3), spreadRadius: 8)])),
                        ),
                        Positioned(
                          bottom: 16, left: 16, right: 16,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: 0.65))),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(children: [const Icon(Icons.circle, size: 10, color: InsightTheme.red), const SizedBox(width: 6), Text('Target Site', style: InsightTheme.inter(12, w: FontWeight.w600))]),
                                    Row(children: [const Icon(Icons.circle, size: 10, color: InsightTheme.blue1), const SizedBox(width: 6), Text('You (210m)', style: InsightTheme.inter(12, w: FontWeight.w600, c: InsightTheme.ink2))]),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Button
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: ElevatedButton(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      InspectionProgress.instance.markStepComplete(1);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => GpsVerificationScreen(task: task)));
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ).copyWith(elevation: WidgetStateProperty.all(0)),
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [InsightTheme.blue1, InsightTheme.blue2], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: InsightTheme.blue1.withValues(alpha: 0.32), blurRadius: 20, offset: const Offset(0, 8))],
                      ),
                      child: Container(
                        alignment: Alignment.center, constraints: const BoxConstraints(minHeight: 52),
                        child: Text('Proceed to Location', style: InsightTheme.poppins(15, w: FontWeight.w600, c: Colors.white)),
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

class _GlassBackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _GlassBackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42, height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.65)),
          boxShadow: const [BoxShadow(color: Color(0x0F141628), blurRadius: 10, offset: Offset(0, 4))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12), child: const Center(child: Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: InsightTheme.ink)))),
        ),
      ),
    );
  }
}