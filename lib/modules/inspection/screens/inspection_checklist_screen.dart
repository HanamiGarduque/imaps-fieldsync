import 'package:flutter/material.dart';
import '../../../core/widgets/field_form_widgets.dart';
import 'package:flutter/services.dart';
import 'dart:async';

import 'inspection_step_router.dart';
import '../../tasks/screens/tasks_screen.dart';
import 'inspection_progress.dart';
import 'package:provider/provider.dart';
import '../providers/inspection_provider.dart';
import '../structured_checklist.dart';
import '../widgets/exit_confirm_dialog.dart';
import '../../../core/widgets/sensitive_screen.dart';

import '../../../core/theme/insight_theme.dart';
import '../widgets/inspection_step_header.dart';

class InspectionChecklistScreen extends StatefulWidget {
  final TaskItem task;
  final List<Map<String, dynamic>> capturedPhotos;
  const InspectionChecklistScreen({
    super.key,
    required this.task,
    this.capturedPhotos = const [],
  });
  @override
  State<InspectionChecklistScreen> createState() =>
      _InspectionChecklistScreenState();
}

class _InspectionChecklistScreenState extends State<InspectionChecklistScreen> {
  // The provider owns both fresh and restored evidence; no second defaults.
  final Map<String, bool> _siteCondition = {};
  bool _isSaving = false;
  final Map<String, bool> _zoningObservations = {};
  Timer? _structuredSaveTimer;
  late final TextEditingController _existingUseController;

  int get _doneCount =>
      _siteCondition.values.where((v) => v).length +
      _zoningObservations.values.where((v) => v).length;
  int get _totalCount => _siteCondition.length + _zoningObservations.length;

  @override
  void initState() {
    super.initState();
    final provider = context.read<InspectionProvider>();
    _siteCondition
      ..clear()
      ..addAll(provider.siteCondition);
    _zoningObservations
      ..clear()
      ..addAll(provider.zoningObservations);
    _existingUseController = TextEditingController(
      text: provider.structuredAnswers[StructuredChecklist.existingUse] ?? '',
    );
  }

  @override
  void dispose() {
    _structuredSaveTimer?.cancel();
    _existingUseController.dispose();
    super.dispose();
  }

  /// Persists one CE-05 answer. Dropdown choices save at once like the legacy
  /// checklist; typed use text is debounced so each keystroke cannot queue a
  /// database write.
  void _setStructured(String key, String? value, {bool saveNow = true}) {
    try {
      context.read<InspectionProvider>().setStructuredAnswer(key, value);
    } catch (_) {
      return;
    }
    if (!saveNow) return;
    _structuredSaveTimer?.cancel();
    _saveChecklist();
  }

