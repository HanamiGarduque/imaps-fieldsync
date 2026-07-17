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

  static const Color line = Color(0x12141628);
  static const Color lineStrong = Color(0x21141628);

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
class FieldFindingsScreen extends StatefulWidget {
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
  State<FieldFindingsScreen> createState() => _FieldFindingsScreenState();
}

class _FieldFindingsScreenState extends State<FieldFindingsScreen> {
  late final TextEditingController _notesController;
  late final TextEditingController _discrepancyTitleController;
  late final TextEditingController _discrepancyDetailController;
  late final TextEditingController _recommendationsController;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController(
      text: 'Describe what you observed on site — structure condition, land use, notable features...',
    );
    _discrepancyTitleController = TextEditingController(text: 'Unpermitted accessory structure');
    _discrepancyDetailController = TextEditingController(text: 'Rear yard, approx. 12 sqm');
    _recommendationsController = TextEditingController(
      text: 'Enter recommendation for this inspection (e.g., required permits, follow-up actions)...',
    );
  }

  @override
  void dispose() {
    _notesController.dispose();
    _discrepancyTitleController.dispose();
    _discrepancyDetailController.dispose();
    _recommendationsController.dispose();
    super.dispose();
  }

  void _handleContinue() {
    HapticFeedback.selectionClick();
    context.read<InspectionProvider>().updateFindings(
          actualLandUse: widget.task.landUseClass,
          notes: _notesController.text.trim(),
          discrepancies: '${_discrepancyTitleController.text.trim()} — ${_discrepancyDetailController.text.trim()}',
          recommendations: _recommendationsController.text.trim(),
          boundaryStatus: 'Not yet verified via GPS',
        );

    InspectionProgress.instance.markStepComplete(5);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReviewSubmitScreen(task: widget.task)),
    );
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    return Scaffold(
      backgroundColor: InsightTheme.bg,
      body: Stack(
        children: [
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
          SafeArea(
            child: Column(
              children: [
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
                          widthFactor: 0.833,
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
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      const _SectionLabel(title: 'OBSERVATIONS'),
                      const SizedBox(height: 10),
                      _EditableTextCard(controller: _notesController, hint: 'Describe what you observed on-site...'),

                      if (widget.capturedPhotos.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, size: 14, color: InsightTheme.green),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${widget.capturedPhotos.length} geotagged photo${widget.capturedPhotos.length == 1 ? '' : 's'} attached from capture',
                                style: InsightTheme.inter(11.5, c: InsightTheme.green),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (widget.checklistTotal > 0) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              widget.checklistDone == widget.checklistTotal ? Icons.check_circle_rounded : Icons.info_rounded,
                              size: 14,
                              color: widget.checklistDone == widget.checklistTotal ? InsightTheme.green : InsightTheme.ink3,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Checklist · ${widget.checklistDone} of ${widget.checklistTotal} items reviewed',
                                style: InsightTheme.inter(11.5, c: InsightTheme.ink2),
                              ),
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 24),
                      const _SectionLabel(title: 'DISCREPANCIES'),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                                TextField(
                                  controller: _discrepancyTitleController,
                                  style: InsightTheme.inter(13.5, w: FontWeight.w600, c: InsightTheme.ink),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                    border: InputBorder.none,
                                    hintText: 'Discrepancy title',
                                  ),
                                ),
                                const SizedBox(height: 2),
                                TextField(
                                  controller: _discrepancyDetailController,
                                  style: InsightTheme.inter(11.5, c: InsightTheme.ink2),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                    border: InputBorder.none,
                                    hintText: 'Details / location',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),
                      const _SectionLabel(title: 'RECOMMENDATIONS'),
                      const SizedBox(height: 10),
                      _EditableTextCard(controller: _recommendationsController, hint: 'Enter recommendation for this application...'),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  child: ElevatedButton(
                    onPressed: _handleContinue,
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

/// Same visual container as the old read-only _TextCard, pero editable na.
class _EditableTextCard extends StatelessWidget {
  final TextEditingController controller;
  final String hint;

  const _EditableTextCard({required this.controller, required this.hint});

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
      child: TextField(
        controller: controller,
        maxLines: null,
        minLines: 2,
        style: InsightTheme.inter(12.5, c: InsightTheme.ink2, h: 1.6),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
          hintText: hint,
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