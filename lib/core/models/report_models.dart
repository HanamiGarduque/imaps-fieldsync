import 'dart:convert';

// Reports & Support — inspector-authored report models.
//
// The locked contract (Supabase `diagnostic_reports`) splits reports into TWO
// types that must never be conflated:
//
//   * technical_issue      — a problem with FieldSync itself. NO job,
//                            NO application, NO bridge source, NO category.
//   * application_support  — a concern about one exact assigned/cached task.
//                            MUST carry the exact field_job_id,
//                            supabase_application_id and bridge_source_id.
//
// Local queue states are LOCAL transport state only. They are never the remote
// `diagnostic_reports.status`, which for a new report is always 'submitted'.

enum ReportType {
  technicalIssue('technical_issue'),
  applicationSupport('application_support');

  const ReportType(this.dbValue);
  final String dbValue;

  static ReportType fromDb(String value) => switch (value) {
    'technical_issue' => ReportType.technicalIssue,
    'application_support' => ReportType.applicationSupport,
    _ => throw ArgumentError('Unknown report_type: $value'),
  };
}

enum ReportQueueState {
  pending('pending'),
  sending('sending'),
  sent('sent'),
  failedRetryable('failed_retryable'),
  deliveryUnknown('delivery_unknown');

  const ReportQueueState(this.dbValue);
  final String dbValue;

  static ReportQueueState fromDb(String value) => switch (value) {
    'pending' => ReportQueueState.pending,
    'sending' => ReportQueueState.sending,
    'sent' => ReportQueueState.sent,
    'failed_retryable' => ReportQueueState.failedRetryable,
    'delivery_unknown' => ReportQueueState.deliveryUnknown,
    _ => throw ArgumentError('Unknown queue_state: $value'),
  };
}

/// Existing persisted module vocabulary. The selector and queue share this
/// allow-list; display text cannot introduce new stored values.
const List<String> kTechnicalIssueModules = <String>[
  'Home',
  'My Tasks',
  'Inspection',
  'Checklist',
  'Photos',
  'Site Map',
  'GPS Verification',
  'Sync Center',
  'Analytics Dashboard',
  'Profile',
  'Sign-In & Security',
  'Other',
];

/// Client resource budgets, not SQLite/Supabase schema limits. SQLite stores
/// the JSON as TEXT. Bounding title/narrative/optional text to 200/8,000/4,000
/// UTF-16 units keeps a new report below ~100 KB even with JSON escaping.
/// The larger editing buffer allows correction without truncating a draft;
/// pathological pastes are refused before Flutter lays them out.
class ReportInput {
  static const titleLimit = 200;
  static const descriptionLimit = 8000;
  static const optionalLimit = 4000;
  static const editingLimit = 32768;
  static const tooLong = 'This entry is too long. Please shorten it.';

  static String? textError(
    String? value, {
    required int limit,
    String? requiredMessage,
  }) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return requiredMessage;
    if (text.length > limit) return tooLong;
    // PostgreSQL text cannot contain NUL; invalid UTF-16 must not be silently
    // replaced during JSON/UTF-8 encoding. Ordinary Unicode is left verbatim.
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit == 0 || (unit >= 0xDC00 && unit <= 0xDFFF)) {
        return 'This entry contains an unsupported character. Please remove it.';
      }
      if (unit >= 0xD800 && unit <= 0xDBFF) {
        if (++i >= text.length ||
            text.codeUnitAt(i) < 0xDC00 ||
            text.codeUnitAt(i) > 0xDFFF) {
          return 'This entry contains an unsupported character. Please remove it.';
        }
      }
    }
    return null;
  }

  static String? titleError(String? value) => textError(
    value,
    limit: titleLimit,
    requiredMessage: 'Give your report a short title.',
  );
  static String? summaryError(String? value) => textError(
    value,
    limit: descriptionLimit,
    requiredMessage: 'Describe what happened.',
  );
  static String? descriptionError(String? value) => textError(
    value,
    limit: descriptionLimit,
    requiredMessage: 'Describe the concern.',
  );
  static String? optionalError(String? value) =>
      textError(value, limit: optionalLimit);
  static String? moduleError(String? value) =>
      kTechnicalIssueModules.contains(value)
      ? null
      : 'Choose the screen or module where this happened.';
  static String? categoryError(String? value) =>
      SupportCategories.isValid(value) ? null : 'Choose a support category.';
}

/// Inspector-authored fields for a Technical Issue. No application/task or
/// Planning Officer linkage is collected here by design.
class TechnicalIssueDraft {
  const TechnicalIssueDraft({
    required this.title,
    required this.module,
    required this.summary,
    this.expectedBehavior,
    this.reproSteps,
    this.blocksFieldWork,
    this.occurredAt,
    this.connectivityState,
    this.appVersion,
    this.osVersion,
  });

