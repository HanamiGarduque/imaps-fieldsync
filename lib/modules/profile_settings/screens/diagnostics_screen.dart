import 'package:flutter/material.dart';
import '../services/diagnostics_service.dart';
import '../../../core/widgets/sensitive_screen.dart';
import '../../../core/theme/insight_theme.dart';

// Mapped to standard canonical InsightTheme design tokens
const _kBlue = InsightTheme.blue1;
const _kInk = InsightTheme.ink;
const _kInk2 = InsightTheme.ink2;
const _kLine = InsightTheme.line;
const _kSurface = InsightTheme.surface;
const _kBg = InsightTheme.bg;
const _kAmber = InsightTheme.orange;
const _kGreen = InsightTheme.green;
const _kCoral = InsightTheme.red;

/// Phase 3c — Diagnostics / Error Reports.
///
/// Purpose (see AUTH_SECURITY_MASTER_DOC.md §Phase 3c for the full
/// writeup): lets an inspector flag a problem for the MPDO admin team
/// without needing to understand or debug the app themselves. The
/// inspector provides a short title/description; the more technical
/// fields (technical description, repro steps, affected file,
/// recommended action) are filled in later by the admin/dev team
/// directly in Supabase — the admin has no account inside this app,
/// consistent with how "Forgot Passcode" already works here.
///
/// Security: this summary list screen is deliberately NOT wrapped in
/// SensitiveScreen — it must be safe to screenshot for documentation/
/// support purposes, and never shows secrets, tokens, or auth data. The
/// detail screen (_ReportDetailScreen below), which can contain more
/// technical information once the admin has reviewed a report, IS
/// wrapped in SensitiveScreen.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  late Future<List<DiagnosticReport>> _future;

  @override
  void initState() {
    super.initState();
    _future = DiagnosticsService.fetchMyReports();
  }

  Future<void> _refresh() async {
    setState(() => _future = DiagnosticsService.fetchMyReports());
    await _future;
  }

  Future<void> _openSubmitSheet() async {
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SubmitReportSheet(),
    );
    if (submitted == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    // Deliberately NOT wrapped in SensitiveScreen — see class doc above.
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        foregroundColor: _kInk,
        title: Text('Diagnostics & Support',
            style: InsightTheme.urbanist(17, w: FontWeight.w700, c: _kInk)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openSubmitSheet,
        backgroundColor: _kBlue,
        icon: const Icon(Icons.flag_outlined, color: Colors.white),
        label: Text('Report an Issue', style: InsightTheme.inter(14, w: FontWeight.w600, c: Colors.white)),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<DiagnosticReport>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: _kBlue));
            }
            if (snapshot.hasError) {
              return ListView(
                children: [
                  const SizedBox(height: 120),
                  Icon(Icons.cloud_off_rounded, size: 40, color: _kInk2.withValues(alpha: 0.4)),
                  const SizedBox(height: 12),
                  Center(
                    child: Text('Couldn\'t load your reports.\nPull down to try again.',
                        textAlign: TextAlign.center, style: InsightTheme.inter(14, c: _kInk2)),
                  ),
                ],
              );
            }
            final reports = snapshot.data ?? [];
            if (reports.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 100),
                  Icon(Icons.task_alt_rounded, size: 44, color: _kInk2.withValues(alpha: 0.35)),
                  const SizedBox(height: 12),
                  Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        'No issues reported yet. If something in the app isn\'t working right, tap "Report an Issue" below.',
                        textAlign: TextAlign.center,
                        style: InsightTheme.inter(14, c: _kInk2),
                      ),
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: reports.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _ReportCard(report: reports[i]),
            );
          },
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final DiagnosticReport report;
  const _ReportCard({required this.report});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _kSurface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => _ReportDetailScreen(report: report)),
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kLine),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(report.title,
                        style: InsightTheme.urbanist(15, w: FontWeight.w700, c: _kInk)),
                  ),
                  _StatusPill(status: report.status),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                report.summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: InsightTheme.inter(13, c: _kInk2),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (report.module != null) ...[
                    Icon(Icons.apps_rounded, size: 13, color: _kInk2.withValues(alpha: 0.7)),
                    const SizedBox(width: 4),
                    Text(report.module!, style: InsightTheme.inter(12, c: _kInk2.withValues(alpha: 0.8))),
                    const SizedBox(width: 12),
                  ],
                  Icon(Icons.schedule_rounded, size: 13, color: _kInk2.withValues(alpha: 0.7)),
                  const SizedBox(width: 4),
                  Text(_formatDate(report.createdAt), style: InsightTheme.inter(12, c: _kInk2.withValues(alpha: 0.8))),
                  const Spacer(),
                  Text(report.referenceCode,
                      style: InsightTheme.inter(12, w: FontWeight.w600, c: _kBlue)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    late Color color;
    late String label;
    switch (status) {
      case 'in_review':
        color = _kAmber;
        label = 'In Review';
        break;
      case 'resolved':
        color = _kGreen;
        label = 'Resolved';
        break;
      case 'wont_fix':
        color = _kInk2;
        label = 'Won\'t Fix';
        break;
      default:
        color = _kBlue;
        label = 'Submitted';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: InsightTheme.inter(12, w: FontWeight.w700, c: color)),
    );
  }
}

