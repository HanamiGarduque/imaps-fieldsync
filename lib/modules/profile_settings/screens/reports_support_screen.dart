import 'package:flutter/material.dart';

import '../../../core/models/report_models.dart';
import '../../../core/services/report_submission_service.dart';
import '../../../core/theme/insight_theme.dart';
import '../widgets/report_form_widgets.dart';
import 'report_history_screen.dart';
import 'technical_issue_screen.dart';
import 'application_support_screen.dart';

// Mapped to standard canonical InsightTheme design tokens
const _kBlue = InsightTheme.blue1;
const _kInk = InsightTheme.ink;
const _kInk2 = InsightTheme.ink2;
const _kLine = InsightTheme.line;
const _kSurface = InsightTheme.surface;
const _kBg = InsightTheme.bg;
const _kGreen = InsightTheme.green;
const _kCoral = InsightTheme.red;

/// Reports & Support — the inspector's entry point.
///
/// Two clearly separated concerns, because they route to different people:
///   * Technical Issue     — something is wrong with FieldSync itself.
///   * Application Support — something about ONE of your assigned
///                           tasks/applications needs clarification or a
///                           correction.
/// Plus "My Reports", which merges the server's record of what was filed with
/// this device's own unsent queue so nothing is hidden and nothing is
/// double-counted.
///
/// Security: this summary screen stays screenshot-safe (it shows no secrets,
/// tokens or auth data). The report DETAIL screen is wrapped in
/// SensitiveScreen, consistent with the pre-existing Diagnostics behaviour.
class ReportsSupportScreen extends StatefulWidget {
  const ReportsSupportScreen({
    super.key,
    // Scoped to the authenticated inspector, never the whole device. This is
    // the user-facing "not yet sent" summary, so it must not be able to surface
    // another inspector account's queued report text on a shared device.
    this.loadLocal = ReportQueueService.myRows,
  });

  final Future<List<LocalReportRow>> Function() loadLocal;

  @override
  State<ReportsSupportScreen> createState() => _ReportsSupportScreenState();
}

class _ReportsSupportScreenState extends State<ReportsSupportScreen> {
  List<LocalReportRow> _unsent = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUnsent();
  }

  Future<void> _loadUnsent() async {
    List<LocalReportRow> rows;
    try {
      rows = await widget.loadLocal();
      _error = null;
    } catch (e) {
      debugPrint('[REPORTS] local summary failed: $e');
      _error =
          'Could not read reports saved on this device. Pull down to try again.';
      rows = const [];
    }
    if (!mounted) return;
    setState(() {
      _unsent = rows;
      _loading = false;
    });
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (mounted) await _loadUnsent();
  }

  @override
  Widget build(BuildContext context) {
    final unsent = _unsent
        .where((r) => r.queueState != ReportQueueState.sent)
        .toList(growable: false);

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: _kInk,
        title: Text(
          'Reports & Support',
          style: InsightTheme.urbanist(18, w: FontWeight.w700, c: _kInk),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadUnsent,
          color: _kBlue,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: reportPagePadding(context),
            children: [
              Text(
                'Tell us what needs attention. Reports go to the MPDO team through iMAPS.',
                style: InsightTextStyles.bodySecondary(),
              ),
              const SizedBox(height: 24),
              Text(
                'FILE A REPORT',
                style: InsightTextStyles.sectionHeaderPill(),
              ),
              const SizedBox(height: 12),
              _ActionCard(
                icon: Icons.bug_report_outlined,
                title: 'Technical Issue',
                subtitle:
                    'A problem with FieldSync — a screen, button, sync, GPS or map. No task needed.',
                tint: _kCoral,
                onTap: () => _open(const TechnicalIssueScreen()),
              ),
              const SizedBox(height: 12),
              _ActionCard(
                icon: Icons.assignment_outlined,
                title: 'Application Support',
                subtitle:
                    'Something about one of your assigned tasks or applications needs clarifying or correcting.',
                tint: _kBlue,
                onTap: () => _open(const ApplicationSupportScreen()),
              ),
              const SizedBox(height: 24),
              Text(
                'HISTORY & STATUS',
                style: InsightTextStyles.sectionHeaderPill(),
              ),
              const SizedBox(height: 12),
              _ActionCard(
                icon: Icons.receipt_long_outlined,
                title: 'My Reports',
                subtitle:
                    'Everything you have filed, and anything still waiting on this device.',
                tint: _kGreen,
                onTap: () => _open(const ReportHistoryScreen()),
              ),
              const SizedBox(height: 24),
              if (_loading) const Text('Loading device reports…'),
              if (_error != null) ReportNotice(_error!, error: true),
              if (!_loading && unsent.isNotEmpty) ...[
                Text(
                  'ON THIS DEVICE',
                  style: InsightTheme.inter(
                    11,
                    w: FontWeight.w700,
                    c: _kInk2,
                    ls: 0.6,
                  ),
                ),
                const SizedBox(height: 10),
                for (final row in unsent) ...[
                  _UnsentChip(key: ValueKey(row.id), row: row),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 6),
              ],
              const SizedBox(height: 12),
              Text(
                'FieldSync never contacts a Planning Officer directly. Routing and follow-up happen in iMAPS.',
                style: InsightTheme.inter(12, c: _kInk2, h: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tint,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: Material(
        color: _kSurface,
        borderRadius: InsightTheme.roundedMd,
        child: InkWell(
          onTap: onTap,
          borderRadius: InsightTheme.roundedMd,
          child: Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: InsightTheme.roundedMd,
              border: Border.all(color: _kLine),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: tint, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: InsightTheme.urbanist(18, w: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: InsightTheme.inter(13, c: _kInk2, h: 1.35),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: _kInk2,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact, honest transport state. Deliberately never says "Submitted" for
/// a report the server has not confirmed.
class _UnsentChip extends StatelessWidget {
  const _UnsentChip({super.key, required this.row});
  final LocalReportRow row;

  @override
  Widget build(BuildContext context) {
    final color = switch (row.queueState) {
      ReportQueueState.pending ||
      ReportQueueState.sending => InsightTheme.amberInk,
      ReportQueueState.failedRetryable ||
      ReportQueueState.deliveryUnknown => InsightTheme.redInk,
      ReportQueueState.sent => InsightTheme.greenInk,
    };
    // Shared with the history screen so the wording can never drift.
    final label = ReportQueueService.labelFor(row);
    final title = row.payload['title'] as String? ?? row.reportType.dbValue;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, size: 9, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: InsightTheme.inter(12, w: FontWeight.w700, c: color),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: InsightTheme.inter(12, c: _kInk2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
