import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:latlong2/latlong.dart';

/// A road-network route returned by the routing engine.
class RouteResult {
  /// Ordered polyline of the actual road path (device → target).
  final List<LatLng> points;

  /// Route length in meters, as driven along the road network.
  final double distanceMeters;

  /// Estimated travel time in seconds for the driving profile.
  final double durationSeconds;

  const RouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });
}

/// A real OSRM route persisted locally so Step 1 can draw the SAME road
/// geometry while offline.
///
/// This is navigation-support data only. It carries no inspection lifecycle
/// meaning, is never enqueued to the outbox, and is safe to lose — if it is
/// missing, Step 1 simply shows no road route.
class CachedRoute {
  /// The exact `field_jobs.id` this route belongs to. One job, one row.
  final String jobId;

  /// Ordered road geometry, as returned by OSRM.
  final List<LatLng> points;

  final double? distanceMeters;
  final double? durationSeconds;

  /// Where the route was requested from when it was fetched.
  final double originLat;
  final double originLng;

  /// ISO-8601 UTC timestamp of the fetch that produced this route.
  final DateTime fetchedAt;

  const CachedRoute({
    required this.jobId,
    required this.points,
    required this.originLat,
    required this.originLng,
    required this.fetchedAt,
    this.distanceMeters,
    this.durationSeconds,
  });

  /// Promotes a freshly fetched online route into a storable cache entry.
  factory CachedRoute.fromRoute({
    required String jobId,
    required RouteResult route,
    required LatLng origin,
    DateTime? fetchedAt,
  }) {
    return CachedRoute(
      jobId: jobId,
      points: route.points,
      distanceMeters: route.distanceMeters,
      durationSeconds: route.durationSeconds,
      originLat: origin.latitude,
      originLng: origin.longitude,
      fetchedAt: (fetchedAt ?? DateTime.now()).toUtc(),
    );
  }

  /// Rebuilds a cache entry from a stored row. Throws [FormatException] when
  /// the geometry is unusable, so a corrupted row is rejected rather than
  /// silently drawn as a wrong-shaped route.
  factory CachedRoute.fromRow(Map<String, Object?> row) {
    final jobId = row['job_id'] as String?;
    if (jobId == null || jobId.isEmpty) {
      throw const FormatException('Cached route has no job id');
    }
    final geometry = row['geometry_json'] as String?;
    if (geometry == null || geometry.isEmpty) {
      throw const FormatException('Cached route has no geometry');
    }
    final fetchedAtRaw = row['fetched_at'] as String?;
    if (fetchedAtRaw == null || fetchedAtRaw.isEmpty) {
      throw const FormatException('Cached route has no fetch timestamp');
    }
    return CachedRoute(
      jobId: jobId,
      points: RouteService.decodeRoutePoints(geometry),
      distanceMeters: (row['distance_meters'] as num?)?.toDouble(),
      durationSeconds: (row['duration_seconds'] as num?)?.toDouble(),
      originLat: (row['origin_lat'] as num).toDouble(),
      originLng: (row['origin_lng'] as num).toDouble(),
      fetchedAt: DateTime.parse(fetchedAtRaw).toUtc(),
    );
  }

  /// Row shape written to `local_route_cache`.
  Map<String, Object?> toRow() => {
    'job_id': jobId,
    'geometry_json': RouteService.encodeRoutePoints(points),
    'distance_meters': distanceMeters,
    'duration_seconds': durationSeconds,
    'origin_lat': originLat,
    'origin_lng': originLng,
    'fetched_at': fetchedAt.toUtc().toIso8601String(),
  };
}

