import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/models/report_models.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/db_helper.dart';
import '../../core/services/supabase_service.dart';

/// Reports-specific offline queue (`local_report_queue`).
///
/// Deliberately SEPARATE from `SyncOutboxService`/`pending_actions`: an outbox
/// row is an inspection lifecycle action with a NOT NULL `job_id`, while a
/// Technical Issue has no job at all and an Application Support report is not
/// an inspection event. Mixing them would corrupt both.
///
/// Local identity is a UUID generated BEFORE the first network attempt. Remote
/// canonical identity (`diagnostic_reports.id` / `reference_code`) is attached
/// only after a confirmed server insert — never manufactured locally.
class ReportQueueService {
  ReportQueueService._();

  /// Local report ids currently inside a send. A row can never be in two
  /// simultaneous network sends even if two callers race.
  static final Set<String> _sending = <String>{};

  /// Guards the whole submit path so a double tap cannot create two rows.
  static bool _submitInProgress = false;

  @visibleForTesting
  static Future<Map<String, dynamic>> Function(Map<String, dynamic> insert)?
  remoteInsertOverride;

  @visibleForTesting
  static Future<bool> Function()? connectivityOverride;

  /// Inspector id source. Overridden in tests because the real one needs an
  /// initialised Supabase session.
  @visibleForTesting
  static String? Function()? inspectorIdOverride;

  @visibleForTesting
  static void resetTestHooks() {
    remoteInsertOverride = null;
    connectivityOverride = null;
    inspectorIdOverride = null;
    _sending.clear();
    _submitInProgress = false;
  }

  static String? get _inspectorId => inspectorIdOverride != null
      ? inspectorIdOverride!()
      : SupabaseService.client.auth.currentUser?.id;

  static bool get hasSubmitInProgress => _submitInProgress;

  // ── Persist-before-send ────────────────────────────────────────────────

  /// Validates, persists locally, then attempts a send. Typed text is durable
  /// before the network request begins.
  static Future<String> enqueueTechnicalIssue(TechnicalIssueDraft draft) async {
    final problem = draft.validationError;
    if (problem != null) throw ReportSubmissionException(problem);
    // Ownership is captured BEFORE the row exists: a row is never created
    // without an author, so there is no window in which an unattributable
    // provisional report could reach the device.
    final uid = _requireInspectorId();
    return _enqueue(
      LocalReportRow(
        id: newLocalId(),
        reportType: ReportType.technicalIssue,
        payload: draft.toJson(),
        queueState: ReportQueueState.pending,
        retryCount: 0,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        inspectorId: uid,
      ),
      uid,
    );
  }

  /// [draft] must carry the exact identity triple taken verbatim from the
  /// inspector-selected cached job. Nothing is inferred.
  static Future<String> enqueueApplicationSupport(
    ApplicationSupportDraft draft,
  ) async {
    final problem = draft.validationError;
    if (problem != null) throw ReportSubmissionException(problem);
    final uid = _requireInspectorId();
    return _enqueue(
      LocalReportRow(
        id: newLocalId(),
        reportType: ReportType.applicationSupport,
        payload: draft.toJson(),
        queueState: ReportQueueState.pending,
        retryCount: 0,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        fieldJobId: draft.fieldJobId,
        supabaseApplicationId: draft.supabaseApplicationId,
        bridgeSourceId: draft.bridgeSourceId,
        localJobId: draft.fieldJobId,
        inspectorId: uid,
      ),
      uid,
    );
  }

  /// The one place an authenticated inspector is demanded.
  ///
  /// With no authenticated Supabase user there is no authoritative owner to
  /// record, so the report is refused through the existing safe auth/session
  /// error path instead of creating a row nobody may ever see.
  static String _requireInspectorId() {
    final uid = _inspectorId;
    if (uid == null || uid.isEmpty) {
      throw ReportSubmissionException('Sign in again before sending a report.');
    }
    return uid;
  }

