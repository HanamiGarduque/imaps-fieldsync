import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../modules/auth_startup/services/secure_prefs_service.dart';
import 'route_service.dart';
import 'report_queue_schema.dart';
import 'inspection_ownership_schema.dart';
import 'supabase_service.dart';

enum LocalOwnershipResult { current, foreign, legacyUnknown, mixed }

class DBHelper {
  /// Local-only fixtures explicitly supply an authenticated identity. Production
  /// never falls back to a preference, assignment, name, or legacy NULL owner.
  @visibleForTesting
  static String? inspectorIdForTesting;
  static String? get currentInspectorId {
    if (inspectorIdForTesting != null) return inspectorIdForTesting;
    try { return SupabaseService.client.auth.currentUser?.id; }
    catch (_) { return null; }
  }

  static String requireInspector() {
    final uid = currentInspectorId;
    if (uid == null || uid.isEmpty) throw StateError('Authenticated inspector required');
    return uid;
  }

  static void requireSameInspector(String uid) {
    if (currentInspectorId != uid) throw StateError('Inspector session changed');
  }

  static Future<void> _requireOwnedRow(DatabaseExecutor db, String table,
      String key, String id, String uid) async {
    requireSameInspector(uid);
    final rows = await db.query(table, columns: ['inspector_id'],
      where: '$key = ?', whereArgs: [id]);
    if (rows.any((r) => r['inspector_id'] != uid)) {
      throw StateError('Local evidence belongs to another or unknown inspector');
    }
  }

  /// All job-keyed evidence participates: a replacement assignee cannot create
  /// a new draft over a retained legacy/foreign round on this device.
  static Future<void> requireOwnedJob(DatabaseExecutor db, String jobId, String uid) async {
    if (await classifyJobOwnership(db, jobId, uid) != LocalOwnershipResult.current) {
      throw StateError('Local evidence belongs to another or unknown inspector');
    }
    requireSameInspector(uid);
  }

  /// Read-only local classification, never remote authority or legacy adoption.
  /// An empty graph permits the existing fresh-write flow; it proves no history.
  static Future<LocalOwnershipResult> classifyJobOwnership(
      DatabaseExecutor db, String jobId, String uid) async {
    requireSameInspector(uid);
    final owners = <String?>{};
    for (final entry in {
      'local_jobs': 'id', 'local_inspections': 'id', 'local_photos': 'job_id',
      'inspection_job_retention': 'job_id', 'pending_actions': 'job_id',
    }.entries) {
      final rows = await db.query(entry.key, columns: ['inspector_id'],
        where: '${entry.value} = ?', whereArgs: [jobId]);
      requireSameInspector(uid);
      owners.addAll(rows.map((row) => row['inspector_id'] as String?));
    }
    if (owners.any((owner) => owner != null && owner != uid)) {
      return owners.length == 1 ? LocalOwnershipResult.foreign : LocalOwnershipResult.mixed;
    }
    return owners.contains(null) ? LocalOwnershipResult.legacyUnknown : LocalOwnershipResult.current;
  }
  static Database? _database;

  /// The in-flight `_initDB()` future, memoised.
  ///
  /// Without this, two callers that reach [database] before the first open
  /// finishes BOTH run `_initDB()`, and each performs its own
  /// `openDatabase(..., version: 15, onUpgrade: ...)`. On a real device that
  /// is reachable at cold start: MainShellScreen's report-queue recovery, the
  /// Tasks screen, and startup all resolve the database concurrently. Both
  /// opens read the same pre-v15 `user_version`, both decide to upgrade, one
  /// commits the v15 ALTERs and bumps the version, and the loser then runs
  /// `ALTER TABLE local_jobs ADD COLUMN supabase_application_id` against a
  /// table that already has it — the observed
  /// "duplicate column name: supabase_application_id".
  ///
  /// Memoising the future guarantees exactly one open, one version check and
  /// one migration per process.
  static Future<Database>? _opening;

  /// Inject an isolated SQLite connection in persistence tests. Never opens or
  /// closes an application database; the test owns the connection lifecycle.
  @visibleForTesting
  static void useDatabaseForTesting(Database? db) {
    _database = db;
    _opening = null;
  }

  /// The route-cache DDL, for migration tests that rebuild the schema against
  /// an isolated temporary database. Never used at runtime.
  @visibleForTesting
  static String get localRouteCacheSchemaForTesting => _localRouteCacheSchema;

  static Future<Database> get database async {
    final existing = _database;
    if (existing != null) return existing;
    return _opening ??= _initDB().then(
      (db) {
        _database = db;
        // A failed open must not be cached, or one transient error would poison
        // the whole process.
        _opening = null;
        return db;
      },
      onError: (Object error, StackTrace stack) {
        _opening = null;
        throw error;
      },
    );
  }

  /// Cryptographically-random 32-byte key, generated once and reused for
  /// the life of the install (Keystore-backed via SecurePrefsService).
  /// Deliberately NOT derived from anything predictable (e.g. a timestamp)
  /// — that exact mistake was found and flagged elsewhere in this app's
  /// pattern-lock salt generation; not repeating it here.
  static Future<String> _getOrCreateDbKey() async {
    final existing = await SecurePrefsService.getDbEncryptionKey();
    if (existing != null && existing.isNotEmpty) return existing;

    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final key = base64Url.encode(bytes);
    await SecurePrefsService.setDbEncryptionKey(key);
    return key;
  }

  /// True if [path] can actually be read as a SQLCipher database using
  /// [password] — opening alone isn't a reliable check with SQLCipher
  /// (a wrong key can still "open" the file handle), the first real query
  /// is what actually proves the key is correct.
  static Future<bool> _opensWithKey(String path, String? password) async {
    Database? db;
    try {
      db = await openDatabase(path, password: password, readOnly: true);
      await db.rawQuery('SELECT count(*) FROM sqlite_master');
      return true;
    } catch (_) {
      return false;
    } finally {
      await db?.close();
    }
  }

  /// One-time migration for installs that ran before this database was
  /// encrypted. Uses SQLCipher's documented sqlcipher_export() approach —
  /// attach a new encrypted database, copy everything into it, then swap
  /// it into place. The original plaintext file is renamed aside (not
  /// deleted) as a safety net in case anything about the migration looks
  /// wrong after the fact; it is NOT auto-deleted.
  static Future<void> _migrateLegacyPlaintextDb(
    String path,
    String password,
  ) async {
    debugPrint(
      '[DB] Legacy unencrypted database detected — migrating to SQLCipher.',
    );
    final plainDb = await openDatabase(path);
    final tmpPath = '$path.encrypting_tmp';
    final tmpFile = File(tmpPath);
    if (await tmpFile.exists()) {
      // Leftover from a previous interrupted attempt — start clean.
      await tmpFile.delete();
    }

    try {
      await plainDb.execute(
        "ATTACH DATABASE '$tmpPath' AS encrypted KEY '$password'",
      );
      await plainDb.execute("SELECT sqlcipher_export('encrypted')");
      await plainDb.execute('DETACH DATABASE encrypted');
    } finally {
      await plainDb.close();
    }

    final backupPath = '$path.pre_encryption_backup';
    final backupFile = File(backupPath);
    if (await backupFile.exists()) await backupFile.delete();
    await File(path).rename(backupPath);
    await tmpFile.rename(path);

    debugPrint(
      '[DB] Migration complete. Original plaintext file preserved at '
      '$backupPath — safe to delete manually once the app has been '
      'confirmed working with the encrypted database.',
    );
  }