  BoxDecoration get _cardDecoration => BoxDecoration(
    color: InsightTheme.surface,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: InsightTheme.line),
    boxShadow: InsightTheme.inspectionCardShadow,
  );

  Widget _structuredQuestion(
    String key,
    Map<String, String?> answers,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          StructuredChecklist.questionLabels[key]!,
          style: InsightTheme.inter(
            14,
            w: FontWeight.w500,
            c: InsightTheme.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          StructuredChecklist.questionHints[key]!,
          style: InsightTheme.inter(12, c: InsightTheme.ink3),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey('structured_$key'),
          initialValue: answers[key] ?? '',
          isExpanded: true,
          decoration: InsightTheme.compactFormInput,
          items: [
            const DropdownMenuItem(value: '', child: Text('Not recorded')),
            for (final option in StructuredChecklist.optionsFor(key).entries)
              DropdownMenuItem(value: option.key, child: Text(option.value)),
          ],
          onChanged: _isSaving
              ? null
              : (selected) =>
                    _setStructured(key, selected == '' ? null : selected),
        ),
      ],
    );
  }

  Widget _existingUseField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          StructuredChecklist.questionLabels[StructuredChecklist.existingUse]!,
          style: InsightTheme.inter(
            14,
            w: FontWeight.w500,
            c: InsightTheme.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          StructuredChecklist.questionHints[StructuredChecklist.existingUse]!,
          style: InsightTheme.inter(12, c: InsightTheme.ink3),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('structured_existing_use_input'),
          controller: _existingUseController,
          enabled: !_isSaving,
          maxLength: 120,
          style: InsightTheme.inter(16, c: InsightTheme.ink),
          decoration: InsightTheme.compactFormInput.copyWith(
            hintText: 'e.g. residential, commercial, agricultural',
            counterText: '',
          ),
          onChanged: (value) {
            _setStructured(
              StructuredChecklist.existingUse,
              value,
              saveNow: false,
            );
            _structuredSaveTimer?.cancel();
            _structuredSaveTimer = Timer(
              const Duration(milliseconds: 400),
              _saveChecklist,
            );
          },
        ),
      ],
    );
  }

  Future<bool> _saveChecklist() async {
    bool ok;
    try {
      ok = await context.read<InspectionProvider>().saveStepChecklist();
    } catch (_) {
      ok = false;
    }
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not save the checklist on this device. Keep this screen open, check available storage and try again.',
          ),
        ),
      );
    }
    return ok;
  }

  Future<void> _continueToFindings() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    final ok = await _saveChecklist();
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (!ok) return;
    InspectionProgress.instance.markStepComplete(4);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => buildNextInspectionStep(
          currentStep: 4,
          task: widget.task,
          provider: context.read<InspectionProvider>(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    final structured = context.watch<InspectionProvider>().structuredAnswers;
    return SensitiveScreen(
      child: PopScope(
        canPop:
            !_isSaving &&
            !context.read<InspectionProvider>().isReworkMode &&
            InspectionProgress.instance.currentStep > 1,
        onPopInvokedWithResult: (didPop, _) {
          if (_isSaving) return;
          if (didPop) {
            // Already popped natively (smooth swipe/hardware-back animation) —
            // fire the save in the background, nothing to block on here.
            context.read<InspectionProvider>().saveStepChecklist();
            return;
          }
          handleInspectionExit(
            context,
            onSaveProgress: () =>
                context.read<InspectionProvider>().saveStepChecklist(),
            isReworkMode: context.read<InspectionProvider>().isReworkMode,
          );
        },
        child: Scaffold(
          backgroundColor: InsightTheme.bg,
          body: FieldFormBody(
            header: InspectionStepHeader(
              formStyle: true,
              title: 'Zoning Checklist',
              subtitle: widget.task.location,
              stepNumber: 4,
              stepSubtitle: 'VERIFY CRITERIA',
              onBack: () => _isSaving
                  ? null
                  : handleInspectionExit(
                      context,
                      onSaveProgress: () => context
                          .read<InspectionProvider>()
                          .saveStepChecklist(),
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
                              final ok = await _saveChecklist();
                              if (!context.mounted) return;
                              setState(() => _isSaving = false);
                              // Issue 2 fix (Completed Category enhancement):
                              // single Save button during rework, returns to
                              // Inspection Summary instead of leaving the
                              // inspector on the step needing a separate
                              // "Continue" tap that doesn't apply here.
                              if (ok) {
                                Navigator.pop(context);
                              }
                            },
                    ),
                  ),
                ] else ...[
                  Expanded(
                    child: FieldPrimaryButton(
                      label: nextStepLabel(4),
                      busy: _isSaving,
                      busyLabel: 'Saving on device…',
                      onPressed: _isSaving ? null : _continueToFindings,
                    ),
                  ),
                ],
              ],
            ),
            children: [
              FieldSectionHeading(
                title: 'Site condition',
                hint:
                    'Check only statements you verified on-site. Unchecked means not affirmed, not automatically non-compliant.',
                trailing: Text(
                  '$_doneCount of $_totalCount checked',
                  style: InsightTheme.inter(
                    13,
                    w: FontWeight.w600,
                    c: InsightTheme.blueInk,
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: InsightTheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: InsightTheme.line),
                  boxShadow: InsightTheme.inspectionCardShadow,
                ),
                child: Column(
                  children: _siteCondition.entries.toList().asMap().entries.map((
                    entry,
                  ) {
                    var e = entry.value;
                    return _ChecklistItem(
                      title: e.key,
                      isChecked: e.value,
                      isLast: entry.key == _siteCondition.length - 1,
                      onTap: () {
                        if (_isSaving) return;
                        // Persist through the provider FIRST: it refuses a write that is no
                        // longer owned by this session, and the visible
                        // checkbox must never diverge from that.
                        try {
                          context.read<InspectionProvider>().setSiteCondition(
                            e.key,
                            !e.value,
                          );
                        } catch (_) {
                          return;
                        }
                        setState(() => _siteCondition[e.key] = !e.value);
                        _saveChecklist();
                      },
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 24),
              const FieldSectionHeading(
                title: 'Zoning observations',
                hint:
                    'Record what you verified. Explain any discrepancy or uncertainty in Findings; no minimum checked count is required here.',
              ),
              Container(
                decoration: BoxDecoration(
                  color: InsightTheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: InsightTheme.line),
                  boxShadow: InsightTheme.inspectionCardShadow,
                ),
                child: Column(
                  children: _zoningObservations.entries
                      .toList()
                      .asMap()
                      .entries
                      .map((entry) {
                        var e = entry.value;
                        return _ChecklistItem(
                          title: e.key,
                          isChecked: e.value,
                          isLast: entry.key == _zoningObservations.length - 1,
                          onTap: () {
                            if (_isSaving) return;
                            try {
                              context
                                  .read<InspectionProvider>()
                                  .setZoningObservation(e.key, !e.value);
                            } catch (_) {
                              return;
                            }
                            setState(
                              () => _zoningObservations[e.key] = !e.value,
                            );
                            _saveChecklist();
                          },
                        );
                      })
                      .toList(),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: _cardDecoration,
                padding: const EdgeInsets.all(16),
                child: _structuredQuestion(
                  StructuredChecklist.mojonObserved,
                  structured,
                ),
              ),
              const SizedBox(height: 24),
              const FieldSectionHeading(
                title: 'Project status',
                hint:
                    'Record only what you verified. An unanswered question stays Not recorded and is never treated as No.',
              ),
              Container(
                decoration: _cardDecoration,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _structuredQuestion(
                      StructuredChecklist.existingDevelopment,
                      structured,
                    ),
                    if (structured[StructuredChecklist
                            .existingDevelopment] ==
                        StructuredChecklist.yes) ...[
                      const SizedBox(height: 18),
                      _existingUseField(),
                    ],
                    const SizedBox(height: 18),
                    _structuredQuestion(
                      StructuredChecklist.extensionOfExisting,
                      structured,
                    ),
                    const SizedBox(height: 18),
                    _structuredQuestion(
                      StructuredChecklist.proposalStage,
                      structured,
                    ),
                    if (structured[StructuredChecklist.proposalStage] ==
                        StructuredChecklist.yes) ...[
                      const SizedBox(height: 18),
                      _structuredQuestion(
                        StructuredChecklist.treesPresent,
                        structured,
                      ),
                      const SizedBox(height: 18),
                      _structuredQuestion(
                        StructuredChecklist.canalWaterway,
                        structured,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChecklistItem extends StatelessWidget {
  final String title;
  final bool isChecked;
  final bool isLast;
  final VoidCallback onTap;
  const _ChecklistItem({
    required this.title,
    required this.isChecked,
    required this.isLast,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: isChecked,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          borderRadius: BorderRadius.vertical(
            top: isLast ? Radius.zero : const Radius.circular(20),
            bottom: isLast ? const Radius.circular(20) : Radius.zero,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              border: isLast
                  ? null
                  : const Border(bottom: BorderSide(color: InsightTheme.line)),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 200),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isChecked ? InsightTheme.blue1 : Colors.transparent,
                    border: isChecked
                        ? null
                        : Border.all(color: InsightTheme.lineStrong, width: 2),
                  ),
                  child: isChecked
                      ? const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 16,
                        )
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: InsightTheme.inter(
                      14,
                      w: FontWeight.w500,
                      c: InsightTheme.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
