import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Shared OFFLINE → ONLINE recovery for the two map surfaces.
///
/// Both maps fetch the OSRM road route and the OSM basemap exactly once,
/// during `_loadMapData()`. There is no connectivity listener, so a device
/// that was offline when the screen opened stays on the local fallback route
/// with a grey basemap until the inspector leaves and re-enters the screen.
///
/// This class adds only that missing reaction:
///
///   * [tileResetStream] is handed to `TileLayer(reset: ...)`. flutter_map
///     caches failed tiles as error images, so a network that returns does not
///     by itself redraw anything — the layer must be told to reset.
///   * [start]'s [onOnline] fires once per genuine OFFLINE → ONLINE
///     transition, so the caller can re-attempt its network work.
///
/// It deliberately holds no map, route, persistence or boundary knowledge: it
/// only observes connectivity and signals a transition. Offline map data
/// (bundled boundary geometry, cached parcels) never passes through here.
class MapConnectivityRecovery {
  MapConnectivityRecovery({this.connectivity});

  /// Test seam only; production observes the platform inside [start].
  final Stream<List<ConnectivityResult>>? connectivity;

  final StreamController<void> _tileReset = StreamController<void>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  /// Null until the first reading is taken, so the initial state is recorded
  /// without firing [onOnline] — recovering from the state the screen was
  /// opened in is the caller's own `initState` job, not a transition.
  bool? _online;
  bool _disposed = false;

  /// Feed this to `TileLayer(reset: ...)` so a recovered network actually
  /// re-fetches the grey tiles.
  Stream<void> get tileResetStream => _tileReset.stream;

  /// Whether the last observed state is online.
  bool get isOnline => _online ?? false;

  /// True once [stop] has run, so a late event cannot touch a dead screen.
  bool get isDisposed => _disposed;

  /// Begins watching connectivity. Seeded with [initiallyOnline] so a screen
  /// opened while offline does not immediately treat its first event as a
  /// recovery. [onOnline] is invoked once per OFFLINE → ONLINE transition
  /// only — duplicate and repeated-online events are ignored.
  Future<void> start({
    required bool initiallyOnline,
    required Future<void> Function() onOnline,
  }) async {
    _online = initiallyOnline;
    final supplied = connectivity;
    if (supplied == null) {
      // Production: observe the platform. Only a transition triggers.
      _subscription = Connectivity().onConnectivityChanged.listen(
        (results) => _handle(results, onOnline),
      );
      return;
    }
    // Test seam: drive the same transition logic from a supplied stream.
    _subscription = supplied.listen((results) => _handle(results, onOnline));
  }

  void _handle(
    List<ConnectivityResult> results,
    Future<void> Function() onOnline,
  ) {
    if (_disposed) return;
    final nowOnline = results.any((r) => r != ConnectivityResult.none);
    final wasOnline = _online ?? false;
    _online = nowOnline;
    // Only a real OFFLINE → ONLINE edge is a recovery. Staying online (or
    // noisy repeated readings of the same state) must not refetch a route.
    if (nowOnline && !wasOnline) unawaited(onOnline());
  }

  /// Asks the tile layer to drop its failed tiles and refetch. Safe to call
  /// when already disposed.
  void resetTiles() {
    if (_disposed || _tileReset.isClosed) return;
    _tileReset.add(null);
  }

  Future<void> stop() async {
    _disposed = true;
    await _subscription?.cancel();
    _subscription = null;
    await _tileReset.close();
  }
}
