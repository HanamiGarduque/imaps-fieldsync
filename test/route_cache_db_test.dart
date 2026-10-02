// local_route_cache — additive migration, per-job isolation, and safe failure.
//
// All destructive migration testing runs against ISOLATED temporary databases
// built from DBHelper's own CREATE TABLE statements. The real device database
// is never opened, read or modified by this file.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/route_service.dart';
import 'package:latlong2/latlong.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Creates a throwaway database with the schema DBHelper's onCreate produces,
/// then rebuilds it at [targetVersion] through the real onUpgrade branches.
Future<Database> buildDb(String path, {required int fromVersion}) async {
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: fromVersion,
      onCreate: (database, version) async {
        for (final match
            in RegExp(
              r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)',
            ).allMatches(
              File('lib/core/services/db_helper.dart').readAsStringSync(),
            )) {
          await database.execute(match.group(0)!);
        }
      },
    ),
  );
  await db.insert('local_jobs', {'id': 'job-a', 'status': 'assigned'});
  await db.insert('local_inspections', {
    'id': 'job-a',
    'notes': 'prior draft',
    'current_step': 2,
  });
  await db.close();

  // Re-open one version lower, so onUpgrade runs exactly one step.
  final lower = fromVersion == 14 ? 13 : fromVersion;
  return databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: lower,
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 14) {
          await database.execute(DBHelper.localRouteCacheSchemaForTesting);
        }
      },
    ),
  );
}