  final String title;
  final String module;
  final String summary;
  final String? expectedBehavior;
  final String? reproSteps;
  final bool? blocksFieldWork;
  final DateTime? occurredAt;
  final String? connectivityState;
  final String? appVersion;
  final String? osVersion;

  String? get validationError =>
      ReportInput.titleError(title) ??
      ReportInput.moduleError(module) ??
      ReportInput.summaryError(summary) ??
      ReportInput.optionalError(expectedBehavior) ??
      ReportInput.optionalError(reproSteps);

  Map<String, dynamic> toJson() => {
    'report_type': 'technical_issue',
    'title': title.trim(),
    'module': module.trim(),
    'summary': summary.trim(),
    if (expectedBehavior != null && expectedBehavior!.trim().isNotEmpty)
      'expected_behavior': expectedBehavior!.trim(),
    if (reproSteps != null && reproSteps!.trim().isNotEmpty)
      'repro_steps': reproSteps!.trim(),
    if (blocksFieldWork != null) 'blocks_field_work': blocksFieldWork,
    if (occurredAt != null)
      'occurred_at': occurredAt!.toUtc().toIso8601String(),
    if (connectivityState != null && connectivityState!.isNotEmpty)
      'connectivity_state': connectivityState,
    if (appVersion != null && appVersion!.isNotEmpty) 'app_version': appVersion,
    if (osVersion != null && osVersion!.isNotEmpty) 'os_version': osVersion,
  };

  static TechnicalIssueDraft fromJson(Map<String, dynamic> json) =>
      TechnicalIssueDraft(
        title: json['title'] as String? ?? '',
        module: json['module'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
        expectedBehavior: json['expected_behavior'] as String?,
        reproSteps: json['repro_steps'] as String?,
        blocksFieldWork: json['blocks_field_work'] as bool?,
        occurredAt: json['occurred_at'] == null
            ? null
            : DateTime.parse(json['occurred_at'] as String),
        connectivityState: json['connectivity_state'] as String?,
        appVersion: json['app_version'] as String?,
        osVersion: json['os_version'] as String?,
      );
}

/// The six locked Application Support categories (value -> label).
class SupportCategories {
  static const Map<String, String> labels = {
    'incorrect_information': 'Incorrect Information',
    'missing_information': 'Missing Information',
    'additional_site_information': 'Additional Site Information',
    'clarification_request': 'Clarification Needed',
    'correction_request': 'Correction Request',
    'other': 'Other',
  };

  static bool isValid(String? value) =>
      value != null && labels.containsKey(value);
}

/// Inspector-authored fields for Application Support, bound to the exact
/// selected job. All three identity members must be present and come from the
/// selected cached job verbatim — never inferred.
class ApplicationSupportDraft {
  const ApplicationSupportDraft({
    required this.fieldJobId,
    required this.supabaseApplicationId,
    required this.bridgeSourceId,
    required this.supportCategory,
    required this.description,
    this.affectedField,
    this.requestedChange,
    this.blocksFieldWork,
  });

  final String fieldJobId;
  final String supabaseApplicationId;
  final String bridgeSourceId;
  final String supportCategory;
  final String description;
  final String? affectedField;
  final String? requestedChange;
  final bool? blocksFieldWork;

  bool get hasExactIdentity =>
      fieldJobId.trim().isNotEmpty &&
      supabaseApplicationId.trim().isNotEmpty &&
      bridgeSourceId.trim().isNotEmpty;

  String? get validationError => !hasExactIdentity
      ? 'Refresh this task online before reporting an application concern.'
      : ReportInput.categoryError(supportCategory) ??
            ReportInput.descriptionError(description) ??
            ReportInput.optionalError(affectedField) ??
            ReportInput.optionalError(requestedChange);

  Map<String, dynamic> toJson() => {
    'report_type': 'application_support',
    // diagnostic_reports.title is NOT NULL server-side, but the inspector
    // is never asked to invent a title for an application concern. The
    // category label is an accurate, deterministic title for exactly what
    // was filed; `summary` carries the inspector's own words.
    'title': SupportCategories.labels[supportCategory] ?? 'Application Support',
    'field_job_id': fieldJobId,
    'supabase_application_id': supabaseApplicationId,
    'bridge_source_id': bridgeSourceId,
    'support_category': supportCategory,
    'summary': description.trim(),
    if (affectedField != null && affectedField!.trim().isNotEmpty)
      'affected_field': affectedField!.trim(),
    if (requestedChange != null && requestedChange!.trim().isNotEmpty)
      'requested_change': requestedChange!.trim(),
    if (blocksFieldWork != null) 'blocks_field_work': blocksFieldWork,
  };

