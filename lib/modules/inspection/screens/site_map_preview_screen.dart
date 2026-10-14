import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:geolocator/geolocator.dart';
import 'package:flutter_compass/flutter_compass.dart';

import '../services/location_service.dart';
import '../../../core/services/auth_service.dart';
import '../widgets/rosario_boundary_overlay.dart';
import '../widgets/map_connectivity_recovery.dart';
import '../../../core/widgets/imaps_loading_indicator.dart';
import '../../../core/widgets/sensitive_screen.dart';

import '../../../core/theme/insight_theme.dart';
import '../../../core/layout/responsive_layout.dart';
import '../../../core/widgets/field_form_widgets.dart';
import '../../../core/widgets/quick_actions_sheet.dart' show MapDetailPanel;

/// Standalone Site Map viewer — full-bleed map showing only the
/// inspector's own live position as a pulsing beacon marker. No route
/// line, no distance readout — this screen has nothing to compare
/// against (that's what the task-bound `SiteMapScreen` is for).
///
/// Fixes in this pass (per Master's report from a real device):
///   - Background was solid black while the map was loading — switched
///     to the app's normal light background so it reads as "loading",
///     not broken.
///   - Back button now uses an explicit `Positioned(top: 0, ...)` +
///     `SafeArea` instead of relying on Stack's implicit top-start
///     default, so its position can't be ambiguous.
///   - "Your current location" moved out of the top pill into a bottom
///     info card that now actually shows the coordinates, accuracy, and
///     heading — previously that data was fetched but never displayed.
class SiteMapPreviewScreen extends StatefulWidget {
  const SiteMapPreviewScreen({super.key});

  @override
  State<SiteMapPreviewScreen> createState() => _SiteMapPreviewScreenState();
}

