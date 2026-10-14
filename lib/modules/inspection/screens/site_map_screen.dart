import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../services/location_service.dart';
import '../inspection_constants.dart';
import '../../../core/services/route_service.dart';
import '../../../core/services/supabase_service.dart';
import 'gps_verification_screen.dart';
import '../../tasks/screens/tasks_screen.dart';
import 'inspection_progress.dart';

import 'package:connectivity_plus/connectivity_plus.dart';
import '../../../core/services/db_helper.dart';
import '../services/spatial_offline_service.dart';
import '../../../core/widgets/imaps_loading_indicator.dart';
import '../../../core/widgets/sensitive_screen.dart';
import '../../../core/theme/insight_theme.dart';
import 'package:provider/provider.dart';
import '../providers/inspection_provider.dart';
import '../widgets/site_verification_view.dart';
import '../widgets/rosario_boundary_overlay.dart';
import '../widgets/map_connectivity_recovery.dart';

/// Fit both pins after flutter_map knows its viewport, before loading tiles for
/// the final camera. Manual first-frame moves can race its initial size event.
MapOptions siteMapOptions({
  required ll.LatLng parcel,
  ll.LatLng? device,
  List<ll.LatLng> route = const [],
  EdgeInsets padding = const EdgeInsets.fromLTRB(50, 160, 50, 220),
}) => MapOptions(
  initialCenter: parcel,
  initialZoom: 17,
  initialCameraFit: CameraFit.bounds(
    bounds: LatLngBounds.fromPoints([
      parcel,
      ?device,
      ...route,
    ]),
    maxZoom: 17,
    padding: padding,
  ),
);

/// Site Verification (Step 1): task-bound GPS, cached/live real road geometry
/// and the existing inspection callbacks, with orientation-aware presentation.
/// Road distance and driving time are guidance only; the separate site distance
/// remains the parcel-boundary RPC / offline Haversine measurement. Routing
/// failure preserves the last real route, or draws none when none is available.
///
///   - Parcel coordinates: SupabaseService.fetchParcelDetails(parcelId)
///   - Device position: LocationService.getCurrentLocation()
///   - Distance: SupabaseService.getDistanceToParcelBoundary() (same RPC
///     Step 2 uses, so the number here matches what Step 2 will show —
///     no confusing discrepancy between the two screens).
class SiteMapScreen extends StatefulWidget {
  final TaskItem task;
  const SiteMapScreen({super.key, required this.task});

  @override
  State<SiteMapScreen> createState() => _SiteMapScreenState();
}

