import 'package:flutter/material.dart';

import '../../../core/models/report_models.dart';
import '../../../core/services/report_submission_service.dart';
import '../../../core/widgets/sensitive_screen.dart';
import '../services/diagnostics_service.dart';
import '../../../core/theme/insight_theme.dart';
import '../widgets/report_form_widgets.dart';

const _kBlue = InsightTheme.blue1;
const _kInk = InsightTheme.ink;
const _kInk2 = InsightTheme.ink2;
const _kLine = InsightTheme.line;
const _kSurface = InsightTheme.surface;
const _kBg = InsightTheme.bg;
const _kAmber = InsightTheme.orange;
const _kCoral = InsightTheme.red;

const _kMonths = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `Oct 4, 2026, 7:03 AM` in the device's local time.
/// Manual, so no formatting dependency is introduced for one stamp.
String formatResponseStamp(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  return '${_kMonths[local.month - 1]} ${local.day}, ${local.year}, '
      '$hour:$minute ${local.hour < 12 ? 'AM' : 'PM'}';
}

/// My Reports — one logical list.
///
/// A confirmed local row and its matching server row are rendered ONCE, keyed
/// on the server's `diagnostic_reports.id`: the server is authoritative for
/// status and reference code, the local row only supplies transport context.
/// Rows the server never confirmed (pending / retry needed / uncertain) are
/// shown separately and are never labelled "Submitted".
class ReportHistoryScreen extends StatefulWidget {
  const ReportHistoryScreen({
    super.key,
    this.loadLocal = ReportQueueService.allRows,
    this.loadRemote = DiagnosticsService.fetchMyReports,
  });

  final Future<List<LocalReportRow>> Function() loadLocal;
  final Future<List<DiagnosticReport>> Function() loadRemote;

  @override
  State<ReportHistoryScreen> createState() => _ReportHistoryScreenState();
}

class _ReportHistoryScreenState extends State<ReportHistoryScreen> {
  List<DiagnosticReport> _remote = const [];
  List<LocalReportRow> _local = const [];
  bool _loadingLocal = true;
  bool _loadingRemote = true;
  String? _error;
  String? _retryError;
  final _retrying = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Local rows are shown FIRST and independently: a slow or failing remote
    // fetch must never hide a report the inspector already saved on this
    // device.
    List<LocalReportRow> local;
    try {
      local = await widget.loadLocal();
    } catch (_) {
      local = const [];
    }
    if (mounted) {
      setState(() {
        _local = local;
        _loadingLocal = false;
        _loadingRemote = true;
        _error = null;
      });
    }

