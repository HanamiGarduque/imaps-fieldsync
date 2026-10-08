import 'package:flutter/material.dart';
import '../../../core/widgets/field_form_widgets.dart';
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
    _discrepancyDetailController = TextEditingController(
      text: provider.discrepancies,
    );
    _recommendationsController = TextEditingController(
      text: provider.recommendations,
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

    final discrepancyTitle = _discrepancyTitleController.text.trim();
    final discrepancyDetail = _discrepancyDetailController.text.trim();
    // Don't save a bare " — " when the inspector legitimately found nothing.
    final discrepancies =
        (discrepancyTitle.isEmpty && discrepancyDetail.isEmpty)
        ? ''
        : [
            discrepancyTitle,
            discrepancyDetail,
          ].where((s) => s.isNotEmpty).join(' — ');

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
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReviewSubmitScreen(task: widget.task)),
    );
  }

  Future<bool> _syncControllersAndSave() async {
    final provider = context.read<InspectionProvider>();
    final discrepancyTitle = _discrepancyTitleController.text.trim();
    final discrepancyDetail = _discrepancyDetailController.text.trim();
    final discrepancies =
        (discrepancyTitle.isEmpty && discrepancyDetail.isEmpty)
        ? ''
        : [
            discrepancyTitle,
            discrepancyDetail,
          ].where((s) => s.isNotEmpty).join(' — ');
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
    return SensitiveScreen(
      child: PopScope(
        canPop:
            !context.read<InspectionProvider>().isReworkMode &&
            InspectionProgress.instance.currentStep > 1,
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
          body: FieldFormBody(
            header: InspectionStepHeader(
              formStyle: true,
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
            action: Row(
              children: [
                if (context.watch<InspectionProvider>().isReworkMode) ...[
                  Expanded(
                    child: FieldPrimaryButton(
                      label: 'Save',
                      busy: _isSaving,
                      onPressed: _isSaving
                          ? null
                          : () async {
                              setState(() => _isSaving = true);
                              final ok = await _syncControllersAndSave();
                              if (!context.mounted) return;
                              setState(() => _isSaving = false);
                              // Issue 2 fix (Completed Category enhancement):
                              // single Save button during rework, returns
                              // to Inspection Summary.
                              if (ok) {
                                Navigator.pop(context);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Save failed.')),
                                );
                              }
                            },
                    ),
                  ),
                ] else ...[
                  Expanded(
                    child: FieldPrimaryButton(
                      label: 'Continue to Review',
                      onPressed: _handleContinue,
                    ),
                  ),
                ],
              ],
            ),
            children: [
              const FieldSectionHeading(
                title: 'Observations',
                hint:
                    'Record the site condition, land use and notable features.',
                hintSize: 12.5,
              ),
              TextField(
                controller: _notesController,
                maxLines: 4,
                minLines: 3,
                style: InsightTheme.inter(16, c: InsightTheme.ink),
                decoration: InsightTheme.formInput.copyWith(
                  labelText: 'Site observations',
                  alignLabelWithHint: true,
                  hintText: 'Describe what you observed on-site…',
                ),
              ),
              if (widget.capturedPhotos.isNotEmpty ||
                  widget.checklistTotal > 0) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    if (widget.capturedPhotos.isNotEmpty)
                      Text(
                        '${widget.capturedPhotos.length} ${widget.capturedPhotos.length == 1 ? 'photo' : 'photos'} attached',
                        style: InsightTheme.inter(13, c: InsightTheme.ink3),
                      ),
                    if (widget.checklistTotal > 0)
                      Text(
                        'Checklist: ${widget.checklistDone}/${widget.checklistTotal} checked',
                        style: InsightTheme.inter(13, c: InsightTheme.ink3),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              const FieldSectionHeading(
                title: 'Discrepancies',
                hint:
                    'Optional. Leave these fields blank if no issues were found.',
                hintSize: 12.5,
              ),
              TextField(
                controller: _discrepancyTitleController,
                maxLines: 2,
                minLines: 1,
                style: InsightTheme.inter(16, c: InsightTheme.ink),
                decoration: InsightTheme.formInput.copyWith(
                  labelText: 'Issue title',
                  hintText: 'Brief description of the issue',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _discrepancyDetailController,
                minLines: 2,
                maxLines: 5,
                style: InsightTheme.inter(16, c: InsightTheme.ink),
                decoration: InsightTheme.formInput.copyWith(
                  labelText: 'Issue details',
                  alignLabelWithHint: true,
                  hintText: 'Location and supporting details',
                ),
              ),
              const SizedBox(height: 24),
              const FieldSectionHeading(
                title: 'Recommendations',
                hint:
                    'Describe any permits, follow-up or other recommended action.',
                hintSize: 12.5,
              ),
              TextField(
                controller: _recommendationsController,
                maxLines: 3,
                minLines: 2,
                style: InsightTheme.inter(16, c: InsightTheme.ink),
                decoration: InsightTheme.formInput.copyWith(
                  labelText: 'Recommended action',
                  alignLabelWithHint: true,
                  hintText: 'Enter your recommendation…',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