  static Future<String> _enqueue(LocalReportRow row, String inspectorId) async {
    if (_submitInProgress) {
      throw ReportSubmissionException(
        'A report is already being submitted. Please wait.',
      );
    }
    _submitInProgress = true;
    try {
      final db = await DBHelper.database;
      // The row is written with its owner in the same statement. There is no
      // insert-then-claim window.
      await db.transaction((txn) async {
        if (_requireInspectorId() != inspectorId) {
          throw ReportSubmissionException('Your session changed. Nothing was sent.');
        }
        await txn.insert('local_report_queue', row.toRow());
        if (_requireInspectorId() != inspectorId) {
          throw ReportSubmissionException('Your session changed. Nothing was sent.');
        }
      });
      // Keep the submit guard through dispatch, including slow online sends.
      // The row is durable before the existing processor touches the network.
      await processPending();
      return row.id;
    } finally {
      _submitInProgress = false;
    }
  }

  static final Random _random = Random();

  /// Converts any submission failure into one concise, actionable sentence.
  ///
  /// Raw `DatabaseException` / `PostgrestException` / `SocketException` text —
  /// which includes SQL statements and driver codes — is written to the debug
  /// log for developers and NEVER returned here. Meaningful categories are
  /// preserved: saved offline, could not be filed, submission status uncertain.
  static String userFacingMessage(Object error, {required String reportType}) {
    debugPrint('[REPORTS] $reportType submission failed: $error');
    if (error is ReportSubmissionException) return error.message;

    final text = error.toString().toLowerCase();

    // SQLite could not even store the report locally. Say so plainly, and do
    // not claim anything was saved.
    if (text.contains('databaseexception') ||
        text.contains('sqflite') ||
        text.contains('sqlite') ||
        text.contains('duplicate column') ||
        text.contains('no such table')) {
      return 'This device could not save your report. Nothing was sent. Please '
          'tell the MPDO team and try again later.';
    }

    if (error is AmbiguousSendOutcome) {
      return 'Submission status uncertain. The report is saved on this device '
          'and may already have reached the server — check My Reports before '
          'sending it again.';
    }
    if (error is AuthOrRlsRejection) {
      return 'Could not be filed: you are not allowed to file this report. '
          'Please contact the MPDO team.';
    }
    if (error is DeterministicRejection) {
      return 'Could not be filed: the MPDO team\'s records refused this report '
          'as submitted. Nothing was lost — please send it to them directly.';
    }
    if (error is TransientSendFailure) {
      return 'Saved on this device. There is no connection right now, so it '
          'will be submitted automatically when you are back online.';
    }

    // Anything left is unclassified: fail safe and never claim success.
    return 'Could not finish saving your report. Your entries are still here. '
        'Check My Reports before trying again.';
  }

  /// Transport identity only. Never the canonical remote report reference —
  /// `reference_code` is generated by Supabase.
  static String newLocalId() {
    final bytes = List.generate(
      16,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    );
    return 'rq-${DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(16)}-${bytes.join()}';
  }

  // ── Startup recovery ───────────────────────────────────────────────────

  /// A row persisted as `sending` proves only that this process was alive
  /// mid-request. The remote schema has no client idempotency key, so it is
  /// impossible to tell whether Supabase already accepted it. The honest,
  /// non-destructive state is `delivery_unknown` — never an automatic resend.
  static Future<void> recoverInterruptedSends() async {
    final db = await DBHelper.database;
    await db.rawUpdate(
      "UPDATE local_report_queue SET queue_state='delivery_unknown', "
      "updated_at=? WHERE queue_state='sending'",
      [DateTime.now().toUtc().toIso8601String()],
    );
  }

  // ── Reads ──────────────────────────────────────────────────────────────

  /// EVERY report row on the device, across all inspector accounts.
  ///
  /// UNSAFE FOR ANY USER-FACING PATH. This unscoped read is what leaked one
  /// inspector's provisional report cards — type, category and message text —
  /// to another inspector on a shared device. It is retained only for
  /// maintenance/diagnostics and for tests that need to assert on the raw
  /// table (including legacy rows nobody may see). Use
  /// [allRowsForInspector] everywhere a person can read a list.
  @visibleForTesting
  static Future<List<LocalReportRow>> allRowsOnDevice() async {
    final db = await DBHelper.database;
    final rows = await db.query(
      'local_report_queue',
      orderBy: 'created_at DESC',
    );
    return rows.map(LocalReportRow.fromMap).toList();
  }

