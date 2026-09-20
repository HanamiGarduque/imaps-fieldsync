import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/supabase_service.dart';
import 'package:imaps_fieldsync/core/services/sync_outbox_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  const baseTime = '2026-01-01T00:00:00Z';

  Future<void> runScenario({
    required bool localFileExists,
    required List<int>? initialStorageBytes,
    required String initialRemoteUpdatedAt,
    Map<String, dynamic>? Function(
      String photoId,
      String object,
      String publicUrl,
    )?
    metadataBuilder,
    required String queuedSnapshotUpdatedAt,
    required String expectedStatus,
    required int expectedUploads,
    required int expectedInserts,
    required int expectedPatches,
    String actionType = 'photos_update',
    String actionId = 'photos_a',
    List<int>? localFileBytes,
    Map<String, dynamic>? remoteJobOverrides,
  }) async {
    final overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    SyncOutboxService.resetRecoverySessionForTesting();
    final temp = await Directory.systemTemp.createTemp('r4-photo-');
    final file = File('${temp.path}/evidence.jpg');
    if (localFileExists) {
      await file.writeAsBytes(localFileBytes ?? [1, 2, 3]);
    }
    final key = base64Url.encode(utf8.encode(file.path)).replaceAll('=', '');
    final object = 'inspections/a/photo_$key.jpg';
    final photoId = const Uuid().v5(
      '6ba7b811-9dad-11d1-80b4-00c04fd430c8',
      object,
    );
    const base = '2026-01-01T00:00:00Z';
    var job = <String, dynamic>{
      'id': 'a',
      'assigned_inspector_id': 'inspector',
      'status': 'in_progress',
      'updated_at': initialRemoteUpdatedAt,
      'photo_paths': <String>[],
      'photo_count': 0,
      ...?remoteJobOverrides,
    };
    var uploads = 0;
    var inserts = 0;
    var patches = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final publicUrl =
        'http://127.0.0.1:${server.port}/storage/v1/object/public/inspection-photos/$object';
    final metadata = metadataBuilder?.call(photoId, object, publicUrl);
    var storageBytes = initialStorageBytes;

    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/rest/v1/field_jobs') {
        if (request.method == 'PATCH') {
          patches++;
          job = {
            ...job,
            ...jsonDecode(body) as Map<String, dynamic>,
            'updated_at': '2026-01-02T00:00:00Z',
          };
        }
        request.response.write(
          jsonEncode(request.method == 'PATCH' ? job : [job]),
        );
      } else if (request.uri.path == '/rest/v1/field_job_photos') {
        if (request.method == 'GET') {
          request.response.write(
            jsonEncode(metadata == null ? [] : [metadata]),
          );
        } else {
          inserts++;
          final inserted = Map<String, dynamic>.from(jsonDecode(body) as Map);
          request.response.statusCode = 201;
          request.response.write(jsonEncode(inserted));
        }
      } else if (request.uri.path == '/rest/v1/activity_log') {
        request.response.statusCode = 201;
        request.response.write('[]');
      } else if (request.uri.path.startsWith('/storage/v1/object/')) {
        if (request.method == 'GET') {
          if (storageBytes == null) {
            request.response.statusCode = 404;
            request.response.write(
              jsonEncode({'statusCode': '404', 'error': 'Not Found'}),
            );
          } else {
            request.response.headers.contentType = ContentType.binary;
            request.response.add(storageBytes!);
          }
        } else {
          uploads++;
          storageBytes = localFileBytes ?? [1, 2, 3];
          request.response.write('{"Key": "inspection-photos/$object"}');
        }
      }
      await request.response.close();
    });

    final db = await databaseFactoryFfi.openDatabase('${temp.path}/test.db');
    try {
      final source = await File(
        'lib/core/services/db_helper.dart',
      ).readAsString();
      for (final m in RegExp(
        r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)',
      ).allMatches(source)) {
        await db.execute(m.group(0)!);
      }
      DBHelper.useDatabaseForTesting(db);
      await Supabase.initialize(
        url: 'http://127.0.0.1:${server.port}',
        publishableKey: 'fixture',
        authOptions: FlutterAuthClientOptions(
          autoRefreshToken: false,
          detectSessionInUri: false,
          localStorage: EmptyLocalStorage(),
        ),
      );
      await SupabaseService.client.auth.setInitialSession(
        jsonEncode({
          'access_token': 'fixt',
          'refresh_token': 'fixt',
          'token_type': 'bearer',
          'expires_in': 3600,
          'user': {'id': 'inspector', 'aud': 'authenticated'},
        }),
      );

      final photoPayload = {
        'photoPath': file.path,
        'notes': 'fixture',
        'latitude': null,
        'longitude': null,
        'capturedAt': base,
      };
      var payload = <String, dynamic>{
        'cachedUpdatedAtSnapshot': queuedSnapshotUpdatedAt,
        'photos': [photoPayload],
      };
      if (actionType == 'submit_inspection') {
        payload = {
          'cachedUpdatedAtSnapshot': queuedSnapshotUpdatedAt,
          'photosData': [photoPayload],
          'findings': 'test',
          'isCompliant': true,
          'inspectionResult': 'Compliant',
          'observations': 'obs',
          'discrepancies': null,
          'recommendations': null,
          'inspectorNotes': 'notes',
          'checklistCompletedCount': 0,
          'checklistTotalCount': 0,
          'checklistData': <dynamic>[],
        };
      }

      await db.insert('pending_actions', {
        'id': actionId,
        'type': actionType,
        'job_id': 'a',
        'status': 'syncing',
        'retry_count': 0,
        'created_at': base,
        'updated_at': base,
        'payload': jsonEncode({...payload, 'r4RecoveryRequired': true}),
      });
      await SyncOutboxService.drain();
      expect(
        (await db.query('pending_actions')).single['status'],
        expectedStatus,
      );
      expect(uploads, expectedUploads);
      expect(inserts, expectedInserts);
      expect(patches, expectedPatches);
      if (expectedStatus == 'synced') {
        final pp = patches, pu = uploads, pi = inserts;
        await SyncOutboxService.drain();
        expect(patches, pp);
        expect(uploads, pu);
        expect(inserts, pi);
      }
    } finally {
      DBHelper.useDatabaseForTesting(null);
      await db.close();
      await Supabase.instance.dispose();
      await server.close(force: true);
      await temp.delete(recursive: true);
      HttpOverrides.global = overrides;
      SyncOutboxService.resetRecoverySessionForTesting();
    }
  }

  test(
    'Case A: Storage Present + Metadata Present -> 0 uploads, 0 inserts, 1 patch (synced)',
    () async {
      await runScenario(
        localFileExists: true,
        initialStorageBytes: [1, 2, 3],
        metadataBuilder: (p, o, u) => {
          'id': p,
          'field_job_id': 'a',
          'photo_url': u,
          'latitude': null,
          'longitude': null,
          'captured_at': baseTime,
          'notes': 'fixture',
        },
        initialRemoteUpdatedAt: baseTime,
        queuedSnapshotUpdatedAt: baseTime,
        expectedStatus: 'synced',
        expectedUploads: 0,
        expectedInserts: 0,
        expectedPatches: 1,
      );
    },
  );
  test(
    'Case B: Storage Present + Metadata Missing -> 0 uploads, 1 insert, 1 patch (synced)',
    () async {
      await runScenario(
        localFileExists: true,
        initialStorageBytes: [1, 2, 3],
        metadataBuilder: null,
        initialRemoteUpdatedAt: baseTime,
        queuedSnapshotUpdatedAt: baseTime,
        expectedStatus: 'synced',
        expectedUploads: 0,
        expectedInserts: 1,
        expectedPatches: 1,
      );
    },
  );
  test(
    'Case C: Storage Present + Metadata Differing -> 0 uploads, 0 inserts, 0 patches (conflict)',
    () async {
      await runScenario(
        localFileExists: true,
        initialStorageBytes: [1, 2, 3],
        metadataBuilder: (p, o, u) => {
          'id': p,
          'field_job_id': 'a',
          'photo_url': u,
          'latitude': 14.5,
          'longitude': 120.9,
          'captured_at': baseTime,
          'notes': 'diff',
        },
        initialRemoteUpdatedAt: baseTime,
        queuedSnapshotUpdatedAt: baseTime,
        expectedStatus: 'conflict',
        expectedUploads: 0,
        expectedInserts: 0,
        expectedPatches: 0,
      );
    },
  );
  test(
    'Case D: Storage Missing + Local File Missing -> 0 uploads, 0 inserts, 0 patches (conflict)',
    () async {
      await runScenario(
        localFileExists: false,
        initialStorageBytes: null,
        metadataBuilder: null,
        initialRemoteUpdatedAt: baseTime,
        queuedSnapshotUpdatedAt: baseTime,
        expectedStatus: 'conflict',
        expectedUploads: 0,
        expectedInserts: 0,
        expectedPatches: 0,
      );
    },
  );
  test(
    'Case E: Storage Missing + Metadata Missing -> 1 upload, 1 insert, 1 patch (synced)',
    () async {
      await runScenario(
        localFileExists: true,
        initialStorageBytes: null,
        metadataBuilder: null,
        initialRemoteUpdatedAt: baseTime,
        queuedSnapshotUpdatedAt: baseTime,
        expectedStatus: 'synced',
        expectedUploads: 1,
        expectedInserts: 1,
        expectedPatches: 1,
      );
    },
  );
  test(
    'Case F: Storage Missing + Outdated Durable Base -> 0 uploads, 0 inserts, 0 patches (conflict)',
    () async {
      await runScenario(
        localFileExists: true,
        initialStorageBytes: null,
        metadataBuilder: null,
        initialRemoteUpdatedAt: '2026-01-05T00:00:00Z',
        queuedSnapshotUpdatedAt: baseTime,
        expectedStatus: 'conflict',
        expectedUploads: 0,
        expectedInserts: 0,
        expectedPatches: 0,
      );
    },
  );
  test(
    'missing object + matching metadata + local file present -> 1 upload, 0 inserts, 1 patch (synced)',
    () async {
      await runScenario(
        localFileExists: true,
        initialStorageBytes: null,
        metadataBuilder: (p, o, u) => {
          'id': p,
          'field_job_id': 'a',
          'photo_url': u,
          'latitude': null,
          'longitude': null,
          'captured_at': baseTime,
          'notes': 'fixture',
        },
        initialRemoteUpdatedAt: baseTime,
        queuedSnapshotUpdatedAt: baseTime,
        expectedStatus: 'synced',
        expectedUploads: 1,
        expectedInserts: 0,
        expectedPatches: 1,
      );
    },
  );
  test('missing object + differing metadata -> conflict, 0 uploads', () async {
    await runScenario(
      localFileExists: true,
      initialStorageBytes: null,
      metadataBuilder: (p, o, u) => {
        'id': p,
        'field_job_id': 'a',
        'photo_url': u,
        'latitude': 14.5,
        'longitude': 120.9,
        'captured_at': baseTime,
        'notes': 'diff',
      },
      initialRemoteUpdatedAt: baseTime,
      queuedSnapshotUpdatedAt: baseTime,
      expectedStatus: 'conflict',
      expectedUploads: 0,
      expectedInserts: 0,
      expectedPatches: 0,
    );
  });
  test(
    'submit_inspection photo subroutine parity: Case E (object absent, metadata absent, local present)',
    () async {
      await runScenario(
        localFileExists: true,
        initialStorageBytes: null,
        metadataBuilder: null,
        initialRemoteUpdatedAt: baseTime,
        queuedSnapshotUpdatedAt: baseTime,
        actionType: 'submit_inspection',
        actionId: 'submit_a',
        expectedStatus: 'synced',
        expectedUploads: 1,
        expectedInserts: 1,
        expectedPatches: 1,
      );
    },
  );
  test(
    'historical URL and object path identity equivalence in extractStorageObjectPath',
    () {
      const jobId = '11111111-1111-4111-8111-111111111111';
      const localPath = '/data/user/0/com.app/cache/photo.jpg';
      final objectPath = SupabaseService.photoStoragePath(jobId, localPath);

      final publicUrl =
          'https://proj.supabase.co/storage/v1/object/public/inspection-photos/$objectPath';
      expect(
        SupabaseService.extractStorageObjectPath(publicUrl),
        equals(objectPath),
      );

      final authUrl =
          'https://proj.supabase.co/storage/v1/object/authenticated/inspection-photos/$objectPath';
      expect(
        SupabaseService.extractStorageObjectPath(authUrl),
        equals(objectPath),
      );

      expect(
        SupabaseService.extractStorageObjectPath(objectPath),
        equals(objectPath),
      );
      expect(
        SupabaseService.extractStorageObjectPath(
          'https://proj.supabase.co/storage/v1/object/public/avatars/$objectPath',
        ),
        isNull,
      );
      expect(
        SupabaseService.extractStorageObjectPath(
          'inspections/$jobId/../other.jpg',
        ),
        isNull,
      );
      expect(SupabaseService.extractStorageObjectPath(''), isNull);
    },
  );
  test(
    'deterministic identity: same job + local path -> same storage path and UUID',
    () {
      const p1 = '/path/to/local/photo.jpg';
      final k1 = SupabaseService.stablePhotoKey(p1);
      final sp1 = SupabaseService.photoStoragePath('jobA', p1);
      final id1 = SupabaseService.photoRowId(sp1);

      expect(SupabaseService.stablePhotoKey(p1), equals(k1));
      expect(SupabaseService.photoStoragePath('jobA', p1), equals(sp1));
      expect(SupabaseService.photoRowId(sp1), equals(id1));

      final sp2 = SupabaseService.photoStoragePath('jobB', p1);
      expect(sp2, isNot(equals(sp1)));
      expect(SupabaseService.photoRowId(sp2), isNot(equals(id1)));
    },
  );
  test('no duplicate metadata ID: UUID v5 is deterministic', () {
    const ns = '6ba7b811-9dad-11d1-80b4-00c04fd430c8';
    const path1 = 'inspections/job1/photo_123.jpg';
    final id1 = const Uuid().v5(ns, path1);
    final id2 = const Uuid().v5(ns, path1);
    expect(id1, equals(id2));
    expect(id1, equals(SupabaseService.photoRowId(path1)));
  });
  test('satisfied job references -> zero PATCH', () async {
    final overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    SyncOutboxService.resetRecoverySessionForTesting();
    final temp = await Directory.systemTemp.createTemp('r4-sat-');
    final file = File('${temp.path}/evidence.jpg')..writeAsBytesSync([1, 2, 3]);
    final key = base64Url.encode(utf8.encode(file.path)).replaceAll('=', '');
    final object = 'inspections/a/photo_$key.jpg';
    final photoId = const Uuid().v5(
      '6ba7b811-9dad-11d1-80b4-00c04fd430c8',
      object,
    );

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final publicUrl =
        'http://127.0.0.1:${server.port}/storage/v1/object/public/inspection-photos/$object';
    var patches = 0;
    final job = <String, dynamic>{
      'id': 'a',
      'assigned_inspector_id': 'inspector',
      'status': 'in_progress',
      'updated_at': baseTime,
      'photo_paths': [publicUrl],
      'photo_count': 1,
    };
    final metadata = {
      'id': photoId,
      'field_job_id': 'a',
      'photo_url': publicUrl,
      'latitude': null,
      'longitude': null,
      'captured_at': baseTime,
      'notes': 'fixture',
    };

    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/rest/v1/field_jobs') {
        if (request.method == 'PATCH') {
          patches++;
        }
        request.response.write(
          jsonEncode(request.method == 'PATCH' ? job : [job]),
        );
      } else if (request.uri.path == '/rest/v1/field_job_photos') {
        request.response.write(jsonEncode([metadata]));
      } else if (request.uri.path.startsWith('/storage/v1/object/')) {
        request.response.headers.contentType = ContentType.binary;
        request.response.add([1, 2, 3]);
      }
      await request.response.close();
    });

    final db = await databaseFactoryFfi.openDatabase('${temp.path}/test.db');
    try {
      final source = await File(
        'lib/core/services/db_helper.dart',
      ).readAsString();
      for (final m in RegExp(
        r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)',
      ).allMatches(source)) {
        await db.execute(m.group(0)!);
      }
      DBHelper.useDatabaseForTesting(db);
      await Supabase.initialize(
        url: 'http://127.0.0.1:${server.port}',
        publishableKey: 'fixture',
        authOptions: FlutterAuthClientOptions(
          autoRefreshToken: false,
          detectSessionInUri: false,
          localStorage: EmptyLocalStorage(),
        ),
      );
      await SupabaseService.client.auth.setInitialSession(
        jsonEncode({
          'access_token': 'fixt',
          'refresh_token': 'fixt',
          'token_type': 'bearer',
          'expires_in': 3600,
          'user': {'id': 'inspector', 'aud': 'authenticated'},
        }),
      );

      await db.insert('pending_actions', {
        'id': 'photos_a',
        'type': 'photos_update',
        'job_id': 'a',
        'status': 'syncing',
        'retry_count': 0,
        'created_at': baseTime,
        'updated_at': baseTime,
        'payload': jsonEncode({
          'cachedUpdatedAtSnapshot': baseTime,
          'r4RecoveryRequired': true,
          'photos': [
            {
              'photoPath': file.path,
              'notes': 'fixture',
              'latitude': null,
              'longitude': null,
              'capturedAt': baseTime,
            },
          ],
        }),
      });
      await SyncOutboxService.drain();
      expect((await db.query('pending_actions')).single['status'], 'synced');
      expect(
        patches,
        0,
        reason: 'Satisfied job references must not issue PATCH',
      );
    } finally {
      DBHelper.useDatabaseForTesting(null);
      await db.close();
      await Supabase.instance.dispose();
      await server.close(force: true);
      await temp.delete(recursive: true);
      HttpOverrides.global = overrides;
      SyncOutboxService.resetRecoverySessionForTesting();
    }
  });
  test('zero-row conditional PATCH -> conflict', () async {
    final overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    SyncOutboxService.resetRecoverySessionForTesting();
    final temp = await Directory.systemTemp.createTemp('r4-zr-');
    final file = File('${temp.path}/evidence.jpg')..writeAsBytesSync([1, 2, 3]);
    final key = base64Url.encode(utf8.encode(file.path)).replaceAll('=', '');
    final object = 'inspections/a/photo_$key.jpg';

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/rest/v1/field_jobs') {
        if (request.method == 'PATCH') {
          request.response.write('null');
        } else {
          request.response.write(
            jsonEncode([
              {
                'id': 'a',
                'assigned_inspector_id': 'inspector',
                'status': 'in_progress',
                'updated_at': baseTime,
                'photo_paths': <String>[],
                'photo_count': 0,
              },
            ]),
          );
        }
      } else if (request.uri.path == '/rest/v1/field_job_photos') {
        request.response.statusCode = 201;
        request.response.write('[]');
      } else if (request.uri.path.startsWith('/storage/v1/object/')) {
        if (request.method == 'GET') {
          request.response.statusCode = 404;
          request.response.write(
            jsonEncode({'statusCode': '404', 'error': 'Not Found'}),
          );
        } else {
          request.response.write('{"Key": "inspection-photos/$object"}');
        }
      }
      await request.response.close();
    });

    final db = await databaseFactoryFfi.openDatabase('${temp.path}/test.db');
    try {
      final source = await File(
        'lib/core/services/db_helper.dart',
      ).readAsString();
      for (final m in RegExp(
        r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)',
      ).allMatches(source)) {
        await db.execute(m.group(0)!);
      }
      DBHelper.useDatabaseForTesting(db);
      await Supabase.initialize(
        url: 'http://127.0.0.1:${server.port}',
        publishableKey: 'fixture',
        authOptions: FlutterAuthClientOptions(
          autoRefreshToken: false,
          detectSessionInUri: false,
          localStorage: EmptyLocalStorage(),
        ),
      );
      await SupabaseService.client.auth.setInitialSession(
        jsonEncode({
          'access_token': 'fixt',
          'refresh_token': 'fixt',
          'token_type': 'bearer',
          'expires_in': 3600,
          'user': {'id': 'inspector', 'aud': 'authenticated'},
        }),
      );

      await db.insert('pending_actions', {
        'id': 'photos_a',
        'type': 'photos_update',
        'job_id': 'a',
        'status': 'syncing',
        'retry_count': 0,
        'created_at': baseTime,
        'updated_at': baseTime,
        'payload': jsonEncode({
          'cachedUpdatedAtSnapshot': baseTime,
          'r4RecoveryRequired': true,
          'photos': [
            {
              'photoPath': file.path,
              'notes': 'fixture',
              'latitude': null,
              'longitude': null,
              'capturedAt': baseTime,
            },
          ],
        }),
      });
      await SyncOutboxService.drain();
      expect((await db.query('pending_actions')).single['status'], 'conflict');
    } finally {
      DBHelper.useDatabaseForTesting(null);
      await db.close();
      await Supabase.instance.dispose();
      await server.close(force: true);
      await temp.delete(recursive: true);
      HttpOverrides.global = overrides;
      SyncOutboxService.resetRecoverySessionForTesting();
    }
  });
  test('r4RecoveryRequired marker does not discard original payload', () async {
    final tempDir = await Directory.systemTemp.createTemp('r4v2-marker-');
    final file = File('${tempDir.path}/test.jpg')..writeAsBytesSync([1]);
    final db = await databaseFactoryFfi.openDatabase('${tempDir.path}/test.db');
    final source = await File(
      'lib/core/services/db_helper.dart',
    ).readAsString();
    for (final m in RegExp(
      r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)',
    ).allMatches(source)) {
      await db.execute(m.group(0)!);
    }
    DBHelper.useDatabaseForTesting(db);
    final pl = {
      'cachedUpdatedAtSnapshot': baseTime,
      'photos': [
        {
          'photoPath': file.path,
          'notes': 'my note',
          'latitude': 14.5,
          'longitude': 120.9,
          'capturedAt': baseTime,
        },
      ],
    };
    await db.insert('pending_actions', {
      'id': 'photos_a',
      'type': 'photos_update',
      'job_id': 'a',
      'status': 'syncing',
      'retry_count': 0,
      'created_at': baseTime,
      'updated_at': baseTime,
      'payload': jsonEncode(pl),
    });
    await DBHelper.recoverAbandonedClaims();
    final row = (await db.query('pending_actions')).single;
    expect(row['status'], 'failed');
    final rec = jsonDecode(row['payload'] as String);
    expect(rec['r4RecoveryRequired'], isTrue);
    expect(rec['cachedUpdatedAtSnapshot'], baseTime);
    expect(rec['photos'][0]['photoPath'], file.path);
    expect(rec['photos'][0]['notes'], 'my note');
    DBHelper.useDatabaseForTesting(null);
    await db.close();
    await tempDir.delete(recursive: true);
  });
  test(
    'photos_update job isolation: recovery for job A does not affect job B',
    () async {
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({});
      SyncOutboxService.resetRecoverySessionForTesting();
      final temp = await Directory.systemTemp.createTemp('r4-iso-');
      final file = File('${temp.path}/evidence.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      final key = base64Url.encode(utf8.encode(file.path)).replaceAll('=', '');
      final objectA = 'inspections/a/photo_$key.jpg';
      var patchesB = 0;

      final jobA = {
        'id': 'a',
        'assigned_inspector_id': 'inspector',
        'status': 'in_progress',
        'updated_at': baseTime,
        'photo_paths': <String>[],
        'photo_count': 0,
      };
      final jobB = {
        'id': 'b',
        'assigned_inspector_id': 'inspector',
        'status': 'in_progress',
        'updated_at': baseTime,
        'photo_paths': <String>[],
        'photo_count': 0,
      };

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path == '/rest/v1/field_jobs') {
          final qs = request.uri.queryParameters;
          if (request.method == 'PATCH' && qs['id']?.contains('b') == true) {
            patchesB++;
          }
          final isA = (qs['id'] ?? '').contains('a');
          request.response.write(
            jsonEncode(
              request.method == 'PATCH'
                  ? (isA ? jobA : jobB)
                  : [isA ? jobA : jobB],
            ),
          );
        } else if (request.uri.path == '/rest/v1/field_job_photos') {
          request.response.statusCode = 201;
          request.response.write('[]');
        } else if (request.uri.path.startsWith('/storage/v1/object/')) {
          if (request.method == 'GET') {
            request.response.statusCode = 404;
            request.response.write(
              jsonEncode({'statusCode': '404', 'error': 'Not Found'}),
            );
          } else {
            request.response.write('{"Key": "inspection-photos/$objectA"}');
          }
        }
        await request.response.close();
      });

      final db = await databaseFactoryFfi.openDatabase('${temp.path}/test.db');
      try {
        final source = await File(
          'lib/core/services/db_helper.dart',
        ).readAsString();
        for (final m in RegExp(
          r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)',
        ).allMatches(source)) {
          await db.execute(m.group(0)!);
        }
        DBHelper.useDatabaseForTesting(db);
        await Supabase.initialize(
          url: 'http://127.0.0.1:${server.port}',
          publishableKey: 'fixture',
          authOptions: FlutterAuthClientOptions(
            autoRefreshToken: false,
            detectSessionInUri: false,
            localStorage: EmptyLocalStorage(),
          ),
        );
        await SupabaseService.client.auth.setInitialSession(
          jsonEncode({
            'access_token': 'fixt',
            'refresh_token': 'fixt',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {'id': 'inspector', 'aud': 'authenticated'},
          }),
        );

        await db.insert('pending_actions', {
          'id': 'photos_a',
          'type': 'photos_update',
          'job_id': 'a',
          'status': 'syncing',
          'retry_count': 0,
          'created_at': baseTime,
          'updated_at': baseTime,
          'payload': jsonEncode({
            'cachedUpdatedAtSnapshot': baseTime,
            'r4RecoveryRequired': true,
            'photos': [
              {
                'photoPath': file.path,
                'notes': 'fixture',
                'latitude': null,
                'longitude': null,
                'capturedAt': baseTime,
              },
            ],
          }),
        });
        await SyncOutboxService.drain();
        expect((await db.query('pending_actions')).single['status'], 'synced');
        expect(
          patchesB,
          0,
          reason: 'Job B must not be patched by job A recovery',
        );
      } finally {
        DBHelper.useDatabaseForTesting(null);
        await db.close();
        await Supabase.instance.dispose();
        await server.close(force: true);
        await temp.delete(recursive: true);
        HttpOverrides.global = overrides;
        SyncOutboxService.resetRecoverySessionForTesting();
      }
    },
  );
  Future<void> runFaultInjectionScenario({
    required bool failStorageFirstPass,
    required bool failMetadataFirstPass,
    required bool failPatchFirstPass,
    required int expectedPass1Uploads,
    required int expectedPass1Inserts,
    required int expectedPass1Patches,
    required int expectedPass2Uploads,
    required int expectedPass2Inserts,
    required int expectedPass2Patches,
  }) async {
    final overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    SyncOutboxService.resetRecoverySessionForTesting();
    final temp = await Directory.systemTemp.createTemp('r4-fi-');
    final file = File('${temp.path}/evidence.jpg')..writeAsBytesSync([1, 2, 3]);
    final key = base64Url.encode(utf8.encode(file.path)).replaceAll('=', '');
    final object = 'inspections/a/photo_$key.jpg';

    var uploads = 0, inserts = 0, patches = 0;
    var failStorage = failStorageFirstPass;
    var failMetadata = failMetadataFirstPass;
    var failPatch = failPatchFirstPass;
    Uint8List? storageBytes;
    Map<String, dynamic>? metadata;

    var job = <String, dynamic>{
      'id': 'a',
      'assigned_inspector_id': 'inspector',
      'status': 'in_progress',
      'updated_at': baseTime,
      'photo_paths': <String>[],
      'photo_count': 0,
    };

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      req.response.headers.contentType = ContentType.json;
      if (req.uri.path == '/rest/v1/field_jobs') {
        if (req.method == 'PATCH') {
          if (failPatch) {
            req.response.statusCode = 500;
            req.response.write('{"error":"injected patch failure"}');
          } else {
            patches++;
            job = {...job, ...jsonDecode(body) as Map<String, dynamic>, 'updated_at': '2026-01-02T00:00:00Z'};
            req.response.write(jsonEncode(job));
          }
        } else {
          req.response.write(jsonEncode([job]));
        }
      } else if (req.uri.path == '/rest/v1/field_job_photos') {
        if (req.method == 'GET') {
          req.response.write(jsonEncode(metadata == null ? [] : [metadata]));
        } else {
          if (failMetadata) {
            req.response.statusCode = 500;
            req.response.write('{"error":"injected metadata failure"}');
          } else {
            inserts++;
            metadata = Map<String, dynamic>.from(jsonDecode(body) as Map);
            req.response.statusCode = 201;
            req.response.write(jsonEncode(metadata));
          }
        }
      } else if (req.uri.path.startsWith('/storage/v1/object/')) {
        if (req.method == 'GET') {
          if (storageBytes == null) {
            req.response.statusCode = 404;
            req.response.write('{"error":"Not Found"}');
          } else {
            req.response.headers.contentType = ContentType.binary;
            req.response.add(storageBytes!);
          }
        } else {
          if (failStorage) {
            req.response.statusCode = 500;
            req.response.write('{"error":"injected storage failure"}');
          } else {
            uploads++;
            storageBytes = Uint8List.fromList([1, 2, 3]);
            req.response.write('{"Key":"inspection-photos/$object"}');
          }
        }
      }
      await req.response.close();
    });

    final db = await databaseFactoryFfi.openDatabase('${temp.path}/test.db');
    try {
      final source = await File('lib/core/services/db_helper.dart').readAsString();
      for (final m in RegExp(r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)').allMatches(source)) {
        await db.execute(m.group(0)!);
      }
      DBHelper.useDatabaseForTesting(db);
      await Supabase.initialize(
        url: 'http://127.0.0.1:${server.port}', publishableKey: 'fixture',
        authOptions: FlutterAuthClientOptions(autoRefreshToken: false, detectSessionInUri: false, localStorage: EmptyLocalStorage()),
      );
      await SupabaseService.client.auth.setInitialSession(jsonEncode({
        'access_token': 'fixt', 'refresh_token': 'fixt', 'token_type': 'bearer', 'expires_in': 3600,
        'user': {'id': 'inspector', 'aud': 'authenticated'},
      }));

      final photoPayload = {'photoPath': file.path, 'notes': 'fixture', 'latitude': null, 'longitude': null, 'capturedAt': baseTime};
      await db.insert('pending_actions', {
        'id': 'photos_a', 'type': 'photos_update', 'job_id': 'a', 'status': 'pending', 'retry_count': 0,
        'created_at': baseTime, 'updated_at': baseTime,
        'payload': jsonEncode({'cachedUpdatedAtSnapshot': baseTime, 'r4RecoveryRequired': true, 'photos': [photoPayload]}),
      });

      // Pass 1: Drain with injected failure
      await SyncOutboxService.drain();
      final p1 = (await db.query('pending_actions')).single;
      expect(p1['status'], 'failed');
      expect(p1['retry_count'], 1);
      expect(jsonDecode(p1['payload'] as String)['r4RecoveryRequired'], isTrue);
      expect(uploads, expectedPass1Uploads);
      expect(inserts, expectedPass1Inserts);
      expect(patches, expectedPass1Patches);

      // Pass 2: Clear failures and recover
      failStorage = false; failMetadata = false; failPatch = false;
      await SyncOutboxService.drain();
      final p2 = (await db.query('pending_actions')).single;
      expect(p2['status'], 'synced');
      expect(uploads, expectedPass2Uploads);
      expect(inserts, expectedPass2Inserts);
      expect(patches, expectedPass2Patches);

      // Pass 3 (FI-5): Re-drain already synced
      await SyncOutboxService.drain();
      expect((await db.query('pending_actions')).single['status'], 'synced');
      expect(uploads, expectedPass2Uploads);
      expect(inserts, expectedPass2Inserts);
      expect(patches, expectedPass2Patches);
    } finally {
      DBHelper.useDatabaseForTesting(null);
      await db.close();
      await Supabase.instance.dispose();
      await server.close(force: true);
      await temp.delete(recursive: true);
      HttpOverrides.global = overrides;
      SyncOutboxService.resetRecoverySessionForTesting();
    }
  }

  test(
    'FI-1: storage upload succeeds, metadata write fails -> fail pass 1, recover on pass 2 (synced)',
    () async {
      await runFaultInjectionScenario(
        failStorageFirstPass: false,
        failMetadataFirstPass: true,
        failPatchFirstPass: false,
        expectedPass1Uploads: 1,
        expectedPass1Inserts: 0,
        expectedPass1Patches: 0,
        expectedPass2Uploads: 1,
        expectedPass2Inserts: 1,
        expectedPass2Patches: 1,
      );
    },
  );

  test(
    'FI-2: metadata write succeeds, job patch fails -> fail pass 1, retry only guarded patch on pass 2 (synced)',
    () async {
      await runFaultInjectionScenario(
        failStorageFirstPass: false,
        failMetadataFirstPass: false,
        failPatchFirstPass: true,
        expectedPass1Uploads: 1,
        expectedPass1Inserts: 1,
        expectedPass1Patches: 0,
        expectedPass2Uploads: 1,
        expectedPass2Inserts: 1,
        expectedPass2Patches: 1,
      );
    },
  );

  test(
    'FI-3: storage upload fails before metadata -> fail pass 1, full recovery on pass 2 (synced)',
    () async {
      await runFaultInjectionScenario(
        failStorageFirstPass: true,
        failMetadataFirstPass: false,
        failPatchFirstPass: false,
        expectedPass1Uploads: 0,
        expectedPass1Inserts: 0,
        expectedPass1Patches: 0,
        expectedPass2Uploads: 1,
        expectedPass2Inserts: 1,
        expectedPass2Patches: 1,
      );
    },
  );

  test(
    'FI-5: already synced re-drain idempotency -> zero requests on re-drain',
    () async {
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({});
      SyncOutboxService.resetRecoverySessionForTesting();
      final temp = await Directory.systemTemp.createTemp('r4-fi5-');
      final file = File('${temp.path}/evidence.jpg')..writeAsBytesSync([1, 2, 3]);
      final key = base64Url.encode(utf8.encode(file.path)).replaceAll('=', '');
      final object = 'inspections/a/photo_$key.jpg';

      var uploads = 0, inserts = 0, patches = 0;
      Uint8List? storageBytes;
      Map<String, dynamic>? metadata;

      var job = <String, dynamic>{
        'id': 'a',
        'assigned_inspector_id': 'inspector',
        'status': 'in_progress',
        'updated_at': baseTime,
        'photo_paths': <String>[],
        'photo_count': 0,
      };

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final body = await utf8.decoder.bind(req).join();
        req.response.headers.contentType = ContentType.json;
        if (req.uri.path == '/rest/v1/field_jobs') {
          if (req.method == 'PATCH') {
            patches++;
            job = {...job, ...jsonDecode(body) as Map<String, dynamic>, 'updated_at': '2026-01-02T00:00:00Z'};
            req.response.write(jsonEncode(job));
          } else {
            req.response.write(jsonEncode([job]));
          }
        } else if (req.uri.path == '/rest/v1/field_job_photos') {
          if (req.method == 'GET') {
            req.response.write(jsonEncode(metadata == null ? [] : [metadata]));
          } else {
            inserts++;
            metadata = Map<String, dynamic>.from(jsonDecode(body) as Map);
            req.response.statusCode = 201;
            req.response.write(jsonEncode(metadata));
          }
        } else if (req.uri.path.startsWith('/storage/v1/object/')) {
          if (req.method == 'GET') {
            if (storageBytes == null) {
              req.response.statusCode = 404;
              req.response.write('{"error":"Not Found"}');
            } else {
              req.response.headers.contentType = ContentType.binary;
              req.response.add(storageBytes!);
            }
          } else {
            uploads++;
            storageBytes = Uint8List.fromList([1, 2, 3]);
            req.response.write('{"Key":"inspection-photos/$object"}');
          }
        }
        await req.response.close();
      });

      final db = await databaseFactoryFfi.openDatabase('${temp.path}/test.db');
      try {
        final source = await File('lib/core/services/db_helper.dart').readAsString();
        for (final m in RegExp(r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)').allMatches(source)) {
          await db.execute(m.group(0)!);
        }
        DBHelper.useDatabaseForTesting(db);
        await Supabase.initialize(
          url: 'http://127.0.0.1:${server.port}', publishableKey: 'fixture',
          authOptions: FlutterAuthClientOptions(autoRefreshToken: false, detectSessionInUri: false, localStorage: EmptyLocalStorage()),
        );
        await SupabaseService.client.auth.setInitialSession(jsonEncode({
          'access_token': 'fixt', 'refresh_token': 'fixt', 'token_type': 'bearer', 'expires_in': 3600,
          'user': {'id': 'inspector', 'aud': 'authenticated'},
        }));

        final photoPayload = {'photoPath': file.path, 'notes': 'fixture', 'latitude': null, 'longitude': null, 'capturedAt': baseTime};
        await db.insert('pending_actions', {
          'id': 'photos_a', 'type': 'photos_update', 'job_id': 'a', 'status': 'pending', 'retry_count': 0,
          'created_at': baseTime, 'updated_at': baseTime,
          'payload': jsonEncode({'cachedUpdatedAtSnapshot': baseTime, 'r4RecoveryRequired': true, 'photos': [photoPayload]}),
        });

        // Pass 1: Drain to synced
        await SyncOutboxService.drain();
        expect((await db.query('pending_actions')).single['status'], 'synced');
        expect(uploads, 1);
        expect(inserts, 1);
        expect(patches, 1);

        // Pass 2: Re-drain already synced
        await SyncOutboxService.drain();
        expect((await db.query('pending_actions')).single['status'], 'synced');
        expect(uploads, 1, reason: 'Zero new uploads on re-drain');
        expect(inserts, 1, reason: 'Zero new metadata writes on re-drain');
        expect(patches, 1, reason: 'Zero new job PATCHes on re-drain');
      } finally {
        DBHelper.useDatabaseForTesting(null);
        await db.close();
        await Supabase.instance.dispose();
        await server.close(force: true);
        await temp.delete(recursive: true);
        HttpOverrides.global = overrides;
        SyncOutboxService.resetRecoverySessionForTesting();
      }
    },
  );

  test(
    'FI-4: interruption after partial success + PERSISTED REOPEN SIMULATION -> recover on startup (synced)',
    () async {
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({});
      SyncOutboxService.resetRecoverySessionForTesting();
      final temp = await Directory.systemTemp.createTemp('r4-fi4-');
      final dbFile = '${temp.path}/test.db';
      final file = File('${temp.path}/evidence.jpg')..writeAsBytesSync([1, 2, 3]);
      final key = base64Url.encode(utf8.encode(file.path)).replaceAll('=', '');
      final object = 'inspections/a/photo_$key.jpg';

      var uploads = 0, inserts = 0, patches = 0;
      Uint8List? storageBytes = Uint8List.fromList([1, 2, 3]);
      Map<String, dynamic>? metadata;

      var job = <String, dynamic>{
        'id': 'a',
        'assigned_inspector_id': 'inspector',
        'status': 'in_progress',
        'updated_at': baseTime,
        'photo_paths': <String>[],
        'photo_count': 0,
      };

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final body = await utf8.decoder.bind(req).join();
        req.response.headers.contentType = ContentType.json;
        if (req.uri.path == '/rest/v1/field_jobs') {
          if (req.method == 'PATCH') {
            patches++;
            job = {...job, ...jsonDecode(body) as Map<String, dynamic>, 'updated_at': '2026-01-02T00:00:00Z'};
            req.response.write(jsonEncode(job));
          } else {
            req.response.write(jsonEncode([job]));
          }
        } else if (req.uri.path == '/rest/v1/field_job_photos') {
          if (req.method == 'GET') {
            req.response.write(jsonEncode(metadata == null ? [] : [metadata]));
          } else {
            inserts++;
            metadata = Map<String, dynamic>.from(jsonDecode(body) as Map);
            req.response.statusCode = 201;
            req.response.write(jsonEncode(metadata));
          }
        } else if (req.uri.path.startsWith('/storage/v1/object/')) {
          if (req.method == 'GET') {
            if (storageBytes == null) {
              req.response.statusCode = 404;
              req.response.write(jsonEncode({'error': 'Not Found'}));
            } else {
              req.response.headers.contentType = ContentType.binary;
              req.response.add(storageBytes!);
            }
          } else {
            uploads++;
            storageBytes = Uint8List.fromList([1, 2, 3]);
            req.response.write('{"Key":"inspection-photos/$object"}');
          }
        }
        await req.response.close();
      });

      // Session 1: Create DB, tables, and interrupted in-flight syncing action
      var db = await databaseFactoryFfi.openDatabase(dbFile);
      final source = await File('lib/core/services/db_helper.dart').readAsString();
      for (final m in RegExp(r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)').allMatches(source)) {
        await db.execute(m.group(0)!);
      }
      DBHelper.useDatabaseForTesting(db);
      await Supabase.initialize(
        url: 'http://127.0.0.1:${server.port}', publishableKey: 'fixture',
        authOptions: FlutterAuthClientOptions(autoRefreshToken: false, detectSessionInUri: false, localStorage: EmptyLocalStorage()),
      );
      await SupabaseService.client.auth.setInitialSession(jsonEncode({
        'access_token': 'fixt', 'refresh_token': 'fixt', 'token_type': 'bearer', 'expires_in': 3600,
        'user': {'id': 'inspector', 'aud': 'authenticated'},
      }));
      final photoPayload = {'photoPath': file.path, 'notes': 'fixture', 'latitude': null, 'longitude': null, 'capturedAt': baseTime};
      await db.insert('pending_actions', {
        'id': 'photos_a', 'type': 'photos_update', 'job_id': 'a', 'status': 'syncing', 'retry_count': 0,
        'created_at': baseTime, 'updated_at': baseTime,
        'payload': jsonEncode({'cachedUpdatedAtSnapshot': baseTime, 'photos': [photoPayload]}),
      });

      // Restart boundary: Full teardown of in-memory DB handle, Supabase client, and session state
      DBHelper.useDatabaseForTesting(null);
      await db.close();
      await Supabase.instance.dispose();
      SyncOutboxService.resetRecoverySessionForTesting();

      // Session 2: PERSISTED REOPEN SIMULATION - reopen disk DB, reinit client
      db = await databaseFactoryFfi.openDatabase(dbFile);
      DBHelper.useDatabaseForTesting(db);
      await Supabase.initialize(
        url: 'http://127.0.0.1:${server.port}', publishableKey: 'fixture',
        authOptions: FlutterAuthClientOptions(autoRefreshToken: false, detectSessionInUri: false, localStorage: EmptyLocalStorage()),
      );
      await SupabaseService.client.auth.setInitialSession(jsonEncode({
        'access_token': 'fixt', 'refresh_token': 'fixt', 'token_type': 'bearer', 'expires_in': 3600,
        'user': {'id': 'inspector', 'aud': 'authenticated'},
      }));

      // Drain after restart: triggers startup recovery on persisted database
      await SyncOutboxService.drain();

      try {
        final row = (await db.query('pending_actions')).single;
        expect(row['status'], 'synced');
        expect(jsonDecode(row['payload'] as String)['r4RecoveryRequired'], isTrue);
        expect(uploads, 0, reason: 'Zero duplicate uploads during reopen recovery');
        expect(inserts, 1, reason: 'Metadata inserted exactly once');
        expect(patches, 1, reason: 'Guarded job PATCH executed exactly once');
      } finally {
        DBHelper.useDatabaseForTesting(null);
        await db.close();
        await Supabase.instance.dispose();
        await server.close(force: true);
        await temp.delete(recursive: true);
        HttpOverrides.global = overrides;
        SyncOutboxService.resetRecoverySessionForTesting();
      }
    },
  );

}

class EmptyLocalStorage extends LocalStorage {
  String? _data;
  @override
  Future<void> initialize() async {}
  @override
  Future<String?> accessToken() async => _data;
  @override
  Future<bool> hasAccessToken() async => _data != null;
  @override
  Future<void> persistSession(String s) async => _data = s;
  @override
  Future<void> removePersistedSession() async => _data = null;
}
