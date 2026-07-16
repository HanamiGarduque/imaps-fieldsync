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
      version: 2,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Existing installs won't have this column yet — add it so
          // drafts saved before this fix don't crash on read/write.
          await db.execute(
            'ALTER TABLE local_inspections ADD COLUMN inspection_result TEXT',
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
            supabase_parcel_id TEXT,
            applicant_name TEXT,
            barangay TEXT,
            reference_number TEXT,
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
      },
    );
  }

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
          'supabase_parcel_id': job['supabase_parcel_id'],
          'applicant_name': app['applicant_name'] ?? 'Unknown Applicant',
          'barangay': app['barangay'] ?? 'No barangay listed',
          'reference_number': app['reference_number'] ?? '',
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
}