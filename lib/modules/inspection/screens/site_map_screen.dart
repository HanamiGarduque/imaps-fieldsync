import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../services/location_service.dart';
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
/// NOTE on the route line: there's no routing-service dependency in this
/// project (no Directions API / OSRM, etc.), so the bent line is a
/// stylized, geometrically-generated path between the two points — it
/// reads as "not a straight line" the way a real route does, but it is
/// NOT an actual road-network route. Flagging this rather than silently
/// pretending it's real turn-by-turn routing; wiring an actual routing
/// service would be a new dependency/backend decision, out of scope here.
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

class _SiteMapScreenState extends State<SiteMapScreen> with WidgetsBindingObserver {
  bool _loading = true;
  String? _error;

  ll.LatLng? _parcelLatLng;
  ll.LatLng? _deviceLatLng;
  double? _distanceMeters;
  bool _retryingDeviceLocation = false;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadMapData();
  }

  @override
  void dispose() {
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
    if (state == AppLifecycleState.resumed && _deviceLatLng == null && !_loading) {
      _retryDeviceLocation();
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
      final connectivityResult = await Connectivity().checkConnectivity();
      final online = connectivityResult is List
          ? (connectivityResult as List).any((r) => r != ConnectivityResult.none)
          : connectivityResult != ConnectivityResult.none;
      final pos = await LocationService.getCurrentLocation();
      final newDeviceLatLng = ll.LatLng(pos.latitude, pos.longitude);
      final newDistance = online
          ? await SupabaseService.getDistanceToParcelBoundary(
              parcelId: widget.task.parcelId!,
              latitude: pos.latitude,
              longitude: pos.longitude,
            )
          : SpatialOfflineService.haversineMeters(
              pos.latitude, pos.longitude, _parcelLatLng!.latitude, _parcelLatLng!.longitude);
      if (!mounted) return;
      setState(() {
        _deviceLatLng = newDeviceLatLng;
        _distanceMeters = newDistance;
        _retryingDeviceLocation = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitBounds());
    } catch (_) {
      // Still unavailable — leave the badge as a retry target, no need to
      // surface a separate error for this secondary, best-effort fetch.
      if (!mounted) return;
      setState(() => _retryingDeviceLocation = false);
    }
  }

  Future<void> _loadMapData() async {
    setState(() { _loading = true; _error = null; });
    try {
      if (widget.task.parcelId == null) {
        throw Exception('No parcel linked to this task.');
      }

      final connectivityResult = await Connectivity().checkConnectivity();
      final online = connectivityResult is List
          ? (connectivityResult as List).any((r) => r != ConnectivityResult.none)
          : connectivityResult != ConnectivityResult.none;
      double? lat;
      double? lng;

      if (online) {
        final parcel = await SupabaseService.fetchParcelDetails(widget.task.parcelId!);
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
        throw Exception(online
            ? 'This parcel has no recorded coordinates yet.'
            : 'No cached coordinates for this site yet — connect to the internet once so it can be saved for offline use.');
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
            : SpatialOfflineService.haversineMeters(pos.latitude, pos.longitude, lat, lng);
      } catch (_) {
        _deviceLatLng = null;
        _distanceMeters = null;
      }

      if (!mounted) return;
      setState(() => _loading = false);
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitBounds());
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
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
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.fromLTRB(50, 160, 50, 220)),
    );
  }

  /// Stylized route path between two points — NOT a real road-network
  /// route (no routing-service dependency here, see class doc comment).
  /// Purely a presentation choice so the line reads like a real route
  /// instead of a straight "as the crow flies" line.
  List<ll.LatLng> _buildRoutePath(ll.LatLng start, ll.LatLng end) {
    final dLat = end.latitude - start.latitude;
    final dLng = end.longitude - start.longitude;
    final p1 = ll.LatLng(start.latitude + dLat * 0.10, start.longitude + dLng * 0.52);
    final p2 = ll.LatLng(start.latitude + dLat * 0.62, start.longitude + dLng * 0.52);
    final p3 = ll.LatLng(start.latitude + dLat * 0.62, start.longitude + dLng * 0.86);
    return [start, p1, p2, p3, end];
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
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.imaps.fieldsync',
                  ),
                  if (_deviceLatLng != null)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _buildRoutePath(_deviceLatLng!, _parcelLatLng!),
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
                        width: 32, height: 32,
                        child: Container(
                          decoration: BoxDecoration(color: InsightTheme.red, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: [BoxShadow(color: InsightTheme.red.withValues(alpha: 0.4), blurRadius: 8)]),
                        ),
                      ),
                      if (_deviceLatLng != null)
                        Marker(
                          point: _deviceLatLng!,
                          width: 34, height: 34,
                          child: Container(
                            decoration: BoxDecoration(color: InsightTheme.blue1, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: [BoxShadow(color: InsightTheme.blue1.withValues(alpha: 0.4), blurRadius: 10, spreadRadius: 2)]),
                          ),
                        ),
                    ],
                  ),
                ],
              ),

            // ── Floating glass header — back button + title + step progress bar ───
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
            if (!_loading && _error == null)
              Positioned(
                right: 16,
                top: 190,
                child: SafeArea(
                  bottom: false,
                  child: _GlassIconButton(icon: Icons.center_focus_strong_rounded, onTap: _fitBounds),
                ),
              ),

            // ── Floating bottom card — status row + CTA combined into one
            // modern card (matches reference picture 1's bottom-card
            // style) instead of a separate status pill + button below it.
            if (!_loading && _error == null)
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
                      boxShadow: const [BoxShadow(color: Color(0x1F0B1440), blurRadius: 32, offset: Offset(0, 16))],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(children: [const Icon(Icons.circle, size: 10, color: InsightTheme.red), const SizedBox(width: 6), Text('Target Site', style: InsightTheme.inter(12, w: FontWeight.w600))]),
                            GestureDetector(
                              onTap: _deviceLatLng == null && !_retryingDeviceLocation
                                  ? _retryDeviceLocation
                                  : null,
                              child: Row(children: [
                                const Icon(Icons.circle, size: 10, color: InsightTheme.blue1),
                                const SizedBox(width: 6),
                                if (_retryingDeviceLocation)
                                  const SizedBox(
                                    width: 12, height: 12,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                else
                                  Text(
                                    _deviceLatLng == null
                                        ? 'Location unavailable — tap to retry'
                                        : _distanceMeters != null
                                            ? 'You (${_distanceMeters!.round()}m)'
                                            : 'You',
                                    style: InsightTheme.inter(12, w: FontWeight.w600, c: InsightTheme.ink2),
                                  ),
                              ]),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              final isReworkMode = context.read<InspectionProvider>().isReworkMode;
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
                              Navigator.push(context, MaterialPageRoute(builder: (_) => GpsVerificationScreen(task: task)));
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ).copyWith(elevation: WidgetStateProperty.all(0)),
                            child: Ink(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [InsightTheme.blue1, InsightTheme.blue2], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [BoxShadow(color: InsightTheme.blue1.withValues(alpha: 0.32), blurRadius: 20, offset: const Offset(0, 8))],
                              ),
                              child: Container(
                                alignment: Alignment.center, constraints: const BoxConstraints(minHeight: 52),
                                width: double.infinity,
                                child: Text(
                                  context.watch<InspectionProvider>().isReworkMode ? 'Save' : 'Proceed to Location',
                                  style: InsightTheme.poppins(15, w: FontWeight.w600, c: Colors.white),
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

class _GlassPill extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _GlassPill({required this.child, this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12)});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
            boxShadow: const [BoxShadow(color: Color(0x140B1440), blurRadius: 20, offset: Offset(0, 8))],
          ),
          child: child,
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
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
              boxShadow: const [BoxShadow(color: Color(0x140B1440), blurRadius: 20, offset: Offset(0, 8))],
            ),
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
              const Icon(Icons.location_off_rounded, size: 40, color: InsightTheme.ink3),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center, style: InsightTheme.inter(13, c: InsightTheme.ink2)),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      ),
    );
  }
}