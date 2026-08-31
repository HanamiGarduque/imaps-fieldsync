import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'review_submit_screen.dart';
import '../../tasks/screens/tasks_screen.dart';
import 'inspection_progress.dart';
import 'package:provider/provider.dart';
import '../providers/inspection_provider.dart';
import '../widgets/exit_confirm_dialog.dart';
import '../../../core/widgets/sensitive_screen.dart';

import '../../../core/theme/insight_theme.dart';
import '../widgets/inspection_step_header.dart';

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
  bool _isSaving = false;
  late final TextEditingController _notesController;
  late final TextEditingController _discrepancyTitleController;
  late final TextEditingController _discrepancyDetailController;
  late final TextEditingController _recommendationsController;

  @override
  void initState() {
    super.initState();
    // BUG FIX #4A — Global Data Persistence.
    // Controllers used to always start empty, even when InspectionProvider
    // already had real hydrated data (rework mode, or a resumed Ongoing
    // task). That meant the inspector saw blank fields for findings that
    // were already on file, and hitting "Continue" without retyping would
    // silently overwrite that real data with empty strings. Prefill from
    // the provider's current state instead — it's already correctly
    // seeded via hydrateForRework() / startInspection()'s local draft load.
    final provider = context.read<InspectionProvider>();
    _notesController = TextEditingController(text: provider.notes);
    _discrepancyTitleController = TextEditingController();
    _discrepancyDetailController = TextEditingController(text: provider.discrepancies);
    _recommendationsController = TextEditingController(text: provider.recommendations);
  }

  @override
  void dispose() {
    _notesController.dispose(); _discrepancyTitleController.dispose(); _discrepancyDetailController.dispose(); _recommendationsController.dispose();
    super.dispose();
  }

  void _handleContinue() {
    HapticFeedback.selectionClick();

    final discrepancyTitle = _discrepancyTitleController.text.trim();
    final discrepancyDetail = _discrepancyDetailController.text.trim();
    // Don't save a bare " — " when the inspector legitimately found nothing.
    final discrepancies = (discrepancyTitle.isEmpty && discrepancyDetail.isEmpty)
        ? ''
        : [discrepancyTitle, discrepancyDetail].where((s) => s.isNotEmpty).join(' — ');

    final provider = context.read<InspectionProvider>();
    provider.updateFindings(
          actualLandUse: widget.task.landUseClass,
          notes: _notesController.text.trim(),
          discrepancies: discrepancies,
          recommendations: _recommendationsController.text.trim(),
          // Carries forward whatever GpsVerificationScreen actually recorded
          // in Step 2 (e.g. "Verified on-site — 6m from declared location")
          // instead of hardcoding a status that may not reflect reality.
          boundaryStatus: provider.boundaryStatus,
        );
    InspectionProgress.instance.markStepComplete(5);
    // Issue 4 fix — same rationale as capture_photo_screen.dart's
    // _finishAndContinue: findings never auto-saved on normal forward
    // progress before, only on exit/rework-save/final-submit. Now has
    // its own outbox fallback too (enqueueFindingsUpdate).
    provider.saveStepFindings();
    Navigator.push(context, MaterialPageRoute(builder: (_) => ReviewSubmitScreen(task: widget.task)));
  }

  Future<bool> _syncControllersAndSave() async {
    final provider = context.read<InspectionProvider>();
    final discrepancyTitle = _discrepancyTitleController.text.trim();
    final discrepancyDetail = _discrepancyDetailController.text.trim();
    final discrepancies = (discrepancyTitle.isEmpty && discrepancyDetail.isEmpty)
        ? ''
        : [discrepancyTitle, discrepancyDetail].where((s) => s.isNotEmpty).join(' — ');
    provider.updateFindings(
      actualLandUse: widget.task.landUseClass,
      notes: _notesController.text.trim(),
      discrepancies: discrepancies,
      recommendations: _recommendationsController.text.trim(),
      boundaryStatus: provider.boundaryStatus,
    );
    return provider.saveStepFindings();
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    return SensitiveScreen(child: PopScope(
      canPop: !context.read<InspectionProvider>().isReworkMode && InspectionProgress.instance.currentStep > 1,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _syncControllersAndSave();
          return;
        }
        handleInspectionExit(
          context,
          onSaveProgress: _syncControllersAndSave,
          isReworkMode: context.read<InspectionProvider>().isReworkMode,
        );
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
                InspectionStepHeader(
                  title: 'Field Findings',
                  subtitle: widget.task.location,
                  stepNumber: 5,
                  stepSubtitle: 'LOG OBSERVATIONS',
                  onBack: () => handleInspectionExit(
                    context,
                    onSaveProgress: _syncControllersAndSave,
                    isReworkMode: context.read<InspectionProvider>().isReworkMode,
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
                        decoration: BoxDecoration(
                          color: InsightTheme.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: InsightTheme.line),
                          boxShadow: InsightTheme.inspectionCardShadow,
                        ),
                        child: TextField(controller: _notesController, maxLines: 4, minLines: 3, style: InsightTheme.inter(14, c: InsightTheme.ink), decoration: InputDecoration(isDense: true, contentPadding: EdgeInsets.zero, border: InputBorder.none, hintText: 'Describe what you observed on-site — structure condition, land use, notable features...')),
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
                        decoration: BoxDecoration(
                          color: InsightTheme.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: InsightTheme.line),
                          boxShadow: InsightTheme.inspectionCardShadow,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: InsightTheme.redTint, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.warning_amber_rounded, size: 18, color: InsightTheme.redInk)),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                children: [
                                  TextField(
                                    controller: _discrepancyTitleController,
                                    maxLines: 2,
                                    minLines: 1,
                                    style: InsightTheme.inter(14, w: FontWeight.w600, c: InsightTheme.ink),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                      border: InputBorder.none,
                                      hintText: 'Issue title (leave blank if none found)',
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  TextField(controller: _discrepancyDetailController, style: InsightTheme.inter(13, c: InsightTheme.ink2), decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.zero, border: InputBorder.none, hintText: 'Location or details')),
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
                        decoration: BoxDecoration(
                          color: InsightTheme.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: InsightTheme.line),
                          boxShadow: InsightTheme.inspectionCardShadow,
                        ),
                        child: TextField(controller: _recommendationsController, maxLines: 3, minLines: 2, style: InsightTheme.inter(14, c: InsightTheme.ink), decoration: InputDecoration(isDense: true, contentPadding: EdgeInsets.zero, border: InputBorder.none, hintText: 'Enter recommendation for this application (e.g., required permits, follow-up actions)...')),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Row(
                    children: [
                      if (context.watch<InspectionProvider>().isReworkMode) ...[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isSaving ? null : () async {
                              setState(() => _isSaving = true);
                              final ok = await _syncControllersAndSave();
                              if (!mounted) return;
                              if (!context.mounted) return;
                              setState(() => _isSaving = false);
                              // Issue 2 fix (Completed Category enhancement):
                              // single Save button during rework, returns
                              // to Inspection Summary.
                              if (ok) {
                                Navigator.pop(context);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Save failed.')));
                              }
                            },
                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                            child: _isSaving
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : Text('Save', style: InsightTheme.poppins(15, w: FontWeight.w600, c: InsightTheme.blue1)),
                          ),
                        ),
                      ] else ...[
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _handleContinue,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ).copyWith(elevation: WidgetStateProperty.all(0)),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Ink(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [InsightTheme.blue1, InsightTheme.blue2], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [BoxShadow(color: InsightTheme.blue1.withValues(alpha: 0.32), blurRadius: 20, offset: const Offset(0, 8))],
                            ),
                            child: Container(
                              width: double.infinity,
                              alignment: Alignment.center,
                              constraints: const BoxConstraints(minHeight: 52),
                              padding: const EdgeInsets.symmetric(horizontal: 18),
                              child: Text('Continue to Review', textAlign: TextAlign.center, style: InsightTheme.poppins(15, w: FontWeight.w600, c: Colors.white)),
                            ),
                          ),
                        ),
                        ),
                      ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    ));
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