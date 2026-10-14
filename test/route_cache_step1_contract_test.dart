// Offline cached road route — Step 1 behaviour contract.
//
// The DB-level behaviour (schema, isolation, serialization) is proven
// executably in route_cache_db_test.dart. This file proves the SCREEN contract:
// that only real OSRM geometry is ever drawn as a road route, schematic links
// never become a synthetic road fallback, the blue dot stays independent, and nothing
// about GPS verification, step completion, the Rosario boundary or Quick Action
// changed.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/modules/inspection/inspection_constants.dart';

const step1 = 'lib/modules/inspection/screens/site_map_screen.dart';
const view = 'lib/modules/inspection/widgets/site_verification_view.dart';
const quickMap = 'lib/modules/inspection/screens/site_map_preview_screen.dart';
const dbHelper = 'lib/core/services/db_helper.dart';
const routeService = 'lib/core/services/route_service.dart';
const boundaryWidget =
    'lib/modules/inspection/widgets/rosario_boundary_overlay.dart';
const recovery =
    'lib/modules/inspection/widgets/map_connectivity_recovery.dart';

void main() {
  final step1Source = File(step1).readAsStringSync();
  final viewSource = File(view).readAsStringSync();
  final quickMapSource = File(quickMap).readAsStringSync();
  final dbSource = File(dbHelper).readAsStringSync();
  final routeSource = File(routeService).readAsStringSync();
  final boundarySource = File(boundaryWidget).readAsStringSync();

  test('no fabricated road fallback survives in the codebase', () {
    expect(
      step1Source,
      isNot(contains('_buildRoutePath')),
      reason:
          'a fabricated line must not survive as dead code or as a fallback',
    );
    expect(step1Source, isNot(contains('dLat * 0.10')));
    expect(step1Source, isNot(contains('dLng * 0.52')));
  });

  test('the polyline renders only when real route geometry exists', () {
    expect(step1Source, contains('if (_routePoints != null)'));
    final polylineAt = step1Source.indexOf('if (_routePoints != null)');
    final layer = step1Source.substring(
      polylineAt,
      step1Source.indexOf('MarkerLayer(', polylineAt),
    );
    // No "points ?? something" fallback may supply geometry.
    expect(layer, isNot(contains('??')));
    expect(layer, contains('points: _routePoints!'));
  });

  test(
    'a successful online route is displayed and cached for the exact job',
    () {
      expect(step1Source, contains('_routePoints = result.points;'));
      expect(
        step1Source,
        contains('_routeDistanceMeters = result.distanceMeters;'),
      );
      expect(
        step1Source,
        contains('_routeDurationSeconds = result.durationSeconds;'),
      );
      expect(step1Source, contains('_routeFromCache = false;'));
      expect(step1Source, contains('DBHelper.saveRouteCache('));
      expect(step1Source, contains('jobId: widget.task.id'));
    },
  );

  test(
    'cache failure never removes the route the inspector is looking at',
    () async {
      // Persistence is serialized with the request and wrapped, AFTER the state
      // fields and paint are assigned, so a cache failure cannot undo the route.
      final assignAt = step1Source.indexOf('_routePoints = result.points;');
      final persistAt = step1Source.indexOf(
        'await _persistRoute(result, start);',
      );
      expect(assignAt, greaterThan(0));
      expect(persistAt, greaterThan(assignAt));
      final start = step1Source.indexOf('Future<void> _persistRoute(');
      final body = step1Source.substring(
        start,
        step1Source.indexOf('\n  }', start),
      );
      expect(body, contains('try'));
      expect(body, contains('debugPrint'));
      expect(body, isNot(contains('rethrow')));
    },
  );

  test('offline open restores the cached real route before any fetch', () {
    final initAt = step1Source.indexOf('void initState()');
    final restoreAt = step1Source.indexOf('unawaited(_restoreCachedRoute());');
    final loadAt = step1Source.indexOf('_loadMapData();', initAt);
    expect(restoreAt, greaterThan(initAt));
    expect(restoreAt, lessThan(loadAt));
    expect(
      step1Source,
      contains('final cached = await DBHelper.getRouteCache(widget.task.id);'),
    );
    expect(step1Source, contains('_routePoints = cached.points;'));
    expect(step1Source, contains('_routeFromCache = true;'));
  });

  test('cached geometry is labelled as cached, never as newly calculated', () {
    expect(step1Source, contains('routeFromCache: _routeFromCache'));
    expect(viewSource, contains("'Saved road route'"));
    expect(viewSource, contains("'Road route'"));
    expect(
      viewSource,
      isNot(contains('Cached road route · Offline')),
      reason: 'cache provenance does not prove current connectivity',
    );
  });

  test('no route at all reports honestly instead of drawing a fake one', () {
    expect(viewSource, contains('Road route unavailable'));
    // The notice is informational: it must not gate the Proceed button.
    expect(viewSource, contains('onPressed: widget.onProceed'));
    expect(step1Source, contains('onProceed: _proceed'));
    expect(
      step1Source,
      contains('InspectionProgress.instance.markStepComplete(1)'),
    );
  });

  test('the blue dot stays independent of route geometry', () {
    final updateStart = step1Source.indexOf('Future<void> _onPositionUpdate(');
    // Bound to this method's own body, not to everything that follows it.
    final updateEnd = step1Source.indexOf('\n  }', updateStart);
    final update = step1Source.substring(updateStart, updateEnd);
    // Moving the device marker must not recompute or mutate the route.
    expect(update, contains('_acceptFix(pos)'));
    final acceptStart = step1Source.indexOf('bool _acceptFix(');
    final accept = step1Source.substring(
      acceptStart,
      step1Source.indexOf('\n  }', acceptStart),
    );
    expect(accept, contains('_deviceLatLng = newPos;'));
    expect(accept, isNot(contains('nearestSiteRoadPoint')));
    expect(update, contains('setState('));
    // A GPS tick may never assign route geometry or touch the route cache.
    expect(RegExp(r'_routePoints\s*=').hasMatch(update), isFalse);
    expect(update, isNot(contains('saveRouteCache')));
    expect(update, isNot(contains('_restoreCachedRoute')));
    expect(update, isNot(contains('CachedRoute')));
  });

  test(
    'reconnect refreshes once and a failed refresh keeps the cached route',
    () {
      final recoveryAt = step1Source.indexOf(
        'Future<void> _onConnectivityRecovered()',
      );
      final body = step1Source.substring(
        recoveryAt,
        step1Source.indexOf('@override', recoveryAt),
      );
      expect(body, contains('_recovery.resetTiles()'));
      expect(body, contains('_fetchRouteAndUpdate(online: true)'));
      expect(body, contains('if (!mounted) return;'));

      // A null OSRM result returns before touching any displayed state.
      final fetch = step1Source.substring(
        step1Source.indexOf('Future<void> _fetchRoute('),
        step1Source.indexOf('Future<void> _persistRoute('),
      );
      expect(fetch, contains('requestVersion != _routeRequestVersion'));
      expect(
        fetch.indexOf('requestVersion != _routeRequestVersion'),
        lessThan(fetch.indexOf('_routePoints = result.points;')),
      );
      expect(fetch, contains('!usableSiteRoad(result.points)'));
      expect(fetch, isNot(contains('_routePoints = null')));
      expect(fetch, isNot(contains('DBHelper.deleteRouteCache')));
    },
  );

  test('request spam is guarded at every level', () {
    expect(step1Source, contains('_routeRequestInFlight'));
    expect(step1Source, contains('requestVersion != _routeRequestVersion'));
    expect(
      File(recovery).readAsStringSync(),
      contains('if (nowOnline && !wasOnline)'),
    );
  });

  test('route cache is keyed on the exact job id, never reference number', () {
    expect(step1Source, contains('jobId: widget.task.id'));
    expect(dbSource, contains("where: 'job_id = ?'"));
    for (final forbidden in [
      'reference_number',
      'applicant',
      'local_inspection_id',
    ]) {
      final cacheApi = dbSource.substring(
        dbSource.indexOf('static Future<void> saveRouteCache'),
        dbSource.indexOf('static Future<void> deleteRouteCache'),
      );
      expect(cacheApi, isNot(contains(forbidden)));
    }
  });

  test(
    'the cache table is isolated and carries no sync or lifecycle columns',
    () {
      expect(
        dbSource,
        contains('CREATE TABLE IF NOT EXISTS local_route_cache('),
      );
      expect(dbSource, contains('job_id TEXT PRIMARY KEY NOT NULL'));
      expect(dbSource, contains('geometry_json TEXT NOT NULL'));
      expect(dbSource, contains('origin_lat REAL NOT NULL'));
      expect(dbSource, contains('origin_lng REAL NOT NULL'));
      expect(dbSource, contains('fetched_at TEXT NOT NULL'));
      // Destination stays authoritative in local_jobs.parcel_lat/parcel_lng.
      final schemaStart = dbSource.indexOf(
        'CREATE TABLE IF NOT EXISTS local_route_cache(',
      );
      final schema = dbSource.substring(schemaStart, schemaStart + 320);
      expect(schema, isNot(contains('dest_lat')));
      expect(schema, isNot(contains('is_synced')));
    },
  );

  test('serialization is lossless and explicitly GeoJSON-ordered', () {
    expect(
      routeSource,
      contains('jsonEncode(points.map((p) => [p.longitude, p.latitude])'),
    );
    expect(routeSource, contains('LatLng(latitude, longitude)'));
    // No decimation anywhere in the write path.
    expect(routeSource, isNot(contains('toStringAsFixed')));
    expect(routeSource, isNot(contains('simplif')));
  });

  test(
    'Step 2 keeps 30m confirmation; Step 1 now estimates the mapped point',
    () {
      expect(siteVerificationDistanceThresholdMeters, 30.0);
      expect(
        RegExp(
          r'bool get _arrived =>\s*_distanceMeters != null &&\s*'
          r'_distanceMeters! <= siteVerificationDistanceThresholdMeters;',
        ).hasMatch(step1Source),
        isTrue,
      );
      expect(step1Source, isNot(contains('getDistanceToParcelBoundary')));
      expect(step1Source, contains('SpatialOfflineService.haversineMeters'));
      final gps = File(
        'lib/modules/inspection/screens/gps_verification_screen.dart',
      ).readAsStringSync();
      expect(gps, contains('getDistanceToParcelBoundary'));
      expect(
        gps,
        contains('_distance! <= siteVerificationDistanceThresholdMeters'),
      );
      expect(gps, contains('verified && !submitting ? onConfirm : null'));
    },
  );

  test('Quick Action Map gains no routing and no route cache', () {
    for (final forbidden in [
      'RouteService',
      'PolylineLayer',
      'local_route_cache',
      'saveRouteCache',
      'getRouteCache',
      'CachedRoute',
      'TaskItem',
    ]) {
      expect(
        quickMapSource,
        isNot(contains(forbidden)),
        reason: 'Quick Action must stay GPS/compass/boundary only: $forbidden',
      );
    }
  });

  test('the Rosario boundary remains an independent local render layer', () {
    expect(step1Source, contains('const RosarioBoundaryOverlay()'));
    for (final forbidden in [
      'RouteService',
      'CachedRoute',
      'saveRouteCache',
      'MapConnectivityRecovery',
      'DBHelper',
    ]) {
      expect(
        boundarySource,
        isNot(contains(forbidden)),
        reason:
            'boundary must not know about routes, caches or connectivity: $forbidden',
      );
    }
    // Boundary still sits under the route and markers.
    expect(
      step1Source.indexOf('const RosarioBoundaryOverlay('),
      lessThan(step1Source.indexOf('if (_routePoints != null)')),
    );
  });
}