  /// The rows [inspectorId] is allowed to see: exactly the reports that
  /// inspector created.
  ///
  /// A `NULL` `inspector_id` matches nothing. Legacy pre-v16 rows carry no
  /// author, and this contract forbids inventing one, so they are invisible to
  /// every inspector rather than shown to an arbitrary one.
  static Future<List<LocalReportRow>> allRowsForInspector(String inspectorId) async {
    final db = await DBHelper.database;
    final rows = await db.query(
      'local_report_queue',
      where: 'inspector_id = ?',
      whereArgs: [inspectorId],
      orderBy: 'created_at DESC',
    );
    return rows.map(LocalReportRow.fromMap).toList();
  }

  static Future<LocalReportRow?> rowById(String id) async {
    final db = await DBHelper.database;
    final rows = await db.query(
      'local_report_queue',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LocalReportRow.fromMap(rows.first);
  }

  /// Rows [inspectorId] may see. Convenience for user-facing code: resolves
  /// the authenticated user and returns an empty list when there is none, so
  /// an unauthenticated session shows no reports at all instead of everyone's.
  static Future<List<LocalReportRow>> myRows() async {
    final uid = _inspectorId;
    if (uid == null || uid.isEmpty) return const [];
    return allRowsForInspector(uid);
  }

  /// Rows eligible for an automatic send **for this inspector only**. Never
  /// includes `sent`, `delivery_unknown`, or another inspector's rows.
  static Future<List<LocalReportRow>> retryableRowsForInspector(
    String inspectorId,
  ) async {
    final db = await DBHelper.database;
    final rows = await db.query(
      'local_report_queue',
      where: "inspector_id = ? AND queue_state IN ('pending','failed_retryable')",
      whereArgs: [inspectorId],
      orderBy: 'created_at ASC',
    );
    return rows
        .map(LocalReportRow.fromMap)
        .where((r) => !isNonRetryable(r))
        .toList();
  }

  /// Device-wide automatic-retry candidate list. UNSAFE FOR USER-FACING AND
  /// RETRY PATHS — it spans every account, including legacy rows that belong
  /// to nobody. Retained for maintenance/diagnostics and tests only; the
  /// processor itself must use [retryableRowsForInspector].
  @visibleForTesting
  static Future<List<LocalReportRow>> autoRetryableRowsOnDevice() async {
    final db = await DBHelper.database;
    final rows = await db.query(
      'local_report_queue',
      where: "queue_state IN ('pending','failed_retryable')",
      orderBy: 'created_at ASC',
    );
    return rows
        .map(LocalReportRow.fromMap)
        .where((r) => !isNonRetryable(r))
        .toList();
  }

  /// An already-known-bad outcome. The row is preserved and reported with
  /// actionable wording, but re-sending it would just reproduce the same
  /// deterministic result on every reconnect, so the processor skips it.
  ///
  /// Both failure kinds share the `failed_retryable` transport state — that is
  /// where "not yet filed" lives — and are told apart by an explicit marker on
  /// `last_error`, so no new SQLite state is needed:
  ///   * `auth_error:`  the server refused this inspector (auth / RLS)
  ///   * `rejected:`    the server rejected the submitted data itself
  static bool isNonRetryable(LocalReportRow row) {
    final error = row.lastError;
    if (error == null) return false;
    return error.startsWith(authErrorMarker) ||
        error.startsWith(rejectionErrorMarker);
  }

  static const String authErrorMarker = 'auth_error:';
  static const String rejectionErrorMarker = 'rejected:';

  /// Inspector-facing label. Never promises an automatic retry that will not
  /// actually happen, and never calls an unconfirmed report "submitted".
  static String labelFor(LocalReportRow row) => switch (row.queueState) {
    ReportQueueState.pending => 'Pending on this device',
    ReportQueueState.sending => 'Sending…',
    ReportQueueState.failedRetryable =>
      isNonRetryable(row) ? 'Could not be filed' : 'Retry needed',
    ReportQueueState.deliveryUnknown => 'Submission status uncertain',
    ReportQueueState.sent => 'Filed',
  };

  // ── Processor ──────────────────────────────────────────────────────────

  /// Serial, tightly controlled. Safe to call from startup, an online
  /// transition, or a manual "try again" — never a busy loop.
  /// Sends only the AUTHENTICATED inspector's eligible rows.
  ///
  /// Scoping here is the point: with inspector B signed in, inspector A's
  /// pending row is not merely hidden from B's list, it is not picked up by
  /// the automatic retry at all. With no authenticated user, nothing is sent.
  static Future<void> processPending() async {
    final uid = _inspectorId;
    if (uid == null || uid.isEmpty) return;
    if (connectivityOverride != null) {
      if (!await connectivityOverride!()) return;
    } else if (!await AuthService.hasConnectivity()) {
      return;
    }
    for (final row in await retryableRowsForInspector(uid)) {
      await sendOnce(row);
    }
  }

  /// Manual retry for a row the inspector chose to resend. For
  /// `delivery_unknown` this can create a duplicate: the server has no client
  /// idempotency key, so the UI must warn before calling this.
  ///
  /// Ownership is re-checked before the send: a row id alone is not authority.
  /// A legacy `NULL`-owner row is refused outright — there is nobody to
  /// attribute a remote write to.
  static Future<void> retryManually(String localRowId) async {
    final uid = _inspectorId;
    if (uid == null || uid.isEmpty) return;
    final row = await rowById(localRowId);
    if (row == null) return;
    if (row.inspectorId != uid) return;
    if (row.queueState == ReportQueueState.sent) return;
    if (connectivityOverride == null && !await AuthService.hasConnectivity()) {
      return;
    }
    await sendOnce(row);
  }

  /// One send attempt. Transitions the row through `sending` to a terminal
  /// transport state. Never throws for an expected failure, and a row can never
  /// be in two simultaneous sends — the guard lives here so every caller is
  /// covered by construction.
  static Future<ReportQueueState> sendOnce(LocalReportRow row) async {
    if (!_sending.add(row.id)) {
      // Already in flight: refuse rather than race a second network send.
      return row.queueState;
    }
    try {
      return await _sendOnce(row);
    } finally {
      _sending.remove(row.id);
    }
  }

  static Future<ReportQueueState> _sendOnce(LocalReportRow row) async {
    final db = await DBHelper.database;

    // THE MANDATORY GUARD, before ANY remote write.
    //
    // A queued report is only ever sent by the inspector who wrote it. If the
    // live session is somebody else — or nobody, or the row is a legacy row
    // with no recorded owner — the send is refused outright. Without this, a
    // report typed by inspector A could reach the network while inspector B was
    // signed in and be attributed to B, because the remote `inspector_id` used
    // to be read from the live session at send time.
    //
    // The row is deliberately left untouched: not deleted, not marked failed.
    // Its owner logs back in and it becomes eligible again.
    final currentAuthUid = _inspectorId;
    if (currentAuthUid == null ||
        currentAuthUid.isEmpty ||
        row.inspectorId == null ||
        row.inspectorId!.isEmpty ||
        row.inspectorId != currentAuthUid) {
      debugPrint(
        '[REPORTS] blocked send: row ${row.id} is owned by '
        '${row.inspectorId ?? '(legacy, no owner)'} but the authenticated '
        'inspector is ${currentAuthUid ?? '(none)'}. Not sending.',
      );
      return row.queueState;
    }

    final attempt = row.retryCount + 1;
    await db.update(
      'local_report_queue',
      {
        'queue_state': ReportQueueState.sending.dbValue,
        'retry_count': attempt,
        'last_attempt_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [row.id],
    );

    try {
      final result = await insertRemote(remoteInsertFor(row));
      await db.update(
        'local_report_queue',
        {
          'queue_state': ReportQueueState.sent.dbValue,
          'remote_report_id': result['id'] as String?,
          'reference_code': result['reference_code'] as String?,
          'last_error': null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [row.id],
      );
      return ReportQueueState.sent;
    } on AuthOrRlsRejection catch (e) {
      await _park(
        db,
        row,
        ReportQueueState.failedRetryable,
        '$authErrorMarker ${e.message}',
      );
      return ReportQueueState.failedRetryable;
    } on TransientSendFailure catch (e) {
      // Another connection attempt may genuinely succeed without the report
      // changing, so this stays auto-eligible.
      await _park(db, row, ReportQueueState.failedRetryable, e.message);
      return ReportQueueState.failedRetryable;
    } on DeterministicRejection catch (e) {
      // The server proved the insert was rejected because the submitted data
      // itself is unacceptable. Re-sending unchanged text would fail the same
      // way forever, so this is recorded with the non-retryable marker and the
      // processor will skip it.
      await _park(
        db,
        row,
        ReportQueueState.failedRetryable,
        '$rejectionErrorMarker ${e.message}',
      );
      return ReportQueueState.failedRetryable;
    } on AmbiguousSendOutcome catch (e) {
      await _park(db, row, ReportQueueState.deliveryUnknown, e.toString());
      return ReportQueueState.deliveryUnknown;
    } catch (e) {
      // Anything not positively classified may have reached the server.
      // Fail safe: never auto-retry an outcome we cannot prove.
      await _park(
        db,
        row,
        ReportQueueState.deliveryUnknown,
        'The request outcome is uncertain (${e.runtimeType}).',
      );
      return ReportQueueState.deliveryUnknown;
    }
  }

  static Future<void> _park(
    Database db,
    LocalReportRow row,
    ReportQueueState state,
    String error,
  ) async {
    await db.update(
      'local_report_queue',
      {
        'queue_state': state.dbValue,
        'last_error': error,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [row.id],
    );
  }

  // ── Remote insert ──────────────────────────────────────────────────────

  /// The exact `diagnostic_reports` insert for this row. Admin review fields
  /// are always explicitly NULL: they are never inspector-owned, and the
  /// server-side filing validator rejects a report that pre-fills them.
  @visibleForTesting
  static Map<String, dynamic> remoteInsertFor(LocalReportRow row) {
    final p = row.payload;
    // The remote author is the row's OWN stored owner, never the live session.
    // `_sendOnce` has already proven the two are equal before we get here, so
    // this cannot diverge; reading it from the row keeps that guarantee even if
    // a future caller reaches this function from a new path.
    final insert = <String, dynamic>{
      'inspector_id': row.inspectorId,
      'report_type': row.reportType.dbValue,
      'title': p['title'],
      'summary': p['summary'],
      'status': 'submitted',
      'technical_description': null,
      'affected_file': null,
      'recommended_action': null,
      if (p.containsKey('module')) 'module': p['module'],
      if (p.containsKey('expected_behavior'))
        'expected_behavior': p['expected_behavior'],
      if (p.containsKey('repro_steps')) 'repro_steps': p['repro_steps'],
      if (p.containsKey('blocks_field_work'))
        'blocks_field_work': p['blocks_field_work'],
      if (p.containsKey('occurred_at')) 'occurred_at': p['occurred_at'],
      if (p.containsKey('connectivity_state'))
        'connectivity_state': p['connectivity_state'],
      if (p.containsKey('app_version')) 'app_version': p['app_version'],
      if (p.containsKey('os_version')) 'os_version': p['os_version'],
    };

    if (row.reportType == ReportType.technicalIssue) {
      return insert
        ..['field_job_id'] = null
        ..['supabase_application_id'] = null
        ..['bridge_source_id'] = null
        ..['support_category'] = null;
    }

    return insert
      ..['field_job_id'] = row.fieldJobId
      ..['supabase_application_id'] = row.supabaseApplicationId
      ..['bridge_source_id'] = row.bridgeSourceId
      ..['support_category'] = p['support_category']
      ..['affected_field'] = p['affected_field']
      ..['requested_change'] = p['requested_change'];
  }

  @visibleForTesting
  static Future<Map<String, dynamic>> insertRemote(
    Map<String, dynamic> insert,
  ) async {
    if (remoteInsertOverride != null) {
      try {
        return await remoteInsertOverride!(insert);
      } catch (e) {
        throw classifySendError(e);
      }
    }
    try {
      final row = await SupabaseService.client
          .from('diagnostic_reports')
          .insert(insert)
          .select()
          .single();
      return Map<String, dynamic>.from(row as Map);
    } catch (e) {
      throw classifySendError(e);
    }
  }

  /// Classifies a transport failure.
  ///
  /// Classifies a transport failure into exactly one of three outcomes.
  ///
  ///  * [TransientSendFailure]  — proven to have failed BEFORE dispatch, so
  ///    another attempt may succeed without changing anything. Auto-eligible.
  ///  * [DeterministicRejection] — the server answered and rejected the
  ///    submitted data (validation, CHECK constraint, duplicate, 4xx). The
  ///    outcome is KNOWN, so this is not a `delivery_unknown`, and re-sending
  ///    unchanged text is pointless, so it is never automatic.
  ///  * [AmbiguousSendOutcome] — the request may or may not have been accepted.
  ///    Never auto-retried.
  ///
  /// Anything unrecognised falls to the ambiguous bucket: failing safe means
  /// never claiming a retry is safe when the outcome is unknown.
  @visibleForTesting
  static Object classifySendError(Object error) {
    final text = error.toString().toLowerCase();

    // A lost response may follow an accepted insert. Ambiguity takes precedence
    // over generic connectivity wording and numbers in socket diagnostics.
    if (text.contains('timeout') ||
        text.contains('timed out') ||
        text.contains('connection reset') ||
        text.contains('connection lost') ||
        text.contains('connection closed') ||
        text.contains('abort')) {
      return const AmbiguousSendOutcome();
    }

    // Only explicit pre-dispatch failures prove that retrying is safe.
    if (text.contains('failed host lookup') ||
        text.contains('connection refused') ||
        text.contains('network is unreachable') ||
        text.contains('no address associated') ||
        text.contains('unable to connect')) {
      return TransientSendFailure(
        'No connection when the report was sent. It will retry automatically.',
      );
    }
    if (text.contains('socketexception')) {
      return const AmbiguousSendOutcome();
    }

    if (text.contains('row-level security') ||
        text.contains('permission denied') ||
        text.contains('42501') ||
        text.contains('not authenticated') ||
        text.contains('jwt') ||
        text.contains('violates row-level')) {
      return AuthOrRlsRejection('You are not allowed to file this report.');
    }

    // Definitive server-side rejection: the response proves the insert was
    // refused because of the submitted data itself. HTTP codes need a status/code
    // marker; a port or byte count is not evidence of a server response.
    if (text.contains('violates check constraint') ||
        text.contains('dr_') ||
        text.contains('pgrst') ||
        text.contains('duplicate key') ||
        text.contains('foreign key') ||
        text.contains('invalid input value') ||
        text.contains('value too long') ||
        RegExp(
          r'\b(?:http|postgrest|status(?:[\s_-]*code)?|code)\s*[:=]?\s*(?:400|401|403|409|422)\b',
        ).hasMatch(text)) {
      return DeterministicRejection(
        'The MPDO team\'s records refused this report as submitted. Nothing was '
        'lost — please send it to them directly.',
      );
    }

    return const AmbiguousSendOutcome();
  }
}

/// Raised when Supabase (or an RLS policy) authoritatively refuses the insert.
class AuthOrRlsRejection implements Exception {
  AuthOrRlsRejection(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A validation problem the inspector can actually fix. [message] is safe to
/// show verbatim — it never contains SQL, driver text or a stack trace.
class ReportSubmissionException implements Exception {
  ReportSubmissionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Raised when the report provably never left the device. The report itself is
/// still acceptable, so another attempt may succeed unchanged: auto-eligible.
class TransientSendFailure implements Exception {
  TransientSendFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Raised when the request may or may not have been accepted. Never retried
/// automatically.
class AmbiguousSendOutcome implements Exception {
  const AmbiguousSendOutcome();
  @override
  String toString() =>
      'The request outcome is uncertain. The report may already have reached '
      'the server.';
}

/// Raised when the server answered and rejected the submitted data itself
/// (HTTP 400/409/422, PostgREST validation error, CHECK constraint violation,
/// duplicate key). The outcome is KNOWN — so this is deliberately not a
/// [AmbiguousSendOutcome] — but re-sending the same text would be rejected the
/// same way forever, so it is never retried automatically.
class DeterministicRejection implements Exception {
  DeterministicRejection(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Deterministic-per-process RNG. Report transport ids only need to be unique
/// on one device, never unpredictable; `dart:math`'s default source is fine.