/// OSRM routing client for the Route Guidance feature (Site Verification
/// Step 1). Returns a real road-network route between two coordinates.
///
/// COST / LICENSING (hard constraint — keep this true):
///   - The configured endpoint below is the FREE, community-run OSRM demo
///     server (sponsored by FOSSGIS). No API key, no billing, no credit
///     card, no usage charges.
///   - THE DEMO SERVER IS FOR DEVELOPMENT / TESTING ONLY: its policy is
///     reasonable NON-COMMERCIAL use, max 1 request/sec, an identifying
///     User-Agent, logged requests, and NO uptime SLA. Production
///     deployment should point [_baseUrl] at a CONTROLLED / SELF-HOSTED
///     OSRM instance (still free/open source). That is the ONLY line that
///     changes here -- screens never build OSRM URLs themselves.
///
/// ROUTE SEMANTICS: the returned geometry / road distance / duration are
/// for NAVIGATION AND ORIENTATION only. They are NOT the authoritative
/// Site Verification measurement -- that remains the separate parcel-
/// boundary distance (RPC / haversine) computed by callers.
///
/// All failures (offline, timeout anywhere in the operation INCLUDING the
/// response-body read, non-200, non-Ok code, malformed response) return
/// NULL so callers can gracefully fall back to their pre-existing
/// straight-line / haversine behavior instead of erroring. Every code
/// path is time-bounded.
class RouteService {
  /// COORDINATE ORDER — the single documented rule for cached geometry.
  ///
  /// OSRM and GeoJSON both express positions as `[longitude, latitude]`.
  /// Flutter's `LatLng` is `(latitude, longitude)`. Every conversion between
  /// the two goes through [encodeRoutePoints]/[decodeRoutePoints] so the flip
  /// exists in exactly one place and cannot drift.
  ///
  /// The cache stores GeoJSON order (`[lng, lat]`) deliberately: that is the
  /// order OSRM itself returned, so a cached route is a byte-faithful record of
  /// the response rather than a second interpretation of it.
  ///
  /// Encoding is lossless — full double precision, no rounding, no decimation.
  static String encodeRoutePoints(List<LatLng> points) =>
      jsonEncode(points.map((p) => [p.longitude, p.latitude]).toList());

  /// Reverses [encodeRoutePoints]. Throws [FormatException] on anything that is
  /// not an ordered array of finite `[lng, lat]` pairs.
  static List<LatLng> decodeRoutePoints(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! List) {
      throw const FormatException('Route geometry must be an array');
    }
    if (decoded.length < 2) {
      throw const FormatException('Route geometry needs at least two points');
    }
    final points = <LatLng>[];
    for (final entry in decoded) {
      if (entry is! List || entry.length != 2) {
        throw const FormatException('Expected [longitude, latitude] pair');
      }
      if (entry[0] is! num || entry[1] is! num) {
        throw const FormatException('Non-numeric route coordinate');
      }
      final longitude = (entry[0] as num).toDouble();
      final latitude = (entry[1] as num).toDouble();
      if (!longitude.isFinite || !latitude.isFinite) {
        throw const FormatException('Non-finite route coordinate');
      }
      if (longitude.abs() > 180 || latitude.abs() > 90) {
        throw const FormatException('Route coordinate out of WGS84 range');
      }
      points.add(LatLng(latitude, longitude));
    }
    return List.unmodifiable(points);
  }

  /// OSRM base URL. Isolated here so the provider can later be switched
  /// from the public demo server to a self-hosted instance without
  /// touching any screen logic.
  static const String _baseUrl = 'https://router.project-osrm.org';

  /// Identifying User-Agent required by the OSRM demo-server usage policy
  /// (application name/version/purpose only - no personal information).
  /// Provider-specific detail: lives here, never in screens/widgets.
  static const String _userAgent =
      'iMAPS-FieldSync/1.0 (field-inspection capstone app)';

  static Future<RouteResult?> fetchDrivingRoute({
    required LatLng start,
    required LatLng end,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      final url =
          '$_baseUrl/route/v1/driving/'
          '${start.longitude},${start.latitude}'
          ';'
          '${end.longitude},${end.latitude}'
          '?overview=full&geometries=geojson&alternatives=false&generate_hints=false';

      final client = HttpClient();
      client.connectionTimeout = timeout;
      try {
        final request = await client.getUrl(Uri.parse(url));
        // Identify the application per the demo-server usage policy.
        request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
        final response = await request.close().timeout(timeout);
        if (response.statusCode != 200) return null;

        // Bound the BODY read too: connectionTimeout and the .timeout above
        // only cover connecting and receiving response headers. Without this
        // a stalled body stream could hang the call indefinitely.
        final body = await response
            .transform(utf8.decoder)
            .join()
            .timeout(timeout);
        final json = jsonDecode(body) as Map<String, dynamic>;
        if (json['code'] != 'Ok') return null;

        final routes = json['routes'] as List?;
        if (routes == null || routes.isEmpty) return null;
        final route = routes.first as Map<String, dynamic>;

        final coordinates =
            (route['geometry'] as Map<String, dynamic>)['coordinates'] as List;
        if (coordinates.isEmpty) return null;

        // GeoJSON coordinates are [lng, lat] pairs — flip to LatLng(lat, lng).
        final points = coordinates
            .map(
              (c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
            )
            .toList();

        return RouteResult(
          points: points,
          distanceMeters: (route['distance'] as num).toDouble(),
          durationSeconds: (route['duration'] as num).toDouble(),
        );
      } finally {
        client.close();
      }
    } catch (_) {
      // Offline, timeout, malformed response — caller falls back gracefully.
      return null;
    }
  }
}
