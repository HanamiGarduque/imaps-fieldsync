import 'package:sqflite/sqflite.dart';

/// Local SQLite schema for Reports & Support (database version 15).
///
/// Kept in its own file — not inside `db_helper.dart` — for two reasons:
///
///  1. It is genuinely a separate transport. The inspection schema (jobs,
///     inspections, photos, `pending_actions`, retention, route cache) must
///     never be able to read or write a report row, and vice versa.
///  2. The migration suites that verify the inspection schema rebuild a fixture
///     database by scraping `CREATE TABLE ...` statements out of
///     `db_helper.dart` with a pattern that stops at the first `)`. The queue's
///     CHECK constraints nest parentheses, so keeping the DDL here means that
///     fixture scrape stays correct without every one of those suites needing
///     a parser upgrade.
///
/// DBHelper still owns the version number and the `onUpgrade` branch; this file
/// only owns the SQL.
class ReportQueueSchema {
  ReportQueueSchema._();

  static const String tableDdl = '''
CREATE TABLE IF NOT EXISTS local_report_queue(
  id TEXT PRIMARY KEY,
  report_type TEXT NOT NULL CHECK (report_type IN ('technical_issue', 'application_support')),
  payload TEXT NOT NULL,
  local_job_id TEXT,
  field_job_id TEXT,
  supabase_application_id TEXT,
  bridge_source_id TEXT,
  remote_report_id TEXT,
  reference_code TEXT,
  queue_state TEXT NOT NULL DEFAULT 'pending' CHECK (queue_state IN ('pending', 'sending', 'sent', 'failed_retryable', 'delivery_unknown')),
  retry_count INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  created_at TEXT NOT NULL,
  last_attempt_at TEXT,
  updated_at TEXT NOT NULL,
  CHECK (
    (
      report_type = 'technical_issue'
      AND field_job_id IS NULL
      AND supabase_application_id IS NULL
      AND bridge_source_id IS NULL
    )
    OR
    (
      report_type = 'application_support'
      AND field_job_id IS NOT NULL
      AND supabase_application_id IS NOT NULL
      AND bridge_source_id IS NOT NULL
    )
  )
)
''';

  /// Additive and idempotent (`IF NOT EXISTS` throughout), so it is safe on a
  /// fresh install and on every upgrade path.
  static Future<void> createTable(DatabaseExecutor db) async {
    await db.execute(tableDdl);
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_local_report_queue_state '
      'ON local_report_queue(queue_state)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_local_report_queue_type '
      'ON local_report_queue(report_type)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_local_report_queue_field_job '
      'ON local_report_queue(field_job_id)',
    );
    // One confirmed remote identity may only ever belong to one local row.
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_local_report_queue_remote_report_unique '
      'ON local_report_queue(remote_report_id) WHERE remote_report_id IS NOT NULL',
    );
  }

  /// The columns of [table], read with the repository's standard
  /// `PRAGMA table_info` idiom. An empty result means the table is absent.
  static Future<Set<String>> columnsOf(
    DatabaseExecutor db,
    String table,
  ) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.map((r) => r['name'] as String).toSet();
  }

  /// Adds [column] to [table] ONLY if it is not already there.
  ///
  /// This is what makes the v15 migration resumable. A real field device can
  /// legitimately reach this point with the column already present — for
  /// example when a previous open was interrupted between the two ALTERs, or
  /// when two opens raced the version check. `ALTER TABLE ... ADD COLUMN` has
  /// no `IF NOT EXISTS` form in SQLite, so the only safe equivalent is to
  /// inspect the real table first. Idempotent, and never destructive.
  static Future<void> addColumnIfMissing(
    DatabaseExecutor db,
    String table,
    String column,
    String definition,
  ) async {
    if ((await columnsOf(db, table)).contains(column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }

  /// The approved v14 → v15 migration: two nullable identity columns on
  /// `local_jobs`, plus the new queue table and its indexes. Nothing is dropped,
  /// truncated or rewritten, so every existing row survives — and the whole
  /// thing is resumable, so an interrupted or already-partially-applied upgrade
  /// simply continues instead of failing.
  static Future<void> applyV15(DatabaseExecutor db) async {
    await addColumnIfMissing(
      db,
      'local_jobs',
      'supabase_application_id',
      'TEXT',
    );
    await addColumnIfMissing(db, 'local_jobs', 'bridge_source_id', 'TEXT');
    await createTable(db);
  }
}
