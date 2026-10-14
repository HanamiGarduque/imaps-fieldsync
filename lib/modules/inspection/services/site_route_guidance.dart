import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'spatial_offline_service.dart';

/// Step 1 guidance only. None of these decisions authorizes an inspection step.
bool validSiteMapPoint(LatLng point) =>
    point.latitude.isFinite &&
    point.longitude.isFinite &&
    point.latitude.abs() <= 90 &&
    point.longitude.abs() <= 180;

bool usableSiteRoad(List<LatLng> points) =>
    points.length >= 2 &&
    points.every(validSiteMapPoint) &&
    points.any((point) => point != points.first);

double sitePointDistance(LatLng a, LatLng b) =>
    SpatialOfflineService.haversineMeters(
      a.latitude,
      a.longitude,
      b.latitude,
      b.longitude,
    );

bool reliableSiteFix({
  required double accuracyMeters,
  required DateTime timestamp,
  required DateTime now,
}) {
  final age = now.difference(timestamp);
  return accuracyMeters.isFinite &&
      accuracyMeters > 0 &&
      accuracyMeters <= 25 &&
      age >= const Duration(seconds: -2) &&
      age <= const Duration(seconds: 15);
}

/// A poor/expired fix hides the notice without rearming its 100m episode.
bool siteApproachEpisode({
  required bool wasNear,
  required double distanceMeters,
  required bool reliable,
}) => !reliable || !distanceMeters.isFinite
    ? wasNear
    : wasNear
    ? distanceMeters < 140
    : distanceMeters <= 100;

/// Nearest point on an ordered road segment, not just its nearest vertex.
/// ponytail: local tangent projection suits these municipal road segments;
/// use geodesic segment projection if guidance expands to continental routes.
({LatLng point, double meters})? nearestSiteRoadPoint(
  LatLng position,
  List<LatLng> road,
) {
  if (!validSiteMapPoint(position) || !usableSiteRoad(road)) return null;
  final longitudeScale = math.max(
    math.cos(position.latitude * math.pi / 180).abs(),
    0.000001,
  );
  LatLng? nearest;
  var best = double.infinity;
  for (var i = 1; i < road.length; i++) {
    final a = road[i - 1];
    final b = road[i];
    final dx = (b.longitude - a.longitude) * longitudeScale;
    final dy = b.latitude - a.latitude;
    final lengthSquared = dx * dx + dy * dy;
    final fraction = lengthSquared == 0
        ? 0.0
        : (((position.longitude - a.longitude) * longitudeScale * dx +
                      (position.latitude - a.latitude) * dy) /
                  lengthSquared)
              .clamp(0.0, 1.0);
    final point = LatLng(
      a.latitude + (b.latitude - a.latitude) * fraction,
      a.longitude + (b.longitude - a.longitude) * fraction,
    );
    final meters = sitePointDistance(position, point);
    if (meters < best) {
      nearest = point;
      best = meters;
    }
  }
  return nearest == null ? null : (point: nearest, meters: best);
}

/// Schematic links only. The real GPS coordinate and road are never modified.
List<List<LatLng>> siteDirectLinks({
  required List<LatLng> road,
  required LatLng target,
  LatLng? device,
  required double accuracyMeters,
  required bool reliable,
}) {
  if (!usableSiteRoad(road) || !validSiteMapPoint(target)) return const [];
  final links = <List<LatLng>>[];
  if (device != null && reliable) {
    final nearest = nearestSiteRoadPoint(device, road);
    if (nearest != null &&
        nearest.meters > math.max(12, accuracyMeters * 1.5)) {
      links.add([device, nearest.point]);
    }
  }
  if (sitePointDistance(road.last, target) > 10) {
    links.add([road.last, target]);
  }
  return links;
}

/// Deviation is measured against the last requested origin's road offset.
/// An expected provider snap therefore does not trigger an endless retry loop.
bool siteRoadRefreshNeeded({
  required LatLng device,
  required LatLng? previousAttempt,
  required List<LatLng> road,
  required double accuracyMeters,
  required bool aged,
  required bool failed,
}) {
  if (previousAttempt == null || failed) return true;
  final moved = sitePointDistance(previousAttempt, device);
  if (moved >= math.max(30, accuracyMeters * 2)) return true;
  if (moved < 10) return false;
  if (aged) return true;
  final currentOffset = nearestSiteRoadPoint(device, road)?.meters;
  final originalOffset = nearestSiteRoadPoint(previousAttempt, road)?.meters;
  return currentOffset != null &&
      originalOffset != null &&
      currentOffset >= math.max(20, accuracyMeters * 2) &&
      currentOffset - originalOffset >= math.max(15, accuracyMeters);
}
