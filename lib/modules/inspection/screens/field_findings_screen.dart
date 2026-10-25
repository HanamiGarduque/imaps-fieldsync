import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/widgets/field_form_widgets.dart';
import 'package:flutter/services.dart';

import 'inspection_step_router.dart';
import '../../tasks/screens/tasks_screen.dart';
import 'inspection_progress.dart';
import 'package:provider/provider.dart';
import '../providers/inspection_provider.dart';
import '../widgets/exit_confirm_dialog.dart';
import '../../../core/widgets/sensitive_screen.dart';

import '../../../core/theme/insight_theme.dart';
import '../widgets/inspection_step_header.dart';
import '../structured_checklist.dart';
import '../widgets/structured_checklist_summary.dart';
import '../services/photo_evidence_presentation.dart';

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

class _FieldFindingsScreenState extends State<FieldFindingsScreen>
    with WidgetsBindingObserver {
  bool _isSaving = false;
  late final InspectionProvider _provider;
  late final TextEditingController _notesController;
  late final TextEditingController _discrepancyTitleController;
  late final TextEditingController _discrepancyDetailController;
  late final TextEditingController _recommendationsController;
  // Normal (not rework) typing autosaves so a process interruption cannot
  // discard field evidence that was never submitted. Rework keeps its
  // explicit Save contract, where one Save is one deliberate revision.
  Timer? _autosaveTimer;
  bool _autosavePending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // BUG FIX #4A — Global Data Persistence.
    // Controllers used to always start empty, even when InspectionProvider
    // already had real hydrated data (rework mode, or a resumed Ongoing
    // task). That meant the inspector saw blank fields for findings that
    // were already on file, and hitting "Continue" without retyping would
    // silently overwrite that real data with empty strings. Prefill from
    // the provider's current state instead — it's already correctly
    // seeded via hydrateForRework() / startInspection()'s local draft load.
    final provider = context.read<InspectionProvider>();
    _provider = provider;
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
    WidgetsBinding.instance.removeObserver(this);
    // Flush whatever is still typed before the screen (and any later app
    // kill) can drop it. Fire-and-forget: dispose cannot await.
    _flushAutosave();
    _notesController.dispose();
    _discrepancyTitleController.dispose();
    _discrepancyDetailController.dispose();
    _recommendationsController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _flushAutosave();
    }
  }

  void _scheduleAutosave() {
    if (_isSaving || _provider.isReworkMode) return;
    _autosavePending = true;
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 400), _flushAutosave);
  }

  void _flushAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    if (!_autosavePending || _isSaving) return;
    _autosavePending = false;
    unawaited(() async {
      try {
        _collectControllersIntoProvider();
        final ok = await _provider.saveStepFindings();
        if (!ok) _autosavePending = true;
      } catch (e) {
        // Ownership can change or local storage can fail while the debounce
        // is pending. Keep the typed text on screen and let the next edit or
        // lifecycle flush retry instead of throwing from a timer/dispose.
        _autosavePending = true;
        debugPrint('FieldFindings autosave deferred — $e');
      }
    }());
  }

  Future<void> _handleContinue() async {
    if (_isSaving) return;
    HapticFeedback.selectionClick();
    setState(() => _isSaving = true);
    var ok = false;
    try {
      ok = await _syncControllersAndSave();
    } catch (_) {
      // Keep the typed evidence visible if ownership or local storage fails.
    }
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not save findings on this device. Keep this screen open, check available storage and try again.',
          ),
        ),
      );
      return;
    }
    InspectionProgress.instance.markStepComplete(5);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => buildNextInspectionStep(
          currentStep: 5,
          task: widget.task,
          provider: _provider,
        ),
      ),
    );
  }

  /// Moves the controller text into provider state. Memory only — this is what
  /// an in-session draft is, and the input every persist path below reads.
  void _collectControllersIntoProvider() {
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
    _provider.updateFindings(
      actualLandUse: widget.task.landUseClass,
      notes: _notesController.text.trim(),
      discrepancies: discrepancies,
      recommendations: _recommendationsController.text.trim(),
      // Carries forward whatever GpsVerificationScreen actually recorded
      // in Step 2 (e.g. "Verified on-site — 6m from declared location")
      // instead of hardcoding a status that may not reflect reality.
      boundaryStatus: _provider.boundaryStatus,
    );
  }

  Future<bool> _syncControllersAndSave() async {
    _collectControllersIntoProvider();
    return context.read<InspectionProvider>().saveStepFindings();
  }

  /// The Field Findings Save button — the only path allowed to report a
  /// "Field Findings updated" activity.
  Future<bool> _syncControllersAndSaveExplicitly() async {
    _collectControllersIntoProvider();
    return context.read<InspectionProvider>().saveStepFindings(
      isExplicitSave: true,
    );
  }

  /// Leaving a completed task's Field Findings without pressing Save keeps the
  /// text as an in-session draft and nothing more: no evidence write, no queued
  /// write, and above all no "saved/updated" activity claiming a save that was
  /// never made. An unfinished inspection is a different contract — Back there
  /// means "my progress is saved", so it keeps autosaving.
  Future<bool> _onExit() async {
    if (context.read<InspectionProvider>().isReworkMode) {
      _collectControllersIntoProvider();
      return true;
    }
    return _syncControllersAndSave();
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    final provider = context.watch<InspectionProvider>();
    final structured = provider.structuredAnswers;
    final evidence = PhotoEvidencePresentation(
      provider.activeTask?.id == widget.task.id
          ? provider.capturedPhotos
          : widget.capturedPhotos,
      requireMetadata: provider.isReworkMode,
    );
    final hasStructured = StructuredChecklist.activeAnswers(
      structured,
    ).isNotEmpty;
    return SensitiveScreen(
      child: PopScope(
        canPop:
            !_isSaving &&
            !context.read<InspectionProvider>().isReworkMode &&
            InspectionProgress.instance.currentStep > 1,
        onPopInvokedWithResult: (didPop, _) {
          if (_isSaving) return;
          if (didPop) {
            _onExit();
            return;
          }
          handleInspectionExit(
            context,
            onSaveProgress: _onExit,
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
              onBack: () => _isSaving
                  ? null
                  : handleInspectionExit(
                      context,
                      onSaveProgress: _onExit,
                      isReworkMode: context
                          .read<InspectionProvider>()
                          .isReworkMode,
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
                              final ok =
                                  await _syncControllersAndSaveExplicitly();
                              if (!context.mounted) return;
                              setState(() => _isSaving = false);
                              // Issue 2 fix (Completed Category enhancement):
                              // single Save button during rework, returns
                              // to Inspection Summary.
                              if (ok) {
                                Navigator.pop(context);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Could not save findings on this device. Keep this screen open, check available storage and try again.',
                                    ),
                                  ),
                                );
                              }
                            },
                    ),
                  ),
                ] else ...[
                  Expanded(
                    child: FieldPrimaryButton(
                      label: nextStepLabel(5),
                      busy: _isSaving,
                      busyLabel: 'Saving on device…',
                      onPressed: _isSaving ? null : _handleContinue,
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
                bottomSpacing: 8,
              ),
              TextField(
                controller: _notesController,
                readOnly: _isSaving,
                onChanged: (_) => _scheduleAutosave(),
                maxLines: 4,
                minLines: 3,
                style: InsightTheme.inter(16, c: InsightTheme.ink),
                decoration: InsightTheme.compactFormInput.copyWith(
                  labelText: 'Site observations',
                  alignLabelWithHint: true,
                  hintText: 'Describe what you observed on-site…',
                ),
              ),
              if (evidence.totalCount > 0 ||
                  widget.checklistTotal > 0 ||
                  hasStructured) ...[
                const SizedBox(height: 16),
                if (hasStructured)
                  StructuredChecklistSummary(
                    heading: 'Site conditions & project status',
                    answers: structured,
                  ),
                if (hasStructured &&
                    (evidence.totalCount > 0 || widget.checklistTotal > 0))
                  const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    if (evidence.totalCount > 0)
                      Text(
                        '${evidence.sitePhotoCount} ${evidence.sitePhotoCount == 1 ? 'site photo' : 'site photos'} attached',
                        style: InsightTheme.inter(13, c: InsightTheme.ink3),
                      ),
                    if (evidence.referenceCount > 0)
                      Text(
                        'Site Location Reference attached',
                        style: InsightTheme.inter(13, c: InsightTheme.ink3),
                      ),
                    if (evidence.unclassifiedCount > 0)
                      Text(
                        '${evidence.unclassifiedCount} evidence attachments (type unavailable)',
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
              const SizedBox(height: 20),
              const FieldSectionHeading(
                title: 'Discrepancies / assessment explanation',
                hint:
                    'Optional. Leave these fields blank if no issues were found. Required for any non-Compliant assessment: describe what was observed and why it differs or needs review/reinspection.',
                hintSize: 12.5,
                bottomSpacing: 8,
              ),
              TextField(
                controller: _discrepancyTitleController,
                readOnly: _isSaving,
                onChanged: (_) => _scheduleAutosave(),
                maxLines: 2,
                minLines: 1,
                style: InsightTheme.inter(16, c: InsightTheme.ink),
                decoration: InsightTheme.compactFormInput.copyWith(
                  labelText: 'Issue title (optional)',
                  hintText: 'Brief description of the issue',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _discrepancyDetailController,
                readOnly: _isSaving,
                onChanged: (_) => _scheduleAutosave(),
                minLines: 2,
                maxLines: 5,
                style: InsightTheme.inter(16, c: InsightTheme.ink),
                decoration: InsightTheme.compactFormInput.copyWith(
                  labelText: 'Issue details',
                  alignLabelWithHint: true,
                  hintText:
                      'What was observed, where, and why it differs or needs follow-up',
                ),
              ),
              const SizedBox(height: 20),
              const FieldSectionHeading(
                title: 'Recommendations',
                hint:
                    'Describe any permits, follow-up or other recommended action.',
                hintSize: 12.5,
                bottomSpacing: 8,
              ),
              TextField(
                controller: _recommendationsController,
                readOnly: _isSaving,
                onChanged: (_) => _scheduleAutosave(),
                maxLines: 3,
                minLines: 2,
                style: InsightTheme.inter(16, c: InsightTheme.ink),
                decoration: InsightTheme.compactFormInput.copyWith(
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
