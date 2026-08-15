import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../modules/auth_startup/services/secure_prefs_service.dart';

class DBHelper {
  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
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
  static Future<void> _migrateLegacyPlaintextDb(String path, String password) async {
    debugPrint('[DB] Legacy unencrypted database detected — migrating to SQLCipher.');
    final plainDb = await openDatabase(path);
    final tmpPath = '$path.encrypting_tmp';
    final tmpFile = File(tmpPath);
    if (await tmpFile.exists()) {
      // Leftover from a previous interrupted attempt — start clean.
      await tmpFile.delete();
    }

    try {
      await plainDb.execute("ATTACH DATABASE '$tmpPath' AS encrypted KEY '$password'");
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
      version: 8,
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
      },
      onCreate: (db, version) async {
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
            cached_updated_at TEXT,
            rework_started_at TEXT,
            parcel_lat REAL,
            parcel_lng REAL,
            lot_area_sqm REAL,
            declared_land_use TEXT,
            parcel_address TEXT
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
            is_synced INTEGER DEFAULT 0,
            updated_at TEXT
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
      },
    );
  }

  static const String _pendingActionsSchema = '''
    CREATE TABLE pending_actions(
      id TEXT PRIMARY KEY,
      type TEXT NOT NULL,
      job_id TEXT NOT NULL,
      payload TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      retry_count INTEGER NOT NULL DEFAULT 0,
      last_error TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
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
    CREATE TABLE sync_log_entries(
      id TEXT PRIMARY KEY,
      pending_action_id TEXT,
      job_id TEXT,
      event_type TEXT NOT NULL,
      result TEXT NOT NULL,
      message TEXT NOT NULL,
      technical_details TEXT,
      created_at TEXT NOT NULL
    )
  ''';

  // --- LOCAL JOBS CACHING ---

  static Future<void> cacheJobs(List<Map<String, dynamic>> jobs) async {
    final db = await database;
    final batch = db.batch();

    // Clear old local jobs first before caching the latest fetched list
    batch.delete('local_jobs');

    for (final job in jobs) {
      final app = job['supabase_zoning_applications'] ?? {};
      final parcel = job['supabase_parcels'] ?? {};
      batch.insert('local_jobs', {
        'id': job['id'],
        'local_inspection_id': job['local_inspection_id'],
        'status': job['status'],
        'scheduled_date': job['scheduled_date'],
        'deadline_date': job['deadline_date'],
        'is_self_scheduled': (job['is_self_scheduled'] == true) ? 1 : 0,
        'supabase_parcel_id': job['supabase_parcel_id'],
        'applicant_name': app['applicant_name'] ?? 'Unknown Applicant',
        'barangay': app['barangay'] ?? 'No barangay listed',
        'reference_number': app['reference_number'] ?? '',
        'application_type': app['application_type'],
        'cached_updated_at': job['updated_at'],
        'rework_started_at': job['rework_started_at'],
        'parcel_lat': parcel['latitude'],
        'parcel_lng': parcel['longitude'],
        'lot_area_sqm': parcel['lot_area_sqm'],
        'declared_land_use':
            parcel['declared_land_use'] ?? 'Single-detached residential',
        'parcel_address': parcel['address'] ?? '',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  static Future<List<Map<String, dynamic>>> getCachedJobs() async {
    final db = await database;
    return await db.query('local_jobs');
  }

  static Future<String?> getCachedJobUpdatedAt(String jobId) async {
    final db = await database;
    final rows = await db.query(
      'local_jobs',
      columns: ['cached_updated_at'],
      where: 'id = ?',
      whereArgs: [jobId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final value = rows.first['cached_updated_at'];
    return value == null ? null : value.toString();
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
    final db = await database;
    await db.insert('local_inspections', {
      'id': jobId,
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
  }

  static Future<Map<String, dynamic>?> getLocalInspection(String jobId) async {
    final db = await database;
    final results = await db.query(
      'local_inspections',
      where: 'id = ?',
      whereArgs: [jobId],
    );
    if (results.isEmpty) return null;
    return results.first;
  }

  static Future<List<Map<String, dynamic>>> getPendingInspections() async {
    final db = await database;
    return await db.query('local_inspections', where: 'is_synced = 0');
  }

  static Future<void> markInspectionSynced(String jobId) async {
    final db = await database;
    await db.update(
      'local_inspections',
      {'is_synced': 1},
      where: 'id = ?',
      whereArgs: [jobId],
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
    final db = await database;
    await db.insert('local_photos', {
      'id': photoId,
      'job_id': jobId,
      'photo_path': photoPath,
      'notes': notes,
      'latitude': latitude,
      'longitude': longitude,
      'captured_at': DateTime.now().toIso8601String(),
      'is_synced': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<Map<String, dynamic>>> getLocalPhotos(String jobId) async {
    final db = await database;
    return await db.query(
      'local_photos',
      where: 'job_id = ?',
      whereArgs: [jobId],
    );
  }

  static Future<List<Map<String, dynamic>>> getPendingPhotos() async {
    final db = await database;
    return await db.query('local_photos', where: 'is_synced = 0');
  }

  static Future<void> markPhotoSynced(String photoId) async {
    final db = await database;
    await db.update(
      'local_photos',
      {'is_synced': 1},
      where: 'id = ?',
      whereArgs: [photoId],
    );
  }

  /// Removes one photo's row from local_photos, if it was ever persisted
  /// there. Added alongside the "remove photo" feature on the Photos step
  /// — a photo the inspector removes before submitting was previously
  /// impossible to un-persist, since local_photos had no delete path at
  /// all (only insert-or-replace and mark-synced). Safe to call even if
  /// the photo was never saved to SQLite yet (in-memory only) — deletes
  /// zero rows in that case.
  static Future<void> deleteLocalPhoto(String photoId) async {
    final db = await database;
    await db.delete('local_photos', where: 'id = ?', whereArgs: [photoId]);
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
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.insert('pending_actions', {
      'id': id,
      'type': type,
      'job_id': jobId,
      'payload': jsonEncode(payload),
      'status': 'pending',
      'retry_count': 0,
      'last_error': null,
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Rows ready to (re)try — pending or previously-failed, oldest first so
  /// actions sync in the order they happened.
  static Future<List<Map<String, dynamic>>> getActionableActions() async {
    final db = await database;
    return await db.query(
      'pending_actions',
      where: "status IN ('pending', 'failed')",
      orderBy: 'created_at ASC',
    );
  }

  static Future<List<Map<String, dynamic>>> getSyncCenterQueueActions() async {
    final db = await database;
    return await db.query(
      'pending_actions',
      where: "status IN ('pending', 'failed', 'syncing', 'conflict')",
      orderBy: 'created_at ASC',
    );
  }

  static Future<int> getPendingActionsCount() async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM pending_actions WHERE status IN ('pending', 'failed', 'conflict')",
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Known Issue #4 (AUTH_SECURITY_MASTER_DOC.md §17) — clears every
  /// locally-cached inspection-related table. This is a low-level
  /// primitive only: it does NOT check for unsynced pending work first —
  /// that safety check belongs to the caller (see
  /// LocalDataGuardService.reconcileLocalDataOwnership), which must never
  /// call this while getPendingActionsCount() > 0, or real unsynced field
  /// inspection work would be destroyed permanently. Deliberately clears
  /// rows rather than deleting the database file itself, so the SQLCipher
  /// encryption key/setup is untouched.
  static Future<void> wipeAllLocalData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('local_jobs');
      await txn.delete('local_inspections');
      await txn.delete('local_photos');
      await txn.delete('pending_actions');
      await txn.delete('sync_log_entries');
    });
    debugPrint('[DB] wipeAllLocalData: all local inspection tables cleared.');
  }

  static Future<void> markActionSyncing(String id) async {
    final db = await database;
    await db.update(
      'pending_actions',
      {'status': 'syncing', 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
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
      where: 'id = ?',
      whereArgs: [id],
    );
    await db.rawDelete('''
      DELETE FROM pending_actions
      WHERE status = 'synced' AND id NOT IN (
        SELECT id FROM pending_actions WHERE status = 'synced'
        ORDER BY updated_at DESC LIMIT 50
      )
    ''');
  }

  /// Real completed-sync history for the Sync Center's audit log —
  /// replaces the old screen's hardcoded rows.
  static Future<List<Map<String, dynamic>>> getRecentSyncedActions({
    int limit = 20,
  }) async {
    final db = await database;
    return await db.query(
      'pending_actions',
      where: "status = 'synced'",
      orderBy: 'updated_at DESC',
      limit: limit,
    );
  }

  static Future<void> markActionFailed(String id, String error) async {
    final db = await database;
    await db.rawUpdate(
      "UPDATE pending_actions SET status = 'failed', retry_count = retry_count + 1, "
      "last_error = ?, updated_at = ? WHERE id = ?",
      [error, DateTime.now().toIso8601String(), id],
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
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> markActionForceSync(String id) async {
    final db = await database;
    final rows = await db.query(
      'pending_actions',
      columns: ['payload'],
      where: 'id = ?',
      whereArgs: [id],
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
      where: 'id = ?',
      whereArgs: [id],
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
    final db = await database;
    await db.insert('sync_log_entries', {
      'id': const Uuid().v4(),
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
  }

  /// Paginated, newest-first fetch — the Notifications "Sync" tab loads
  /// this in pages (default 20) instead of the whole table at once, so a
  /// long-lived install with thousands of entries stays fast to open.
  static Future<List<Map<String, dynamic>>> getSyncLogEntries({
    int limit = 20,
    int offset = 0,
    String? jobId,
  }) async {
    final db = await database;
    return db.query(
      'sync_log_entries',
      where: jobId != null ? 'job_id = ?' : null,
      whereArgs: jobId != null ? [jobId] : null,
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
  }

  static Future<int> getSyncLogCount({String? jobId}) async {
    final db = await database;
    final result = await db.rawQuery(
      jobId != null
          ? 'SELECT COUNT(*) as c FROM sync_log_entries WHERE job_id = ?'
          : 'SELECT COUNT(*) as c FROM sync_log_entries',
      jobId != null ? [jobId] : null,
    );
    return Sqflite.firstIntValue(result) ?? 0;
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

    final jobsCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) as c FROM local_jobs'),
        ) ??
        0;

    final syncedPhotoRows = await db.query(
      'local_photos',
      columns: ['photo_path'],
      where: 'is_synced = 1',
    );
    final unsyncedPhotoCount = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) as c FROM local_photos WHERE is_synced = 0',
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
    final syncedRows = await db.query(
      'local_photos',
      where: 'is_synced = 1',
    );

    var cleared = 0;
    for (final row in syncedRows) {
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

    await db.delete('local_photos', where: 'is_synced = 1');

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
    await db.rawDelete('''
      DELETE FROM sync_log_entries
      WHERE id NOT IN (
        SELECT id FROM sync_log_entries ORDER BY created_at DESC LIMIT ?
      )
    ''', [keep]);
  }
}