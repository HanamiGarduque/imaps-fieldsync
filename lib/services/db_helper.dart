import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DBHelper {
  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  static Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'imaps_fieldsync.db');

    return await openDatabase(
      path,
      version: 5,
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
          await db.execute('ALTER TABLE local_jobs ADD COLUMN deadline_date TEXT');
          await db.execute('ALTER TABLE local_jobs ADD COLUMN is_self_scheduled INTEGER DEFAULT 0');
          await db.execute('ALTER TABLE local_jobs ADD COLUMN application_type TEXT');
        }
        if (oldVersion < 4) {
          await db.execute(_pendingActionsSchema);
        }
        if (oldVersion < 5) {
  await db.execute(
    'ALTER TABLE local_inspections ADD COLUMN current_step INTEGER DEFAULT 0'
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

  // --- LOCAL JOBS CACHING ---

  static Future<void> cacheJobs(List<Map<String, dynamic>> jobs) async {
    final db = await database;
    final batch = db.batch();

    // Clear old local jobs first before caching the latest fetched list
    batch.delete('local_jobs');

    for (final job in jobs) {
      final app = job['supabase_zoning_applications'] ?? {};
      final parcel = job['supabase_parcels'] ?? {};
      batch.insert(
        'local_jobs',
        {
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
          'parcel_lat': parcel['latitude'],
          'parcel_lng': parcel['longitude'],
          'lot_area_sqm': parcel['lot_area_sqm'],
          'declared_land_use': parcel['declared_land_use'] ?? 'Single-detached residential',
          'parcel_address': parcel['address'] ?? '',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  static Future<List<Map<String, dynamic>>> getCachedJobs() async {
    final db = await database;
    return await db.query('local_jobs');
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
    await db.insert(
      'local_inspections',
      {
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
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
    await db.insert(
      'local_photos',
      {
        'id': photoId,
        'job_id': jobId,
        'photo_path': photoPath,
        'notes': notes,
        'latitude': latitude,
        'longitude': longitude,
        'captured_at': DateTime.now().toIso8601String(),
        'is_synced': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
    await db.insert(
      'pending_actions',
      {
        'id': id,
        'type': type,
        'job_id': jobId,
        'payload': jsonEncode(payload),
        'status': 'pending',
        'retry_count': 0,
        'last_error': null,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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

  static Future<int> getPendingActionsCount() async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM pending_actions WHERE status IN ('pending', 'failed')",
    );
    return Sqflite.firstIntValue(result) ?? 0;
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
  static Future<List<Map<String, dynamic>>> getRecentSyncedActions({int limit = 20}) async {
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
}