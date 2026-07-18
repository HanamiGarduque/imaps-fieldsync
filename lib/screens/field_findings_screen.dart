import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'review_submit_screen.dart';
import 'tasks_screen.dart';
import 'inspection_progress.dart';
import 'package:provider/provider.dart';
import '../providers/inspection_provider.dart';

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
  static const Color green = Color(0xFF12A150);
  static const Color redTint = Color(0xFFFDECEE);
  static const Color redInk = Color(0xFFB72A3B);
  static const Color line = Color(0x1A141628); 
  
  static TextStyle poppins(double size, {FontWeight w = FontWeight.w600, Color? c, double? h, double? ls}) => GoogleFonts.poppins(fontSize: size, fontWeight: w, color: c ?? ink, height: h ?? 1.2, letterSpacing: ls);
  static TextStyle inter(double size, {FontWeight w = FontWeight.w400, Color? c, double? h, double? ls}) => GoogleFonts.inter(fontSize: size, fontWeight: w, color: c ?? ink2, height: h ?? 1.5, letterSpacing: ls);
  static TextStyle jetBrains(double size, {FontWeight w = FontWeight.w500, Color? c, double? ls}) => GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: w, color: c ?? ink3, letterSpacing: ls);
}

class FieldFindingsScreen extends StatefulWidget {
  final TaskItem task;
  final List<Map<String, dynamic>> capturedPhotos;
  final int checklistDone;
  final int checklistTotal;

  const FieldFindingsScreen({super.key, required this.task, this.capturedPhotos = const [], this.checklistDone = 0, this.checklistTotal = 0});
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
    _notesController = TextEditingController(text: 'Structure condition appears stable. Need to verify land use documents.');
    _discrepancyTitleController = TextEditingController(text: 'Unpermitted accessory structure');
    _discrepancyDetailController = TextEditingController(text: 'Rear yard, approx. 12 sqm');
    _recommendationsController = TextEditingController();
  }

  @override
  void dispose() {
    _notesController.dispose(); _discrepancyTitleController.dispose(); _discrepancyDetailController.dispose(); _recommendationsController.dispose();
    super.dispose();
  }

  void _handleContinue() {
    HapticFeedback.selectionClick();
    context.read<InspectionProvider>().updateFindings(actualLandUse: widget.task.landUseClass, notes: _notesController.text.trim(), discrepancies: '${_discrepancyTitleController.text.trim()} — ${_discrepancyDetailController.text.trim()}', recommendations: _recommendationsController.text.trim(), boundaryStatus: 'Verified');
    InspectionProgress.instance.markStepComplete(5);
    Navigator.push(context, MaterialPageRoute(builder: (_) => ReviewSubmitScreen(task: widget.task)));
  }

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
            child: Column(
              children: [
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
                            Text('Field Findings', style: InsightTheme.poppins(17, w: FontWeight.w700)),
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
                          alignment: Alignment.centerLeft, widthFactor: 5/6,
                          child: Container(decoration: BoxDecoration(gradient: const LinearGradient(colors: [InsightTheme.blue1, InsightTheme.blue2]), borderRadius: BorderRadius.circular(4))),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text('STEP 5 OF 6', style: InsightTheme.jetBrains(10, w: FontWeight.w700, c: InsightTheme.blueInk, ls: 0.5)),
                          Text(' — LOG OBSERVATIONS', style: InsightTheme.jetBrains(10, c: InsightTheme.ink3, ls: 0.5)),
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
                      _SectionLabel(title: 'OBSERVATIONS'),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: InsightTheme.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: InsightTheme.line), boxShadow: const [BoxShadow(color: Color(0x0A141628), blurRadius: 10, offset: Offset(0, 4))]),
                        child: TextField(controller: _notesController, maxLines: 4, minLines: 3, style: InsightTheme.inter(14, c: InsightTheme.ink), decoration: InputDecoration(isDense: true, contentPadding: EdgeInsets.zero, border: InputBorder.none, hintText: 'Enter specific observations...')),
                      ),
                      if (widget.capturedPhotos.isNotEmpty || widget.checklistTotal > 0) ...[
                        const SizedBox(height: 16),
                        if (widget.capturedPhotos.isNotEmpty) Row(children: [const Icon(Icons.check_circle_rounded, size: 16, color: InsightTheme.green), const SizedBox(width: 8), Text('${widget.capturedPhotos.length} photos attached', style: InsightTheme.inter(13, c: InsightTheme.green))]),
                        if (widget.checklistTotal > 0) Padding(padding: const EdgeInsets.only(top: 6), child: Row(children: [Icon(widget.checklistDone == widget.checklistTotal ? Icons.check_circle_rounded : Icons.info_rounded, size: 16, color: widget.checklistDone == widget.checklistTotal ? InsightTheme.green : InsightTheme.ink3), const SizedBox(width: 8), Text('Checklist: ${widget.checklistDone}/${widget.checklistTotal} completed', style: InsightTheme.inter(13, c: InsightTheme.ink2))])),
                      ],
                      const SizedBox(height: 28),
                      _SectionLabel(title: 'DISCREPANCIES'),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: InsightTheme.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: InsightTheme.line), boxShadow: const [BoxShadow(color: Color(0x0A141628), blurRadius: 10, offset: Offset(0, 4))]),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: InsightTheme.redTint, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.warning_amber_rounded, size: 18, color: InsightTheme.redInk)),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                children: [
                                  TextField(controller: _discrepancyTitleController, style: InsightTheme.inter(14, w: FontWeight.w600, c: InsightTheme.ink), decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.zero, border: InputBorder.none, hintText: 'Issue Title')),
                                  const SizedBox(height: 6),
                                  TextField(controller: _discrepancyDetailController, style: InsightTheme.inter(13, c: InsightTheme.ink2), decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.zero, border: InputBorder.none, hintText: 'Location or Details')),
                                ],
                              ),
                            )
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      _SectionLabel(title: 'RECOMMENDATIONS'),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: InsightTheme.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: InsightTheme.line), boxShadow: const [BoxShadow(color: Color(0x0A141628), blurRadius: 10, offset: Offset(0, 4))]),
                        child: TextField(controller: _recommendationsController, maxLines: 3, minLines: 2, style: InsightTheme.inter(14, c: InsightTheme.ink), decoration: InputDecoration(isDense: true, contentPadding: EdgeInsets.zero, border: InputBorder.none, hintText: 'Required actions or permits...')),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: ElevatedButton(
                    onPressed: _handleContinue,
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
                        child: Text('Continue to Review', style: InsightTheme.poppins(15, w: FontWeight.w600, c: Colors.white)),
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