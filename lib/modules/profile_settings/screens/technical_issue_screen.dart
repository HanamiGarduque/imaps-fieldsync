import 'dart:io';

import 'package:flutter/material.dart';
import '../../../core/widgets/sensitive_screen.dart';

import '../../../core/models/report_models.dart';
import '../../../core/services/app_info_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/report_submission_service.dart';
import '../../../core/theme/insight_theme.dart';
import '../widgets/report_form_widgets.dart';

/// Technical Issue is job-independent. The existing queue owns persistence and
/// delivery; the form only captures context and validates inspector input.
class TechnicalIssueScreen extends StatefulWidget {
  const TechnicalIssueScreen({super.key});

  @override
  State<TechnicalIssueScreen> createState() => _TechnicalIssueScreenState();
}

class _TechnicalIssueScreenState extends State<TechnicalIssueScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _summary = TextEditingController();
  final _expected = TextEditingController();
  final _repro = TextEditingController();
  String _module = kTechnicalIssueModules.first;
  bool _blocks = false;
  bool _submitting = false;
  String? _error;
  final DateTime _occurredAt = DateTime.now();

  @override
  void dispose() {
    _title.dispose();
    _summary.dispose();
    _expected.dispose();
    _repro.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !validateReportForm(_formKey)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final online = await AuthService.hasConnectivity();
      if (!mounted) return;
      await ReportQueueService.enqueueTechnicalIssue(
        TechnicalIssueDraft(
          title: _title.text,
          module: _module,
          summary: _summary.text,
          expectedBehavior: _expected.text,
          reproSteps: _repro.text,
          blocksFieldWork: _blocks,
          occurredAt: _occurredAt,
          connectivityState: online ? 'online' : 'offline',
          appVersion: AppInfoService.fullVersionString,
          osVersion: _osVersion(),
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e, stack) {
      debugPrintStack(label: '[REPORTS] Technical Issue', stackTrace: stack);
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = ReportQueueService.userFacingMessage(
            e,
            reportType: 'Technical Issue',
          );
        });
      }
    }
  }

  String _osVersion() {
    try {
      return Platform.operatingSystemVersion;
    } catch (_) {
      return 'unavailable';
    }
  }

  @override
  Widget build(BuildContext context) => SensitiveScreen(child: _scaffold());

  Widget _scaffold() => Scaffold(
    backgroundColor: InsightTheme.bg,
    appBar: AppBar(
      backgroundColor: InsightTheme.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      foregroundColor: InsightTheme.ink,
      title: Text(
        'Technical Issue',
        style: InsightTheme.urbanist(18, w: FontWeight.w700),
      ),
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: reportPagePadding(context),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Modern Intro Banner ──
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: InsightTheme.blueTint.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: InsightTheme.blue1.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 20,
                      color: InsightTheme.blueInk,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Report a problem with FieldSync itself. No task or application is needed.',
                        style: InsightTheme.inter(13, c: InsightTheme.ink2, h: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Section 1: Issue Details Card ──
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: InsightTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: InsightTheme.line),
                  boxShadow: InsightTheme.cardShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: InsightTheme.blueTint,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.bug_report_outlined,
                            size: 18,
                            color: InsightTheme.blue1,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Issue Details',
                          style: InsightTheme.urbanist(
                            16,
                            w: FontWeight.w800,
                            c: InsightTheme.ink,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Divider(height: 1, color: InsightTheme.line),
                    const SizedBox(height: 16),
                    ReportTextField(
                      label: 'Title',
                      hint: 'e.g. App closes when I open a task',
                      controller: _title,
                      validator: ReportInput.titleError,
                      minLines: 1,
                      maxLines: 2,
                      textInputAction: TextInputAction.next,
                      enabled: !_submitting,
                    ),
                    const SizedBox(height: 16),
                    const ExcludeSemantics(
                      child: ReportFieldLabel('Screen or module'),
                    ),
                    Semantics(
                      label: 'Screen or module, required',
                      child: ButtonTheme(
                        alignedDropdown: true,
                        child: DropdownButtonFormField<String>(
                          initialValue: _module,
                          isExpanded: true,
                          isDense: false,
                          itemHeight: null,
                          style: InsightTextStyles.bodySecondary(
                            color: InsightTheme.ink,
                          ),
                          dropdownColor: InsightTheme.surface,
                          borderRadius: InsightTheme.roundedSm,
                          elevation: 3,
                          menuMaxHeight: MediaQuery.sizeOf(context).height * 0.5,
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: InsightTheme.ink2,
                          ),
                          decoration: reportInputDecoration('Where did it happen?')
                              .copyWith(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 4,
                                ),
                              ),
                          validator: ReportInput.moduleError,
                          items: [
                            for (final module in kTechnicalIssueModules)
                              DropdownMenuItem(
                                value: module,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Text(module),
                                ),
                              ),
                          ],
                          onChanged: _submitting
                              ? null
                              : (value) {
                                  if (value != null) setState(() => _module = value);
                                },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ReportTextField(
                      label: 'What happened?',
                      hint: 'Describe what you saw, in your own words',
                      controller: _summary,
                      validator: ReportInput.summaryError,
                      minLines: 3,
                      maxLines: 5,
                      enabled: !_submitting,
                    ),
                    const SizedBox(height: 16),
                    ReportTextField(
                      label: 'What did you expect to happen?',
                      hint: 'What should FieldSync have done?',
                      controller: _expected,
                      validator: ReportInput.optionalError,
                      required: false,
                      enabled: !_submitting,
                    ),
                    const SizedBox(height: 16),
                    ReportTextField(
                      label: 'Steps to reproduce',
                      hint: 'What did you tap, in order?',
                      controller: _repro,
                      validator: ReportInput.optionalError,
                      required: false,
                      enabled: !_submitting,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Section 2: Work Impact Card ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: InsightTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: InsightTheme.line),
                  boxShadow: InsightTheme.cardShadow,
                ),
                child: SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  activeTrackColor: InsightTheme.blue1,
                  title: Text(
                    'Does this block your field work?',
                    style: InsightTextStyles.formLabel(),
                  ),
                  subtitle: Text(
                    'Turn off if you can keep working.',
                    style: InsightTextStyles.caption(),
                  ),
                  value: _blocks,
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() => _blocks = value),
                ),
              ),
              const SizedBox(height: 16),

              // ── Section 3: Device Diagnostics Card ──
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: InsightTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: InsightTheme.line),
                  boxShadow: InsightTheme.cardShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: InsightTheme.blueTint,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.devices_rounded,
                            size: 18,
                            color: InsightTheme.blue1,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Captured for this report',
                          style: InsightTheme.urbanist(
                            15,
                            w: FontWeight.w800,
                            c: InsightTheme.ink,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: InsightTheme.surface2.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: InsightTheme.line.withValues(alpha: 0.6),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.access_time_rounded,
                                size: 14,
                                color: InsightTheme.ink3,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _occurredAt.toLocal().toString().split('.').first,
                                style: InsightTheme.inter(
                                  12,
                                  w: FontWeight.w600,
                                  c: InsightTheme.ink,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(
                                Icons.phone_android_rounded,
                                size: 14,
                                color: InsightTheme.ink3,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'App ${AppInfoService.fullVersionString} · ${_osVersion()}',
                                  style: InsightTheme.inter(
                                    12,
                                    w: FontWeight.w500,
                                    c: InsightTheme.ink2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'App version and connection details are attached automatically.',
                      style: InsightTextStyles.caption(),
                    ),
                  ],
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 16),
                ReportNotice(_error!, error: true),
              ],
              const SizedBox(height: 20),
              ReportSubmitButton(submitting: _submitting, onPressed: _submit),
              const SizedBox(height: 16),
              const ReportOfflineNote(),
            ],
          ),
        ),
      ),
    ),
  );
}
