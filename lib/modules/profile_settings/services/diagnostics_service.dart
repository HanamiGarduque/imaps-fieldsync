import 'package:flutter/foundation.dart';

import '../../../core/models/report_models.dart';
import '../../../core/services/supabase_service.dart';

/// A single report, as the inspector's own summary list sees it.
///
/// Read-only. Admin review fields (`technicalDescription`, `affectedFile`,
/// `recommendedAction`) are written by the iMAPS Admin/support team, never by
/// this app.
class DiagnosticReport {
  final String id;
  final String referenceCode;
  final String title;
  final String summary;
  final String? module;
  final String status; // submitted | in_review | resolved | wont_fix
  final ReportType reportType;
  final String? fieldJobId;
  final String? supabaseApplicationId;
  final String? bridgeSourceId;
  final String? supportCategory;
  final String? affectedField;
  final String? requestedChange;
  final String? expectedBehavior;
  final bool? blocksFieldWork;
  final String? technicalDescription;
  final String? reproSteps;
  final String? affectedFile;
  final String? recommendedAction;
  /// The official MPDO response, written by iMAPS. Read-only here: this app is
  /// never the author. Null for submitted, in_review and every legacy row.
  final String? responseMessage;
  /// Display attribution for [responseMessage] — the ONLY responder identity
  /// this app shows. Local `performed_by` ids, audit ids and handshake values
  /// never exist in this payload and must never be introduced.
  final String? respondedByName;
  final DateTime? respondedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DiagnosticReport({
    required this.id,
    required this.referenceCode,
    required this.title,
    required this.summary,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.reportType = ReportType.technicalIssue,
    this.module,
    this.fieldJobId,
    this.supabaseApplicationId,
    this.bridgeSourceId,
    this.supportCategory,
    this.affectedField,
    this.requestedChange,
    this.expectedBehavior,
    this.blocksFieldWork,
    this.technicalDescription,
    this.reproSteps,
    this.affectedFile,
    this.recommendedAction,
    this.responseMessage,
    this.respondedByName,
    this.respondedAt,
  });

  bool get isApplicationSupport => reportType == ReportType.applicationSupport;

  String get typeLabel =>
      isApplicationSupport ? 'Application Support' : 'Technical Issue';

  /// True only when the MPDO has actually answered.
  ///
  /// Keyed on the RESPONSE, never on the status: `resolved` / `wont_fix` are
  /// the statuses the server pairs with a response, but a status alone is not
  /// evidence that one was written. Whitespace-only text is not a response
  /// either, because the server's own CHECK rejects it.
  bool get hasOfficialResponse => responseMessage != null && responseMessage!.trim().isNotEmpty;

  /// True only if the MPDO/support team has added detail of any kind.
  ///
  /// `repro_steps` is deliberately EXCLUDED: inspectors author their own
  /// repro steps when filing, so its presence proves nothing about admin
  /// review and previously made an unreviewed report look reviewed.
  ///
  /// The official inspector-facing response IS such a signal. Before this, a
  /// report the MPDO had already answered still rendered the "Not yet
  /// reviewed by the MPDO team" placeholder, because Application Support
  /// responses never populate the legacy technical-review fields.
  bool get hasDetail =>
      technicalDescription != null ||
      affectedFile != null ||
      recommendedAction != null ||
      hasOfficialResponse;

  /// Tolerant stamp parse: a missing key, an explicit null, an empty string
  /// and an unparseable value all yield null instead of throwing. Never
  /// inferred from the status — a client must not fabricate a responder time.
  static DateTime? _parseStamp(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return DateTime.tryParse(value);
  }

  factory DiagnosticReport.fromMap(Map<String, dynamic> map) {
    return DiagnosticReport(
      id: map['id'] as String,
      referenceCode: map['reference_code'] as String? ?? '',
      title: map['title'] as String,
      summary: map['summary'] as String,
      module: map['module'] as String?,
      status: map['status'] as String? ?? 'submitted',
      reportType: ReportType.fromDb(
        map['report_type'] as String? ?? 'technical_issue',
      ),
      fieldJobId: map['field_job_id'] as String?,
      supabaseApplicationId: map['supabase_application_id'] as String?,
      bridgeSourceId: map['bridge_source_id'] as String?,
      supportCategory: map['support_category'] as String?,
      affectedField: map['affected_field'] as String?,
      requestedChange: map['requested_change'] as String?,
      expectedBehavior: map['expected_behavior'] as String?,
      blocksFieldWork: map['blocks_field_work'] as bool?,
      technicalDescription: map['technical_description'] as String?,
      reproSteps: map['repro_steps'] as String?,
      affectedFile: map['affected_file'] as String?,
      recommendedAction: map['recommended_action'] as String?,
      responseMessage: map['response_message'] as String?,
      respondedByName: map['responded_by_name'] as String?,
      respondedAt: _parseStamp(map['responded_at']),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}

class DiagnosticsService {
  DiagnosticsService._();

  static final _client = SupabaseService.client;

  /// The current inspector's own reports only. RLS enforces this server-side
  /// as well — this isn't the only thing protecting it.
  static Future<List<DiagnosticReport>> fetchMyReports() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return [];
    try {
      final rows = await _client
          .from('diagnostic_reports')
          .select()
          .eq('inspector_id', uid)
          .order('created_at', ascending: false);
      return (rows as List)
          .map((r) => DiagnosticReport.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[DIAGNOSTICS] fetchMyReports error: $e');
      rethrow;
    }
  }

  /// The local rows that must still be listed on their own.
  ///
  /// A `sent` local row whose remote id appears in [remote] is the SAME report
  /// as that server row, so it is folded away and the server's version (with
  /// its status and reference code) is rendered once. Anything the server has
  /// not confirmed stays visible independently — and is never labelled
  /// "Submitted".
  static List<LocalReportRow> unconfirmedLocalRows(
    List<LocalReportRow> local,
    List<DiagnosticReport> remote,
  ) => local
      .where(
        (l) =>
            l.queueState != ReportQueueState.sent ||
            !remote.any((r) => r.id == l.remoteReportId),
      )
      .toList(growable: false);

  /// Legacy direct submit, retained for the pre-queue Technical Issue path.
  /// New work goes through ReportQueueService so text survives offline.
  static Future<DiagnosticReport> submitReport({
    required String title,
    required String summary,
    String? module,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      throw StateError('Cannot submit a report while signed out.');
    }
    try {
      final row = await _client
          .from('diagnostic_reports')
          .insert({
            'inspector_id': uid,
            'title': title.trim(),
            'summary': summary.trim(),
            'report_type': 'technical_issue',
            if (module != null && module.trim().isNotEmpty)
              'module': module.trim(),
          })
          .select()
          .single();
      await SupabaseService.logActivity(
        eventType: 'diagnostic_report_submitted',
        title: 'Diagnostic report submitted',
        subtitle: title.trim(),
      );
      return DiagnosticReport.fromMap(row);
    } catch (e) {
      debugPrint('[DIAGNOSTICS] submitReport error: $e');
      rethrow;
    }
  }
}
