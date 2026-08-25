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
      final url = '$_baseUrl/route/v1/driving/'
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
        final body =
            await response.transform(utf8.decoder).join().timeout(timeout);
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
            .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
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