CachedRoute route(String jobId, {int points = 3}) => CachedRoute(
  jobId: jobId,
  points: List.generate(
    points,
    (i) => LatLng(13.70 + i * 0.001, 121.17 + i * 0.002),
  ),
  distanceMeters: 1234.5,
  durationSeconds: 321.0,
  originLat: 13.70,
  originLng: 121.17,
  fetchedAt: DateTime.utc(2026, 10, 2, 9, 30),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory dir;
  late Database db;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fieldsync-route-cache-');
    db = await buildDb('${dir.path}/fixture.db', fromVersion: 14);
    DBHelper.useDatabaseForTesting(db);
  });

  tearDown(() async {
    DBHelper.useDatabaseForTesting(null);
    await db.close();
    await dir.delete(recursive: true);
  });

  test(
    'fresh database contains local_route_cache with the required contract',
    () async {
      final columns = (await db.rawQuery(
        'PRAGMA table_info(local_route_cache)',
      )).map((r) => r['name'] as String).toList();
      expect(columns, [
        'job_id',
        'geometry_json',
        'distance_meters',
        'duration_seconds',
        'origin_lat',
        'origin_lng',
        'fetched_at',
      ]);
      // No destination duplication: local_jobs stays authoritative for the target.
      expect(columns, isNot(contains('dest_lat')));
      expect(columns, isNot(contains('dest_lng')));
      // Never synced: no lifecycle or sync columns.
      for (final forbidden in [
        'is_synced',
        'status',
        'type',
        'payload',
        'retry_count',
      ]) {
        expect(columns, isNot(contains(forbidden)));
      }
    },
  );

  test('upgrade preserves existing rows and adds only the new table', () async {
    await db.insert('local_route_cache', route('job-a').toRow());
    await db.close();

    final path = '${dir.path}/fixture.db';
    db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 14,
        onUpgrade: (database, oldVersion, newVersion) async {
          if (oldVersion < 14) {
            await database.execute(DBHelper.localRouteCacheSchemaForTesting);
          }
        },
      ),
    );
    DBHelper.useDatabaseForTesting(db);

    // Pre-existing data survived the migration untouched.
    expect((await db.query('local_jobs')).single['id'], 'job-a');
    expect(
      (await db.query('local_inspections')).single['notes'],
      'prior draft',
    );
    expect((await db.query('local_inspections')).single['current_step'], 2);
    // And every table that existed before is still present.
    final tables = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    )).map((r) => r['name'] as String);
    for (final expected in [
      'local_jobs',
      'local_inspections',
      'local_photos',
      'pending_actions',
      'sync_log_entries',
      'inspection_job_retention',
      'local_route_cache',
    ]) {
      expect(tables, contains(expected));
    }
  });

  test('migration is idempotent across repeated application', () async {
    await db.execute(DBHelper.localRouteCacheSchemaForTesting);
    await db.execute(DBHelper.localRouteCacheSchemaForTesting);
    final rows = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM sqlite_master WHERE type='table' AND name='local_route_cache'",
    );
    expect(rows.single['c'], 1);
  });

  test(
    'write/read round-trips geometry, distance, duration, origin and time',
    () async {
      final original = route('job-a', points: 120);
      await DBHelper.saveRouteCache(original);

      final loaded = await DBHelper.getRouteCache('job-a');
      expect(loaded, isNotNull);
      expect(loaded!.jobId, 'job-a');
      expect(loaded.points, hasLength(120));
      expect(loaded.distanceMeters, 1234.5);
      expect(loaded.durationSeconds, 321.0);
      expect(loaded.originLat, 13.70);
      expect(loaded.originLng, 121.17);
      expect(loaded.fetchedAt, DateTime.utc(2026, 10, 2, 9, 30));
      for (var i = 0; i < original.points.length; i++) {
        expect(loaded.points[i].latitude, original.points[i].latitude);
        expect(loaded.points[i].longitude, original.points[i].longitude);
      }
    },
  );

  test('coordinate order is GeoJSON [lng, lat] and is not inverted', () async {
    final cached = CachedRoute(
      jobId: 'job-a',
      points: const [LatLng(13.70, 121.17), LatLng(13.80, 121.30)],
      originLat: 13.70,
      originLng: 121.17,
      fetchedAt: DateTime.utc(2026, 10, 2),
    );
    // Stored order must be longitude first — latitude 13.x must never appear
    // in the longitude slot.
    expect(cached.toRow()['geometry_json'], '[[121.17,13.7],[121.3,13.8]]');

    final restored = CachedRoute.fromRow(cached.toRow());
    expect(restored.points.first.latitude, 13.70);
    expect(restored.points.first.longitude, 121.17);
    expect(
      restored.points.first.latitude,
      isNot(restored.points.first.longitude),
    );
  });

  test('routes are isolated per exact job id', () async {
    await DBHelper.saveRouteCache(route('job-a', points: 3));
    await DBHelper.saveRouteCache(route('job-b', points: 9));

    final a = await DBHelper.getRouteCache('job-a');
    final b = await DBHelper.getRouteCache('job-b');
    expect(a!.points, hasLength(3));
    expect(b!.points, hasLength(9));
    expect(a.jobId, 'job-a');
    expect(b.jobId, 'job-b');
    expect(await DBHelper.getRouteCache('job-missing'), isNull);
  });

  test('re-saving the same job replaces the previous route', () async {
    await DBHelper.saveRouteCache(route('job-a', points: 3));
    await DBHelper.saveRouteCache(route('job-a', points: 40));

    final loaded = await DBHelper.getRouteCache('job-a');
    expect(loaded!.points, hasLength(40));
    final rows = await db.query('local_route_cache');
    expect(rows, hasLength(1), reason: 'one cache row per exact job');
  });

  test('malformed cached geometry is rejected safely, not drawn', () {
    for (final geometry in [
      'not json',
      '{}',
      '[]',
      '[[1]]',
      '[["a","b"]]',
      '[[121.17,13.7],[121.3]]',
      '[[999,13.7],[121.3,13.8]]',
      '[[121.17,null],[121.3,13.8]]',
    ]) {
      expect(
        () => RouteService.decodeRoutePoints(geometry),
        throwsA(isA<FormatException>()),
        reason: 'must reject: $geometry',
      );
    }
  });

  test(
    'a corrupt stored row reads back as absent instead of throwing',
    () async {
      await db.insert('local_route_cache', {
        'job_id': 'job-bad',
        'geometry_json': '{"not":"an array"}',
        'origin_lat': 13.7,
        'origin_lng': 121.17,
        'fetched_at': '2026-10-02T00:00:00.000Z',
      });
      expect(await DBHelper.getRouteCache('job-bad'), isNull);
    },
  );

  test('route cache never touches the sync outbox', () async {
    final before = await db.query('pending_actions');
    await DBHelper.saveRouteCache(route('job-a'));
    await DBHelper.getRouteCache('job-a');
    await DBHelper.deleteRouteCache('job-a');
    final after = await db.query('pending_actions');

    expect(after, hasLength(before.length));
    expect(await DBHelper.getActionableActions(), isEmpty);
    // No outbox row may reference a route at all.
    expect(after.where((r) => '${r['type']}'.contains('route')), isEmpty);
  });

  test(
    'route cache does not modify inspection lifecycle or job rows',
    () async {
      final jobBefore = await db.query('local_jobs');
      final inspectionBefore = await db.query('local_inspections');

      await DBHelper.saveRouteCache(route('job-a'));

      expect(await db.query('local_jobs'), jobBefore);
      expect(await db.query('local_inspections'), inspectionBefore);
    },
  );

  test('deleteRouteCache removes only the addressed job', () async {
    await DBHelper.saveRouteCache(route('job-a'));
    await DBHelper.saveRouteCache(route('job-b'));
    await DBHelper.deleteRouteCache('job-a');
    expect(await DBHelper.getRouteCache('job-a'), isNull);
    expect(await DBHelper.getRouteCache('job-b'), isNotNull);
  });
}
