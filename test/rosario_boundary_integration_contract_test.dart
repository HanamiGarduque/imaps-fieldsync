// Boundary-overlay integration contract for the two map surfaces.
//
// The overlay's behaviour is proven executably in
// rosario_boundary_overlay_test.dart (parse, coordinate order, graceful
// failure, offline render). This file proves the *wiring*: that both screens
// mount the same shared overlay, that it sits under route/marker content, and
// that it introduces no persistence, sync, or network coupling into the
// inspection flow.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/modules/inspection/inspection_constants.dart';

const overlay = 'lib/modules/inspection/widgets/rosario_boundary_overlay.dart';
const step1 = 'lib/modules/inspection/screens/site_map_screen.dart';
const quickMap = 'lib/modules/inspection/screens/site_map_preview_screen.dart';
const routeService = 'lib/core/services/route_service.dart';

void main() {
  final overlaySource = File(overlay).readAsStringSync();
  final step1Source = File(step1).readAsStringSync();
  final quickMapSource = File(quickMap).readAsStringSync();

  test('both map surfaces mount the same shared overlay', () {
    for (final source in [step1Source, quickMapSource]) {
      expect(
        source,
        contains("import '../widgets/rosario_boundary_overlay.dart';"),
      );
      expect(source, contains('const RosarioBoundaryOverlay()'));
    }
    // One loader, one asset path — no per-screen duplicate implementation.
    expect(overlaySource, contains("'assets/maps/rosario_boundary.geojson'"));
    expect(step1Source, isNot(contains('assets/maps/')));
    expect(quickMapSource, isNot(contains('assets/maps/')));
  });

  test('overlay renders beneath route and marker layers', () {
    int indexOf(String source, String needle) => source.indexOf(needle);
    for (final source in [step1Source, quickMapSource]) {
      final overlayAt = indexOf(source, 'const RosarioBoundaryOverlay()');
      expect(overlayAt, greaterThan(indexOf(source, 'TileLayer(')));
      expect(overlayAt, lessThan(indexOf(source, 'MarkerLayer(')));
    }
    // Step 1's road route keeps its existing position above the boundary.
    expect(
      indexOf(step1Source, 'PolylineLayer('),
      greaterThan(indexOf(step1Source, 'const RosarioBoundaryOverlay()')),
    );
  });

  test('overlay adds no persistence, sync, network or provider coupling', () {
    for (final forbidden in [
      'SupabaseService',
      'DBHelper',
      'SyncOutboxService',
      'InspectionProvider',
      'InspectionProgress',
      'http',
      'dart:io',
      'RouteService',
      'getDistanceToParcelBoundary',
      'siteVerificationDistanceThresholdMeters',
    ]) {
      expect(
        overlaySource,
        isNot(contains(forbidden)),
        reason: 'boundary overlay must not reference $forbidden',
      );
    }
    // Pure local geometry: only these package imports are permitted.
    final imports = RegExp(
      r"^import '([^']+)'",
      multiLine: true,
    ).allMatches(overlaySource).map((m) => m.group(1)).toSet();
    expect(imports, {
      'dart:convert',
      'package:flutter/material.dart',
      'package:flutter/services.dart',
      'package:flutter_map/flutter_map.dart',
      'package:latlong2/latlong.dart',
      '../../../core/theme/insight_theme.dart',
    });
  });

  test('Step 1 business rules are untouched by the overlay', () {
    // Arrival and the 30 m rule still derive from the device/parcel distance
    // alone; nothing reads the boundary.
    expect(
      RegExp(
        r'bool get _arrived =>\s*_distanceMeters != null &&\s*'
        r'_distanceMeters! <= siteVerificationDistanceThresholdMeters;',
      ).hasMatch(step1Source),
      isTrue,
    );
    expect(siteVerificationDistanceThresholdMeters, 30.0);
    // Proceeding to Step 2 keeps its own unconditional handler.
    expect(
      step1Source,
      contains('InspectionProgress.instance.markStepComplete(1)'),
    );
    final proceedAt = step1Source.indexOf('onPressed: () {');
    final completeAt = step1Source.indexOf('markStepComplete(1)');
    expect(completeAt, greaterThan(proceedAt));
    expect(
      step1Source.substring(proceedAt, completeAt),
      isNot(contains('_boundary')),
    );
    expect(step1Source, isNot(contains('_boundaryLoaded')));
  });

  test('road-route behaviour is preserved and never boundary-derived', () {
    // Route fetching still happens post-paint, best-effort, online-only.
    expect(
      step1Source,
      contains('unawaited(_fetchRouteAndUpdate(online: online))'),
    );
    expect(
      step1Source,
      contains(
        'if (!online || _deviceLatLng == null || _parcelLatLng == null) return;',
      ),
    );
    // Offline there is no fabricated road line: Step 1 draws only real OSRM
    // geometry (freshly fetched, or this task's cached copy).
    expect(step1Source, isNot(contains('_buildRoutePath')));
    // The routing service takes only start/end points and has no concept of a
    // municipal boundary, so no clipping or rejection is possible by construction.
    final service = File(routeService).readAsStringSync();
    expect(service, contains('fetchDrivingRoute'));
    for (final boundaryConcept in [
      'rosario',
      'Polygon',
      'polygon',
      'MultiPolygon',
      'clip',
      'contains(',
      'isWithin',
    ]) {
      expect(
        service,
        isNot(contains(boundaryConcept)),
        reason: 'routing must not gain boundary awareness: $boundaryConcept',
      );
    }
  });

  test('Quick Action Map stays task-independent', () {
    expect(quickMapSource, isNot(contains('TaskItem')));
    expect(quickMapSource, isNot(contains('parcelId')));
    expect(quickMapSource, isNot(contains('SupabaseService')));
    expect(quickMapSource, isNot(contains('DBHelper')));
    // Device position and compass behaviour are untouched.
    expect(quickMapSource, contains('FlutterCompass.events'));
    expect(quickMapSource, contains('LocationService.getCurrentLocation()'));
  });

  test('boundary attribution is factual and adds no invented metadata', () {
    expect(step1Source, contains('Municipal boundary: MPDO Rosario'));
    // Only the attribution line itself is constrained; unrelated screen text
    // may legitimately use these words.
    final line = step1Source
        .split('\n')
        .firstWhere((l) => l.contains('Municipal boundary: MPDO Rosario'));
    for (final invented in ['version', 'issue date', 'issued', 'licen', '©']) {
      expect(
        line.toLowerCase(),
        isNot(contains(invented)),
        reason: 'no invented provenance on the attribution line: $invented',
      );
    }
  });
}
