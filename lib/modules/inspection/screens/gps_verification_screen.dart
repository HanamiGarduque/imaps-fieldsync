import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:flutter_compass/flutter_compass.dart';

import '../services/location_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/sync_outbox_service.dart';
import '../providers/inspection_provider.dart';
import 'capture_photo_screen.dart';
import '../../tasks/screens/tasks_screen.dart';
import 'inspection_progress.dart';
import '../widgets/exit_confirm_dialog.dart';
import '../../../core/layout/responsive_layout.dart';

import 'package:connectivity_plus/connectivity_plus.dart';
import '../../../core/services/db_helper.dart';
import '../services/spatial_offline_service.dart';
import '../inspection_constants.dart';
import '../../../core/widgets/sensitive_screen.dart';
import '../../../core/widgets/imaps_loading_indicator.dart';
import '../../../core/theme/insight_theme.dart';

/// Vertical room the alignment tip needs below the dial: the 14px gap plus its
/// text, which the theme floors at 12pt.
const double kGpsCompassTipAllowance = 62.0;

/// Diameter for the GPS compass dial that fits the space it was given.
///
/// The original build used `.clamp(160.0, 268.0)`. That 160px floor is what
/// made a short landscape viewport overflow: the fixed header (~112) and
/// verification card (~274) left the compass an ~80px slot while the dial
/// insisted on 160 — the "BOTTOM OVERFLOWED BY 80 PIXELS" stripe.
///
/// There is deliberately no minimum. A small dial beats a layout error, and in
/// the split layout the compass still owns the primary pane, so it stays large
/// wherever there is room for it.
double fitCompassDiameter({
  required double availableWidth,
  required double availableHeight,
  required double ceiling,
}) {
  final budget = math.max(0.0, availableHeight - kGpsCompassTipAllowance);
  return math
      .min(availableWidth * 0.86, math.min(budget * 0.92, ceiling))
      .clamp(0.0, ceiling)
      .toDouble();
}

class GpsVerificationScreen extends StatefulWidget {
  final TaskItem task;
  const GpsVerificationScreen({super.key, required this.task});

  @override
  State<GpsVerificationScreen> createState() => _GpsVerificationScreenState();
}

class _GpsVerificationScreenState extends State<GpsVerificationScreen> {
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  double? _distance;
  double? _accuracy;
  double? _latitude;
  double? _longitude;
  double? _bearingToParcel;

  StreamSubscription<Position>? _positionSub;
  bool _isLive = false;
  bool _recomputing = false;

  StreamSubscription<CompassEvent>? _compassSub;
  double? _heading;
  bool _compassUnavailable = false;

  bool get _verified =>
      _distance != null &&
      _distance! <= siteVerificationDistanceThresholdMeters;

  static const _cardinals = ['N','NNE','NE','ENE','E','ESE','SE','SSE','S','SSW','SW','WSW','W','WNW','NW','NNW'];
  String get _headingCardinal {
    if (_heading == null) return '--';
    return _cardinals[(((_heading! + 11.25) ~/ 22.5) % 16)];
  }

  @override
  void initState() {
    super.initState();
    _checkLocation();
    _startCompass();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _compassSub?.cancel();
    super.dispose();
  }

  void _startCompass() {
    final events = FlutterCompass.events;
    if (events == null) {
      setState(() => _compassUnavailable = true);
      return;
    }
    _compassSub = events.listen((event) {
      if (!mounted || event.heading == null) return;
      setState(() => _heading = event.heading);
    });
  }