  static Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'imaps_fieldsync.db');
    final password = await _getOrCreateDbKey();

    if (await File(path).exists()) {
      final alreadyEncrypted = await _opensWithKey(path, password);
      if (!alreadyEncrypted) {
        final isReadablePlaintext = await _opensWithKey(path, null);
        if (isReadablePlaintext) {
          await _migrateLegacyPlaintextDb(path, password);
        } else {
          // Neither the current key nor a plaintext read works. Don't
          // guess — overwriting or deleting here risks real inspection
          // data with no way back. Surface this loudly instead.
          debugPrint(
            '[DB] WARNING: existing database at $path could not be opened '
            'with the stored key or as plaintext. Leaving it untouched — '
            'this needs manual investigation, not an automatic fix.',
          );
          throw StateError(
            'Local database exists but is unreadable with the current '
            'encryption key. Needs manual investigation before proceeding.',
          );
        }
      }
    }

    return await openDatabase(
      path,
      password: password,
      version: 17,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Existing installs won't have this column yet — add it so
          // drafts saved before this fix don't crash on read/write.
          await db.execute(
            'ALTER TABLE local_inspections ADD COLUMN inspection_result TEXT',
          );
        }
        if (oldVersion < 3) {
          // local_jobs was missing deadline_date, is_self_scheduled, and
          // application_type — meaning offline mode silently fell back to
          // default categorization/deadline-checking instead of reflecting
          // what the online path already knows. Add them so cached jobs
          // carry the same fields as a live fetch.
          await db.execute(
            'ALTER TABLE local_jobs ADD COLUMN deadline_date TEXT',
          );
          await db.execute(
            'ALTER TABLE local_jobs ADD COLUMN is_self_scheduled INTEGER DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE local_jobs ADD COLUMN application_type TEXT',
          );
        }
        if (oldVersion < 4) {
          await db.execute(_pendingActionsSchema);
        }
        if (oldVersion < 5) {
          await db.execute(
            'ALTER TABLE local_inspections ADD COLUMN current_step INTEGER DEFAULT 0',
          );
        }
        if (oldVersion < 6) {
          await db.execute(
            'ALTER TABLE local_jobs ADD COLUMN cached_updated_at TEXT',
          );
        }
        if (oldVersion < 7) {
          // Phase 6 (Detailed Sync Logs): local-first, offline-capable log
          // of every synchronization EVENT (not just final action status).
          // Deliberately separate from `activity_log` (Supabase, online,
          // user-initiated actions like Login/Submit) — this table is
          // system-initiated sync events (Queue Started, Upload Failed,
          // Retry, Conflict Detected, etc.), consumed by the Notifications
          // screen's new "Sync" tab. `event_type` is a free-form string
          // (not an enum/CHECK constraint) so future event types (Document
          // Sync, Background Sync, future cloud integrations) never need a
          // schema migration to add.
          await db.execute(_syncLogEntriesSchema);
        }
        if (oldVersion < 8) {
          // Rework redesign: mirrors the new Supabase field_jobs column.
          // Non-null while a completed task has an unfinished rework
          // session (status itself stays 'completed' throughout — see
          // SupabaseService.reopenForRework), cleared back to null when
          // the inspector finalizes via Review & Submit. Needed locally
          // too so the "Modified" badge and rework state survive being
          // offline, not just the online fetch path.
          await db.execute(
            'ALTER TABLE local_jobs ADD COLUMN rework_started_at TEXT',
          );
        }
        if (oldVersion < 9) {
          // Per-step completion timestamps (approved F1 fix): JSON map like
          // {"1": "2026-08-25T04:00:00.000Z", ...} recording when each step
          // was actually saved/proceeded, per task. Mirrors the new
          // field_jobs.step_timestamps jsonb column so the Task Overview
          // shows real saved times offline as well as online.
          await db.execute(
            'ALTER TABLE local_inspections ADD COLUMN step_timestamps TEXT',
          );
        }
        if (oldVersion < 10) {
          await createInspectionRetentionTable(db);
        }
        if (oldVersion < 11) {
          await db.execute(
            'ALTER TABLE local_jobs ADD COLUMN assignment_instructions TEXT',
          );
          await db.execute(
            'ALTER TABLE local_jobs ADD COLUMN assigned_by_imaps_user_id TEXT',
          );
          await db.execute(
            'ALTER TABLE local_jobs ADD COLUMN assigned_by_name TEXT',
          );
        }
        if (oldVersion < 12) {
          // Loop 8 — read-only Planning Review metadata for this exact round.
          // Optional JSON; absence simply means "no Planning Review", and it is
          // never allowed to influence status, category, current_step or
          // progress. Reuses the existing local_jobs cache; no new cache system.
          await db.execute(
            'ALTER TABLE local_jobs ADD COLUMN planning_review TEXT',
          );
        }
        if (oldVersion < 13) {
          // Offline/online list parity: the Tasks screen already sorts the
          // Completed category by submitted_at (newest first, oldest last).
          // Without this cached column the offline path had no sort key at all,
          // so Completed fell back to raw row order and the sequence differed
          // from the online list. Presentational only; no lifecycle effect.
          await db.execute(
            'ALTER TABLE local_jobs ADD COLUMN submitted_at TEXT',
          );
        }
        if (oldVersion < 14) {
          // Road-route continuity: a successfully fetched OSRM route is cached
          // per job so Step 1 can still draw REAL road geometry while offline,
          // instead of a synthetic line that only looked like a road.
          //
          // Purely local navigation-support data: a NEW isolated table, so no
          // existing table is touched, and no lifecycle/photo/checklist/sync
          // query can accidentally read or write it. Deliberately has NO sync
          // flag and NO outbox action type — it never leaves the device and is
          // safe to lose. Destination coordinates are intentionally NOT stored
          // here: local_jobs.parcel_lat/parcel_lng remain authoritative, so
          // duplicating them would allow the two to disagree.
          //
          // Additive and idempotent (CREATE TABLE IF NOT EXISTS), so it is safe
          // on both a fresh install and every upgrade path. Rollback: drop this
          // one table; nothing else references it.
          await db.execute(_localRouteCacheSchema);
        }
        if (oldVersion < 15) {
          // Reports & Support: inspector-authored reports persist locally
          // before any network attempt, so typed text survives offline and a
          // restart. Additive only — two nullable identity columns on
          // local_jobs (so Application Support can carry the EXACT
          // field_job_id + application + bridge-source triple instead of
          // inferring one) plus one new isolated queue table. No lifecycle row
          // is touched, no existing table is rewritten, nothing is dropped.
          await ReportQueueSchema.applyV15(db);
        }
        if (oldVersion < 16) {
          // Reports & Support: per-inspector queue ownership. Before this the
          // queue stored no author at all, so on a shared device one inspector
          // saw the provisional report cards another inspector had typed —
          // report type, category and message text across accounts. One
          // nullable column, additive and idempotent like every step above:
          // existing rows keep all their data and simply have no author
          // recorded, so they are attributed to nobody rather than guessed at
          // from a name, message or job.
          await ReportQueueSchema.applyV16(db);
        }
        if (oldVersion < 17) await InspectionOwnershipSchema.applyV17(db);
      },
      onCreate: (db, version) async {
        await createInspectionRetentionTable(db);
        // Table for caching assigned jobs
        await db.execute('''
          CREATE TABLE local_jobs(
            id TEXT PRIMARY KEY,
            local_inspection_id INTEGER,
            status TEXT,
            scheduled_date TEXT,
            deadline_date TEXT,
            is_self_scheduled INTEGER DEFAULT 0,
            supabase_parcel_id TEXT,
            applicant_name TEXT,
            barangay TEXT,
            reference_number TEXT,
            application_type TEXT,
            assignment_instructions TEXT,
            assigned_by_imaps_user_id TEXT,
            assigned_by_name TEXT,
            planning_review TEXT,
            submitted_at TEXT,
            cached_updated_at TEXT,
            rework_started_at TEXT,
            parcel_lat REAL,
            parcel_lng REAL,
            lot_area_sqm REAL,
            declared_land_use TEXT,
            parcel_address TEXT,
            supabase_application_id TEXT,
            bridge_source_id TEXT
            ,inspector_id TEXT
          )
        ''');

        // Table for storing completed/in-progress inspections offline
        await db.execute('''
          CREATE TABLE local_inspections(
            id TEXT PRIMARY KEY,
            actual_land_use TEXT,
            notes TEXT,
            is_compliant INTEGER,
            inspection_result TEXT,
            checklist_json TEXT,
            boundary_status TEXT,
            current_step INTEGER DEFAULT 0,
            step_timestamps TEXT,
            is_synced INTEGER DEFAULT 0,
            updated_at TEXT
            ,inspector_id TEXT
          )
        ''');

        // Table for storing captured photo evidence offline
        await db.execute('''
          CREATE TABLE local_photos(
            id TEXT PRIMARY KEY,
            job_id TEXT,
            photo_path TEXT,
            notes TEXT,
            latitude REAL,
            longitude REAL,
            captured_at TEXT,
            is_synced INTEGER DEFAULT 0
            ,inspector_id TEXT
          )
        ''');

        // Generic offline-action outbox (FieldSync). Every offline-capable
        // write — GPS confirm, checklist update, photo upload, submit,
        // status change — becomes one row here instead of each screen
        // having its own bespoke offline logic. SyncOutboxService drains
        // this in order once connectivity returns.
        await db.execute(_pendingActionsSchema);

        // Phase 6 — Detailed Sync Logs (see _syncLogEntriesSchema below).
        await db.execute(_syncLogEntriesSchema);

        // Road-route cache for offline Step 1 (see onUpgrade, oldVersion < 14).
        await db.execute(_localRouteCacheSchema);

        // Reports & Support offline queue (see onUpgrade, oldVersion < 15).
        await ReportQueueSchema.createTable(db);
        await InspectionOwnershipSchema.applyV17(db);
      },
    );
  }

  /// Per-job cache of a real OSRM road route.
  ///
  /// [geometry_json] is the ordered OSRM/GeoJSON coordinate array, stored as
  /// `[longitude, latitude]` pairs (see RouteService.encodeRoutePoints).
  /// [origin_lat]/[origin_lng] record where the route started, so a future
  /// off-route/staleness check can tell how far the inspector has travelled
  /// since it was fetched. [fetched_at] is an ISO-8601 UTC timestamp.
  ///
  /// This table is intentionally disposable: it carries no lifecycle status,
  /// no sync flag and no Supabase id, and is never enqueued to the outbox.
  static const String _localRouteCacheSchema = '''
    CREATE TABLE IF NOT EXISTS local_route_cache(
      job_id TEXT PRIMARY KEY NOT NULL,
      geometry_json TEXT NOT NULL,
      distance_meters REAL,
      duration_seconds REAL,
      origin_lat REAL NOT NULL,
      origin_lng REAL NOT NULL,
      fetched_at TEXT NOT NULL
    )
  ''';

  static const String _pendingActionsSchema = '''
    CREATE TABLE IF NOT EXISTS pending_actions(
      id TEXT PRIMARY KEY,
      type TEXT NOT NULL,
      job_id TEXT NOT NULL,
      payload TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      retry_count INTEGER NOT NULL DEFAULT 0,
      last_error TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
      ,inspector_id TEXT
    )
  ''';

  // ─────────────────────────────────────────────────────────────────────
  // Phase 6 — Detailed Sync Logs
  //   Local-first (SQLite) event log for the SYNCHRONIZATION ENGINE
  //   itself — deliberately separate from the online `activity_log`
  //   table (Supabase), which records USER-initiated actions (Login,
  //   Manual Sync tap, Inspection Submitted). This table records
  //   SYSTEM-initiated sync events: Queue Started/Finished, Upload
  //   Started/Completed/Failed, Retry Attempt, Conflict Detected —
  //   one row per event, not just a final status.
  //
  //   `event_type` is free-form TEXT (no CHECK constraint / enum) so new
  //   event types (Document Sync, Background Sync, future cloud
  //   integrations) never require a schema migration.
  //
  //   `message` is the sanitized, user-friendly line shown by default
  //   (e.g. "Network connection lost.") — never a raw exception string.
  //   `technical_details` is optional JSON (HTTP status, function name,
  //   exception type) shown only inside an expandable section; it must
  //   never contain tokens, keys, passwords, connection strings, or PII —
  //   sanitize before writing, not just before display.
  //
  //   `pending_action_id`/`job_id` give data-integrity: every log entry
  //   traces back to the exact outbox action and job it came from, so
  //   entries from one inspection can never bleed into another's history.
  // ─────────────────────────────────────────────────────────────────────
  static const String _syncLogEntriesSchema = '''
    CREATE TABLE IF NOT EXISTS sync_log_entries(
      id TEXT PRIMARY KEY,
      pending_action_id TEXT,
      job_id TEXT,
      event_type TEXT NOT NULL,
      result TEXT NOT NULL,
      message TEXT NOT NULL,
      technical_details TEXT,
      created_at TEXT NOT NULL
      ,inspector_id TEXT
    )
  ''';

  /// Shared by the version-10 upgrade and fresh database creation.
  static Future<void> createInspectionRetentionTable(DatabaseExecutor db) =>
      db.execute('''
        CREATE TABLE IF NOT EXISTS inspection_job_retention(
          job_id TEXT PRIMARY KEY NOT NULL,
          retained_at TEXT NOT NULL
          ,inspector_id TEXT
        )
      ''');

  /// Normal step entry only. No lifecycle transition and no network request.
  /// The fetched payload is optional for Tasks/offline entry, where the exact
  /// cached row already exists. Cache + retention commit together.
  static Future<void> retainInspectionJob(
    String jobId, {
    Map<String, dynamic>? fetchedJob,
  }) async {
    final uid = requireInspector();
    if (jobId.isEmpty || (fetchedJob != null && fetchedJob['id'] != jobId)) {
      throw StateError('Inspection entry requires the exact field job.');
    }
    final db = await database;
    await db.transaction((txn) async {
      await requireOwnedJob(txn, jobId, uid);
      if (fetchedJob != null) {
        final effective = _projectPendingCompletions([
          fetchedJob,
        ], await _pendingCompletionJobIds(txn)).single;
        await txn.insert(
          'local_jobs',
          {..._cachedJobRow(effective), 'inspector_id': uid},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      final rows = await txn.query(
        'local_jobs',
        where: 'id = ?',
        whereArgs: [jobId],
      );
      if (rows.length != 1) {
        throw StateError(
          'Inspection entry requires the exact cached field job.',
        );
      }
      // Retention is not a way into completed rework or unsupported lifecycle.
      if (!const [
        'assigned',
        'Pending',
        'pending',
        'in_progress',
        'in-progress',
        'ongoing',
      ].contains(rows.single['status'])) {
        throw StateError('Only unfinished normal inspections can be retained.');
      }
      await txn.insert('inspection_job_retention', {
        'job_id': jobId,
        'retained_at': DateTime.now().toUtc().toIso8601String(),
        'inspector_id': uid,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      requireSameInspector(uid);
    });
  }

  /// Called only after confirmed online acceptance, outside the business
  /// submission catch. Failure leaves retention intact for recovery via cache.
  /// Returning false reports cleanup failure without resubmitting remote work.
  static Future<bool> finalizeAcceptedOnlineInspection(String jobId, {
    InspectionAuthorityResult remoteResult = InspectionAuthorityResult.offlineOrUnverifiable,
  }) async {
    if (remoteResult != InspectionAuthorityResult.authorized) return false;
    try {
      final uid = requireInspector();
      final db = await database;
      await db.transaction((txn) async {
        await requireOwnedJob(txn, jobId, uid);
        await txn.update(
          'local_jobs',
          {'status': 'completed'},
          where: 'id = ? AND inspector_id = ?',
          whereArgs: [jobId, uid],
        );
        await txn.delete(
          'inspection_job_retention',
          where: 'job_id = ? AND inspector_id = ?',
          whereArgs: [jobId, uid],
        );
      });
      return true;
    } catch (e) {
      debugPrint(
        'Online inspection accepted; local cleanup failed for $jobId: $e',
      );
      return false;
    }
  }

  // --- LOCAL JOBS CACHING ---

  static Future<Set<String>> _pendingCompletionJobIds(
    DatabaseExecutor db,
  ) async {
    final rows = await db.rawQuery('''
      SELECT j.id FROM local_jobs j
      WHERE j.status IN ('completed', 'Completed', 'submitted')
      AND j.inspector_id = ?
      AND EXISTS (
        SELECT 1 FROM pending_actions a
        WHERE a.job_id = j.id AND a.type = 'submit_inspection'
        AND a.status IN ('pending', 'failed', 'syncing', 'conflict')
      )
    ''', [currentInspectorId]);
    return rows.map((row) => row['id'] as String).toSet();
  }

  static List<Map<String, dynamic>> _projectPendingCompletions(
    List<Map<String, dynamic>> jobs,
    Set<String> protectedIds,
  ) {
    return jobs.map((job) {
      if (!protectedIds.contains(job['id'])) {
        return Map<String, dynamic>.of(job);
      }
      switch (job['status']) {
        case 'assigned':
        case 'Pending':
        case 'pending':
        case 'in_progress':
        case 'in-progress':
        case 'ongoing':
          return {...job, 'status': 'completed'};
        case 'completed':
        case 'Completed':
        case 'submitted':
          return Map<String, dynamic>.of(job);
        default:
          // Field work is complete; remote disagreement is a separate local
          // diagnostic, not a reason to fail every consumer's refresh. These
          // keys are in-memory only (_cachedJobRow uses an explicit allowlist).
          // Log classification only, never arbitrary remote text or payloads.
          debugPrint(
            '[DB] Field job ${job['id']}: unsupported remote lifecycle; '
            'local pending completion protection active.',
          );
          return {
            ...job,
            'status': 'completed',
            '_localPendingCompletionConflict': true,
            '_remoteStatusSnapshot': job['status'],
          };
      }
    }).toList();
  }

  /// Shared single-job cache mapping. Used by full-list cacheJobs() and
  /// normal inspection entry so both persist identical metadata.
  static Map<String, dynamic> _cachedJobRow(Map<String, dynamic> job) {
    final app = job['supabase_zoning_applications'] ?? {};
    final parcel = job['supabase_parcels'] ?? {};
    final rawAssignedByName = job['assigned_by_name'];
    final normalizedAssignedByName = rawAssignedByName is String
        ? rawAssignedByName.trim()
        : rawAssignedByName?.toString().trim();
    return {
      'id': job['id'],
      'inspector_id': requireInspector(),
      'local_inspection_id': job['local_inspection_id'],
      'status': job['status'],
      'scheduled_date': job['scheduled_date'],
      'deadline_date': job['deadline_date'],
      'is_self_scheduled': (job['is_self_scheduled'] == true) ? 1 : 0,
      'supabase_parcel_id': job['supabase_parcel_id'],
      // Exact remote identity for the Application Support queue. These travel
      // with the job into local_jobs so the report selector never infers a
      // namespace from display text. NULL only for upgraded v14 rows that have
      // not been refreshed online yet — those rows block Application Support.
      'supabase_application_id': job['supabase_application_id'],
      'bridge_source_id': job['bridge_source_id'],
      'applicant_name': app['applicant_name'] ?? 'Unknown Applicant',
      'barangay': app['barangay'] ?? 'No barangay listed',
      'reference_number': app['reference_number'] ?? '',
      'application_type': app['application_type'],
      'assignment_instructions': job['assignment_instructions'],
      'assigned_by_imaps_user_id': job['assigned_by_imaps_user_id']?.toString(),
      'assigned_by_name':
          (normalizedAssignedByName != null &&
              normalizedAssignedByName.isNotEmpty)
          ? normalizedAssignedByName
          : null,
      'cached_updated_at': job['updated_at'],
      'rework_started_at': job['rework_started_at'],
      'parcel_lat': parcel['latitude'],
      'parcel_lng': parcel['longitude'],
      'lot_area_sqm': parcel['lot_area_sqm'],
      'declared_land_use':
          parcel['declared_land_use'] ?? 'Single-detached residential',
      'parcel_address': parcel['address'] ?? '',
      // Offline/online list parity: the Tasks screen sorts Completed by
      // submitted_at, so the cached row must carry it or the offline order
      // silently diverges from the online order.
      'submitted_at': job['submitted_at'],
      // Loop 8 — cache the optional read-only Planning Review row for this
      // exact job so it stays presentable offline. Presentational only.
      'planning_review': _planningReviewCacheJson(job['field_job_reviews']),
    };
  }

  /// Serialize the optional `field_job_reviews` embed for the local_jobs cache.
  /// Returns null when there is no review row, which is the normal state for
  /// any task that has not been reviewed.
  static String? _planningReviewCacheJson(dynamic embedded) {
    if (embedded is! List || embedded.isEmpty) {
      return null;
    }

    final first = embedded.first;
    if (first is! Map) {
      return null;
    }

    final row = Map<String, dynamic>.from(first);
    final decision = row['decision']?.toString().trim();
    if (decision == null || decision.isEmpty) {
      return null;
    }

    try {
      return jsonEncode({
        'decision': decision,
        'reviewed_by_name': row['reviewed_by_name'],
        'reviewed_at': row['reviewed_at'],
        'technical_review_id': row['technical_review_id'],
        'reviewed_site_inspection_id': row['reviewed_site_inspection_id'],
        'field_job_id': row['field_job_id'],
      });
    } catch (e) {
      debugPrint('Loop 8 planning review cache encode failed: $e');
      return null;
    }
  }

  /// Local UI projection, never a remote write. One rule for every consumer
  /// and cache replacement; acknowledgement removes the exception.
  static Future<List<Map<String, dynamic>>> projectPendingCompletions(
    List<Map<String, dynamic>> jobs,
  ) async {
    final db = await database;
    return db.transaction((txn) async {
      return _projectPendingCompletions(
        jobs,
        await _pendingCompletionJobIds(txn),
      );
    });
  }

  static Future<void> cacheJobs(List<Map<String, dynamic>> jobs) async {
    final uid = currentInspectorId;
    if (uid == null || uid.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      requireSameInspector(uid);
      final protectedIds = await _pendingCompletionJobIds(txn);
      final effectiveJobs = _projectPendingCompletions(jobs, protectedIds);
      // Only actual canonical remote completion releases unfinished retention.
      // Projection above remains exclusively pending-completion behavior.
      for (final job in jobs.where((job) => job['status'] == 'completed')) {
        await txn.delete(
          'inspection_job_retention',
          where: 'job_id = ? AND inspector_id = ?',
          whereArgs: [job['id'], uid],
        );
      }
      final retained = await txn.query('inspection_job_retention');
      protectedIds.addAll(retained.map((row) => row['job_id'] as String));
      final batch = txn.batch();

      // Separate unfinished-work and pending-completion reasons protect rows.
      // Unretained rows still follow ordinary full-refresh replacement.
      if (protectedIds.isEmpty) {
        batch.delete('local_jobs', where: 'inspector_id = ?', whereArgs: [uid]);
      } else {
        batch.delete(
          'local_jobs',
          where:
              'inspector_id = ? AND id NOT IN (${List.filled(protectedIds.length, '?').join(',')})',
          whereArgs: [uid, ...protectedIds],
        );
      }

      for (final job in effectiveJobs) {
        final existingOwner = await txn.query('local_jobs', columns: ['inspector_id'],
          where: 'id = ?', whereArgs: [job['id']]);
        if (existingOwner.any((r) => r['inspector_id'] != uid)) continue;
        final incoming = Map<String, dynamic>.of(job);
        final existingRows = await txn.query(
          'local_jobs',
          columns: ['status'],
          where: 'id = ?',
          whereArgs: [job['id']],
          limit: 1,
        );
        if (existingRows.isNotEmpty &&
            existingRows.single['status'] == 'completed' &&
            const {
              'assigned',
              'Pending',
              'pending',
              'in_progress',
              'in-progress',
              'ongoing',
            }.contains(incoming['status'])) {
          // A recognized stale lifecycle refresh cannot reclassify a
          // canonically completed cached round as ongoing or pending. Preserve
          // legacy completed equivalents and unsupported diagnostic states.
          incoming['status'] = 'completed';
        }
        batch.insert(
          'local_jobs',
          {..._cachedJobRow(incoming), 'inspector_id': uid},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
      requireSameInspector(uid);
    });
  }

  static Future<List<Map<String, dynamic>>> getCachedJobs() async {
    final db = await database;
    return await db.query('local_jobs', where: 'inspector_id = ?', whereArgs: [currentInspectorId]);
  }

  // --- ROAD-ROUTE CACHE (local navigation support; never synced) ---------
  //
  // Deliberately NOT an outbox action and NOT mirrored to Supabase: a cached
  // route is disposable help for drawing the map offline. Losing it costs a
  // redraw, never data.

  /// Stores (or replaces) the real road route cached for [CachedRoute.jobId].
  ///
  /// Keyed on the exact `field_jobs.id`, so one task's route can never be read
  /// as another's. Replaces any previous row for the same job.
  static Future<void> saveRouteCache(CachedRoute route) async {
    final db = await database;
    await db.insert(
      'local_route_cache',
      route.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Returns the cached road route for [jobId], or null when this task has
  /// never had one fetched. A row whose geometry is unreadable is treated as
  /// absent rather than surfaced as a broken route.
  static Future<CachedRoute?> getRouteCache(String jobId) async {
    final db = await database;
    final rows = await db.query(
      'local_route_cache',
      where: 'job_id = ?',
      whereArgs: [jobId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    try {
      return CachedRoute.fromRow(rows.single);
    } on FormatException catch (e) {
      debugPrint('[DB] Discarding unusable cached route for job $jobId: $e');
      return null;
    }
  }

  /// Removes the cached route for [jobId]. Used when a task is no longer
  /// relevant locally so navigation data does not outlive the work.
  static Future<void> deleteRouteCache(String jobId) async {
    final db = await database;
    await db.delete(
      'local_route_cache',
      where: 'job_id = ?',
      whereArgs: [jobId],
    );
  }

  static Future<String?> getCachedJobUpdatedAt(String jobId) async {
    final db = await database;
    final rows = await db.query(
      'local_jobs',
      columns: ['cached_updated_at'],
      where: 'id = ? AND inspector_id = ?',
      whereArgs: [jobId, currentInspectorId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final value = rows.first['cached_updated_at'];
    return value?.toString();
  }

  // --- LOCAL INSPECTIONS ---

  static Future<void> saveInspectionLocally({
    required String jobId,
    required String actualLandUse,
    required String notes,
    required bool isCompliant,
    required String inspectionResult,
    required Map<String, dynamic> checklist,
    required String boundaryStatus,
    int currentStep = 0,
  }) async {
    final uid = requireInspector();
    final db = await database;
    await db.transaction((txn) async {
    await requireOwnedJob(txn, jobId, uid);
    await txn.insert('local_inspections', {
      'id': jobId,
      'inspector_id': uid,
      'actual_land_use': actualLandUse,
      'notes': notes,
      'is_compliant': isCompliant ? 1 : 0,
      'inspection_result': inspectionResult,
      'checklist_json': jsonEncode(checklist),
      'boundary_status': boundaryStatus,
      'current_step': currentStep,
      'is_synced': 0,
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    requireSameInspector(uid);
    });
  }

  static Future<Map<String, dynamic>?> getLocalInspection(String jobId) async {
    final db = await database;
    final results = await db.query(
      'local_inspections',
      where: 'id = ? AND inspector_id = ?',
      whereArgs: [jobId, currentInspectorId],
    );
    if (results.isEmpty) return null;
    return results.first;
  }

  static Future<void> saveInspectionStep(String jobId, int step,
      Map<String, String> timestamps, String inspectorId) async {
    requireSameInspector(inspectorId);
    final db = await database;
    await db.transaction((txn) async {
      await requireOwnedJob(txn, jobId, inspectorId);
      final values = {
        'current_step': step, 'step_timestamps': jsonEncode(timestamps),
        'updated_at': DateTime.now().toIso8601String(), 'is_synced': 0,
      };
      final updated = await txn.update('local_inspections', values,
        where:'id = ? AND inspector_id = ?', whereArgs:[jobId, inspectorId]);
      if (updated == 0) {
        requireSameInspector(inspectorId);
        await txn.insert('local_inspections', {'id':jobId, 'inspector_id':inspectorId, ...values});
      }
      requireSameInspector(inspectorId);
    });
  }

  static Future<List<Map<String, dynamic>>> getPendingInspections() async {
    final db = await database;
    return await db.query('local_inspections', where: 'is_synced = 0 AND inspector_id = ?',
      whereArgs: [currentInspectorId]);
  }

  static Future<void> markInspectionSynced(String jobId) async {
    final db = await database;
    await db.update(
      'local_inspections',
      {'is_synced': 1},
      where: 'id = ? AND inspector_id = ?',
      whereArgs: [jobId, currentInspectorId],
    );
  }

  // --- LOCAL PHOTOS ---

  static Future<void> savePhotoLocally({
    required String photoId,
    required String jobId,
    required String photoPath,
    required String notes,
    required double? latitude,
    required double? longitude,
  }) async {
    final uid = requireInspector();
    final db = await database;
    await db.transaction((txn) async {
    await requireOwnedJob(txn, jobId, uid);
    await _requireOwnedRow(txn, 'local_photos', 'id', photoId, uid);
    await txn.insert('local_photos', {
      'id': photoId,
      'inspector_id': uid,
      'job_id': jobId,
      'photo_path': photoPath,
      'notes': notes,
      'latitude': latitude,
      'longitude': longitude,
      'captured_at': DateTime.now().toIso8601String(),
      'is_synced': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    requireSameInspector(uid);
    });
  }

  static Future<List<Map<String, dynamic>>> getLocalPhotos(String jobId) async {
    final db = await database;
    return await db.query(
      'local_photos',
      where: 'job_id = ? AND inspector_id = ?',
      whereArgs: [jobId, currentInspectorId],
    );
  }

  static Future<List<Map<String, dynamic>>> getPendingPhotos() async {
    final db = await database;
    return await db.query('local_photos', where: 'is_synced = 0 AND inspector_id = ?',
      whereArgs: [currentInspectorId]);
  }

  static Future<void> markPhotoSynced(String photoId) async {
    final db = await database;
    await db.update(
      'local_photos',
      {'is_synced': 1},
      where: 'id = ? AND inspector_id = ?',
      whereArgs: [photoId, currentInspectorId],
    );
  }

  /// Acknowledge only photo rows already proven remote-complete by the
  /// canonical writer/recovery path. No row is created or deleted here.
  static Future<void> markPhotosSynced(Iterable<String?> photoIds) async {
    final ids = photoIds
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    if (ids.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.update(
          'local_photos',
          {'is_synced': 1},
          where: 'id = ? AND inspector_id = ?',
          whereArgs: [id, currentInspectorId],
        );
      }
    });
  }

  static Future<Map<String, dynamic>?> getLocalPhoto(String photoId) async {
    final db = await database;
    final rows = await db.query(
      'local_photos',
      where: 'id = ? AND inspector_id = ?',
      whereArgs: [photoId, currentInspectorId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Removes one photo's local row only after its physical file has been
  /// removed. The file-first order prevents the UI from acknowledging a
  /// removal while leaving an orphan behind. A missing file is already
  /// clean; a file deletion failure propagates and the row is retained.
  static Future<void> deleteLocalPhoto(
    String photoId, {
    String? photoPath,
  }) async {
    final uid = requireInspector();
    final db = await database;
    final rows = await db.query('local_photos', where: 'id = ? AND inspector_id = ?',
      whereArgs: [photoId, uid]);
    if (rows.isEmpty) return;
    if (photoPath != null && photoPath != rows.single['photo_path']) {
      throw StateError('Photo path does not match owned evidence');
    }
    if (photoPath != null && photoPath.isNotEmpty) {
      final file = File(photoPath);
      if (await file.exists()) await file.delete();
    }
    requireSameInspector(uid);
    await db.delete('local_photos', where: 'id = ? AND inspector_id = ?', whereArgs: [photoId, uid]);
  }

  // --- PENDING ACTIONS OUTBOX (FieldSync) ---
  //
  // One generic queue for every offline-capable write, instead of
  // per-screen offline logic. `payload` is a JSON-encoded map — its shape
  // depends on `type` (e.g. 'gps_confirm' payload has lat/lng/accuracy).

  static Future<void> enqueueAction({
    required String id,
    required String type,
    required String jobId,
    required Map<String, dynamic> payload,
    bool preserveOnly = false,
    String? expectedInspectorId,
  }) async {
    final uid = requireInspector();
    if (expectedInspectorId != null) requireSameInspector(expectedInspectorId);
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await requireOwnedJob(txn, jobId, uid);
      await _requireOwnedRow(txn, 'pending_actions', 'id', id, uid);
      await txn.insert('pending_actions', {
        'id': id,
        'inspector_id': uid,
        'type': type,
        'job_id': jobId,
        'payload': jsonEncode(payload),
        'status': preserveOnly ? 'conflict' : 'pending',
        'retry_count': 0,
        'last_error': null,
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      if (type == 'gps_confirm' || type == 'mark_ongoing') {
        // A durable start action, not retention or a network failure, accepts
        // local field work. Queue replacement and lifecycle commit together.
        final rows = await txn.query(
          'local_jobs',
          columns: ['status'],
          where: 'id = ?',
          whereArgs: [jobId],
        );
        if (rows.length != 1) {
          throw StateError(
            'Offline start requires the exact cached field job.',
          );
        }
        switch (rows.single['status']) {
          case 'assigned':
          case 'Pending':
          case 'pending':
          case 'in_progress':
          case 'in-progress':
          case 'ongoing':
            final updated = await txn.update(
              'local_jobs',
              {'status': 'in_progress'},
              where: 'id = ?',
              whereArgs: [jobId],
            );
            if (updated != 1) {
              throw StateError(
                'Offline start requires the exact cached field job.',
              );
            }
            break;
          default:
            // Preserve existing enqueue semantics for completed/unsupported
            // rows, but never downgrade completion or invent their lifecycle.
            break;
        }
        // Unfinished inspection retention is deliberately not retired here.
      }
      // A queued submission is preserved intent, not proof of completion.
      // Keep lifecycle and retention until a verified remote acceptance.
      requireSameInspector(uid);
    });
  }

  /// R4: called once under the outbox's process guard before new claims.
  /// The durable marker routes retries back through reconciliation, NEVER
  /// ordinary replay. Preserve action identity, payload fields and retry count.
  static Future<void> recoverAbandonedClaims() async {
    final uid = currentInspectorId;
    if (uid == null) return;
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'pending_actions',
        where: "status = 'syncing' AND inspector_id = ?",
        whereArgs: [uid],
      );
      for (final row in rows) {
        final raw = row['payload'] as String;
        try {
          final payload = Map<String, dynamic>.from(jsonDecode(raw) as Map);
          payload['r4RecoveryRequired'] = true;
          await txn.update(
            'pending_actions',
            {
              'payload': jsonEncode(payload),
              'status': 'failed',
              'last_error':
                  'Interrupted claim: remote reconciliation required.',
            },
            where: "id = ? AND status = 'syncing' AND payload = ?",
            whereArgs: [row['id'], raw],
          );
        } catch (_) {
          await txn.update(
            'pending_actions',
            {
              'status': 'conflict',
              'last_error':
                  'Interrupted claim has invalid payload; review required.',
            },
            where: "id = ? AND status = 'syncing' AND payload = ?",
            whereArgs: [row['id'], raw],
          );
        }
      }
    });
  }

  /// Rows ready to (re)try — pending or previously-failed, oldest first so
  /// actions sync in the order they happened.
  static Future<List<Map<String, dynamic>>> getActionableActions({
    bool includePaused = false,
  }) async {
    final db = await database;
    return await db.query(
      'pending_actions',
      where: "status IN ('pending', 'failed'${includePaused ? ", 'paused'" : ''}) "
          'AND inspector_id = ?',
      whereArgs: [currentInspectorId],
      orderBy: 'created_at ASC',
    );
  }

  static Future<List<Map<String, dynamic>>> getSyncCenterQueueActions() async {
    final db = await database;
    return await db.query(
      'pending_actions',
      where: "status IN ('pending', 'failed', 'syncing', 'conflict', 'paused') AND inspector_id = ?",
      whereArgs: [currentInspectorId],
      orderBy: 'created_at ASC',
    );
  }

  static Future<int> getPendingActionsCount() async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM pending_actions WHERE status IN ('pending', 'failed', 'syncing', 'conflict', 'paused') AND inspector_id = ?",
      [currentInspectorId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  static Future<void> markActionSyncing(String id) async {
    final db = await database;
    await db.update(
      'pending_actions',
      {'status': 'syncing', 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ? AND inspector_id = ?',
      whereArgs: [id, currentInspectorId],
    );
  }

  static Future<void> markActionSynced(String id) async {
    final db = await database;
    // Kept (not deleted) so the Sync Center has real completed-sync
    // history instead of fabricating one. Capped below so the table
    // doesn't grow forever.
    await db.update(
      'pending_actions',
      {'status': 'synced', 'updated_at': DateTime.now().toIso8601String()},
      where: "id = ? AND status = 'syncing' AND inspector_id = ?",
      whereArgs: [id, currentInspectorId],
    );
    await db.rawDelete('''
      DELETE FROM pending_actions
      WHERE status = 'synced' AND inspector_id = ? AND id NOT IN (
        SELECT id FROM pending_actions
        WHERE status = 'synced' AND inspector_id = ?
        ORDER BY updated_at DESC LIMIT 50
      )
    ''', [currentInspectorId, currentInspectorId]);
  }

  /// Real completed-sync history for the Sync Center's audit log —
  /// replaces the old screen's hardcoded rows.
  static Future<List<Map<String, dynamic>>> getRecentSyncedActions({
    int limit = 20,
  }) async {
    final db = await database;
    return await db.query(
      'pending_actions',
      where: "status = 'synced' AND inspector_id = ?",
      whereArgs: [currentInspectorId],
      orderBy: 'updated_at DESC',
      limit: limit,
    );
  }

  static Future<void> markActionFailed(String id, String error) async {
    final db = await database;
    await db.rawUpdate(
      "UPDATE pending_actions SET status = 'failed', retry_count = retry_count + 1, "
      "last_error = ?, updated_at = ? WHERE id = ? AND status = 'syncing' AND inspector_id = ?",
      [error, DateTime.now().toIso8601String(), id, currentInspectorId],
    );
  }

  /// Terminal "needs attention" state: automatic retries have stopped or the
  /// failure is permanent, but the row and its evidence are preserved for the
  /// inspector. Never a silent delete, never a fake success. Only an explicit
  /// user-triggered sync may attempt it again. Not selected by
  /// [getActionableActions], so no automatic drain can revive it.
  static Future<void> markActionPaused(String id, String error) async {
    final db = await database;
    await db.rawUpdate(
      "UPDATE pending_actions SET status = 'paused', last_error = ?, updated_at = ? "
      "WHERE id = ? AND inspector_id = ? AND status IN ('pending', 'failed', 'syncing')",
      [error, DateTime.now().toIso8601String(), id, currentInspectorId],
    );
  }

  static Future<void> markActionConflict(String id, String error) async {
    final db = await database;
    await db.update(
      'pending_actions',
      {
        'status': 'conflict',
        'last_error': error,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: "id = ? AND status = 'syncing' AND inspector_id = ?",
      whereArgs: [id, currentInspectorId],
    );
  }

  static Future<void> markActionForceSync(String id) async {
    final db = await database;
    final rows = await db.query(
      'pending_actions',
      columns: ['payload'],
      where: 'id = ? AND inspector_id = ?',
      whereArgs: [id, currentInspectorId],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final payload = Map<String, dynamic>.from(
      jsonDecode(rows.first['payload'] as String) as Map,
    );
    payload['forceSyncAnyway'] = true;

    await db.update(
      'pending_actions',
      {
        'payload': jsonEncode(payload),
        'status': 'pending',
        'last_error': null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND inspector_id = ?',
      whereArgs: [id, currentInspectorId],
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // PHASE 6 — DETAILED SYNC LOGS
  // ─────────────────────────────────────────────────────────────────────

  /// Writes one synchronization event. Called by SyncOutboxService at
  /// every meaningful point of the drain loop — not just the final
  /// outcome — so the Notifications screen's "Sync" tab can show a real
  /// per-attempt timeline (Attempt 1: timeout, Attempt 2: conflict,
  /// Attempt 3: success), not just the latest state.
  ///
  /// [message] must already be the sanitized, user-friendly line — this
  /// function does not sanitize on your behalf. [technicalDetails] is
  /// optional and only ever shown behind an expandable "Technical
  /// Details" section by the UI — never put tokens/keys/PII/raw SQL in
  /// either field.
  static Future<void> logSyncEvent({
    required String eventType,
    required String result, // 'info' | 'success' | 'error' | 'warning'
    required String message,
    String? jobId,
    String? pendingActionId,
    Map<String, dynamic>? technicalDetails,
  }) async {
    final uid = currentInspectorId;
    if (uid == null || uid.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
    requireSameInspector(uid);
    await txn.insert('sync_log_entries', {
      'id': const Uuid().v4(),
      'inspector_id': uid,
      'pending_action_id': pendingActionId,
      'job_id': jobId,
      'event_type': eventType,
      'result': result,
      'message': message,
      'technical_details': technicalDetails != null
          ? jsonEncode(technicalDetails)
          : null,
      'created_at': DateTime.now().toIso8601String(),
    });
    requireSameInspector(uid);
    });
  }

  /// Paginated, newest-first fetch — the Notifications "Sync" tab loads
  /// this in pages (default 20) instead of the whole table at once, so a
  /// long-lived install with thousands of entries stays fast to open.
  /// Automatically populates from historical `pending_actions` if
  /// `sync_log_entries` was empty.
  static Future<List<Map<String, dynamic>>> getSyncLogEntries({
    int limit = 20,
    int offset = 0,
    String? jobId,
  }) async {
    final uid = currentInspectorId;
    if (uid == null || uid.isEmpty) return [];
    final db = await database;
    requireSameInspector(uid);
    try {
      // Ensure sync_log_entries table exists
      await db.execute(_syncLogEntriesSchema);
    } catch (_) {}

    try {
      final totalLogs =
          Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM sync_log_entries'),
          ) ??
          0;

      if (totalLogs == 0) {
        await db.transaction((txn) async {
        requireSameInspector(uid);
        // Backfill from pending_actions so past sync history is visible
        final pastActions = await txn.query(
          'pending_actions',
          where: 'inspector_id = ?', whereArgs: [uid],
          orderBy: 'updated_at DESC',
          limit: 50,
        );
        for (final a in pastActions) {
          final type = a['type'] as String? ?? 'action';
          final status = a['status'] as String? ?? 'synced';
          final lastError = a['last_error'] as String?;
          final updatedAt =
              a['updated_at'] as String? ??
              a['created_at'] as String? ??
              DateTime.now().toIso8601String();

          String result = 'success';
          if (status == 'failed') result = 'error';
          if (status == 'conflict') result = 'warning';
          if (status == 'pending' || status == 'syncing') result = 'info';

          String actionTitle = 'Data Sync';
          if (type == 'gps_confirm') actionTitle = 'GPS Confirmation';
          if (type == 'checklist_update') actionTitle = 'Checklist Update';
          if (type == 'submit_inspection') {
            actionTitle = 'Inspection Submission';
          }
          if (type == 'status_change') actionTitle = 'Status Update';

          final message = status == 'synced'
              ? '$actionTitle synchronized successfully.'
              : (status == 'failed'
                    ? '$actionTitle sync failed: ${lastError ?? "Network error"}'
                    : (status == 'conflict'
                          ? '$actionTitle conflict detected.'
                          : '$actionTitle queued for sync.'));

          await txn.insert('sync_log_entries', {
            'id': a['id'] ?? const Uuid().v4(),
            'inspector_id': uid,
            'pending_action_id': a['id'],
            'job_id': a['job_id'],
            'event_type': 'sync_$status',
            'result': result,
            'message': message,
            // Sanitization rule (Sync DB audit): never copy the raw outbox
            // payload here — it holds inspector notes, findings text,
            // checklist data, and photo metadata/local file paths (PII).
            // Log only non-personal action metadata.
            'technical_details': jsonEncode({
              'actionType': type,
              'retryCount': a['retry_count'] ?? 0,
              'lastError': ?lastError,
            }),
            'created_at': updatedAt,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        requireSameInspector(uid);
        });
      }
    } on StateError {
      rethrow;
    } catch (_) {}

    try {
      requireSameInspector(uid);
      final rows = await db.query(
        'sync_log_entries',
        where: 'inspector_id = ?${jobId != null ? ' AND job_id = ?' : ''}',
        whereArgs: [uid, ?jobId],
        orderBy: 'created_at DESC',
        limit: limit,
        offset: offset,
      );
      requireSameInspector(uid);
      return rows;
    } on StateError {
      rethrow;
    } catch (_) {
      return [];
    }
  }

  static Future<int> getSyncLogCount({String? jobId}) async {
    final db = await database;
    try {
      final result = await db.rawQuery(
        jobId != null
             ? 'SELECT COUNT(*) as c FROM sync_log_entries WHERE inspector_id = ? AND job_id = ?'
             : 'SELECT COUNT(*) as c FROM sync_log_entries WHERE inspector_id = ?',
        [currentInspectorId, ?jobId],
      );
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // PHASE 7 — STORAGE MANAGEMENT
  //   Shows the inspector what's actually taking up space on-device, and
  //   gives a safe way to reclaim it. Deliberately conservative about
  //   what "clearable" means:
  //     - Cached job/task data (local_jobs, local_inspections) is NEVER
  //       offered for clearing here — it's small (text/JSON) and needed
  //       for the next time the inspector opens that job, even after
  //       it's synced (rework, reference, offline re-view).
  //     - Synced `pending_actions` rows are NEVER deleted by this
  //       feature — they're the data source for the Sync Center's
  //       "Completed Audit Log" section. Clearing them here would break
  //       that feature silently.
  //     - What IS safe to clear: local photo FILES (not rows) once
  //       Supabase already has them (is_synced = 1) — the bytes are
  //       fully redundant with what's in Storage at that point. Also
  //       safe: old sync_log_entries beyond a retention window, since
  //       Phase 6's log has no natural cap and would otherwise grow
  //       forever on a long-lived install.
  // ─────────────────────────────────────────────────────────────────────

  /// Snapshot of on-device cache usage for the Storage section of the
  /// Sync Center. `clearableBytes` is specifically the synced-photo-file
  /// portion — the only thing [clearSyncedPhotoCache] actually removes.
  static Future<Map<String, dynamic>> getCacheStats() async {
    final db = await database;

    final jobsCount =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) as c FROM local_jobs WHERE inspector_id = ?', [currentInspectorId]),
        ) ??
        0;

    final syncedPhotoRows = await db.query(
      'local_photos',
      columns: ['photo_path'],
      where: 'is_synced = 1 AND inspector_id = ?',
      whereArgs: [currentInspectorId],
    );
    final unsyncedPhotoCount =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) as c FROM local_photos WHERE is_synced = 0 AND inspector_id = ?',
            [currentInspectorId],
          ),
        ) ??
        0;

    var clearableBytes = 0;
    for (final row in syncedPhotoRows) {
      final path = row['photo_path'] as String?;
      if (path == null) continue;
      try {
        final file = File(path);
        if (await file.exists()) clearableBytes += await file.length();
      } catch (_) {
        // File already gone / inaccessible — doesn't count, nothing to
        // reclaim from it.
      }
    }

    final syncLogCount = await getSyncLogCount();

    return {
      'cachedJobsCount': jobsCount,
      'syncedPhotoFileCount': syncedPhotoRows.length,
      'unsyncedPhotoFileCount': unsyncedPhotoCount,
      'clearableBytes': clearableBytes,
      'syncLogCount': syncLogCount,
    };
  }

  /// Deletes the on-disk FILE for every already-synced local photo
  /// (`is_synced = 1`), then removes those rows. Never touches photos
  /// still waiting to sync (`is_synced = 0`) — those files are the only
  /// copy that exists until they actually reach Supabase Storage.
  /// Returns the number of files actually freed, for a confirmation
  /// message ("Freed 12 photo(s), 8.4 MB").
  static Future<int> clearSyncedPhotoCache() async {
    final db = await database;
    final uid = requireInspector();
    final syncedRows = await db.query('local_photos', where: 'is_synced = 1 AND inspector_id = ?', whereArgs: [uid]);

    var cleared = 0;
    for (final row in syncedRows) {
      requireSameInspector(uid);
      final path = row['photo_path'] as String?;
      if (path == null) continue;
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
          cleared++;
        }
      } catch (_) {
        // Couldn't delete this one (permissions, already gone) — leave
        // its row alone too, rather than losing track of a file that
        // might still exist.
        continue;
      }
    }

    requireSameInspector(uid);
    await db.delete('local_photos', where: 'is_synced = 1 AND inspector_id = ?', whereArgs: [uid]);

    return cleared;
  }

  /// Keeps `sync_log_entries` from growing forever on a long-lived
  /// install — retains only the most recent [keep] entries. Called
  /// automatically at the end of every drain (see SyncOutboxService),
  /// so this is routine maintenance, not something the inspector has to
  /// think about; the manual "Clear cache" action in Storage Management
  /// additionally offers to run it on demand for an immediate size drop.
  static Future<void> pruneSyncLogEntries({int keep = 500}) async {
    final db = await database;
    final total = await getSyncLogCount();
    if (total <= keep) return;
    await db.rawDelete(
      '''
      DELETE FROM sync_log_entries
      WHERE inspector_id = ? AND id NOT IN (
        SELECT id FROM sync_log_entries WHERE inspector_id = ? ORDER BY created_at DESC LIMIT ?
      )
    ''',
      [currentInspectorId, currentInspectorId, keep],
    );
  }

  static Future<void> clearSyncLogEntries() async {
    final db = await database;
    await db.delete('sync_log_entries', where: 'inspector_id = ?', whereArgs: [currentInspectorId]);
  }
}
