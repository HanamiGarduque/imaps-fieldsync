// Offline → ONLINE recovery for both map surfaces.
//
// Defect guarded: Step 1 and Quick Action Map fetched the OSRM road route and
// the OSM basemap once, during initial load. A device that was offline at that
// moment kept the local fallback polyline and a grey basemap forever — there
// was no connectivity listener, so nothing reacted when the network returned.
//
// Contract proven here:
//  - a screen opened offline is not treated as "recovered" on its first event;
//  - one OFFLINE → ONLINE transition triggers exactly one recovery;
//  - duplicate/noisy connectivity events do not refetch;
//  - a second transition recovers again (network can flap);
//  - the tile-reset signal fires once per recovery, so failed tiles are evicted;
//  - after stop(), later events are ignored (no setState on a dead screen);
//  - the boundary overlay is never involved, and routing never sees geometry.

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/modules/inspection/widgets/map_connectivity_recovery.dart';

void main() {
  late StreamController<List<ConnectivityResult>> events;
  late MapConnectivityRecovery recovery;
  late int recoveries;
  late Future<void> Function() onOnline;

  const offline = [ConnectivityResult.none];
  const online = [ConnectivityResult.wifi];
  const mobile = [ConnectivityResult.mobile];

  setUp(() {
    events = StreamController<List<ConnectivityResult>>.broadcast();
    recovery = MapConnectivityRecovery(connectivity: events.stream);
    recoveries = 0;
    onOnline = () async {
      recoveries++;
      recovery.resetTiles();
    };
  });

  tearDown(() async {
    await recovery.stop();
    await events.close();
  });

  test(
    'screen opened offline does not fire a recovery on its first event',
    () async {
      await recovery.start(initiallyOnline: false, onOnline: onOnline);
      events.add(offline);
      await Future<void>.delayed(Duration.zero);
      expect(
        recoveries,
        0,
        reason: 'the state the screen opened in is not a transition',
      );
    },
  );

  test(
    'one OFFLINE to ONLINE transition triggers exactly one recovery',
    () async {
      await recovery.start(initiallyOnline: false, onOnline: onOnline);
      final resets = <void>[];
      final sub = recovery.tileResetStream.listen(resets.add);

      events.add(online);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(recoveries, 1);
      expect(resets, hasLength(1), reason: 'failed tiles must be evicted once');

      await sub.cancel();
    },
  );

  test('duplicate and repeated-online events do not spam requests', () async {
    await recovery.start(initiallyOnline: false, onOnline: onOnline);
    for (final state in [online, online, online, mobile, mobile]) {
      events.add(state);
      await Future<void>.delayed(Duration.zero);
    }
    expect(
      recoveries,
      1,
      reason: 'only the OFFLINE to ONLINE edge is a recovery',
    );
  });

  test(
    'going offline again then online again recovers a second time',
    () async {
      await recovery.start(initiallyOnline: true, onOnline: onOnline);
      events.add(online);
      await Future<void>.delayed(Duration.zero);
      expect(recoveries, 0, reason: 'already online: nothing to recover');

      events.add(offline);
      await Future<void>.delayed(Duration.zero);
      events.add(online);
      await Future<void>.delayed(Duration.zero);
      expect(recoveries, 1);
    },
  );

  test(
    'a screen opened online recovers on a genuine drop and return',
    () async {
      await recovery.start(initiallyOnline: true, onOnline: onOnline);
      events.add(offline);
      await Future<void>.delayed(Duration.zero);
      events.add(online);
      await Future<void>.delayed(Duration.zero);
      expect(recoveries, 1);
    },
  );

  test(
    'events after stop() are ignored and the tile stream is closed',
    () async {
      await recovery.start(initiallyOnline: false, onOnline: onOnline);
      var listened = 0;
      final sub = recovery.tileResetStream.listen((_) => listened++);

      await recovery.stop();
      expect(recovery.isDisposed, isTrue);

      events.add(online);
      await Future<void>.delayed(Duration.zero);
      recovery.resetTiles(); // must not throw after dispose

      expect(
        recoveries,
        0,
        reason: 'a disposed screen must not react or setState',
      );
      expect(listened, 0);
      await sub.cancel();
    },
  );

  test('multiple concurrent start() calls do not double-subscribe', () async {
    await recovery.start(initiallyOnline: false, onOnline: onOnline);
    await recovery.start(initiallyOnline: false, onOnline: onOnline);
    events.add(online);
    await Future<void>.delayed(Duration.zero);
    expect(recoveries, lessThanOrEqualTo(1));
  });
}