  Future<void> _checkLocation() async {
    setState(() { _loading = true; _error = null; });
    try {
      if (widget.task.parcelId == null) throw Exception('No parcel linked.');
      final pos = await LocationService.getCurrentLocation();
      final connectivityResult = await Connectivity().checkConnectivity();
      final online = connectivityResult.any((r) => r != ConnectivityResult.none);
      double? dist;
      double? parcelLat;
      double? parcelLng;

      if (online) {
        dist = await SupabaseService.getDistanceToParcelBoundary(parcelId: widget.task.parcelId!, latitude: pos.latitude, longitude: pos.longitude);
        final parcel = await SupabaseService.fetchParcelDetails(widget.task.parcelId!);
        parcelLat = (parcel?['latitude'] as num?)?.toDouble();
        parcelLng = (parcel?['longitude'] as num?)?.toDouble();
      } else {
        final cached = await DBHelper.getCachedJobs();
        final match = cached.where((j) => j['id'] == widget.task.id).toList();
        if (match.isNotEmpty) {
          parcelLat = (match.first['parcel_lat'] as num?)?.toDouble();
          parcelLng = (match.first['parcel_lng'] as num?)?.toDouble();
        }
        if (parcelLat != null && parcelLng != null) {
          dist = SpatialOfflineService.haversineMeters(pos.latitude, pos.longitude, parcelLat, parcelLng);
        }
      }

      double? bearing;
      if (parcelLat != null && parcelLng != null) {
        bearing = _bearingBetween(pos.latitude, pos.longitude, parcelLat, parcelLng);
      }
      if (!mounted) return;
      setState(() { _latitude = pos.latitude; _longitude = pos.longitude; _accuracy = pos.accuracy; _distance = dist; _bearingToParcel = bearing; _loading = false; });
      _startLiveTracking();
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  void _startLiveTracking() {
    if (_isLive) return;
    _isLive = true;
    _positionSub = LocationService.getPositionStream().listen(
      _onPositionUpdate,
      onError: (Object e) {
        if (!mounted) return;
        setState(() => _isLive = false);
      },
      cancelOnError: true,
    );
  }

  Future<void> _onPositionUpdate(Position pos) async {
    if (widget.task.parcelId == null || _recomputing) return;
    _recomputing = true;
    try {
      // Phase 1 audit fix (item #2 — Offline Inspection Audit): this used
      // to call the online-only Supabase RPC/fetch unconditionally, so
      // live tracking silently stopped updating the compass/distance the
      // moment the device went offline (every tick threw and got
      // swallowed below). Now it mirrors the same online/offline branch
      // that _checkLocation() already uses.
      final connectivityResult = await Connectivity().checkConnectivity();
      final online = connectivityResult.any((r) => r != ConnectivityResult.none);
      double? dist;
      double? parcelLat;
      double? parcelLng;

      if (online) {
        dist = await SupabaseService.getDistanceToParcelBoundary(
          parcelId: widget.task.parcelId!,
          latitude: pos.latitude,
          longitude: pos.longitude,
        );
        final parcel = await SupabaseService.fetchParcelDetails(widget.task.parcelId!);
        parcelLat = (parcel?['latitude'] as num?)?.toDouble();
        parcelLng = (parcel?['longitude'] as num?)?.toDouble();
      } else {
        final cached = await DBHelper.getCachedJobs();
        final match = cached.where((j) => j['id'] == widget.task.id).toList();
        if (match.isNotEmpty) {
          parcelLat = (match.first['parcel_lat'] as num?)?.toDouble();
          parcelLng = (match.first['parcel_lng'] as num?)?.toDouble();
        }
        if (parcelLat != null && parcelLng != null) {
          dist = SpatialOfflineService.haversineMeters(pos.latitude, pos.longitude, parcelLat, parcelLng);
        }
      }

      double? bearing;
      if (parcelLat != null && parcelLng != null) {
        bearing = _bearingBetween(pos.latitude, pos.longitude, parcelLat, parcelLng);
      }
      if (!mounted) return;
      setState(() {
        _latitude = pos.latitude;
        _longitude = pos.longitude;
        _accuracy = pos.accuracy;
        _distance = dist;
        _bearingToParcel = bearing;
        _error = null;
      });
    } catch (_) {
    } finally {
      _recomputing = false;
    }
  }

  String _formatCoord(double value, String posNegLetters) {
    final letter = value >= 0 ? posNegLetters[0] : posNegLetters[1];
    final abs = value.abs();
    final deg = abs.floor();
    final minFloat = (abs - deg) * 60;
    final min = minFloat.floor();
    final sec = ((minFloat - min) * 60).round();
    return "$deg°$min'$sec\"$letter";
  }

  double _bearingBetween(double lat1, double lon1, double lat2, double lon2) {
    final phi1 = lat1 * math.pi / 180.0, phi2 = lat2 * math.pi / 180.0;
    final dLam = (lon2 - lon1) * math.pi / 180.0;
    final y = math.sin(dLam) * math.cos(phi2);
    final x = math.cos(phi1) * math.sin(phi2) - math.sin(phi1) * math.cos(phi2) * math.cos(dLam);
    return ((math.atan2(y, x) * 180.0 / math.pi) + 360.0) % 360.0;
  }

  /// Ongoing-phase audit fix: `SupabaseService.markJobOngoing()` swallows
  /// its own errors and just returns `false` on failure (e.g. offline) —
  /// with no outbox fallback, unlike every other write in this app. That
  /// meant an inspector exiting before GPS confirmation while offline got
  /// told "saved offline" when nothing was actually queued, and the
  /// status flip was lost for good unless they later passed through GPS
  /// confirmation (which is reliably outbox-backed). This wraps the same
  /// call with that missing fallback, mirroring the pattern already used
  /// for GPS confirm below.
  Future<bool> _markOngoingWithFallback(String jobId) async {
    final result = await SupabaseService.markJobOngoing(jobId);
    if (result == InspectionAuthorityResult.authorized) return true;
    if (result != InspectionAuthorityResult.offlineOrUnverifiable) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
      return false;
    }
    try {
      await SyncOutboxService.enqueueMarkOngoing(jobId: jobId);
      return true; // queued — the exit dialog's "saved" message is now true
    } catch (_) {
      return false;
    }
  }

  Future<void> _startInspection() async {
    if (!_verified || _latitude == null || _submitting) return;
    setState(() => _submitting = true);

    bool queuedOffline = false;
    try {
      await SupabaseService.confirmGpsOnSite(jobId: widget.task.id, latitude: _latitude!, longitude: _longitude!, accuracyMeters: _accuracy ?? 0, locationLabel: widget.task.location);
    } catch (e) {
      try {
        await SyncOutboxService.enqueueGpsConfirm(
          jobId: widget.task.id,
          latitude: _latitude!,
          longitude: _longitude!,
          accuracyMeters: _accuracy ?? 0,
          locationLabel: widget.task.location,
        );
        queuedOffline = true;
      } catch (_) {
        if (!mounted) return;
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
        return;
      }
    }

    if (!mounted) return;
    if (queuedOffline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No signal — GPS check-in saved offline, will sync automatically.')),
      );
    }
    context.read<InspectionProvider>().recordGpsVerification(distanceMeters: _distance ?? 0);
    HapticFeedback.selectionClick();
    setState(() => _submitting = false);
    // Issue 2 fix (Completed Category enhancement): this screen never
    // checked rework mode at all before — it always pushed forward to
    // Photos regardless, advancing the normal wizard instead of returning
    // to Inspection Summary during a rework session. markStepComplete(2)
    // is step-wizard bookkeeping (advances current_step) — it belongs only
    // to the normal forward-progress path below, not to an edit-in-place
    // rework session, so it's no longer called unconditionally beforehand.
    if (context.read<InspectionProvider>().isReworkMode) {
      Navigator.pop(context);
      return;
    }
    InspectionProgress.instance.markStepComplete(2);
    Navigator.push(context, MaterialPageRoute(builder: (_) => CapturePhotoScreen(task: widget.task)));
  }