/// Detail view. Wrapped in SensitiveScreen — once the admin has reviewed
/// a report, this can contain technical detail (affected file, recommended
/// action) that shouldn't be casually screenshotted or shared, unlike the
/// summary list.
class _ReportDetailScreen extends StatelessWidget {
  final DiagnosticReport report;
  const _ReportDetailScreen({required this.report});

  @override
  Widget build(BuildContext context) {
    return SensitiveScreen(
      child: Scaffold(
        backgroundColor: _kBg,
        appBar: AppBar(
          backgroundColor: _kBg,
          elevation: 0,
          foregroundColor: _kInk,
          title: Text(report.referenceCode,
              style: InsightTheme.urbanist(15, w: FontWeight.w700, c: _kInk)),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(report.title,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: _kInk)),
                ),
                _StatusPill(status: report.status),
              ],
            ),
            const SizedBox(height: 16),
            _DetailSection(label: 'What you reported', content: report.summary),
            if (report.module != null) ...[
              const SizedBox(height: 16),
              _DetailSection(label: 'Affected area', content: report.module!),
            ],
            const SizedBox(height: 24),
            const Divider(color: _kLine),
            const SizedBox(height: 16),
            if (!report.hasDetail)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _kAmber.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _kAmber.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.hourglass_top_rounded, color: _kAmber, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Not yet reviewed by the MPDO team. You\'ll see more detail here once someone looks into it.',
                        style: InsightTheme.inter(13, c: _kInk2),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              if (report.technicalDescription != null)
                _DetailSection(label: 'Technical description', content: report.technicalDescription!),
              if (report.reproSteps != null) ...[
                const SizedBox(height: 16),
                _DetailSection(label: 'Steps to reproduce', content: report.reproSteps!),
              ],
              if (report.affectedFile != null) ...[
                const SizedBox(height: 16),
                _DetailSection(label: 'Affected file/module', content: report.affectedFile!, mono: true),
              ],
              if (report.recommendedAction != null) ...[
                const SizedBox(height: 16),
                _DetailSection(label: 'Recommended action', content: report.recommendedAction!),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String label;
  final String content;
  final bool mono;
  const _DetailSection({required this.label, required this.content, this.mono = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: InsightTheme.inter(12, w: FontWeight.w700, c: _kInk2, ls: 0.6)),
        const SizedBox(height: 6),
        Text(
          content,
          style: TextStyle(
            fontSize: 14,
            color: _kInk,
            fontFamily: mono ? 'monospace' : null,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

/// Simple submission form — title, short description, optional affected
/// area. Deliberately no field for "technical description" or similar —
/// that's the admin's job to add later, not something an inspector should
/// be asked to guess at.
class _SubmitReportSheet extends StatefulWidget {
  const _SubmitReportSheet();

  @override
  State<_SubmitReportSheet> createState() => _SubmitReportSheetState();
}

class _SubmitReportSheetState extends State<_SubmitReportSheet> {
  final _titleController = TextEditingController();
  final _summaryController = TextEditingController();
  final _moduleController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _summaryController.dispose();
    _moduleController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final summary = _summaryController.text.trim();
    if (title.isEmpty || summary.isEmpty) {
      setState(() => _error = 'Please fill in both the title and description.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await DiagnosticsService.submitReport(
        title: title,
        summary: summary,
        module: _moduleController.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = 'Couldn\'t submit right now. Check your connection and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: _kLine, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text('Report an Issue',
                style: InsightTheme.urbanist(18, w: FontWeight.w800, c: _kInk)),
            const SizedBox(height: 4),
            Text(
              'Describe what happened in your own words — no need to include technical details, the MPDO team will follow up.',
              style: InsightTheme.inter(13, c: _kInk2),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _titleController,
              decoration: _inputDecoration('Title', 'e.g. "App crashes when opening a task"'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _summaryController,
              maxLines: 4,
              decoration: _inputDecoration('What happened?', 'Describe the issue as you experienced it'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _moduleController,
              decoration: _inputDecoration('Affected screen (optional)', 'e.g. "Photo Capture", "Sync"'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: InsightTheme.inter(13, c: _kCoral)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kBlue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _submitting
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text('Submit Report', style: InsightTheme.inter(14, w: FontWeight.w700, c: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, String hint) => InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(color: _kInk2.withValues(alpha: 0.5), fontSize: 13),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _kLine)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _kLine)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _kBlue, width: 1.5)),
      );
}