  static ApplicationSupportDraft fromJson(Map<String, dynamic> json) =>
      ApplicationSupportDraft(
        fieldJobId: json['field_job_id'] as String? ?? '',
        supabaseApplicationId: json['supabase_application_id'] as String? ?? '',
        bridgeSourceId: json['bridge_source_id'] as String? ?? '',
        supportCategory: json['support_category'] as String? ?? '',
        description: json['summary'] as String? ?? '',
        affectedField: json['affected_field'] as String?,
        requestedChange: json['requested_change'] as String?,
        blocksFieldWork: json['blocks_field_work'] as bool?,
      );
}

/// One persisted row in local_report_queue.
class LocalReportRow {
  const LocalReportRow({
    required this.id,
    required this.reportType,
    required this.payload,
    required this.queueState,
    required this.retryCount,
    required this.createdAt,
    required this.updatedAt,
    this.localJobId,
    this.fieldJobId,
    this.supabaseApplicationId,
    this.bridgeSourceId,
    this.remoteReportId,
    this.referenceCode,
    this.lastError,
    this.lastAttemptAt,
    this.inspectorId,
  });

  final String id;
  final ReportType reportType;
  final Map<String, dynamic> payload;
  final ReportQueueState queueState;
  final int retryCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? localJobId;
  final String? fieldJobId;
  final String? supabaseApplicationId;
  final String? bridgeSourceId;
  final String? remoteReportId;
  final String? referenceCode;
  final String? lastError;
  final DateTime? lastAttemptAt;

  /// The authenticated Supabase user id that created this report.
  ///
  /// Authoritative ownership, taken verbatim from
  /// `SupabaseService.client.auth.currentUser.id` at enqueue time — never
  /// derived from a display name, email, job or message. It is also the ONLY
  /// value that may become the remote `inspector_id` (see
  /// `ReportQueueService`'s send guard), so queued ownership, the
  /// authenticated submitter and the remote author are always the same person.
  ///
  /// `null` means a pre-v16 legacy row: physically stored, attributed to
  /// nobody, and therefore visible to nobody and retryable by nobody. Its
  /// owner is unknowable from what was stored, and this contract forbids
  /// inferring one.
  final String? inspectorId;

  factory LocalReportRow.fromMap(Map<String, dynamic> map) => LocalReportRow(
    id: map['id'] as String,
    reportType: ReportType.fromDb(map['report_type'] as String),
    payload: jsonDecodeMap(map['payload'] as String),
    queueState: ReportQueueState.fromDb(map['queue_state'] as String),
    retryCount: map['retry_count'] as int,
    createdAt: DateTime.parse(map['created_at'] as String),
    updatedAt: DateTime.parse(map['updated_at'] as String),
    localJobId: map['local_job_id'] as String?,
    fieldJobId: map['field_job_id'] as String?,
    supabaseApplicationId: map['supabase_application_id'] as String?,
    bridgeSourceId: map['bridge_source_id'] as String?,
    remoteReportId: map['remote_report_id'] as String?,
    referenceCode: map['reference_code'] as String?,
    lastError: map['last_error'] as String?,
    lastAttemptAt: map['last_attempt_at'] == null
        ? null
        : DateTime.parse(map['last_attempt_at'] as String),
    inspectorId: map['inspector_id'] as String?,
  );

  Map<String, dynamic> toRow() => {
    'id': id,
    'report_type': reportType.dbValue,
    'payload': jsonEncodeMap(payload),
    'queue_state': queueState.dbValue,
    'retry_count': retryCount,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'local_job_id': localJobId,
    'field_job_id': fieldJobId,
    'supabase_application_id': supabaseApplicationId,
    'bridge_source_id': bridgeSourceId,
    'remote_report_id': remoteReportId,
    'reference_code': referenceCode,
    'last_error': lastError,
    'last_attempt_at': lastAttemptAt?.toUtc().toIso8601String(),
    'inspector_id': inspectorId,
  };

  LocalReportRow copyWith({
    ReportQueueState? queueState,
    int? retryCount,
    String? remoteReportId,
    String? referenceCode,
    String? lastError,
    DateTime? lastAttemptAt,
  }) => LocalReportRow(
    id: id,
    reportType: reportType,
    payload: payload,
    queueState: queueState ?? this.queueState,
    retryCount: retryCount ?? this.retryCount,
    createdAt: createdAt,
    updatedAt: DateTime.now().toUtc(),
    localJobId: localJobId,
    fieldJobId: fieldJobId,
    supabaseApplicationId: supabaseApplicationId,
    bridgeSourceId: bridgeSourceId,
    remoteReportId: remoteReportId ?? this.remoteReportId,
    referenceCode: referenceCode ?? this.referenceCode,
    lastError: lastError ?? this.lastError,
    lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
    // Ownership is immutable for the life of a row: never carried through a
    // copyWith that omits it, because that would silently orphan a row.
    inspectorId: inspectorId,
  );
}

Map<String, dynamic> jsonDecodeMap(String source) {
  final decoded = jsonDecode(source);
  if (decoded is Map<String, dynamic>) return decoded;
  return Map<String, dynamic>.from(decoded as Map);
}

String jsonEncodeMap(Map<String, dynamic> map) => jsonEncode(map);