  // Fullscreen mode: hides the header block (back / title / step progress)
  // so the compass and readings fill the screen. The verification card —
  // which carries the screen's primary action — stays visible. In this
  // mode the fullscreen-exit toggle floats top-right.
  bool _fullscreen = false;

  /// Distance formatted for the bottom card: metres below 1 km, otherwise
  /// km (one decimal under 10 km) — mirrors the Site Verification map's
  /// route-distance formatting so both screens read the same way.
  String get _distanceText {
    final d = _distance;
    if (d == null) return '-- m';
    if (d < 1000) return '${d.round()} m';
    return '${(d / 1000).toStringAsFixed(d < 10000 ? 1 : 0)} km';
  }

  /// The verification card is the primary action, so it is only omitted while
  /// there is genuinely nothing to confirm (loading or errored).
  bool get _detailsAvailable => !_loading && _error == null;

  /// Compass + alignment tip.
  ///
  /// Sized from the space it is actually given and never allowed to demand
  /// more than that. The previous build clamped it to a 160px floor, which is
  /// what turned a cramped landscape viewport into a hard
  /// "BOTTOM OVERFLOWED BY 80 PIXELS" instead of simply a smaller dial.
  ///
  /// The tip is *inside* the same scroll view as the dial so that a slot too
  /// short even for a minimum dial cannot overflow the column either.
  Widget _buildCompassPane() {
    if (_loading) return const Center(child: _LoadingState());
    if (_error != null) {
      return Center(
        child: _ErrorState(message: _error!, onRetry: _checkLocation),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // In a split layout the compass owns the primary pane and may grow;
        // stacked portrait keeps the accepted 268px ceiling.
        final ceiling = context.responsive.canSplitTwoPane ? 300.0 : 268.0;

        Widget build(double slot) {
          final compassSize = fitCompassDiameter(
            availableWidth: constraints.maxWidth,
            availableHeight: slot,
            ceiling: ceiling,
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.topCenter,
                children: [
                  // Fixed top heading pointer.
                  Positioned(
                    top: 0,
                    child: CustomPaint(
                      size: Size(compassSize * 0.07, compassSize * 0.05),
                      painter: _TopPointerPainter(color: InsightTheme.amber),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: compassSize * 0.07),
                    child: _Compass(
                      size: compassSize,
                      heading: _heading,
                      bearingToParcel: _bearingToParcel,
                      headingCardinal: _headingCardinal,
                      verified: _verified,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _AlignmentTip(
                verified: _verified,
                bearingToParcel: _bearingToParcel,
                compassUnavailable: _compassUnavailable,
              ),
            ],
          );
        }

        // The fitting function already reserves room for the tip. Subtracting
        // it again shrank the dial unnecessarily in short landscape panes.
        return Center(
          child: SingleChildScrollView(child: build(constraints.maxHeight)),
        );
      },
    );
  }

  /// Coordinate readout for the verification card, null until a fix exists.
  String? get _coordsText => (_latitude != null && _longitude != null)
      ? "${_formatCoord(_latitude!, 'NS')}   ${_formatCoord(_longitude!, 'EW')}"
      : null;

  /// Verification card. When it shares a pane with the compass it scrolls
  /// independently, so no metric and not the confirm action can be pushed
  /// off-screen.
  Widget _buildDetailPane({bool scrollable = false}) {
    final card = _VerificationCard(
      distanceText: _distanceText,
      accuracy: _accuracy,
      verified: _verified,
      heading: _heading,
      headingCardinal: _headingCardinal,
      coords: _coordsText,
      location: widget.task.location,
      submitting: _submitting,
      isReworkMode: context.read<InspectionProvider>().isReworkMode,
      onConfirm: _startInspection,
    );
    if (!scrollable) return card;
    return SingleChildScrollView(child: card);
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    final isReworkMode = context.read<InspectionProvider>().isReworkMode;

    return SensitiveScreen(
      child: PopScope(
        canPop: !isReworkMode && InspectionProgress.instance.currentStep > 1,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) {
            _markOngoingWithFallback(widget.task.id);
            return;
          }
          handleInspectionExit(
            context,
            onSaveProgress: () => _markOngoingWithFallback(widget.task.id),
            isReworkMode: isReworkMode,
          );
        },
        child: Scaffold(
          backgroundColor: InsightTheme.bg,
          body: SafeArea(
            child: Stack(
              children: [
                // ── Responsive composition ────────────────────────────────
                // Portrait keeps the accepted vertical stack. Where a split
                // is worthwhile the spatial compass becomes the primary pane
                // and the detail card moves beside it in its own scroll view,
                // so the verification metrics and the primary action stay
                // reachable without the compass ever being pushed off-screen.
                HeaderSplitBody(
                  landscapeBackButton: SizedBox.square(
                    dimension: InsightBreakpoints.minTouchTarget,
                    child: _HeaderButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      onTap: () => handleInspectionExit(
                        context,
                        onSaveProgress: () =>
                            _markOngoingWithFallback(widget.task.id),
                        isReworkMode: isReworkMode,
                      ),
                    ),
                  ),
                  header: _fullscreen
                      // Immersive mode drops the header entirely.
                      ? null
                      : _GpsHeader(
                          location: widget.task.location,
                          verified: _verified,
                          onBack: () => handleInspectionExit(
                            context,
                            onSaveProgress: () =>
                                _markOngoingWithFallback(widget.task.id),
                            isReworkMode: isReworkMode,
                          ),
                          onToggleFullscreen: () =>
                              setState(() => _fullscreen = !_fullscreen),
                        ),
                  primary: _buildCompassPane(),
                  secondary:
                      _detailsAvailable ? _buildDetailPane(scrollable: true) : null,
                ),

                // Fullscreen exit toggle — the header that used to carry it
                // is hidden in this mode. Last Stack child = topmost hit
                // target (lesson from the dead-button bug).
                if (_fullscreen && !context.responsive.isLandscape &&
                    !_loading && _error == null)
                  Positioned(
                    right: 16,
                    top: 8,
                    child: _HeaderButton(
                      icon: Icons.fullscreen_exit_rounded,
                      onTap: () => setState(() => _fullscreen = !_fullscreen),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ── Header block: back + title card + fullscreen toggle, step progress ──
///
/// Redesigned per the approved dual-state mockup: the fullscreen toggle
/// lives INSIDE the header row (right of the title card), which removes
/// the old floating-button z-order problem entirely. Accent colors follow
/// the verification state (amber far from site, blue in zone).
class _GpsHeader extends StatelessWidget {
  final String location;
  final bool verified;
  final VoidCallback onBack;
  final VoidCallback onToggleFullscreen;

  const _GpsHeader({
    required this.location,
    required this.verified,
    required this.onBack,
    required this.onToggleFullscreen,
  });

  @override
  Widget build(BuildContext context) {
    final accent = verified ? InsightTheme.blue1 : InsightTheme.amber;
    final accentInk = verified ? InsightTheme.blueInk : InsightTheme.amberInk;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: [
          Row(
            children: [
              _HeaderButton(icon: Icons.arrow_back_ios_new_rounded, onTap: onBack),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                  decoration: BoxDecoration(
                    color: InsightTheme.surface,
                    borderRadius: BorderRadius.circular(InsightTheme.radiusMd),
                    border: Border.all(color: InsightTheme.line),
                    boxShadow: InsightTheme.cardShadow,
                  ),
                  child: Column(
                    children: [
                      Text(
                        'GPS Verification',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: InsightTheme.urbanist(13, w: FontWeight.w800, c: InsightTheme.ink),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.location_on_rounded, size: 10, color: accent),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: InsightTheme.inter(10, w: FontWeight.w600, c: InsightTheme.ink2),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              _HeaderButton(icon: Icons.fullscreen_rounded, onTap: onToggleFullscreen),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: InsightTheme.surface,
              borderRadius: BorderRadius.circular(InsightTheme.radiusMd),
              border: Border.all(color: InsightTheme.line),
              boxShadow: InsightTheme.cardShadow,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Text('STEP 2 OF 6', style: InsightTheme.mono(10, w: FontWeight.w800, ls: 0.5, c: accentInk)),
                    Expanded(
                      child: Text(
                        'VERIFY COORDINATES',
                        textAlign: TextAlign.right,
                        style: InsightTheme.mono(10, c: InsightTheme.ink3, ls: 0.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Container(
                    height: 5,
                    color: InsightTheme.surface2,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: 2 / 6.0,
                      child: Container(color: accent),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Square white icon button used for back / fullscreen in the header row
/// and for the floating fullscreen-exit control in fullscreen mode.
class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HeaderButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: InsightTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: InsightTheme.line),
          boxShadow: InsightTheme.cardShadow,
        ),
        child: Icon(icon, size: 16, color: InsightTheme.ink),
      ),
    );
  }
}

/// ── Redesigned dual-state compass ─────────────────────────────────────
///
/// Tick dial (rotates with device heading), a bouncing SITE needle pinned
/// at the RELATIVE bearing to the parcel (target − heading), and a digital
/// center hub (cardinal + heading + target-bearing chip).
///
/// Dual state via [InsightTheme] tokens only:
///   far from site → amber dial, dark slate hub (ink2→ink gradient)
///   in zone       → blue dial, blue gradient hub (blue1→blue2)
/// Only fixed-length content lives inside the fixed circle, so the layout
/// never overflows; [size] is computed responsively by the caller.
class _Compass extends StatelessWidget {
  final double size;
  final double? heading;
  final double? bearingToParcel;
  final String headingCardinal;
  final bool verified;

  const _Compass({
    required this.size,
    required this.heading,
    required this.bearingToParcel,
    required this.headingCardinal,
    required this.verified,
  });

  @override
  Widget build(BuildContext context) {
    var hubSize = size * 0.47;
    if (bearingToParcel != null) {
      final target = TextPainter(
        text: TextSpan(
          text: 'Target: ${bearingToParcel!.round()}°',
          style: InsightTheme.mono(hubSize * 0.066, w: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      // Keep the bearing on one line at readable text sizes. Account for the
      // chip padding and borders instead of shrinking text inside the dial.
      hubSize = math.min(size * 0.7, math.max(hubSize, target.width / 0.86 + 8));
      target.dispose();
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Drop shadow behind the disc.
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (verified ? InsightTheme.blue2 : InsightTheme.amber).withValues(alpha: 0.18),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
          ),

          // Rotating dial (face + ticks + cardinal letters via painter).
          AnimatedRotation(
            turns: heading != null ? -(heading! / 360) : 0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.linear,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: InsightTheme.surface,
                border: Border.all(color: InsightTheme.surface2, width: 4),
              ),
              child: CustomPaint(size: Size(size, size), painter: _DialPainter(verified: verified)),
            ),
          ),

          // SITE needle at the relative bearing (target − heading).
          if (heading != null && bearingToParcel != null)
            Transform.rotate(
              angle: (bearingToParcel! - heading!) * math.pi / 180.0,
              child: SizedBox(
                width: size,
                height: size,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: EdgeInsets.only(top: size * 0.055),
                    child: _GentleBounce(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: size * 0.095,
                            height: size * 0.095,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: InsightTheme.blue1,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: const [BoxShadow(color: Color(0x330F111A), blurRadius: 6, offset: Offset(0, 2))],
                            ),
                            child: Icon(Icons.navigation_rounded, size: size * 0.048, color: Colors.white),
                          ),
                          SizedBox(height: size * 0.008),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: size * 0.016, vertical: 1),
                            decoration: BoxDecoration(
                              color: InsightTheme.blueTint,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: InsightTheme.blue1.withValues(alpha: 0.35)),
                            ),
                            child: Text('SITE', style: InsightTheme.mono(size * 0.032, w: FontWeight.w800, c: InsightTheme.blueInk)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Center hub: cardinal + heading + target-bearing chip.
          Container(
            width: hubSize,
            height: hubSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: verified
                    ? const [InsightTheme.blue1, InsightTheme.blue2]
                    : const [InsightTheme.ink2, InsightTheme.ink],
              ),
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: (verified ? InsightTheme.blue2 : InsightTheme.ink).withValues(alpha: 0.30),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  headingCardinal,
                  style: InsightTheme.mono(hubSize * 0.085, w: FontWeight.w800, ls: 1.5, c: Colors.white.withValues(alpha: 0.8)),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(heading != null ? '${heading!.round()}' : '--', style: InsightTheme.mono(hubSize * 0.19, w: FontWeight.w800, c: Colors.white)),
                    Text('°', style: InsightTheme.mono(hubSize * 0.115, w: FontWeight.w700, c: Colors.white.withValues(alpha: 0.75))),
                  ],
                ),
                if (bearingToParcel != null) ...[
                  SizedBox(height: hubSize * 0.03),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: hubSize * 0.07, vertical: hubSize * 0.018),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                    ),
                    child: Text(
                      'Target: ${bearingToParcel!.round()}°',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: InsightTheme.mono(hubSize * 0.066, w: FontWeight.w600, c: Colors.white.withValues(alpha: 0.85)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Soft vertical bounce for the SITE needle (mockup's animate-bounce).
class _GentleBounce extends StatefulWidget {
  final Widget child;
  const _GentleBounce({required this.child});

  @override
  State<_GentleBounce> createState() => _GentleBounceState();
}

class _GentleBounceState extends State<_GentleBounce> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, -4 * _controller.value),
        child: child,
      ),
    );
  }
}

/// Paints the compass dial face: radial wash ending in the state tint,
/// outer accent ring, dashed inner circle, 10° ticks (30° majors) and the
/// cardinal letters (N in red, per the mockup) + major degree labels.
class _DialPainter extends CustomPainter {
  final bool verified;
  _DialPainter({required this.verified});

  static const _cardinalAt = {0: 'N', 90: 'E', 180: 'S', 270: 'W'};

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final tint = verified ? InsightTheme.blueTint : InsightTheme.amberTint;
    final accent = verified ? InsightTheme.blue1 : InsightTheme.amber;

    // Face: subtle radial wash ending in the state tint at the rim.
    final face = Paint()
      ..shader = RadialGradient(
        colors: [Colors.white, const Color(0xFFF8FAFC), tint],
        stops: const [0.0, 0.82, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius - 4, face);

    // Outer accent ring.
    canvas.drawCircle(
      center,
      radius - 4,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = accent.withValues(alpha: 0.55),
    );

    // Dashed inner circle (2-on / 3-off segments).
    final dashPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = accent.withValues(alpha: 0.30);
    final dashCircle = Path()..addOval(Rect.fromCircle(center: center, radius: radius * 0.72));
    for (final metric in dashCircle.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        canvas.drawPath(metric.extractPath(dist, math.min(dist + 2, metric.length)), dashPaint);
        dist += 5;
      }
    }

    // Ticks + labels.
    for (int deg = 0; deg < 360; deg += 10) {
      final isMajor = deg % 30 == 0;
      final isCardinal = _cardinalAt.containsKey(deg);
      final angle = (deg - 90) * math.pi / 180.0;
      final tickLen = isMajor ? radius * 0.066 : radius * 0.033;
      final outer = Offset(center.dx + (radius - 9) * math.cos(angle), center.dy + (radius - 9) * math.sin(angle));
      final inner = Offset(center.dx + (radius - 9 - tickLen) * math.cos(angle), center.dy + (radius - 9 - tickLen) * math.sin(angle));
      canvas.drawLine(
        inner,
        outer,
        Paint()
          ..color = isMajor ? InsightTheme.ink2 : InsightTheme.ink3.withValues(alpha: 0.45)
          ..strokeWidth = isMajor ? 2 : 1
          ..strokeCap = StrokeCap.round,
      );

      if (isMajor) {
        final isDegreeLabel = !isCardinal;
        final label = _cardinalAt[deg] ?? '$deg°';
        final labelRadius = radius * 0.60;
        final pos = Offset(center.dx + labelRadius * math.cos(angle), center.dy + labelRadius * math.sin(angle));
        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: isCardinal
                ? InsightTheme.urbanist(size.width * 0.055, w: FontWeight.w800, c: deg == 0 ? InsightTheme.red : InsightTheme.ink2)
                : InsightTheme.mono(size.width * 0.036, w: FontWeight.w600, c: InsightTheme.ink3),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
        // isDegreeLabel kept for readability of intent above.
        assert(isDegreeLabel || _cardinalAt.containsKey(deg));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DialPainter oldDelegate) => oldDelegate.verified != verified;
}

/// Fixed amber pointer above the dial marking "straight ahead" (heading 0°
/// relative to the device's top edge).
class _TopPointerPainter extends CustomPainter {
  final Color color;
  _TopPointerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(0, size.height)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.2), 2, false);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _TopPointerPainter oldDelegate) => oldDelegate.color != color;
}

/// Direction-alignment pill under the compass: coaching text while far
/// from the site, success text once inside the verification zone. Also
/// surfaces the compass-unavailable case on devices without a magnetometer.
class _AlignmentTip extends StatelessWidget {
  final bool verified;
  final double? bearingToParcel;
  final bool compassUnavailable;

  const _AlignmentTip({
    required this.verified,
    required this.bearingToParcel,
    required this.compassUnavailable,
  });

  @override
  Widget build(BuildContext context) {
    final bg = verified ? InsightTheme.blueTint : InsightTheme.amberTint;
    final fg = verified ? InsightTheme.blueInk : InsightTheme.amberInk;
    final iconColor = verified ? InsightTheme.blue1 : InsightTheme.amber;

    final String text;
    if (compassUnavailable) {
      text = 'Compass unavailable on this device';
    } else if (verified) {
      text = 'Aligned with site target! Ready to verify.';
    } else if (bearingToParcel != null) {
      text = 'Rotate towards target site (${bearingToParcel!.round()}°)';
    } else {
      text = 'Walk towards the site to start verification';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.18)),
        boxShadow: const [BoxShadow(color: Color(0x0A0B1440), blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            verified ? Icons.check_circle_rounded : Icons.info_outline_rounded,
            size: 12,
            color: iconColor,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 2,
              softWrap: true,
              textAlign: TextAlign.center,
              style: InsightTheme.inter(11, w: FontWeight.w600, c: fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// ── Unified bottom verification card ─────────────────────────────────
///
/// Four rows per the approved mockup: target site + live distance/zone,
/// the Accuracy/Status/Heading metric grid, the tappable coordinates row
/// (copies to clipboard), and the primary action button. Stays visible in
/// fullscreen because confirming is the screen's primary action.
class _VerificationCard extends StatelessWidget {
  final String distanceText;
  final double? accuracy;
  final bool verified;
  final double? heading;
  final String headingCardinal;
  final String? coords;
  final String location;
  final bool submitting;
  final bool isReworkMode;
  final VoidCallback onConfirm;

  const _VerificationCard({
    required this.distanceText,
    required this.accuracy,
    required this.verified,
    required this.heading,
    required this.headingCardinal,
    required this.coords,
    required this.location,
    required this.submitting,
    required this.isReworkMode,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final accent = verified ? InsightTheme.blue1 : InsightTheme.amber;
    final accentInk = verified ? InsightTheme.blueInk : InsightTheme.amberInk;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: InsightTheme.surface,
        borderRadius: BorderRadius.circular(InsightTheme.radiusLg),
        border: Border.all(color: InsightTheme.line),
        boxShadow: InsightTheme.cardShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: target site + distance/zone.
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: verified ? InsightTheme.blueTint : InsightTheme.amberTint,
                  borderRadius: BorderRadius.circular(InsightTheme.radiusSm),
                  border: Border.all(color: accentInk.withValues(alpha: 0.15)),
                ),
                child: Icon(Icons.my_location_rounded, size: 14, color: accentInk),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('TARGET SITE', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: InsightTheme.mono(8.5, w: FontWeight.w800, ls: 1, c: InsightTheme.ink3)),
                    Text(
                      location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: InsightTheme.urbanist(12, w: FontWeight.w700, c: InsightTheme.ink),
                    ),
                  ],
                ),
              ),
              Flexible(fit: FlexFit.tight, child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    heading != null ? '${heading!.round()}°' : '--',
                    style: InsightTheme.mono(15, w: FontWeight.w800, c: InsightTheme.ink),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
                      ),
                      const SizedBox(width: 4),
                      Flexible(child: Text(
                        verified ? 'In Zone (< 30 m)' : 'Outside Zone',
                        textAlign: TextAlign.right,
                        style: InsightTheme.inter(10, w: FontWeight.w700, c: accentInk),
                      )),
                    ],
                  ),
                ],
              )),
            ],
          ),
          const SizedBox(height: 10),

          // Row 2: Accuracy / Status / Heading grid.
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: InsightTheme.bg,
              borderRadius: BorderRadius.circular(InsightTheme.radiusMd),
              border: Border.all(color: InsightTheme.line),
            ),
            child: Row(
              children: [
                _Metric(
                  label: 'ACCURACY',
                  value: '±${accuracy?.round() ?? "--"} m',
                  mono: true,
                  valueColor: InsightTheme.ink,
                ),
                _verticalDivider,
                _Metric(
                  label: 'STATUS',
                  value: verified ? 'In Range' : 'Too Far',
                  mono: false,
                  valueColor: accentInk,
                ),
                _verticalDivider,
                _Metric(
                  label: 'DISTANCE',
                  value: distanceText,
                  mono: true,
                  valueColor: verified ? InsightTheme.blueInk : InsightTheme.ink2,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Row 3: coordinates (tap to copy).
          _CoordinatesRow(coords: coords),
          const SizedBox(height: 12),

          // Row 4: primary action button.
          GestureDetector(
            onTap: (verified && !submitting) ? onConfirm : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 48,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: verified ? InsightTheme.primaryGradient : null,
                color: verified ? null : InsightTheme.surface2,
                borderRadius: BorderRadius.circular(InsightTheme.radiusMd),
                border: Border.all(color: verified ? Colors.transparent : InsightTheme.line),
                boxShadow: verified
                    ? [BoxShadow(color: InsightTheme.blue1.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 8))]
                    : null,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    if (submitting)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    else
                      Icon(
                        verified ? Icons.verified_user_rounded : Icons.location_searching_rounded,
                        size: 16,
                        color: verified ? Colors.white : InsightTheme.ink3,
                      ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        !verified
                            ? 'Approach site (< 30 m)'
                            : (isReworkMode ? 'Save' : 'Verify GPS Location Now'),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: InsightTheme.inter(12, w: FontWeight.w800, ls: 0.8, c: verified ? Colors.white : InsightTheme.ink3),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget get _verticalDivider => Container(width: 1, height: 24, color: InsightTheme.line);
}

/// One cell of the metric grid: tiny uppercase label over the value.
/// [mono] renders the value in JetBrains Mono (readings), otherwise the
/// sans face (word statuses). [FittedBox] lets long readings shrink
/// instead of overflowing.
class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;
  final Color valueColor;

  const _Metric({
    required this.label,
    required this.value,
    required this.mono,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: InsightTheme.mono(8, w: FontWeight.w700, ls: 0.5, c: InsightTheme.ink3)),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: mono
                  ? InsightTheme.mono(11.5, w: FontWeight.w800, c: valueColor)
                  : InsightTheme.inter(11.5, w: FontWeight.w800, c: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tappable coordinates row: copies the current fix to the clipboard and
/// flashes a green "Copied" check for two seconds (mockup behaviour).
class _CoordinatesRow extends StatefulWidget {
  final String? coords;
  const _CoordinatesRow({required this.coords});

  @override
  State<_CoordinatesRow> createState() => _CoordinatesRowState();
}

class _CoordinatesRowState extends State<_CoordinatesRow> {
  bool _copied = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    if (widget.coords == null) return;
    await Clipboard.setData(ClipboardData(text: widget.coords!));
    if (!mounted) return;
    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _copy,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: InsightTheme.bg,
          borderRadius: BorderRadius.circular(InsightTheme.radiusSm),
          border: Border.all(color: InsightTheme.line),
        ),
        child: Row(
          children: [
            const Icon(Icons.public_rounded, size: 12, color: InsightTheme.ink3),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.coords ?? 'Coordinates unavailable',
                maxLines: 2,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
                style: InsightTheme.mono(10.5, w: FontWeight.w600, c: InsightTheme.ink2),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: InsightTheme.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: InsightTheme.line),
              ),
              child: _copied
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_rounded, size: 10, color: InsightTheme.greenInk),
                        const SizedBox(width: 3),
                        Text('Copied', style: InsightTheme.inter(9, w: FontWeight.w800, c: InsightTheme.greenInk)),
                      ],
                    )
                  : const Icon(Icons.copy_rounded, size: 10, color: InsightTheme.ink3),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const ImapsLoadingIndicator(size: 50),
      const SizedBox(height: 16),
      Text('Acquiring satellite lock...', style: InsightTheme.inter(13, c: InsightTheme.ink2)),
    ]);
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.location_off_rounded, size: 40, color: InsightTheme.ink3),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center, softWrap: true, style: InsightTheme.inter(13, c: InsightTheme.ink2)),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
      ]),
    );
  }
}













