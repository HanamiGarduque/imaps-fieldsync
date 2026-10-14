// Wiring contract for Issue 03B online recovery.
//
// The transition logic is proven executably in map_connectivity_recovery_test.dart.
// This file proves the two map screens actually wire it to the tile layer and
// the route fetch, and that nothing about the Rosario boundary, the GPS rules
// or inspection persistence changed.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/modules/inspection/inspection_constants.dart';

const recovery =
    'lib/modules/inspection/widgets/map_connectivity_recovery.dart';
const step1 = 'lib/modules/inspection/screens/site_map_screen.dart';
const quickMap = 'lib/modules/inspection/screens/site_map_preview_screen.dart';
const routeService = 'lib/core/services/route_service.dart';
const boundaryWidget =
    'lib/modules/inspection/widgets/rosario_boundary_overlay.dart';

void main() {
  final recoverySource = File(recovery).readAsStringSync();
  final step1Source = File(step1).readAsStringSync();
  final quickMapSource = File(quickMap).readAsStringSync();
  final boundarySource = File(boundaryWidget).readAsStringSync();

  test('both maps wire the shared recovery to their TileLayer', () {
    for (final source in [step1Source, quickMapSource]) {
      expect(
        source,
        contains("import '../widgets/map_connectivity_recovery.dart';"),
      );
      expect(source, contains('reset: _recovery.tileResetStream'));
      expect(source, contains('evictErrorTileStrategy:'));
      // Failed tiles must be evictable, otherwise recovery cannot redraw them.
      expect(
        source,
        contains('EvictErrorTileStrategy.notVisibleRespectMargin'),
      );
      expect(source, contains('final MapConnectivityRecovery _recovery'));
    }
  });

  test('the subscription is created once and disposed on screen exit', () {
    for (final source in [step1Source, quickMapSource]) {
      expect(source, contains('_recovery.start('));
      expect(source, contains('_recovery.stop()'));
      expect(
        RegExp(
          r'void dispose\(\)[\s\S]{0,400}_recovery\.stop\(\)',
        ).hasMatch(source),
        isTrue,
        reason: 'stop() must be reachable from dispose()',
      );
    }
    expect(recoverySource, contains('await _subscription?.cancel()'));
    expect(recoverySource, contains('if (_disposed) return;'));
  });

  test(
    'Step 1 retries the road route once on recovery, guarded against spam',
    () {
      expect(step1Source, contains('Future<void> _onConnectivityRecovered()'));
      final recoveryAt = step1Source.indexOf('_onConnectivityRecovered()');
      final body = step1Source.substring(
        recoveryAt,
        step1Source.indexOf('@override', recoveryAt),
      );
      expect(body, contains('_recovery.resetTiles()'));
      expect(body, contains('_fetchRouteAndUpdate(online: true)'));
      expect(body, contains('if (!mounted) return;'));
      // Single-attempt guarantees come from the existing route guards.
      expect(step1Source, contains('_routeRequestInFlight'));
      expect(step1Source, contains('requestVersion != _routeRequestVersion'));
    },
  );

  test('opening offline still never calls OSRM', () {
    // The pre-existing offline gate is untouched: no online flag, no fetch.
    expect(
      step1Source,
      contains(
        'if (!online || _deviceLatLng == null || _parcelLatLng == null) return;',
      ),
    );
    expect(
      step1Source,
      contains('unawaited(_fetchRouteAndUpdate(online: online))'),
    );
    // Offline there is now no fabricated road line at all: only a real OSRM
    // route or this task's cached copy may be drawn (offline cached route).
    expect(step1Source, isNot(contains('_buildRoutePath')));
  });

  test('Quick Action Map recovers tiles only and gains no road route', () {
    final recoveryAt = quickMapSource.indexOf('_onConnectivityRecovered()');
    final body = quickMapSource.substring(
      recoveryAt,
      quickMapSource.indexOf('@override', recoveryAt),
    );
    expect(body, contains('_recovery.resetTiles()'));
    expect(body, isNot(contains('RouteService')));
    expect(quickMapSource, isNot(contains('RouteService')));
    expect(quickMapSource, isNot(contains('PolylineLayer')));
    // Its existing contract is preserved.
    expect(quickMapSource, contains('FlutterCompass.events'));
    expect(quickMapSource, contains('LocationService.getCurrentLocation()'));
    expect(quickMapSource, isNot(contains('TaskItem')));
  });

  test('the Rosario boundary is independent of route and connectivity', () {
    expect(step1Source, contains('const RosarioBoundaryOverlay()'));
    expect(quickMapSource, contains('const RosarioBoundaryOverlay()'));
    // The overlay never sees connectivity, route, or map-controller concerns.
    for (final forbidden in [
      'MapConnectivityRecovery',
      'RouteService',
      'PolylineLayer',
      'TileLayer',
      'MapController',
      'Connectivity',
    ]) {
      expect(
        boundarySource,
        isNot(contains(forbidden)),
        reason: 'boundary must stay a pure local render layer: $forbidden',
      );
    }
  });

  test('layer order keeps boundary under route and markers', () {
    int at(String s, String needle) => s.indexOf(needle);
    for (final source in [step1Source, quickMapSource]) {
      expect(
        at(source, 'TileLayer('),
        lessThan(at(source, 'const RosarioBoundaryOverlay(')),
      );
      expect(
        at(source, 'const RosarioBoundaryOverlay('),
        lessThan(at(source, 'MarkerLayer(')),
      );
    }
    // Step 1's route stays above the boundary and below the markers.
    expect(
      at(step1Source, 'const RosarioBoundaryOverlay('),
      lessThan(at(step1Source, 'PolylineLayer(')),
    );
    expect(
      at(step1Source, 'PolylineLayer('),
      lessThan(at(step1Source, 'MarkerLayer(')),
    );
  });

  test('routing never receives boundary geometry', () {
    final service = File(routeService).readAsStringSync();
    for (final concept in [
      'rosario',
      'Polygon',
      'polygon',
      'clip',
      'contains(',
      'isWithin',
    ]) {
      expect(
        service,
        isNot(contains(concept)),
        reason: 'routing must stay boundary-agnostic: $concept',
      );
    }
    // Only start/end are passed; the signature cannot accept geometry.
    expect(
      RegExp(
        r'fetchDrivingRoute\(\{\s*required LatLng start,\s*required LatLng end',
      ).hasMatch(service),
      isTrue,
    );
  });

  test('GPS, distance, arrival and step completion are unchanged', () {
    expect(siteVerificationDistanceThresholdMeters, 30.0);
    expect(
      RegExp(
        r'bool get _arrived =>\s*_distanceMeters != null &&\s*'
        r'_distanceMeters! <= siteVerificationDistanceThresholdMeters;',
      ).hasMatch(step1Source),
      isTrue,
    );
    expect(
      step1Source,
      contains('InspectionProgress.instance.markStepComplete(1)'),
    );
    final recoveryAt = step1Source.indexOf(
      'Future<void> _onConnectivityRecovered()',
    );
    final body = step1Source.substring(
      recoveryAt,
      step1Source.indexOf('@override', recoveryAt),
    );
    for (final forbidden in [
      'DBHelper',
      'SyncOutboxService',
      'SupabaseService',
      'setState',
    ]) {
      expect(
        body,
        isNot(contains(forbidden)),
        reason:
            'recovery must not write, enqueue or hit the network service layer: $forbidden',
      );
    }
  });
}
