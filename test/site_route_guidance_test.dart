import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:imaps_fieldsync/modules/inspection/services/site_route_guidance.dart';

void main() {
  const road = [LatLng(13.842, 121.177), LatLng(13.848, 121.177)];
  const target = LatLng(13.848, 121.178);

  test('nearest road point projects onto the segment, not a route vertex', () {
    final nearest = nearestSiteRoadPoint(const LatLng(13.846, 121.178), road)!;
    expect(nearest.point.latitude, closeTo(13.846, 0.0000001));
    expect(nearest.point.longitude, 121.177);
    expect(nearest.meters, inInclusiveRange(107, 110));
    final before = nearestSiteRoadPoint(const LatLng(13.84, 121.176), road)!;
    expect(before.point, road.first);
    final after = nearestSiteRoadPoint(const LatLng(13.85, 121.178), road)!;
    expect(after.point, road.last);
  });

  test(
    'repeated vertices are harmless but wholly degenerate roads are absent',
    () {
      expect(usableSiteRoad([road.first, road.first]), isFalse);
      expect(nearestSiteRoadPoint(road.first, [road.first]), isNull);
      expect(
        nearestSiteRoadPoint(road.first, [road.first, ...road])!.meters,
        0,
      );
      expect(usableSiteRoad([road.first, const LatLng(91, 121)]), isFalse);
      expect(usableSiteRoad([road.first, const LatLng(13, 181)]), isFalse);
      expect(usableSiteRoad([road.first, LatLng(double.nan, 121)]), isFalse);
    },
  );

  test('accuracy-sized GPS gaps do not masquerade as off-road access', () {
    final links = siteDirectLinks(
      road: road,
      target: road.last,
      device: const LatLng(13.846, 121.1772), // ~22 m lateral offset.
      accuracyMeters: 20,
      reliable: true,
    );
    expect(links, isEmpty); // Inside 1.5× the reported accuracy.
    final visible = siteDirectLinks(
      road: road,
      target: road.last,
      device: const LatLng(13.846, 121.1775), // ~54 m lateral offset.
      accuracyMeters: 20,
      reliable: true,
    );
    expect(visible, hasLength(1));
    expect(visible.single.first, const LatLng(13.846, 121.1775));
    expect(visible.single.last.latitude, closeTo(13.846, 0.0000001));
    expect(visible.single.last.longitude, 121.177);
    expect(road.first, const LatLng(13.842, 121.177));
  });

  test('target link needs a real route but does not need a GPS fix', () {
    expect(
      siteDirectLinks(
        road: road,
        target: target,
        accuracyMeters: double.infinity,
        reliable: false,
      ),
      [
        [road.last, target],
      ],
    );
    expect(
      siteDirectLinks(
        road: [],
        target: target,
        device: road.first,
        accuracyMeters: 5,
        reliable: true,
      ),
      isEmpty,
    );
  });

  for (final gap in [0, 20, 50, 100]) {
    test('both connector ends with a ${gap}m gap and 25m GPS accuracy', () {
      const straightRoad = [LatLng(0, 0), LatLng(0.01, 0)];
      // At the equator, a longitude degree is about 111,195 m.
      final longitude = gap / 111195;
      final fix = LatLng(0.005, longitude);
      final destination = LatLng(0.01, longitude);
      final links = siteDirectLinks(
        road: straightRoad,
        target: destination,
        device: fix,
        accuracyMeters: 25,
        reliable: true,
      );
      expect(
        links,
        hasLength(switch (gap) {
          0 => 0,
          20 => 1,
          _ => 2,
        }),
      );
      if (gap >= 50) {
        expect(links.first, [fix, const LatLng(0.005, 0)]);
      }
      if (gap > 0) expect(links.last, [straightRoad.last, destination]);
    });
  }

  final now = DateTime.utc(2026, 10, 14, 12);
  for (final sample in [
    (accuracy: 25.0, ageSeconds: 15, reliable: true),
    (accuracy: 25.01, ageSeconds: 0, reliable: false),
    (accuracy: 5.0, ageSeconds: 16, reliable: false),
    (accuracy: 5.0, ageSeconds: -2, reliable: true),
    (accuracy: 5.0, ageSeconds: -3, reliable: false),
    (accuracy: 0.0, ageSeconds: 0, reliable: false),
    (accuracy: -1.0, ageSeconds: 0, reliable: false),
    (accuracy: double.nan, ageSeconds: 0, reliable: false),
  ]) {
    test('GPS reliability ${sample.accuracy}m / ${sample.ageSeconds}s', () {
      expect(
        reliableSiteFix(
          accuracyMeters: sample.accuracy,
          timestamp: now.subtract(Duration(seconds: sample.ageSeconds)),
          now: now,
        ),
        sample.reliable,
      );
    });
  }

  test('100m entry and 140m exit form one stable advisory episode', () {
    var episode = false;
    for (final sample in [
      (meters: 101.0, expected: false),
      (meters: 100.0, expected: true),
      (meters: 105.0, expected: true),
      (meters: 99.0, expected: true),
      (meters: 139.9, expected: true),
      (meters: 140.0, expected: false),
      (meters: 105.0, expected: false),
      (meters: 30.0, expected: true),
    ]) {
      episode = siteApproachEpisode(
        wasNear: episode,
        distanceMeters: sample.meters,
        reliable: true,
      );
      expect(episode, sample.expected, reason: '${sample.meters}m');
    }
    expect(
      siteApproachEpisode(wasNear: false, distanceMeters: 50, reliable: false),
      isFalse,
    );
    expect(
      siteApproachEpisode(wasNear: true, distanceMeters: 200, reliable: false),
      isTrue,
    ); // Unreliable data cannot rearm the episode.
  });

  test(
    'refresh policy distinguishes motion, deviation and expected road snaps',
    () {
      bool needs(
        LatLng device, {
        LatLng? previous = const LatLng(13.842, 121.177),
        double accuracy = 5,
        bool aged = false,
        bool failed = false,
      }) => siteRoadRefreshNeeded(
        device: device,
        previousAttempt: previous,
        road: road,
        accuracyMeters: accuracy,
        aged: aged,
        failed: failed,
      );
      expect(needs(const LatLng(13.84226, 121.177)), isFalse); // ~29m.
      expect(needs(const LatLng(13.8423, 121.177)), isTrue); // ~33m.
      expect(needs(const LatLng(13.8423, 121.177), accuracy: 20), isFalse);
      expect(needs(const LatLng(13.842, 121.1772)), isTrue); // ~22m deviation.
      expect(needs(const LatLng(13.842, 121.1772), accuracy: 20), isFalse);
      expect(
        needs(
          const LatLng(13.842, 121.1772),
          previous: const LatLng(13.842, 121.1772),
        ),
        isFalse,
      );
      expect(needs(const LatLng(13.8421, 121.177), aged: true), isTrue);
      expect(needs(road.first, aged: true), isFalse); // No idle polling.
      expect(
        needs(road.first, failed: true),
        isTrue,
      ); // Still budgeted by screen.
      expect(needs(road.first, previous: null), isTrue);
    },
  );
}
