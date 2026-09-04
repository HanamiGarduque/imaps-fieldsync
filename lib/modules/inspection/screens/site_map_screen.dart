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
import '../../../core/theme/insight_theme.dart';
import 'package:provider/provider.dart';
import '../providers/inspection_provider.dart';
import '../widgets/inspection_step_header.dart';

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
    _loadMapData();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
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
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitBounds());
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
    if (_parcelLatLng == null) return;
    if (_deviceLatLng == null) {
      _mapController.move(_parcelLatLng!, 17);
      return;
    }
    final bounds = LatLngBounds.fromPoints([_parcelLatLng!, _deviceLatLng!]);
    _mapController.fitCamera(
      // Extra top/bottom padding vs the old card layout — the floating
      // header and bottom card now sit ON TOP of the full-bleed map
      // instead of squeezing it into a smaller container, so bounds
      // fitting needs more clearance to keep both pins clear of them.
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.fromLTRB(50, 160, 50, 220),
      ),
    );
  }

  /// Stylized route path between two points — NOT a real road-network
  /// route (no routing-service dependency here, see class doc comment).
  /// Purely a presentation choice so the line reads like a real route
  /// instead of a straight "as the crow flies" line.
  List<ll.LatLng> _buildRoutePath(ll.LatLng start, ll.LatLng end) {
    final dLat = end.latitude - start.latitude;
    final dLng = end.longitude - start.longitude;
    final p1 = ll.LatLng(
      start.latitude + dLat * 0.10,
      start.longitude + dLng * 0.52,
    );
    final p2 = ll.LatLng(
      start.latitude + dLat * 0.62,
      start.longitude + dLng * 0.52,
    );
    final p3 = ll.LatLng(
      start.latitude + dLat * 0.62,
      start.longitude + dLng * 0.86,
    );
    return [start, p1, p2, p3, end];
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
    } finally {
      if (requestVersion == _routeRequestVersion) {
        _routeRequestInFlight = false;
      }
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
                options: MapOptions(
                  initialCenter: _parcelLatLng!,
                  initialZoom: 17,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.imaps.fieldsync',
                  ),
                  if (_deviceLatLng != null)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points:
                              _routePoints ??
                              _buildRoutePath(_deviceLatLng!, _parcelLatLng!),
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
              Positioned(
                left: 16,
                right: 16,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.circle,
                              size: 10,
                              color: InsightTheme.red,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Target Site',
                              style: InsightTheme.inter(
                                12,
                                w: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap:
                              _deviceLatLng == null && !_retryingDeviceLocation
                              ? _retryDeviceLocation
                              : null,
                          child: Row(
                            children: [
                              const Icon(
                                Icons.circle,
                                size: 10,
                                color: InsightTheme.blue1,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _deviceLatLng == null
                                      ? 'Location unavailable — tap to retry'
                                      : _distanceMeters != null
                                      ? 'You (${_distanceMeters!.round()}m)'
                                      : 'You',
                                  style: InsightTheme.inter(
                                    12,
                                    w: FontWeight.w600,
                                    c: InsightTheme.ink2,
                                  ),
                                ),
                              ),
                              if (_retryingDeviceLocation)
                                const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // Route Guidance (Phase 1): road-route distance and
                        // ETA from OSRM, shown alongside (not replacing) the
                        // straight-line/RPC distance that Step 2 reuses.
                        if (_routePoints != null &&
                            _routeDistanceMeters != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.route_rounded,
                                  size: 14,
                                  color: InsightTheme.blue1,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Road route: ${_formatRouteDistance(_routeDistanceMeters!)} · ~${_formatRouteDuration(_routeDurationSeconds ?? 0)}',
                                    style: InsightTheme.inter(
                                      12,
                                      w: FontWeight.w600,
                                      c: InsightTheme.ink2,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        // Phase C: Arrival detection indicator.
                        // Shows when the inspector is sufficiently close to the target site.
                        if (_arrived)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: InsightTheme.greenTint,
                                borderRadius: BorderRadius.circular(
                                  InsightTheme.radiusSm,
                                ),
                                border: Border.all(
                                  color: InsightTheme.green.withValues(
                                    alpha: 0.25,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: InsightTheme.green,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Arrived at Site — You are close enough to begin verification.',
                                      style: InsightTheme.inter(
                                        12,
                                        w: FontWeight.w600,
                                        c: InsightTheme.green,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 14),
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
                                      GpsVerificationScreen(task: task),
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
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
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