class _SiteMapScreenState extends State<SiteMapScreen>
    with WidgetsBindingObserver {
  bool _loading = true;
  String? _error;

  ll.LatLng? _parcelLatLng;
  ll.LatLng? _deviceLatLng;
  double? _distanceMeters;
  bool _retryingDeviceLocation = false;
  // Real road route only. Routing failure never supplies fabricated geometry.
  List<ll.LatLng>? _routePoints;
  // Cache provenance is independent of the current connectivity state.
  bool _routeFromCache = false;
  double? _routeDistanceMeters;
  double? _routeDurationSeconds;
  // Live GPS tracking (Phase B): the device marker and the authoritative
  // distance update from the SAME shared LocationService stream that
  // GPS Verification (Step 2) uses.
  StreamSubscription<Position>? _positionSub;
  bool _trackingActive = false;
  bool _recomputingDistance = false;
  DateTime _lastDistanceComputeAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _minDistanceRecalcInterval = Duration(seconds: 4);
  ll.LatLng? _routeOrigin;
  bool _routeRequestInFlight = false;
  int _routeRequestVersion = 0;
  DateTime _lastRouteRequestAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const double _routeRefreshMovementMeters = 50.0;
  static const Duration _routeRefreshCooldown = Duration(seconds: 30);
  final MapController _mapController = MapController();
  EdgeInsets _mapPadding = const EdgeInsets.fromLTRB(50, 160, 50, 220);

  // Offline → ONLINE recovery: retries the OSM basemap and the OSRM road
  // route without the inspector leaving Step 1. Holds no map or business
  // state — see MapConnectivityRecovery.
  final MapConnectivityRecovery _recovery = MapConnectivityRecovery();

  /// Phase C: Arrival detection — true when the inspector is sufficiently
  /// close to the target site. Uses the same threshold as GPS Verification
  /// (Step 2) so the experience is consistent across the workflow.
  bool get _arrived =>
      _distanceMeters != null &&
      _distanceMeters! <= siteVerificationDistanceThresholdMeters;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_startRecovery());
    // Restore any previously cached real route first, so opening this task
    // offline still draws genuine road geometry.
    unawaited(_restoreCachedRoute());
    _loadMapData();
  }

  /// Seeds the watcher with the connectivity state this screen actually opened
  /// in, so only a genuine later transition counts as a recovery.
  Future<void> _startRecovery() async {
    final online = await _checkOnline();
    if (!mounted) return;
    await _recovery.start(
      initiallyOnline: online,
      onOnline: _onConnectivityRecovered,
    );
  }

  /// Network is back: drop the grey OSM tiles so they refetch, and retry the
  /// road route once for the current device position + target. A failed retry
  /// leaves the existing real geometry untouched.
  Future<void> _onConnectivityRecovered() async {
    if (!mounted) return;
    _recovery.resetTiles();
    await _fetchRouteAndUpdate(online: true);
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_recovery.stop());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Bug fix: previously the only way to pick up a location-service
    // change (inspector turns Location back on, or grants the permission,
    // from the system Settings screen) was to leave this screen entirely
    // and reopen it — initState() was the only thing that ever called
    // _loadMapData(). Now, coming back to the app after being backgrounded
    // (e.g. returning from Settings) automatically retries the device
    // position if it wasn't available before, without needing a full
    // parcel/map reload or a manual back-and-forth.
    if (state == AppLifecycleState.resumed && !_loading) {
      // Restart live tracking if the stream dropped since backgrounding
      // (idempotent while tracking is already active).
      _startLiveTracking();
      if (_deviceLatLng == null) {
        _retryDeviceLocation();
      }
    }
  }

  /// Lightweight retry — re-fetches just the device position/distance,
  /// without re-fetching parcel details or refitting the map. Used by the
  /// app-resume hook above and by the tappable "Location unavailable"
  /// badge at the bottom of the map.
  Future<void> _retryDeviceLocation() async {
    if (_retryingDeviceLocation || _parcelLatLng == null) return;
    setState(() => _retryingDeviceLocation = true);
    try {
      final online = await _checkOnline();
      final pos = await LocationService.getCurrentLocation();
      final newDeviceLatLng = ll.LatLng(pos.latitude, pos.longitude);
      final newDistance = online
          ? await SupabaseService.getDistanceToParcelBoundary(
              parcelId: widget.task.parcelId!,
              latitude: pos.latitude,
              longitude: pos.longitude,
            )
          : SpatialOfflineService.haversineMeters(
              pos.latitude,
              pos.longitude,
              _parcelLatLng!.latitude,
              _parcelLatLng!.longitude,
            );
      if (!mounted) return;
      setState(() {
        _deviceLatLng = newDeviceLatLng;
        _distanceMeters = newDistance;
        _retryingDeviceLocation = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitBounds());
      // Refresh the road route from the new position asynchronously - the
      // location retry must never wait on OSRM (same best-effort contract).
      unawaited(_fetchRouteAndUpdate(online: online));
    } catch (_) {
      // Still unavailable — leave the badge as a retry target, no need to
      // surface a separate error for this secondary, best-effort fetch.
      if (!mounted) return;
      setState(() => _retryingDeviceLocation = false);
    }
  }

  Future<void> _loadMapData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (widget.task.parcelId == null) {
        throw Exception('No parcel linked to this task.');
      }

      final online = await _checkOnline();
      double? lat;
      double? lng;

      if (online) {
        final parcel = await SupabaseService.fetchParcelDetails(
          widget.task.parcelId!,
        );
        lat = (parcel?['latitude'] as num?)?.toDouble();
        lng = (parcel?['longitude'] as num?)?.toDouble();
      } else {
        // Offline — read the coordinates DBHelper.cacheJobs() already saved
        // locally last time this list was fetched online, instead of
        // silently failing the network call and showing a misleading
        // "no coordinates" message.
        final cached = await DBHelper.getCachedJobs();
        final match = cached.where((j) => j['id'] == widget.task.id).toList();
        if (match.isNotEmpty) {
          lat = (match.first['parcel_lat'] as num?)?.toDouble();
          lng = (match.first['parcel_lng'] as num?)?.toDouble();
        }
      }

      if (lat == null || lng == null) {
        throw Exception(
          online
              ? 'This parcel has no recorded coordinates yet.'
              : 'No cached coordinates for this site yet — connect to the internet once so it can be saved for offline use.',
        );
      }
      _parcelLatLng = ll.LatLng(lat, lng);

      // Device position is best-effort here — Step 1 is about orientation,
      // not verification, so a location error still lets the inspector see
      // the target site on the map and proceed; only Step 2 hard-requires it.
      try {
        final pos = await LocationService.getCurrentLocation();
        _deviceLatLng = ll.LatLng(pos.latitude, pos.longitude);
        _distanceMeters = online
            ? await SupabaseService.getDistanceToParcelBoundary(
                parcelId: widget.task.parcelId!,
                latitude: pos.latitude,
                longitude: pos.longitude,
              )
            : SpatialOfflineService.haversineMeters(
                pos.latitude,
                pos.longitude,
                lat,
                lng,
              );
      } catch (_) {
        _deviceLatLng = null;
        _distanceMeters = null;
      }

      if (!mounted) return;
      setState(() => _loading = false);
      _startLiveTracking();

      // Route Guidance: fetch the road route AFTER the map is usable -
      // OSRM latency must never delay opening Step 1. Best-effort only:
      // on any failure the last real route and separate site distance remain.
      unawaited(_fetchRouteAndUpdate(online: online));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _fitBounds() {
    if (!mounted || _parcelLatLng == null) return;
    final fit = siteMapOptions(
      parcel: _parcelLatLng!,
      device: _deviceLatLng,
      route: _routePoints ?? const [],
      padding: _mapPadding,
    ).initialCameraFit;
    if (fit == null) {
      _mapController.move(_parcelLatLng!, 17);
      return;
    }
    _mapController.fitCamera(fit);
  }

  /// Starts live GPS tracking for this screen using the SAME shared
  /// LocationService stream Step 2 uses (high accuracy, 4 m distance
  /// filter). Idempotent: safe to call from load completion and on every
  /// app-resume.
  void _startLiveTracking() {
    if (_trackingActive) return;
    _trackingActive = true;
    _positionSub = LocationService.getPositionStream().listen(
      _onPositionUpdate,
      onError: (Object e) {
        // Stream died (e.g. location service switched off mid-session).
        // Allow a later app-resume to restart it.
        if (!mounted) return;
        setState(() => _trackingActive = false);
      },
      cancelOnError: true,
    );
  }

  /// Live position tick: moves the "You are here" marker on EVERY event
  /// and refreshes the AUTHORITATIVE Site Verification distance (boundary
  /// RPC online / haversine offline) behind a reentrancy guard plus a
  /// minimum recalculation interval so rapid ticks cannot flood Supabase.
  /// Online road requests have their own movement/cooldown guard below; GPS
  /// ticks never fabricate geometry or directly change its cached copy.
  Future<void> _onPositionUpdate(Position pos) async {
    if (!mounted || _parcelLatLng == null) return;
    final newPos = ll.LatLng(pos.latitude, pos.longitude);
    final shouldRecompute =
        !_recomputingDistance &&
        DateTime.now().difference(_lastDistanceComputeAt) >=
            _minDistanceRecalcInterval;

    // Move the marker immediately and repaint in EVERY path so the UI is
    // never frozen behind a throttled or in-flight distance recompute.
    _deviceLatLng = newPos;
    setState(() {});
    unawaited(_maybeRefreshRoute(newPos));

    if (!shouldRecompute) {
      return;
    }
    _recomputingDistance = true;
    _lastDistanceComputeAt = DateTime.now();
    try {
      final online = await _checkOnline();
      final dist = online
          ? await SupabaseService.getDistanceToParcelBoundary(
              parcelId: widget.task.parcelId!,
              latitude: pos.latitude,
              longitude: pos.longitude,
            )
          : SpatialOfflineService.haversineMeters(
              pos.latitude,
              pos.longitude,
              _parcelLatLng!.latitude,
              _parcelLatLng!.longitude,
            );
      if (!mounted) return;
      setState(() => _distanceMeters = dist);
    } catch (_) {
      // Transient failure: keep the previous authoritative value; the next
      // qualifying tick retries. The marker was already painted above.
    } finally {
      _recomputingDistance = false;
    }
  }

  /// Single source of the online/offline decision for this screen. It only
  /// gates whether ONLINE calls (Supabase RPC, OSRM route fetch) are
  /// attempted; every network/routing operation itself lives in its service
  /// (SupabaseService / LocationService / RouteService).
  Future<bool> _checkOnline() async {
    final dynamic connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult is List
        ? connectivityResult.any((r) => r != ConnectivityResult.none)
        : connectivityResult != ConnectivityResult.none;
  }

  /// Post-paint route request (initial open, location retries, and controlled
  /// movement refreshes). Road-route distance/ETA are navigation/orientation
  /// aids only - the authoritative Site Verification distance remains the
  /// boundary-RPC/haversine number.
  Future<void> _fetchRouteAndUpdate({required bool online}) async {
    if (!online || _deviceLatLng == null || _parcelLatLng == null) return;
    await _fetchRoute(start: _deviceLatLng!);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _maybeRefreshRoute(ll.LatLng currentPosition) async {
    if (_routeRequestInFlight ||
        DateTime.now().difference(_lastRouteRequestAt) <
            _routeRefreshCooldown) {
      return;
    }

    if (_routeOrigin != null) {
      final movedMeters = Geolocator.distanceBetween(
        _routeOrigin!.latitude,
        _routeOrigin!.longitude,
        currentPosition.latitude,
        currentPosition.longitude,
      );
      if (movedMeters < _routeRefreshMovementMeters) return;
    }
    if (!await _checkOnline() || !mounted) return;

    await _fetchRoute(start: currentPosition);
    if (!mounted) return;
    setState(() {});
  }

  /// Fetches a route through [RouteService]. A failed refresh preserves the
  /// last successful route, while the request version prevents an older
  /// asynchronous response from replacing a newer one.
  Future<void> _fetchRoute({required ll.LatLng start}) async {
    if (_parcelLatLng == null || _routeRequestInFlight) return;
    _routeRequestInFlight = true;
    final requestVersion = ++_routeRequestVersion;
    _lastRouteRequestAt = DateTime.now();
    _routeOrigin = start;
    try {
      final result = await RouteService.fetchDrivingRoute(
        start: start,
        end: _parcelLatLng!,
      );
      if (result == null || requestVersion != _routeRequestVersion) return;
      _routePoints = result.points;
      _routeDistanceMeters = result.distanceMeters;
      _routeDurationSeconds = result.durationSeconds;
      _routeFromCache = false;
      unawaited(_persistRoute(result, start));
    } finally {
      if (requestVersion == _routeRequestVersion) {
        _routeRequestInFlight = false;
      }
    }
  }

  /// Persists a freshly fetched REAL route so it survives going offline.
  ///
  /// Best-effort by design: a cache write failure must never take down the
  /// route the inspector is already looking at, nor Step 1 itself. On failure
  /// the route simply stays online-only until the next successful fetch.
  Future<void> _persistRoute(RouteResult result, ll.LatLng origin) async {
    try {
      await DBHelper.saveRouteCache(
        CachedRoute.fromRoute(
          jobId: widget.task.id,
          route: result,
          origin: origin,
        ),
      );
    } catch (e) {
      debugPrint('[SITE MAP] Could not cache road route: $e');
    }
  }

  /// Restores this task's previously cached real road route.
  ///
  /// Runs on every open, offline or not, BEFORE any network fetch. A fresh
  /// online route fetched later simply overwrites both the displayed geometry
  /// and the cache, so showing the cached copy first costs nothing and means an
  /// offline open still draws genuine road geometry.
  Future<void> _restoreCachedRoute() async {
    try {
      final cached = await DBHelper.getRouteCache(widget.task.id);
      if (cached == null || !mounted) return;
      _routePoints = cached.points;
      _routeDistanceMeters = cached.distanceMeters;
      _routeDurationSeconds = cached.durationSeconds;
      _routeFromCache = true;
      setState(() {});
    } catch (e) {
      debugPrint('[SITE MAP] Could not read cached road route: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    return SensitiveScreen(
      child: Scaffold(
        backgroundColor: InsightTheme.bg,
        body: SiteVerificationView(
          location: widget.task.location,
          ready: !_loading && _error == null,
          hasDeviceLocation: _deviceLatLng != null,
          retryingLocation: _retryingDeviceLocation,
          distanceMeters: _distanceMeters,
          hasRoute: _routePoints != null,
          routeFromCache: _routeFromCache,
          routeDistanceMeters: _routeDistanceMeters,
          routeDurationSeconds: _routeDurationSeconds,
          nearSite: _arrived,
          rework: context.watch<InspectionProvider>().isReworkMode,
          onBack: () => Navigator.pop(context),
          onRetryLocation: _retryDeviceLocation,
          onFit: _fitBounds,
          onProceed: _proceed,
          mapBuilder: (padding) {
            _mapPadding = padding;
            if (_loading) {
              return const Center(child: ImapsLoadingIndicator(size: 60));
            }
            if (_error != null) {
              return _ErrorState(message: _error!, onRetry: _loadMapData);
            }
            return _buildMap();
          },
        ),
      ),
    );
  }

  void _proceed() {
    HapticFeedback.selectionClick();
    if (context.read<InspectionProvider>().isReworkMode) {
      Navigator.pop(context);
      return;
    }
    InspectionProgress.instance.markStepComplete(1);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GpsVerificationScreen(task: widget.task),
      ),
    );
  }

  Widget _buildMap() => FlutterMap(
    mapController: _mapController,
    options: siteMapOptions(
      parcel: _parcelLatLng!,
      device: _deviceLatLng,
      route: _routePoints ?? const [],
      padding: _mapPadding,
    ),
    children: [
      TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.imaps.fieldsync',
        // Lets a recovered network evict the tiles that failed
        // while offline and refetch them (see MapConnectivityRecovery).
        reset: _recovery.tileResetStream,
        evictErrorTileStrategy: EvictErrorTileStrategy.notVisibleRespectMargin,
      ),
      const RosarioBoundaryOverlay(),
      // Only ever real road geometry: a live OSRM route, or the
      // same route restored from local cache while offline. There
      // is deliberately NO synthetic fallback — a made-up line
      // must not be drawn as if it were a road.
      if (_routePoints != null)
        PolylineLayer(
          polylines: [
            Polyline(
              points: _routePoints!,
              strokeWidth: 5,
              color: InsightTheme.blue1,
              borderStrokeWidth: 2,
              borderColor: Colors.white,
            ),
          ],
        ),
      MarkerLayer(
        markers: [
          Marker(
            point: _parcelLatLng!,
            width: 32,
            height: 32,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: InsightTheme.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: InsightTheme.red.withValues(alpha: 0.4),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
                const Positioned(
                  left: 38,
                  top: 0,
                  child: _MapMarkerLabel('Target site'),
                ),
              ],
            ),
          ),
          if (_deviceLatLng != null)
            Marker(
              point: _deviceLatLng!,
              width: 34,
              height: 34,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: InsightTheme.blue1,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: InsightTheme.blue1.withValues(alpha: 0.4),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                  const Positioned(
                    left: 17,
                    bottom: 36,
                    child: FractionalTranslation(
                      translation: Offset(-0.5, 0),
                      child: _MapMarkerLabel('You'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ],
  );
}

class _MapMarkerLabel extends StatelessWidget {
  const _MapMarkerLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: InsightTheme.line),
      ),
      child: Text(
        label,
        style: InsightTheme.inter(12, w: FontWeight.w600, c: InsightTheme.ink),
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: InsightTheme.bg,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.location_off_rounded,
                size: 40,
                color: InsightTheme.ink3,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: InsightTheme.inter(13, c: InsightTheme.ink2),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