    List<DiagnosticReport> remote;
    try {
      remote = await widget.loadRemote();
    } catch (e) {
      if (mounted) {
        setState(() {
          // A failed request is NOT an empty history, and never renders the
          // "you have not filed any reports" message.
          _error =
              'Could not load the reports filed with the MPDO team. '
              'Pull down to try again. Anything saved on this device is still '
              'listed below.';
          _loadingRemote = false;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _remote = remote;
      _loadingRemote = false;
      _error = null;
    });
  }

  /// The server is authoritative: every confirmed report is rendered once from
  /// the remote row. A local `sent` row whose remote id appears here is folded
  /// into that entry rather than listed a second time — see
  /// [_unconfirmedRows].
  List<DiagnosticReport> get _confirmedReports => _remote;

  /// Local rows the server has not (yet) confirmed.
  List<LocalReportRow> get _unconfirmedRows =>
      DiagnosticsService.unconfirmedLocalRows(_local, _remote);

  Future<void> _retry(LocalReportRow row) async {
    if (!_retrying.add(row.id)) return;
    setState(() => _retryError = null);
    try {
      final uncertain = row.queueState == ReportQueueState.deliveryUnknown;
      if (uncertain) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: _kSurface,
            title: Text(
              'Send this again?',
              style: InsightTheme.urbanist(16, w: FontWeight.w800, c: _kInk),
            ),
            content: Text(
              'The submission outcome is uncertain. The report may already have '
              'reached the server, and the server has no way to recognise a '
              'repeat of the same report. Sending again can create a duplicate.',
              style: InsightTheme.inter(13, c: _kInk2, h: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Send again'),
              ),
            ],
          ),
        );
        if (ok != true) return;
      }
      await ReportQueueService.retryManually(row.id);
      if (mounted) await _load();
    } catch (e, stack) {
      debugPrint('[REPORTS] retry failed: $e');
      debugPrintStack(stackTrace: stack);
      if (mounted) {
        setState(
          () => _retryError =
              'Could not finish this attempt. Check My Reports before trying again.',
        );
      }
    } finally {
      _retrying.remove(row.id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final confirmed = _confirmedReports;
    final unconfirmed = _unconfirmedRows;
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: _kInk,
        title: Text(
          'My Reports',
          style: InsightTheme.urbanist(18, w: FontWeight.w700, c: _kInk),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: _kBlue,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: reportPagePadding(context),
            children: [
              Text(
                'Check delivery and follow-up from the MPDO team.',
                style: InsightTextStyles.bodySecondary(),
              ),
              const SizedBox(height: 24),
              if (_loadingLocal)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _kCoral.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _kCoral.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.cloud_off_rounded,
                        size: 18,
                        color: _kCoral,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _error!,
                          style: InsightTheme.inter(13, c: _kInk2, h: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _load,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (_retryError != null) ...[
                ReportNotice(_retryError!, error: true),
                const SizedBox(height: 16),
              ],
              // Local rows appear as soon as they are read, regardless of the
              // remote fetch.
              if (!_loadingLocal && unconfirmed.isNotEmpty) ...[
                Text(
                  'NOT YET CONFIRMED BY THE SERVER',
                  style: InsightTheme.inter(
                    11,
                    w: FontWeight.w700,
                    c: _kInk2,
                    ls: 0.6,
                  ),
                ),
                const SizedBox(height: 10),
                for (final row in unconfirmed) ...[
                  _LocalRowCard(
                    key: ValueKey(row.id),
                    row: row,
                    onRetry: _retrying.contains(row.id)
                        ? null
                        : () => _retry(row),
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 14),
              ],
              const SizedBox(height: 4),
              Text(
                'FILED WITH THE MPDO TEAM',
                style: InsightTheme.inter(
                  11,
                  w: FontWeight.w700,
                  c: _kInk2,
                  ls: 0.6,
                ),
              ),
              const SizedBox(height: 10),
              if (_loadingRemote)
                Semantics(
                  liveRegion: true,
                  label: 'Loading reports',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Loading reports…',
                            style: InsightTextStyles.bodySecondary(),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_error != null)
                // Deliberately no "you have not filed any reports yet" here: a
                // failed request must never look like an empty history.
                const SizedBox.shrink()
              else if (confirmed.isEmpty)
                Text(
                  'You have not filed any reports yet.',
                  style: InsightTheme.inter(13, c: _kInk2),
                )
              else
                for (final report in confirmed) ...[
                  _RemoteCard(key: ValueKey(report.id), report: report),
                  const SizedBox(height: 10),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LocalRowCard extends StatelessWidget {
  const _LocalRowCard({super.key, required this.row, required this.onRetry});
  final LocalReportRow row;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    // Label and detail text both come from ReportQueueService so this screen
    // and the Reports & Support home can never drift apart on wording.
    final label = ReportQueueService.labelFor(row);
    final color = switch (row.queueState) {
      ReportQueueState.pending ||
      ReportQueueState.sending => InsightTheme.amberInk,
      ReportQueueState.failedRetryable ||
      ReportQueueState.deliveryUnknown => InsightTheme.redInk,
      ReportQueueState.sent => InsightTheme.greenInk,
    };
    final detail = switch (row.queueState) {
      ReportQueueState.pending =>
        'Saved here. It will be submitted when you are back online.',
      ReportQueueState.sending => 'In progress.',
      ReportQueueState.failedRetryable =>
        ReportQueueService.isNonRetryable(row)
            ? 'Your report is saved here, but could not be filed. Contact the MPDO team for help.'
            : 'Your report is saved here. FieldSync can try again when a connection is available.',
      ReportQueueState.deliveryUnknown =>
        'The report may already have reached the server. Check the filed list '
            'below before retrying.',
      ReportQueueState.sent => '',
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.circle, size: 9, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: InsightTheme.inter(12, w: FontWeight.w700, c: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            row.reportType == ReportType.technicalIssue
                ? 'Technical Issue'
                : 'Application Support',
            style: InsightTextStyles.caption(),
          ),
          const SizedBox(height: 4),
          Text(
            row.payload['title'] as String? ?? 'Report',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: InsightTheme.inter(15, w: FontWeight.w700, c: _kInk),
          ),
          const SizedBox(height: 4),
          Text(
            row.payload['summary'] as String? ?? '',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: InsightTheme.inter(13, c: _kInk2, h: 1.35),
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(detail, style: InsightTheme.inter(12, c: _kInk2, h: 1.35)),
          ],
          if (row.queueState == ReportQueueState.deliveryUnknown ||
              (row.queueState == ReportQueueState.failedRetryable &&
                  !ReportQueueService.isNonRetryable(row))) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try sending again'),
                style: TextButton.styleFrom(
                  foregroundColor: _kBlue,
                  minimumSize: const Size(48, 48),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RemoteCard extends StatelessWidget {
  const _RemoteCard({super.key, required this.report});
  final DiagnosticReport report;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: Material(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ReportDetailScreen(report: report),
            ),
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kLine),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      report.referenceCode.isEmpty
                          ? 'Report'
                          : report.referenceCode,
                      style: InsightTheme.inter(
                        12,
                        w: FontWeight.w700,
                        c: _kInk2,
                      ),
                    ),
                    _StatusPill(status: report.status),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  report.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: InsightTheme.inter(15, w: FontWeight.w700, c: _kInk),
                ),
                const SizedBox(height: 4),
                Text(
                  report.summary,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: InsightTheme.inter(13, c: _kInk2, h: 1.35),
                ),
                const SizedBox(height: 8),
                Text(
                  report.typeLabel,
                  style: InsightTheme.inter(11, c: _kInk2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Read-only. No post-submission editing is invented here.
class ReportDetailScreen extends StatelessWidget {
  const ReportDetailScreen({super.key, required this.report});
  final DiagnosticReport report;

  @override
  Widget build(BuildContext context) {
    // Screenshot-protected: once a report carries admin review content it must
    // not be casually shared. FLAG_SECURE is not weakened anywhere.
    return SensitiveScreen(
      child: Scaffold(
        backgroundColor: _kBg,
        appBar: AppBar(
          backgroundColor: _kBg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          foregroundColor: _kInk,
          title: Text(
            report.referenceCode.isEmpty ? 'Report' : report.referenceCode,
            style: InsightTheme.urbanist(15, w: FontWeight.w700, c: _kInk),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: reportPagePadding(context),
            children: [
              Text(
                report.title,
                style: InsightTheme.urbanist(22, w: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: _StatusPill(status: report.status),
              ),
              const SizedBox(height: 6),
              Text(report.typeLabel, style: InsightTheme.inter(12, c: _kInk2)),
              const SizedBox(height: 18),
              _DetailSection(
                label: 'What you reported',
                content: report.summary,
              ),
              if (report.isApplicationSupport) ...[
                if (report.supportCategory != null) ...[
                  const SizedBox(height: 16),
                  _DetailSection(
                    label: 'Category',
                    content:
                        SupportCategories.labels[report.supportCategory] ??
                        report.supportCategory!,
                  ),
                ],
                if (report.affectedField != null) ...[
                  const SizedBox(height: 16),
                  _DetailSection(
                    label: 'Affected information',
                    content: report.affectedField!,
                  ),
                ],
                if (report.requestedChange != null) ...[
                  const SizedBox(height: 16),
                  _DetailSection(
                    label: 'Requested change',
                    content: report.requestedChange!,
                  ),
                ],
              ] else if (report.module != null) ...[
                const SizedBox(height: 16),
                _DetailSection(
                  label: 'Affected screen',
                  content: report.module!,
                ),
              ],
              if (report.expectedBehavior != null) ...[
                const SizedBox(height: 16),
                _DetailSection(
                  label: 'What you expected',
                  content: report.expectedBehavior!,
                ),
              ],
              if (report.reproSteps != null) ...[
                const SizedBox(height: 16),
                _DetailSection(
                  label: 'Steps to reproduce',
                  content: report.reproSteps!,
                ),
              ],
              if (report.blocksFieldWork != null) ...[
                const SizedBox(height: 16),
                _DetailSection(
                  label: 'Blocked your field work?',
                  content: report.blocksFieldWork! ? 'Yes' : 'No',
                ),
              ],
              const SizedBox(height: 24),
              const Divider(color: _kLine),
              const SizedBox(height: 16),
              // THE OFFICIAL MPDO RESPONSE. Keyed on the response being present,
              // never on the status, so a response can never be fabricated for
              // an unanswered report. Plain Text only — no HTML, no Markdown.
              if (report.hasOfficialResponse) ...[
                _DetailSection(
                  label: 'MPDO Response',
                  content: report.responseMessage!,
                ),
                if (report.respondedByName != null) ...[
                  const SizedBox(height: 16),
                  _DetailSection(
                    label: 'Responded by',
                    content: report.respondedByName!,
                  ),
                ],
                if (report.respondedAt != null) ...[
                  const SizedBox(height: 16),
                  _DetailSection(
                    label: 'Responded at',
                    content: formatResponseStamp(report.respondedAt!),
                  ),
                ],
                const SizedBox(height: 24),
                const Divider(color: _kLine),
                const SizedBox(height: 16),
              ],
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
                      const Icon(
                        Icons.hourglass_top_rounded,
                        color: _kAmber,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Not yet reviewed by the MPDO team. You\'ll see more detail here once someone looks into it.',
                          style: InsightTheme.inter(13, c: _kInk2, h: 1.35),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                if (report.technicalDescription != null) ...[
                  _DetailSection(
                    label: 'Technical description',
                    content: report.technicalDescription!,
                  ),
                  const SizedBox(height: 16),
                ],
                if (report.affectedFile != null) ...[
                  _DetailSection(
                    label: 'Affected file/module',
                    content: report.affectedFile!,
                    mono: true,
                  ),
                  const SizedBox(height: 16),
                ],
                if (report.recommendedAction != null)
                  _DetailSection(
                    label: 'Recommended action',
                    content: report.recommendedAction!,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.label,
    required this.content,
    this.mono = false,
  });
  final String label;
  final String content;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: InsightTheme.inter(12, w: FontWeight.w700, c: _kInk2, ls: 0.6),
        ),
        const SizedBox(height: 6),
        Text(
          content,
          style: mono
              ? InsightTheme.mono(14)
              : InsightTextStyles.bodySecondary(color: _kInk),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'resolved' => InsightTheme.greenInk,
      'in_review' => InsightTheme.amberInk,
      'wont_fix' => InsightTheme.redInk,
      _ => InsightTheme.blueInk,
    };
    final label = switch (status) {
      'in_review' => 'In review',
      'wont_fix' => 'Not planned',
      'submitted' => 'Submitted',
      'resolved' => 'Resolved',
      _ => 'Filed',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: InsightTheme.inter(11, w: FontWeight.w700, c: color),
      ),
    );
  }
}
