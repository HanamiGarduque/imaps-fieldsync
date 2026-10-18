import 'package:flutter/material.dart';
import '../../../core/widgets/sensitive_screen.dart';

import '../../../core/models/report_models.dart';
import '../../../core/services/report_submission_service.dart';
import '../../../core/services/reportable_tasks.dart';
import '../../../core/theme/insight_theme.dart';
import '../widgets/report_form_widgets.dart';

/// Concerns about one exact inspector-scoped task. The existing loader owns
/// online refresh/cache fallback; iMAPS resolves the current Planning Officer.
class ApplicationSupportScreen extends StatefulWidget {
  const ApplicationSupportScreen({
    super.key,
    this.loadTasks = ReportableTasks.loadForInspector,
  });
  final Future<List<ReportableTask>> Function() loadTasks;

  @override
  State<ApplicationSupportScreen> createState() =>
      _ApplicationSupportScreenState();
}

class _ApplicationSupportScreenState extends State<ApplicationSupportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _taskKey = GlobalKey<FormFieldState<ReportableTask>>();
  final _description = TextEditingController();
  final _affectedField = TextEditingController();
  final _requestedChange = TextEditingController();
  List<ReportableTask> _tasks = const [];
  ReportableTask? _selected;
  String? _category;
  bool _blocks = false;
  bool _loading = true;
  bool _refreshing = false;
  bool _submitting = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _description.dispose();
    _affectedField.dispose();
    _requestedChange.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_refreshing || _submitting) return;
    setState(() => _refreshing = true);
    try {
      final tasks = await widget.loadTasks();
      if (!mounted) return;
      final retained = ReportableTasks.retainSelection(tasks, _selected);
      final invalidated = _selected != null && retained == null;
      setState(() {
        _tasks = tasks;
        _selected = retained;
        _notice = invalidated
            ? 'The task you selected is no longer available or is missing its saved identity. Please choose another task.'
            : null;
      });
      _taskKey.currentState?.didChange(retained);
    } catch (e, stack) {
      debugPrint('[REPORTS] task refresh failed: $e');
      debugPrintStack(stackTrace: stack);
      if (mounted) {
        setState(
          () => _notice =
              'Could not refresh tasks. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_submitting || !validateReportForm(_formKey)) return;
    final task = _selected!;
    final draft = ApplicationSupportDraft(
      fieldJobId: task.fieldJobId,
      supabaseApplicationId: task.supabaseApplicationId!,
      bridgeSourceId: task.bridgeSourceId!,
      supportCategory: _category!,
      description: _description.text,
      affectedField: _affectedField.text,
      requestedChange: _requestedChange.text,
      blocksFieldWork: _blocks,
    );
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ReportQueueService.enqueueApplicationSupport(draft);
      if (mounted) Navigator.pop(context, true);
    } catch (e, stack) {
      debugPrintStack(
        label: '[REPORTS] Application Support',
        stackTrace: stack,
      );
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = ReportQueueService.userFacingMessage(
            e,
            reportType: 'Application Support',
          );
        });
      }
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
        'Application Support',
        style: InsightTheme.urbanist(18, w: FontWeight.w700),
      ),
    ),
    body: SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        color: InsightTheme.blue1,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: reportPagePadding(context),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Report a concern about one of your tasks or applications. '
                  'iMAPS handles routing to the current Planning Officer.',
                  style: InsightTextStyles.bodySecondary(),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(
                      child: ReportFieldLabel('Task / application'),
                    ),
                    IconButton(
                      tooltip: 'Refresh tasks',
                      onPressed: _refreshing || _submitting ? null : _load,
                      icon: const Icon(
                        Icons.refresh_rounded,
                        color: InsightTheme.blue1,
                      ),
                    ),
                  ],
                ),
                FormField<ReportableTask>(
                  key: _taskKey,
                  validator: (task) => task == null
                      ? 'Choose the task this concerns.'
                      : !task.identityComplete
                      ? 'Refresh this task online before reporting an application concern.'
                      : null,
                  builder: (field) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text('Loading your tasks…'),
                        )
                      else if (_tasks.isEmpty)
                        const ReportNotice(
                          'No tasks available for reporting. Open My Tasks while online '
                          'to refresh your assignments, then tap Refresh tasks here.',
                        )
                      else
                        for (final task in _tasks) ...[
                          _TaskTile(
                            key: ValueKey('report-task-${task.fieldJobId}'),
                            task: task,
                            selected: _selected?.fieldJobId == task.fieldJobId,
                            onTap: task.identityComplete && !_submitting
                                ? () {
                                    setState(() {
                                      _selected = task;
                                      _notice = null;
                                    });
                                    field.didChange(task);
                                    if (field.hasError) field.validate();
                                  }
                                : null,
                          ),
                          const SizedBox(height: 8),
                        ],
                      if (field.hasError) _FieldError(field.errorText!),
                    ],
                  ),
                ),
                if (_notice != null) ...[
                  const SizedBox(height: 8),
                  ReportNotice(_notice!),
                ],
                const SizedBox(height: 20),
                const ReportFieldLabel('Support category'),
                FormField<String>(
                  validator: ReportInput.categoryError,
                  builder: (field) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final entry in SupportCategories.labels.entries) ...[
                        _ChoiceTile(
                          title: entry.value,
                          selected: _category == entry.key,
                          onTap: _submitting
                              ? null
                              : () {
                                  setState(() => _category = entry.key);
                                  field.didChange(entry.key);
                                  if (field.hasError) field.validate();
                                },
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (field.hasError) _FieldError(field.errorText!),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ReportTextField(
                  label: 'Description',
                  hint: 'What is wrong or unclear?',
                  controller: _description,
                  validator: ReportInput.descriptionError,
                  minLines: 3,
                  maxLines: 5,
                  enabled: !_submitting,
                ),
                const SizedBox(height: 16),
                ReportTextField(
                  label: 'Affected information',
                  hint: 'Which detail is affected?',
                  controller: _affectedField,
                  validator: ReportInput.optionalError,
                  required: false,
                  enabled: !_submitting,
                ),
                const SizedBox(height: 16),
                ReportTextField(
                  label: 'Requested correction or clarification',
                  hint: 'What should it say instead?',
                  controller: _requestedChange,
                  validator: ReportInput.optionalError,
                  required: false,
                  enabled: !_submitting,
                ),
                const SizedBox(height: 16),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  activeTrackColor: InsightTheme.blue1,
                  title: Text(
                    'Does this block your inspection?',
                    style: InsightTextStyles.formLabel(),
                  ),
                  value: _blocks,
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() => _blocks = value),
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
    ),
  );
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    super.key,
    required this.task,
    required this.selected,
    this.onTap,
  });
  final ReportableTask task;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => _ChoiceTile(
    title: task.displayTitle,
    subtitle: '${task.barangay} · ${task.applicationType} · ${task.status}',
    notice: !task.identityComplete
        ? 'Refresh this task online before reporting an application concern.'
        : null,
    selected: selected,
    onTap: onTap,
  );
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.title,
    required this.selected,
    this.onTap,
    this.subtitle,
    this.notice,
  });
  final String title;
  final String? subtitle;
  final String? notice;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    checked: selected,
    inMutuallyExclusiveGroup: true,
    enabled: onTap != null,
    child: Material(
      color: selected ? InsightTheme.blueTint : InsightTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: InsightTheme.roundedSm,
        side: BorderSide(
          color: selected ? InsightTheme.blue1 : InsightTheme.lineStrong,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: InsightTheme.roundedSm,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: selected ? InsightTheme.blue1 : InsightTheme.ink3,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: InsightTheme.inter(
                        14,
                        w: selected ? FontWeight.w700 : FontWeight.w500,
                        c: InsightTheme.ink,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(subtitle!, style: InsightTextStyles.caption()),
                    ],
                    if (notice != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        notice!,
                        style: InsightTextStyles.caption(
                          color: InsightTheme.amberInk,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _FieldError extends StatelessWidget {
  const _FieldError(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Semantics(
      liveRegion: true,
      child: Text(
        message,
        style: InsightTheme.inter(12, c: InsightTheme.redInk),
      ),
    ),
  );
}
