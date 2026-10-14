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
import '../services/site_route_guidance.dart';
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
    bounds: LatLngBounds.fromPoints([parcel, ?device, ...route]),
    maxZoom: 17,
    padding: padding,
  ),
);

/// Site Verification (Step 1): task-bound GPS, cached/live real road geometry
/// and the existing inspection callbacks, with orientation-aware presentation.
/// The mapped geometry is a point: direct distance is calculated locally.
/// Real roads and schematic dotted links are guidance, not verified access.
/// Step 2 independently owns its existing server/offline 30m confirmation rule.
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
  Position? _lastFix;
  bool _gpsReliable = false;
  bool _approachEpisode = false;
  Timer? _fixExpiry;
  bool _retryingDeviceLocation = false;
  // Real road route only. Routing failure never supplies fabricated geometry.
  List<ll.LatLng>? _routePoints;
  // Cache provenance is independent of the current connectivity state.
  bool _routeFromCache = false;
  double? _routeDistanceMeters;
  double? _routeDurationSeconds;
  // The true marker and direct-point estimate use the SAME shared GPS stream
  // as Step 2. Step 2 independently owns authoritative confirmation.
  StreamSubscription<Position>? _positionSub;
  bool _trackingActive = false;
  ll.LatLng? _routeOrigin;
  ll.LatLng? _lastRouteAttempt;
  ll.LatLng? _routeRequestedFrom;
  bool _routeRequestInFlight = false;
  int _routeRequestVersion = 0;
  Timer? _routeCooldown;
  Timer? _routeEstimateExpiry;
  DateTime? _routeFetchedAt;
  bool _routeEstimateExpired = true;
  bool _routeRefreshPending = false;
  bool _routeRefreshFailed = false;
  int _routeFailures = 0;
  // All Step 1 instances share the demo provider's maximum 1 request/sec.
  // The 15s screen budget is stricter; this also covers fast screen reopening.
  static Timer? _providerCooldown;
  static const _routeRefreshCooldown = Duration(seconds: 15);
  final MapController _mapController = MapController();
  EdgeInsets _mapPadding = const EdgeInsets.fromLTRB(50, 160, 50, 220);

  // Offline → ONLINE recovery: retries the OSM basemap and the OSRM road
  // route without the inspector leaving Step 1. Holds no map or business
  // state — see MapConnectivityRecovery.
  final MapConnectivityRecovery _recovery = MapConnectivityRecovery();

  /// Historical <=30m indicator, now explicitly an informational point estimate.
  /// This and the optional 100m notice never authorize or gate any step.
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
    _fixExpiry?.cancel();
    _routeCooldown?.cancel();
    _routeEstimateExpiry?.cancel();
    _routeRequestVersion++;
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
      if (!mounted) return;
      setState(() {
        _acceptFix(pos);
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
      if (!validSiteMapPoint(_parcelLatLng!)) {
        throw Exception('The mapped site coordinates are invalid.');
      }

      // Device position is best-effort here — Step 1 is about orientation,
      // not verification, so a location error still lets the inspector see
      // the target site on the map and proceed; only Step 2 hard-requires it.
      try {
        final pos = await LocationService.getCurrentLocation();
        if (!mounted) return;
        _acceptFix(pos);
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

  /// Update the true GPS point and direct distance locally on each valid fix.
  /// The road request has its own budget; GPS ticks never call a distance RPC.
  Future<void> _onPositionUpdate(Position pos) async {
    if (!mounted || _parcelLatLng == null) return;
    if (!_acceptFix(pos)) return;
    setState(() {});
    unawaited(_maybeRefreshRoute(_deviceLatLng!));
  }

  bool _acceptFix(Position pos) {
    final newPos = ll.LatLng(pos.latitude, pos.longitude);
    final now = DateTime.now();
    if (!validSiteMapPoint(newPos) ||
        (_lastFix != null &&
            !_lastFix!.timestamp.isAfter(now.add(const Duration(seconds: 2))) &&
            pos.timestamp.isBefore(_lastFix!.timestamp))) {
      return false;
    }
    _lastFix = pos;
    _deviceLatLng = newPos;
    _distanceMeters = SpatialOfflineService.haversineMeters(
      newPos.latitude,
      newPos.longitude,
      _parcelLatLng!.latitude,
      _parcelLatLng!.longitude,
    );
    _gpsReliable = reliableSiteFix(
      accuracyMeters: pos.accuracy,
      timestamp: pos.timestamp,
      now: now,
    );
    if (_gpsReliable &&
        _routeRequestInFlight &&
        _routeRequestedFrom != null &&
        sitePointDistance(_routeRequestedFrom!, newPos) > 50) {
      _routeRequestVersion++;
      _routeRefreshPending = true;
    }
    _approachEpisode = siteApproachEpisode(
      wasNear: _approachEpisode,
      distanceMeters: _distanceMeters!,
      reliable: _gpsReliable,
    );
    _fixExpiry?.cancel();
    if (_gpsReliable) {
      _fixExpiry = Timer(
        const Duration(seconds: 15) - now.difference(pos.timestamp),
        () {
          if (mounted) setState(() => _gpsReliable = false);
        },
      );
    }
    return true;
  }

  /// Single source of the online/offline decision for this screen. It only
  /// gates whether ONLINE calls (parcel lookup, OSRM route fetch) are
  /// attempted; every network/routing operation itself lives in its service
  /// (SupabaseService / LocationService / RouteService).
  Future<bool> _checkOnline() async {
    final dynamic connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult is List
        ? connectivityResult.any((r) => r != ConnectivityResult.none)
        : connectivityResult != ConnectivityResult.none;
  }

  /// Every entry point goes through the same request budget. A recovery or retry
  /// can request a refresh, but cannot bypass cooldown, GPS quality or backoff.
  Future<void> _fetchRouteAndUpdate({required bool online}) async {
    if (!online || _deviceLatLng == null || _parcelLatLng == null) return;
    await _fetchRoute(start: _deviceLatLng!, online: online);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _maybeRefreshRoute(ll.LatLng currentPosition) async {
    if (!_gpsReliable) return;
    final aged =
        _routeFetchedAt != null &&
        (_routeEstimateExpired ||
            DateTime.now().difference(_routeFetchedAt!) >=
                const Duration(seconds: 90));
    if (!_routeRefreshPending &&
        !siteRoadRefreshNeeded(
          device: currentPosition,
          previousAttempt: _lastRouteAttempt,
          road: _routePoints ?? const [],
          accuracyMeters: _lastFix!.accuracy,
          aged: aged,
          failed: _routeRefreshFailed,
        )) {
      return;
    }
    await _fetchRoute(start: currentPosition);
    if (!mounted) return;
    setState(() {});
  }

  void _deferRoute(Duration delay) {
    _routeCooldown?.cancel();
    _routeCooldown = Timer(delay, () {
      _routeCooldown = null;
      if (mounted &&
          !_loading &&
          _routeRefreshPending &&
          _gpsReliable &&
          _deviceLatLng != null) {
        unawaited(_fetchRoute(start: _deviceLatLng!));
      }
    });
  }

  bool get _routeEstimateStale =>
      _routeFromCache ||
      _routeRefreshFailed ||
      _routeEstimateExpired ||
      !_gpsReliable ||
      _routeOrigin == null ||
      _deviceLatLng == null ||
      siteRoadRefreshNeeded(
        device: _deviceLatLng!,
        previousAttempt: _routeOrigin,
        road: _routePoints ?? const [],
        accuracyMeters: _lastFix!.accuracy,
        aged: false,
        failed: false,
      );

  /// One in flight, >=15s between attempts; failures back off 30/60/120s.
  /// Disposed screens and responses overtaken by >50m of reliable movement
  /// cannot replace either the current real geometry or its cached copy.
  Future<void> _fetchRoute({required ll.LatLng start, bool? online}) async {
    if (!mounted || _parcelLatLng == null) return;
    if (!_gpsReliable || _routeRequestInFlight || _routeCooldown != null) {
      _routeRefreshPending = true;
      return;
    }
    _routeRequestInFlight = true;
    _routeRefreshPending = false;
    _routeRequestedFrom = start;
    final requestVersion = ++_routeRequestVersion;
    _deferRoute(_routeRefreshCooldown);
    try {
      if (!(online ?? await _checkOnline())) {
        _routeRefreshPending = true;
        return;
      }
      if (!mounted || requestVersion != _routeRequestVersion) return;
      if (_providerCooldown != null) {
        _routeRefreshPending = true;
        _deferRoute(const Duration(seconds: 1));
        return;
      }
      _providerCooldown = Timer(const Duration(seconds: 1), () {
        _providerCooldown = null;
      });
      _lastRouteAttempt = start;
      // Connectivity/provider waits must not spend the HTTP dispatch budget.
      _deferRoute(_routeRefreshCooldown);
      final result = await RouteService.fetchDrivingRoute(
        start: start,
        end: _parcelLatLng!,
      );
      if (!mounted) return;
      if (result == null ||
          !usableSiteRoad(result.points) ||
          !result.distanceMeters.isFinite ||
          result.distanceMeters < 0 ||
          !result.durationSeconds.isFinite ||
          result.durationSeconds < 0) {
        _routeRefreshFailed = true;
        _routeRefreshPending = true;
        _routeFailures = (_routeFailures + 1).clamp(1, 3);
        _deferRoute(Duration(seconds: 30 * (1 << (_routeFailures - 1))));
        return;
      }
      // Provider failures still consume backoff when their origin/fix becomes
      // obsolete. Eligibility only gates acceptance of successful geometry.
      if (requestVersion != _routeRequestVersion || !_gpsReliable) {
        _routeRefreshPending = true;
        return;
      }
      _routePoints = result.points;
      _routeDistanceMeters = result.distanceMeters;
      _routeDurationSeconds = result.durationSeconds;
      _routeFromCache = false;
      _routeOrigin = start;
      _routeFetchedAt = DateTime.now();
      _routeRefreshFailed = false;
      _routeFailures = 0;
      _routeEstimateExpired = false;
      _routeEstimateExpiry?.cancel();
      _routeEstimateExpiry = Timer(const Duration(minutes: 2), () {
        if (mounted) setState(() => _routeEstimateExpired = true);
      });
      setState(() {});
      // Serialize persistence with this request; a late cache write cannot
      // overtake a later successful refresh. The already-painted map stays usable.
      await _persistRoute(result, start);
    } finally {
      _routeRequestInFlight = false;
      _routeRequestedFrom = null;
      if (mounted) {
        setState(() {});
        if (_routeRefreshPending && _routeCooldown == null && _gpsReliable) {
          _deferRoute(Duration.zero);
        }
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
          fetchedAt: _routeFetchedAt,
        ),
      );
    } catch (e) {
      debugPrint('[SITE MAP] Could not cache road route: $e');
    }
  }

  /// Restores this task's previously cached real road route.
  ///
  /// Read starts on open, but may finish after HTTP. A late read must never
  /// replace a live route that was already accepted during this screen session.
  Future<void> _restoreCachedRoute() async {
    try {
      final cached = await DBHelper.getRouteCache(widget.task.id);
      if (cached == null || !mounted || !usableSiteRoad(cached.points)) return;
      if (_routePoints != null && !_routeFromCache) return;
      _routePoints = cached.points;
      _routeDistanceMeters = cached.distanceMeters;
      _routeDurationSeconds = cached.durationSeconds;
      _routeFromCache = true;
      final origin = ll.LatLng(cached.originLat, cached.originLng);
      _routeOrigin = validSiteMapPoint(origin) ? origin : null;
      _routeFetchedAt = cached.fetchedAt;
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
          routeEstimateStale: _routeEstimateStale,
          nearSite: _arrived,
          approachNotice: _approachEpisode && _gpsReliable,
          gpsReliable: _gpsReliable,
          hasDirectLinks: _directLinks.isNotEmpty,
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

  List<List<ll.LatLng>> get _directLinks => _parcelLatLng == null
      ? const []
      : siteDirectLinks(
          road: _routePoints ?? const [],
          target: _parcelLatLng!,
          device: _deviceLatLng,
          accuracyMeters: _lastFix?.accuracy ?? double.infinity,
          reliable: _gpsReliable,
        );

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
        Builder(
          builder: (context) => IgnorePointer(
            child: PolylineLayer(
              polylines: [
                Polyline(
                  points: _routePoints!,
                  strokeWidth: MapCamera.of(context).zoom < 16 ? 6 : 8,
                  color: InsightTheme.blue1,
                  borderStrokeWidth: 2,
                  borderColor: Colors.white,
                ),
                for (final link in _directLinks)
                  Polyline(
                    points: link,
                    pattern: const StrokePattern.dotted(spacingFactor: 1.8),
                    strokeWidth: _approachEpisode && _gpsReliable ? 5 : 4,
                    color: link.last == _parcelLatLng
                        ? InsightTheme.red
                        : InsightTheme.blueInk,
                    borderStrokeWidth: 1,
                    borderColor: Colors.white,
                  ),
              ],
            ),
          ),
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
