import 'dart:async';
import 'dart:ui';
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
import '../../../core/widgets/quick_actions_sheet.dart' show MapDetailPanel;
import '../../../core/theme/insight_theme.dart';
import 'package:provider/provider.dart';
import '../providers/inspection_provider.dart';
import '../widgets/inspection_step_header.dart';
import '../widgets/rosario_boundary_overlay.dart';
import '../widgets/map_connectivity_recovery.dart';

/// Fit both pins after flutter_map knows its viewport, before loading tiles for
/// the final camera. Manual first-frame moves can race its initial size event.
MapOptions siteMapOptions({required ll.LatLng parcel, ll.LatLng? device}) =>
    MapOptions(
      initialCenter: parcel,
      initialZoom: 17,
      initialCameraFit: device == null ? null : CameraFit.bounds(
        bounds: LatLngBounds.fromPoints([parcel, device]),
        maxZoom: 17,
        padding: const EdgeInsets.fromLTRB(50, 160, 50, 220),
      ),
    );

/// Site Verification (Step 1). Full-bleed map (matches Master's reference
/// picture 1 — edge-to-edge, floating glass controls) with a bent,
/// route-style line between device and target (matches Master's reference
/// picture 3), since — unlike the standalone Quick Actions map — this
/// screen DOES have a real distance to compare (Step 2/GPS Verification
/// uses the same number), so the route visual earns its place here.
///
/// NOTE on the route line (Route Guidance, Phase 1): the polyline is now a
/// REAL road-network route fetched from the free OSRM service (see
/// RouteService — no API key, no billing; demo server in dev, self-hosted
/// for production). When routing is unavailable (offline, timeout, error),
/// the screen falls back to the previous stylized bent line + haversine
/// distance so the screen never hard-fails on routing. The route loads
/// ASYNCHRONOUSLY after the map is already usable: it is an enhancement,
/// never a prerequisite for opening Step 1. Road-route distance/ETA are
/// navigation/orientation aids ONLY; the authoritative Site Verification
/// distance remains the parcel-boundary RPC / haversine number shown above
/// and must never be replaced by road-route distance.
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
  // Route Guidance (Phase 1): real road route from OSRM. Null when routing
  // is unavailable (offline/timeout/error) — the UI then falls back to the
  // stylized bent line and the existing straight-line/RPC distance.
  List<ll.LatLng>? _routePoints;
  // True when the displayed road route came from local cache rather than a
  // live OSRM response. Drives the honest "Cached road route · Offline" label
  // so a replayed route is never presented as freshly calculated.
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
  // Fullscreen map mode: hides the floating header/step bar and the bottom
  // card so the map fills the whole screen (field visibility). The recenter
  // control and the OSM attribution stay visible; the toggle flips icon.
  bool _fullscreen = false;

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
  /// leaves the existing fallback polyline untouched.
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
      // on any failure the bent line + straight-line/RPC distance remain.
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
    final fit = siteMapOptions(parcel: _parcelLatLng!, device: _deviceLatLng).initialCameraFit;
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
  /// The road-route polyline is deliberately left untouched here - the
  /// road route is orientation information fetched once per open; making
  /// it follow the inspector (rerouting) is a separate later phase.
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

  String _formatRouteDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(meters < 10000 ? 1 : 0)} km';
  }

  String _formatRouteDuration(double seconds) {
    final minutes = (seconds / 60).round();
    if (minutes < 1) return 'less than a minute';
    if (minutes < 60) return '$minutes min';
    return '${minutes ~/ 60}h ${minutes % 60}m';
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    return SensitiveScreen(
      child: Scaffold(
        backgroundColor: InsightTheme.bg,
        extendBodyBehindAppBar: true,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // ── Full-bleed map layer ─────────────────────────────────────
            if (_loading)
              const Center(child: ImapsLoadingIndicator(size: 60))
            else if (_error != null)
              _ErrorState(message: _error!, onRetry: _loadMapData)
            else
              FlutterMap(
                mapController: _mapController,
                options: siteMapOptions(parcel: _parcelLatLng!, device: _deviceLatLng),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.imaps.fieldsync',
                    // Lets a recovered network evict the tiles that failed
                    // while offline and refetch them (see MapConnectivityRecovery).
                    reset: _recovery.tileResetStream,
                    evictErrorTileStrategy:
                        EvictErrorTileStrategy.notVisibleRespectMargin,
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
                          strokeWidth: 4,
                          color: InsightTheme.blue1.withValues(alpha: 0.75),
                          borderStrokeWidth: 1,
                          borderColor: Colors.white.withValues(alpha: 0.8),
                        ),
                      ],
                    ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _parcelLatLng!,
                        width: 32,
                        height: 32,
                        child: Container(
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
                      ),
                      if (_deviceLatLng != null)
                        Marker(
                          point: _deviceLatLng!,
                          width: 34,
                          height: 34,
                          child: Container(
                            decoration: BoxDecoration(
                              color: InsightTheme.blue1,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: InsightTheme.blue1.withValues(
                                    alpha: 0.4,
                                  ),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  // Required attribution (OSM tile usage policy) — keep visible.
                  RichAttributionWidget(
                    attributions: [
                      TextSourceAttribution('© OpenStreetMap contributors'),
                      TextSourceAttribution('Municipal boundary: MPDO Rosario'),
                    ],
                    popupBackgroundColor: Colors.white,
                    showFlutterMapAttribution: false,
                  ),
                ],
              ),

            // ── Floating glass header — back button + title + step progress bar ───
            if (!_fullscreen)
              SafeArea(
                bottom: false,
                child: InspectionStepHeader(
                  title: 'Site Verification',
                  subtitle: task.location,
                  stepNumber: 1,
                  stepSubtitle: 'LOCATE TARGET',
                  onBack: () => Navigator.pop(context),
                ),
              ),

            // ── Floating recenter button. ────────────────────────────────
            // ―― Floating map controls: fullscreen toggle + recenter. The
            // controls slide up to the top corner in fullscreen mode since
            // the header they used to sit below is hidden. ――
            if (!_loading && _error == null) ...[
              Positioned(
                right: 16,
                top: _fullscreen ? 16 : 190,
                child: SafeArea(
                  bottom: false,
                  child: _GlassIconButton(
                    icon: _fullscreen
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                    onTap: () => setState(() => _fullscreen = !_fullscreen),
                  ),
                ),
              ),
              Positioned(
                right: 16,
                top: (_fullscreen ? 16 : 190) + 56,
                child: SafeArea(
                  bottom: false,
                  child: _GlassIconButton(
                    icon: Icons.center_focus_strong_rounded,
                    onTap: _fitBounds,
                  ),
                ),
              ),
            ],

            // ── Floating bottom card — status row + CTA combined into one
            // modern card (matches reference picture 1's bottom-card
            // style) instead of a separate status pill + button below it.
            if (!_loading && _error == null && !_fullscreen)
              // Map-first, and collapsible: a compact right-hand side pane in
              // landscape/tablet, a content-sized floating card otherwise, with
              // an explicit hide control so the map is never permanently
              // covered. Sized to its content so there is no dead space below
              // the CTA.
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                bottom: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: MapDetailPanel(
                        child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1F0B1440),
                          blurRadius: 32,
                          offset: Offset(0, 16),
                        ),
                      ],
                    ),
                    // Content-sized: the Column is mainAxisSize.min, so the
                    // card ends at the CTA instead of stretching to fill the
                    // pane. A side pane can be shorter than the card needs,
                    // so it scrolls internally while the map stays visible.
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: _detailCardChildren(context),
                      ),
                    ),
                  ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
  }

  /// Compact, field-readable information. The actual site distance and
  /// road-route distance are deliberately separate (different data sources).
  /// Step 1 navigation, GPS recovery and rework actions are unchanged.
  List<Widget> _detailCardChildren(BuildContext context) {
    final hasRoute = _routePoints != null && _routeDistanceMeters != null;
    final siteDistance = _distanceMeters == null
        ? 'Unavailable'
        : _formatRouteDistance(_distanceMeters!);
    final roadDistance = hasRoute
        ? _formatRouteDistance(_routeDistanceMeters!)
        : 'Unavailable';
    final eta = hasRoute && _routeDurationSeconds != null
        ? '~${_formatRouteDuration(_routeDurationSeconds!)}'
        : null;

    Widget metric({
      required String label,
      required String value,
      String? hint,
      Color valueColor = InsightTheme.ink,
    }) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
          style: InsightTheme.inter(10, w: FontWeight.w700,
              c: InsightTheme.ink3)),
        const SizedBox(height: 4),
        Text(value,
          softWrap: true,
          style: InsightTheme.urbanist(16, w: FontWeight.w800,
              c: valueColor)),
        if (hint != null) ...[
          const SizedBox(height: 2),
          Text(hint, style: InsightTheme.inter(10, c: InsightTheme.ink2)),
        ],
      ],
    );

    return <Widget>[
      Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: InsightTheme.amberTint,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.location_on_outlined,
                size: 19, color: InsightTheme.amberInk),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('TARGET SITE',
                  style: InsightTheme.inter(10, w: FontWeight.w700,
                      c: InsightTheme.ink3)),
                const SizedBox(height: 2),
                Text(widget.task.location,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: InsightTheme.urbanist(14, w: FontWeight.w700,
                      c: InsightTheme.ink)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7, height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _deviceLatLng == null
                        ? InsightTheme.ink3
                        : (_arrived ? InsightTheme.green : InsightTheme.amber),
                  ),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    _deviceLatLng == null
                        ? 'Location unknown'
                        : (_arrived ? 'Near site' : 'Outside zone'),
                    textAlign: TextAlign.right,
                    style: InsightTheme.inter(11, w: FontWeight.w700,
                        c: _deviceLatLng == null
                            ? InsightTheme.ink3
                            : (_arrived ? InsightTheme.green : InsightTheme.amberInk)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      // Comparable values sit together rather than in separate bulky cards.
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: InsightTheme.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: InsightTheme.line),
        ),
        child: LayoutBuilder(builder: (context, constraints) {
          final stacked = constraints.maxWidth < 235 ||
              MediaQuery.textScalerOf(context).scale(12) > 19;
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                metric(label: 'SITE DISTANCE', value: siteDistance,
                    hint: 'Direct distance'),
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 10),
                metric(label: 'ROAD ROUTE', value: roadDistance,
                    hint: eta),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: metric(label: 'SITE DISTANCE', value: siteDistance,
                    hint: 'Direct distance'),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                width: 1, height: 46,
                color: InsightTheme.line,
              ),
              Expanded(
                child: metric(label: 'ROAD ROUTE', value: roadDistance,
                    hint: eta),
              ),
            ],
          );
        }),
      ),
      if (_routeFromCache && hasRoute) ...[
        const SizedBox(height: 7),
        Row(
          children: [
            const Icon(Icons.offline_pin_outlined,
                size: 13, color: InsightTheme.ink3),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Offline · showing the saved road route',
                style: InsightTheme.inter(11, c: InsightTheme.ink2)),
            ),
          ],
        ),
      ],
      if (!hasRoute) ...[
        const SizedBox(height: 7),
        Row(
          children: [
            const Icon(Icons.route_outlined,
                size: 13, color: InsightTheme.ink3),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Road route unavailable. Use the site distance for guidance.',
                style: InsightTheme.inter(11, c: InsightTheme.ink2),
              ),
            ),
          ],
        ),
      ],
      const SizedBox(height: 8),
      if (_deviceLatLng == null)
        TextButton.icon(
          onPressed: _retryingDeviceLocation ? null : _retryDeviceLocation,
          icon: _retryingDeviceLocation
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.my_location_rounded, size: 16),
          label: const Text('Location unavailable · Tap to retry'),
        )
      else
        Row(
          children: [
            const Icon(Icons.my_location_rounded,
                size: 13, color: InsightTheme.blue1),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Current position available',
                style: InsightTheme.inter(11, c: InsightTheme.ink2)),
            ),
          ],
        ),
      if (_arrived) ...[
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: InsightTheme.greenTint,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  size: 16, color: InsightTheme.green),
              const SizedBox(width: 7),
              Expanded(
                child: Text('Near target site · Ready for GPS verification',
                  style: InsightTheme.inter(11, w: FontWeight.w600,
                      c: InsightTheme.green)),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              final isReworkMode = context
                                  .read<InspectionProvider>()
                                  .isReworkMode;
                              if (isReworkMode) {
                                // Issue 2 fix (Completed Category enhancement):
                                // this screen has no editable data of its own
                                // (pure map/location confirmation) — during rework
                                // there's nothing to push forward to, "Continue"
                                // would incorrectly advance the normal wizard
                                // instead of returning to Inspection Summary.
                                Navigator.pop(context);
                                return;
                              }
                              InspectionProgress.instance.markStepComplete(1);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      GpsVerificationScreen(task: widget.task),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ).copyWith(elevation: WidgetStateProperty.all(0)),
                            child: Ink(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    InsightTheme.blue1,
                                    InsightTheme.blue2,
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: InsightTheme.blue1.withValues(
                                      alpha: 0.32,
                                    ),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Container(
                                alignment: Alignment.center,
                                constraints: const BoxConstraints(
                                  minHeight: 52,
                                ),
                                width: double.infinity,
                                child: Text(
                                  context
                                          .watch<InspectionProvider>()
                                          .isReworkMode
                                      ? 'Save'
                                      : 'Proceed to Location',
                                  style: InsightTheme.poppins(
                                    15,
                                    w: FontWeight.w600,
                                    c: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
    ];
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: 44,
            height: 44,
            decoration: InsightTheme.glassIconButtonDecoration(),
            child: Icon(icon, size: 18, color: InsightTheme.ink),
          ),
        ),
      ),
    );
  }
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
