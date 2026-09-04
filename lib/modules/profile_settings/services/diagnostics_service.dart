import 'package:flutter/foundation.dart';
import '../../../core/services/supabase_service.dart';

/// A single diagnostic/error report, as an inspector or the summary list
/// sees it. Detail fields are null until the admin team fills them in
/// directly in Supabase — see supabase/migrations/phase_3c_diagnostic_reports.sql.
class DiagnosticReport {
  final String id;
  final String referenceCode;
  final String title;
  final String summary;
  final String? module;
  final String status; // submitted | in_review | resolved | wont_fix
  final String? technicalDescription;
  final String? reproSteps;
  final String? affectedFile;
  final String? recommendedAction;
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
    this.module,
    this.technicalDescription,
    this.reproSteps,
    this.affectedFile,
    this.recommendedAction,
  });

  /// True if the admin has added any technical detail yet. Drives whether
  /// the detail screen shows "Not yet reviewed" or the real content.
  bool get hasDetail =>
      technicalDescription != null ||
      reproSteps != null ||
      affectedFile != null ||
      recommendedAction != null;

  factory DiagnosticReport.fromMap(Map<String, dynamic> map) {
    return DiagnosticReport(
      id: map['id'] as String,
      referenceCode: map['reference_code'] as String,
      title: map['title'] as String,
      summary: map['summary'] as String,
      module: map['module'] as String?,
      status: map['status'] as String? ?? 'submitted',
      technicalDescription: map['technical_description'] as String?,
      reproSteps: map['repro_steps'] as String?,
      affectedFile: map['affected_file'] as String?,
      recommendedAction: map['recommended_action'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}

class DiagnosticsService {
  DiagnosticsService._();

  static final _client = SupabaseService.client;

  /// Fetches only the current inspector's own reports (RLS enforces this
  /// server-side too — this isn't the only thing protecting it), newest
  /// first.
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

  /// Submits a new report. Only the inspector-provided summary fields are
  /// writable from the app — status defaults to 'submitted' and the
  /// detail fields start null server-side (the table default), regardless
  /// of anything sent here, since the insert policy only checks
  /// inspector_id and the app never sends those columns.
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
            if (module != null && module.trim().isNotEmpty) 'module': module.trim(),
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