class _SiteMapPreviewScreenState extends State<SiteMapPreviewScreen>
    with WidgetsBindingObserver {
  bool _loading = true;
  String? _error;
  Position? _position;
  final MapController _mapController = MapController();
  final _panelKey = GlobalKey();
  final _headerKey = GlobalKey();

  StreamSubscription<CompassEvent>? _compassSub;
  double? _heading;

  ll.LatLng? get _deviceLatLng => _position == null
      ? null
      : ll.LatLng(_position!.latitude, _position!.longitude);

  /// Same grey-basemap recovery as Step 1: when the network returns, evict the
  /// tiles that failed while offline. This screen has no road route, so tile
  /// recovery is the whole of its behavior change.
  final MapConnectivityRecovery _recovery = MapConnectivityRecovery();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startCompass();
    unawaited(_startRecovery());
    _loadLocation();
  }

  Future<void> _startRecovery() async {
    final online = await AuthService.hasConnectivity();
    if (!mounted) return;
    await _recovery.start(
      initiallyOnline: online,
      onOnline: _onConnectivityRecovered,
    );
  }

  Future<void> _onConnectivityRecovered() async {
    if (!mounted) return;
    _recovery.resetTiles();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _compassSub?.cancel();
    unawaited(_recovery.stop());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _position == null && !_loading) {
      _loadLocation();
    }
  }

  void _startCompass() {
    final events = FlutterCompass.events;
    if (events == null) return;
    _compassSub = events.listen((event) {
      if (!mounted) return;
      setState(() => _heading = event.heading);
    });
  }

  Future<void> _loadLocation() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pos = await LocationService.getCurrentLocation();
      _position = pos;
      if (!mounted) return;
      setState(() => _loading = false);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) { if (mounted) _recenter(); },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _recenter() {
    final panel = _panelKey.currentContext?.findRenderObject() as RenderBox?;
    final header = _headerKey.currentContext?.findRenderObject() as RenderBox?;
    if (panel == null || header == null || _deviceLatLng == null) return;
    final size = MediaQuery.sizeOf(context);
    final safe = MediaQuery.paddingOf(context);
    final panelRect = panel.localToGlobal(Offset.zero) & panel.size;
    final headerRect = header.localToGlobal(Offset.zero) & header.size;
    final bp = context.responsive;
    final clear = (bp.canSplitTwoPane || (bp.isLandscape && !bp.isCompactWidth))
      // Reserve the recenter control's 16dp side margin and 48dp target too.
      ? Rect.fromLTRB(safe.left + 64, headerRect.bottom + 12, panelRect.left - 16,
          size.height - safe.bottom - 16)
      : Rect.fromLTRB(safe.left, headerRect.bottom + 12, size.width - safe.right, panelRect.top - 12);
    // Same device point and zoom; the native pixel offset clears the visible chrome.
    _mapController.move(_deviceLatLng!, 17, offset: clear.center - Offset(size.width / 2, size.height / 2));
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    final size = MediaQuery.sizeOf(context);
    final safe = MediaQuery.paddingOf(context);
    final bp = context.responsive;
    final split = bp.canSplitTwoPane || (bp.isLandscape && !bp.isCompactWidth);
    final sideWidth = (size.width * 0.36).clamp(280.0, 400.0);
    final attributionLeft = split ? size.width - safe.right - sideWidth - 16 : safe.left + 16;
    final attributionStyle = InsightTheme.inter(12, c: InsightTheme.ink2);
    const attributionText = 'Rosario boundary · MPDO Rosario\n© OpenStreetMap contributors';
    final measure = TextPainter(text: TextSpan(text: attributionText, style: attributionStyle),
      textDirection: Directionality.of(context), textScaler: MediaQuery.textScalerOf(context))
      ..layout(maxWidth: size.width - attributionLeft - safe.right - 16 - 16);
    final attributionHeight = measure.height + 12;
    measure.dispose();

    return SensitiveScreen(
      child: Scaffold(
        backgroundColor: InsightTheme.bg, // was Colors.black — fixed
        extendBodyBehindAppBar: true,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // ── Base layer — always a light background, so loading/error
            // states never show as a black screen. ─────────────────────
            Container(color: InsightTheme.bg),

            // ── Full-bleed map, once ready. ──────────────────────────────
            if (_loading)
              const Center(child: ImapsLoadingIndicator(size: 60))
            else if (_error != null)
              _ErrorState(message: _error!, onRetry: _loadLocation)
            else
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _deviceLatLng!,
                  initialZoom: 17,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.imaps.fieldsync',
                    reset: _recovery.tileResetStream,
                    evictErrorTileStrategy:
                        EvictErrorTileStrategy.notVisibleRespectMargin,
                  ),
                  const RosarioBoundaryOverlay(),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _deviceLatLng!,
                        width: 140,
                        height: 140,
                        alignment: Alignment.center,
                        child: _PulsingLocationBeacon(heading: _heading),
                      ),
                    ],
                  ),
                ],
              ),

            // ── Back button — explicit top placement, not implicit. ─────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  key: _headerKey,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FieldPageHeader(title: 'Site Map', onBack: () => Navigator.pop(context)),
                  ),
                ),
              ),
            ),

            // ── Floating recenter button. ───────────────────────────────
            // Anchored below the nav reserve rather than to a guessed 210,
            // which collided with the info card in a short landscape viewport.
            if (!_loading && _error == null)
              Positioned(
                left: 16,
                top: safe.top + 84,
                child: SafeArea(
                  top: false, bottom: false,
                  child: IconButton(tooltip: 'Recenter on your location', onPressed: _recenter,
                    constraints: const BoxConstraints.tightFor(width: 48, height: 48),
                    style: IconButton.styleFrom(backgroundColor: InsightTheme.surface,
                      shape: RoundedRectangleBorder(borderRadius: InsightTheme.roundedSm)),
                    icon: const Icon(Icons.center_focus_strong_rounded, size: 20, color: InsightTheme.blueInk)),
                ),
              ),

            // ── Info card — "Your current location" + actual
            // coordinates/accuracy/heading, instead of a bare label. ────
            // Map-first: this is a compact side pane in landscape/tablet and a
            // collapsible, content-sized card otherwise, so the map is never
            // permanently covered.
            if (!_loading && _error == null && _position != null)
              Positioned(
                left: safe.left + 16,
                right: safe.right + 16,
                bottom: safe.bottom + attributionHeight + 28,
                top: safe.top + 16,
                child: Padding(
                    padding: EdgeInsets.zero,
                    child: Align(
                      alignment: split ? Alignment.bottomRight : Alignment.bottomCenter,
                      child: MapDetailPanel(
                        key: _panelKey,
                        title: 'Your current location',
                        child: LayoutBuilder(builder: (context, box) {
                          final stacked = box.maxWidth < MediaQuery.textScalerOf(context).scale(14) * 20;
                          return Wrap(spacing: 16, runSpacing: 12, children: [
                            for (final entry in {
                              'Latitude': _position!.latitude.toStringAsFixed(6),
                              'Longitude': _position!.longitude.toStringAsFixed(6),
                              'Accuracy': '± ${_position!.accuracy.round()} m',
                              'Heading': _heading != null ? '${_heading!.round()}°' : 'Unavailable',
                            }.entries) SizedBox(width: stacked ? box.maxWidth : (box.maxWidth - 16) / 2,
                              child: _InfoField(label: entry.key, value: entry.value)),
                          ]);
                        }),
                      ),
                    ),
                ),
              ),
            Positioned(left: attributionLeft, right: safe.right + 16, bottom: safe.bottom + 16,
              child: IgnorePointer(child: Container(key: const ValueKey('quick-map-attribution'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(8)),
                child: Text(attributionText, style: attributionStyle)))),
          ],
        ),
      ),
    );
  }
}

class _InfoField extends StatelessWidget {
  final String label;
  final String value;
  const _InfoField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
            style: InsightTheme.inter(12),
        ),
        const SizedBox(height: 3),
        Text(
          value,
            style: InsightTheme.inter(14, w: FontWeight.w700, c: InsightTheme.ink),
        ),
      ],
    );
  }
}

/// Soft accuracy ring (static) + an outward-pulsing ring (looping
/// animation) + a solid center dot with a small heading arrow.
class _PulsingLocationBeacon extends StatefulWidget {
  final double? heading;
  const _PulsingLocationBeacon({required this.heading});

  @override
  State<_PulsingLocationBeacon> createState() => _PulsingLocationBeaconState();
}

class _PulsingLocationBeaconState extends State<_PulsingLocationBeacon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: InsightTheme.blue1.withValues(alpha: 0.12),
            ),
          ),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final t = _controller.value;
              return Opacity(
                opacity: (1 - t).clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: 0.35 + t * 1.0,
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: InsightTheme.blue1.withValues(alpha: 0.55),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          if (widget.heading != null)
            Transform.rotate(
              angle: widget.heading! * math.pi / 180,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 34),
                child: Icon(
                  Icons.navigation_rounded,
                  size: 18,
                  color: InsightTheme.blue1.withValues(alpha: 0.85),
                ),
              ),
            ),
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: InsightTheme.blue1,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: InsightTheme.blue1.withValues(alpha: 0.5),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ],
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
    return Center(
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
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
