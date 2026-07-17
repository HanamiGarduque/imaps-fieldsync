import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'field_findings_screen.dart';
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
/// SCREEN 8 — INSPECTION CHECKLIST
/// ==================================================================
class InspectionChecklistScreen extends StatefulWidget {
  final TaskItem task;
  final List<Map<String, dynamic>> capturedPhotos;

  const InspectionChecklistScreen({
    super.key,
    required this.task,
    this.capturedPhotos = const [],
  });

  @override
  State<InspectionChecklistScreen> createState() => _InspectionChecklistScreenState();
}

class _InspectionChecklistScreenState extends State<InspectionChecklistScreen> {
  // Original preserved state maps[cite: 7]
  final Map<String, bool> _siteCondition = {
    'Structure matches declared use': true,
    'Setback distances compliant': true,
  };
  final Map<String, bool> _zoningObservations = {
    'Accessibility & road frontage': true,
    'Surrounding developments noted': false,
    'Signage / commercial activity present': false,
  };

  // Original preserved counter logic[cite: 7]
  int get _doneCount =>
      _siteCondition.values.where((v) => v).length + _zoningObservations.values.where((v) => v).length;
  int get _totalCount => _siteCondition.length + _zoningObservations.length;

  void _continueToFindings() {
    InspectionProgress.instance.markStepComplete(4);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FieldFindingsScreen(
          task: widget.task,
          capturedPhotos: widget.capturedPhotos,
          checklistDone: _doneCount,
          checklistTotal: _totalCount,
        ),
      ),
    );
  }

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
                              'Checklist',
                              style: InsightTheme.poppins(17, w: FontWeight.w700, c: InsightTheme.ink),
                            ),
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
                        height: 6,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: InsightTheme.surface2,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: 0.666, // 66.6% Step 4 of 6
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
                          Text('STEP 4 OF 6', style: InsightTheme.jetBrains(10, w: FontWeight.w700, c: InsightTheme.blueInk, ls: 0.5)),
                          Text(' — CHECKLIST · $_doneCount/$_totalCount COMPLETE', style: InsightTheme.jetBrains(10, c: InsightTheme.ink3, ls: 0.5)),
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
                      // SITE CONDITION SECTION
                      _SectionLabel(title: 'SITE CONDITION'),
                      const SizedBox(height: 10),
                      Container(
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
                          children: _siteCondition.entries.toList().asMap().entries.map((entry) {
                            int idx = entry.key;
                            var e = entry.value;
                            return _ChecklistItem(
                              title: e.key,
                              subtitle: e.value ? null : 'Not yet reviewed',
                              isChecked: e.value,
                              isLast: idx == _siteCondition.length - 1,
                              onTap: () {
  final newValue = !e.value;
  setState(() => _siteCondition[e.key] = newValue);
  context.read<InspectionProvider>().setSiteCondition(e.key, newValue);
},
                            );
                          }).toList(),
                        ),
                      ),
                      
                      const SizedBox(height: 24),

                      // ZONING OBSERVATIONS SECTION
                      _SectionLabel(title: 'ZONING OBSERVATIONS'),
                      const SizedBox(height: 10),
                      Container(
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
                          children: _zoningObservations.entries.toList().asMap().entries.map((entry) {
                            int idx = entry.key;
                            var e = entry.value;
                            return _ChecklistItem(
                              title: e.key,
                              isChecked: e.value,
                              isLast: idx == _zoningObservations.length - 1,
                              onTap: () {
  final newValue = !e.value;
  setState(() => _zoningObservations[e.key] = newValue);
  context.read<InspectionProvider>().setZoningObservation(e.key, newValue);
},
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),

                // BOTTOM ACTION BUTTON
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  child: ElevatedButton(
                    onPressed: _continueToFindings,
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
                          'Continue to findings',
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

class _ChecklistItem extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool isChecked;
  final bool isLast;
  final VoidCallback onTap;

  const _ChecklistItem({
    required this.title,
    this.subtitle,
    required this.isChecked,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.vertical(
        top: isLast ? Radius.zero : const Radius.circular(22),
        bottom: isLast ? const Radius.circular(22) : Radius.zero,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: isLast ? null : const Border(bottom: BorderSide(color: InsightTheme.line)),
        ),
        child: Row(
          crossAxisAlignment: subtitle != null ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            // Custom Animated Checkbox
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22, height: 22,
              margin: EdgeInsets.only(top: subtitle != null ? 1 : 0), // align with title if multiline
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: isChecked ? const LinearGradient(
                  colors: [InsightTheme.blue1, InsightTheme.blue2],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ) : null,
                color: isChecked ? null : Colors.transparent,
                border: isChecked ? null : Border.all(color: InsightTheme.lineStrong, width: 2),
              ),
              child: isChecked 
                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 14) 
                  : null,
            ),
            const SizedBox(width: 12),
            // Texts
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: InsightTheme.inter(13.5, w: FontWeight.w600, c: InsightTheme.ink)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(subtitle!, style: InsightTheme.inter(11.5, c: InsightTheme.ink2)),
                  ]
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