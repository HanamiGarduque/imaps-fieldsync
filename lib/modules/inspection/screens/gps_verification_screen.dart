import 'dart:ui';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
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

import 'package:connectivity_plus/connectivity_plus.dart';
import '../../../core/services/db_helper.dart';
import '../services/spatial_offline_service.dart';
import '../../../core/widgets/sensitive_screen.dart';
import '../../../core/theme/insight_theme.dart';
import '../widgets/inspection_step_header.dart';

class GpsVerificationScreen extends StatefulWidget {
  final TaskItem task;
  const GpsVerificationScreen({super.key, required this.task});

  @override
  State<GpsVerificationScreen> createState() => _GpsVerificationScreenState();
}

class _GpsVerificationScreenState extends State<GpsVerificationScreen> {
  static const double _rangeThresholdMeters = 30.0;
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

  bool get _verified => _distance != null && _distance! <= _rangeThresholdMeters;

  static const _cardinals = ['N','NNE','NE','ENE','E','ESE','SE','SSE','S','SSW','SW','WSW','W','WNW','NW','NNW'];
  String get _headingCardinal {
    if (_heading == null) return '--';
    return _cardinals[(((_heading! + 11.25) ~/ 22.5) % 16)];
  }
  String get _bearingLabel {
    if (_bearingToParcel == null) return 'Direction unknown';
    final bearing = _bearingToParcel!;
    const labels = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW', 'N'];
    return '${labels[((bearing + 22.5) ~/ 45) % 8]} (${bearing.round()}°)';
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
    final ok = await SupabaseService.markJobOngoing(jobId);
    if (ok) return true;
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

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    return SensitiveScreen(child: PopScope(
      canPop: !context.read<InspectionProvider>().isReworkMode && InspectionProgress.instance.currentStep > 1,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _markOngoingWithFallback(widget.task.id);
          return;
        }
        handleInspectionExit(
          context,
          onSaveProgress: () => _markOngoingWithFallback(widget.task.id),
          isReworkMode: context.read<InspectionProvider>().isReworkMode,
        );
      },
      child: Scaffold(
      backgroundColor: InsightTheme.bg,
      body: Stack(
        children: [
          Positioned(top: -60, right: -60, child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40), child: Container(width: 260, height: 260, decoration: BoxDecoration(shape: BoxShape.circle, color: InsightTheme.blue1.withValues(alpha: 0.20))))),
          Positioned(bottom: -80, left: -80, child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40), child: Container(width: 220, height: 220, decoration: BoxDecoration(shape: BoxShape.circle, color: InsightTheme.blue1.withValues(alpha: 0.10))))),

          SafeArea(
            child: Column(
              children: [
                InspectionStepHeader(
                  title: 'GPS Verification',
                  subtitle: widget.task.location,
                  stepNumber: 2,
                  stepSubtitle: 'VERIFY COORDINATES',
                  onBack: () => handleInspectionExit(
                    context,
                    onSaveProgress: () => _markOngoingWithFallback(widget.task.id),
                    isReworkMode: context.read<InspectionProvider>().isReworkMode,
                  ),
                ),

                Expanded(
                  child: _loading
                      ? const Center(child: _LoadingState())
                      : _error != null
                          ? Center(child: _ErrorState(message: _error!, onRetry: _checkLocation))
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                // Compass scales with the smaller of available width/height so it
                                // never forces the column below it off-screen (landscape, small
                                // devices) while staying a true circle.
                                final compassSize = math.min(
                                  constraints.maxWidth * 0.72,
                                  math.min(constraints.maxHeight * 0.62, 268.0),
                                ).clamp(160.0, 268.0).toDouble();

                                return SingleChildScrollView(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _Compass(
                                            size: compassSize,
                                            heading: _heading,
                                            bearingToParcel: _bearingToParcel,
                                            headingCardinal: _headingCardinal,
                                            verified: _verified,
                                          ),
                                          const SizedBox(height: 14),
                                          _DistanceBadge(distance: _distance, verified: _verified),
                                          const SizedBox(height: 14),
                                          if (_latitude != null && _longitude != null)
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 16),
                                              child: Text(
                                                "${_formatCoord(_latitude!, 'NS')}   ${_formatCoord(_longitude!, 'EW')}",
                                                textAlign: TextAlign.center,
                                                softWrap: true,
                                                style: InsightTheme.jetBrains(11.5, w: FontWeight.w600, c: InsightTheme.ink2, ls: 0.4),
                                              ),
                                            ),
                                          const SizedBox(height: 18),
                                          _MetricsRow(
                                            distance: _distance,
                                            accuracy: _accuracy,
                                            verified: _verified,
                                          ),
                                          const SizedBox(height: 10),
                                          if (_bearingToParcel != null)
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 16),
                                              child: Text(_bearingLabel, textAlign: TextAlign.center, softWrap: true, style: InsightTheme.poppins(14, w: FontWeight.w700, c: InsightTheme.blueInk)),
                                            ),
                                          const SizedBox(height: 10),
                                          if (_isLive || _heading != null)
                                            Wrap(
                                              alignment: WrapAlignment.center,
                                              crossAxisAlignment: WrapCrossAlignment.center,
                                              children: [
                                                if (_isLive) ...[
                                                  Container(
                                                    width: 8, height: 8,
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      color: InsightTheme.greenInk,
                                                      boxShadow: [BoxShadow(color: InsightTheme.greenInk.withValues(alpha: 0.5), blurRadius: 6, spreadRadius: 1)],
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text('LIVE TRACKING', style: InsightTheme.jetBrains(9.5, w: FontWeight.w700, c: InsightTheme.greenInk, ls: 0.6)),
                                                ],
                                                if (_isLive && _heading != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('•', style: InsightTheme.jetBrains(9.5, c: InsightTheme.ink3))),
                                                if (_heading != null) Text('COMPASS ACTIVE', style: InsightTheme.jetBrains(9.5, w: FontWeight.w700, c: InsightTheme.blueInk, ls: 0.6)),
                                              ],
                                            )
                                          else if (_compassUnavailable)
                                            Text('Compass unavailable on this device', style: InsightTheme.inter(11, c: InsightTheme.ink3)),
                                          if (!_verified) ...[
                                            const SizedBox(height: 16),
                                            TextButton.icon(onPressed: _checkLocation, icon: const Icon(Icons.refresh_rounded, size: 16, color: InsightTheme.blueInk), label: Text('Recheck Location', style: InsightTheme.inter(13, w: FontWeight.w600, c: InsightTheme.blueInk))),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                ),
                
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: ElevatedButton(
                    onPressed: (_verified && !_submitting) ? _startInspection : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ).copyWith(elevation: WidgetStateProperty.all(0)),
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: _verified ? [InsightTheme.blue1, InsightTheme.blue2] : [InsightTheme.ink3, InsightTheme.ink3], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: _verified ? [BoxShadow(color: InsightTheme.blue1.withValues(alpha: 0.32), blurRadius: 20, offset: const Offset(0, 8))] : [],
                      ),
                      child: Container(
                        alignment: Alignment.center, constraints: const BoxConstraints(minHeight: 52),
                        child: _submitting
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                            : Text(
                                !_verified
                                    ? 'Get closer to the site'
                                    : (context.watch<InspectionProvider>().isReworkMode ? 'Save' : 'Confirm & Continue'),
                                style: InsightTheme.poppins(15, w: FontWeight.w600, c: Colors.white),
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    ));
  }
}

/// Three compact, borderless metrics (Distance / Accuracy / Status) laid out
/// as a single responsive row directly beneath the coordinates — no card,
/// no background container. Each item is [Expanded] so the three share the
/// row equally, and the value line uses [FittedBox] so arbitrarily long
/// readings (e.g. "99999 m") scale down to fit instead of overflowing.
class _MetricsRow extends StatelessWidget {
  final double? distance;
  final double? accuracy;
  final bool verified;
  const _MetricsRow({required this.distance, required this.accuracy, required this.verified});

  @override
  Widget build(BuildContext context) {
    final items = [
      _MetricData(
        icon: Icons.map_outlined,
        value: distance != null ? '${distance!.round()} m' : '-- m',
        label: 'Distance',
        color: InsightTheme.blueInk,
      ),
      _MetricData(
        icon: Icons.gps_fixed_rounded,
        value: accuracy != null ? '±${accuracy!.round()} m' : '± -- m',
        label: 'Accuracy',
        color: InsightTheme.blueInk,
      ),
      _MetricData(
        icon: verified ? Icons.check_circle_rounded : Icons.error_outline_rounded,
        value: verified ? 'Verified' : 'Too far',
        label: 'Status',
        color: verified ? InsightTheme.greenInk : InsightTheme.ink2,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i != 0) const SizedBox(width: 4),
            Expanded(child: _MetricItem(data: items[i])),
          ],
        ],
      ),
    );
  }
}

class _MetricData {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  const _MetricData({required this.icon, required this.value, required this.label, required this.color});
}

class _MetricItem extends StatelessWidget {
  final _MetricData data;
  const _MetricItem({required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // FittedBox lets the icon+value line shrink as a unit rather than
        // wrapping or overflowing when the value is unusually long
        // (e.g. "12000 m", "99999 m").
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(data.icon, size: 15, color: data.color),
              const SizedBox(width: 4),
              Text(data.value, style: InsightTheme.poppins(14, w: FontWeight.w700, c: data.color)),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          data.label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: InsightTheme.jetBrains(9.5, c: InsightTheme.ink2, ls: 0.4),
        ),
      ],
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const CircularProgressIndicator(color: InsightTheme.blue1),
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

/// The circular compass ring + heading readout.
///
/// Only fixed-length content (cardinal letters, "NNW"; degrees, "0°"–"360°")
/// lives inside the fixed circle, so its size never needs to react to
/// variable-length data. [size] itself is computed responsively by the
/// caller via LayoutBuilder, so the compass shrinks gracefully on small
/// screens instead of relying on one hardcoded constant.
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
    // Proportions preserved from the original fixed-size design (250/268 and
    // 148/268) but derived from [size] so they scale together.
    final ringSize = size * (250 / 268);
    final innerSize = size * (148 / 268);
    final headingFontSize = (size / 268) * 34;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: ringSize,
            height: ringSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: InsightTheme.blue1.withValues(alpha: 0.22), blurRadius: 46, spreadRadius: 4)],
            ),
          ),
          AnimatedRotation(
            turns: heading != null ? -(heading! / 360) : 0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.linear,
            child: CustomPaint(size: Size(ringSize, ringSize), painter: _CompassRingPainter(verified: verified)),
          ),
          if (heading != null && bearingToParcel != null)
            Transform.rotate(
              angle: ((bearingToParcel! - heading!) * math.pi / 180.0),
              child: CustomPaint(size: Size(ringSize, ringSize), painter: _TargetArrowPainter(verified: verified)),
            ),
          Positioned(
            top: size * (2 / 268),
            child: CustomPaint(size: Size(18 * size / 268, 14 * size / 268), painter: _ForwardMarkerPainter(verified: verified)),
          ),
          Container(
            width: innerSize,
            height: innerSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: verified ? const [InsightTheme.blue1, InsightTheme.blue2] : [InsightTheme.blue1.withValues(alpha: 0.85), InsightTheme.blue2],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              boxShadow: [BoxShadow(color: InsightTheme.blue2.withValues(alpha: 0.35), blurRadius: 26, offset: const Offset(0, 12))],
              border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2),
            ),
            // Fixed-length content only ("N"/"NNW", "0°"-"360°") — its font
            // size already scales with [size] above, so it never needs to
            // fight a fixed diameter the way the old variable-length
            // distance text did.
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(headingCardinal, style: InsightTheme.poppins(math.max(12.0, headingFontSize * 15 / 34), w: FontWeight.w700, c: Colors.white.withValues(alpha: 0.9), ls: 1.5)),
                const SizedBox(height: 2),
                Text(heading != null ? '${heading!.round()}°' : '--°', style: InsightTheme.poppins(headingFontSize, w: FontWeight.w800, c: Colors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Distance readout pill. Lives outside the fixed compass circle in the
/// normally-flowing part of the column, so a value with any number of
/// digits (15 m ... 12345 m) simply grows the pill's intrinsic width and
/// wraps to a second line on very narrow screens instead of overflowing.
class _DistanceBadge extends StatelessWidget {
  final double? distance;
  final bool verified;
  const _DistanceBadge({required this.distance, required this.verified});

  @override
  Widget build(BuildContext context) {
    final label = distance != null ? '${distance!.round()}m from site' : '-- from site';
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width - 40),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: verified ? InsightTheme.greenTint : InsightTheme.blueTint,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          softWrap: true,
          style: InsightTheme.inter(12, w: FontWeight.w600, c: verified ? InsightTheme.greenInk : InsightTheme.blueInk),
        ),
      ),
    );
  }
}

class _CompassRingPainter extends CustomPainter {
  final bool verified;
  _CompassRingPainter({required this.verified});

  static const _cardinalAt = {0: 'N', 90: 'E', 180: 'S', 270: 'W'};

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final accent = verified ? InsightTheme.blue1 : const Color(0xFFE0A526);

    final ringPaint = Paint()
      ..shader = SweepGradient(
        colors: [accent.withValues(alpha: 0.05), accent.withValues(alpha: 0.35), accent.withValues(alpha: 0.05)],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, radius - 4, ringPaint);

    for (int deg = 0; deg < 360; deg += 10) {
      final isMajor = deg % 30 == 0;
      final isCardinal = _cardinalAt.containsKey(deg);
      final angle = (deg - 90) * math.pi / 180.0;
      final tickLen = isCardinal ? 16.0 : (isMajor ? 11.0 : 6.0);
      final outer = Offset(center.dx + (radius - 6) * math.cos(angle), center.dy + (radius - 6) * math.sin(angle));
      final inner = Offset(center.dx + (radius - 6 - tickLen) * math.cos(angle), center.dy + (radius - 6 - tickLen) * math.sin(angle));
      canvas.drawLine(
        inner, outer,
        Paint()
          ..color = isCardinal ? accent : InsightTheme.ink3.withValues(alpha: isMajor ? 0.55 : 0.3)
          ..strokeWidth = isCardinal ? 3 : (isMajor ? 2 : 1.2)
          ..strokeCap = StrokeCap.round,
      );

      if (isMajor) {
        final label = _cardinalAt[deg] ?? '$deg';
        final labelRadius = radius - 30;
        final pos = Offset(center.dx + labelRadius * math.cos(angle), center.dy + labelRadius * math.sin(angle));
        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: isCardinal
                ? InsightTheme.poppins(15, w: FontWeight.w800, c: accent)
                : InsightTheme.jetBrains(10, w: FontWeight.w600, c: InsightTheme.ink3),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CompassRingPainter oldDelegate) => oldDelegate.verified != verified;
}

class _ForwardMarkerPainter extends CustomPainter {
  final bool verified;
  _ForwardMarkerPainter({required this.verified});

  @override
  void paint(Canvas canvas, Size size) {
    final color = verified ? InsightTheme.blue1 : const Color(0xFFE0A526);
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(0, size.height)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.2), 2, false);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _ForwardMarkerPainter oldDelegate) => oldDelegate.verified != verified;
}

class _TargetArrowPainter extends CustomPainter {
  final bool verified;
  _TargetArrowPainter({required this.verified});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final color = verified ? InsightTheme.greenInk : InsightTheme.blueInk;
    final tip = Offset(center.dx, center.dy - (radius - 16));

    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - 8, tip.dy + 18)
      ..lineTo(tip.dx, tip.dy + 11)
      ..lineTo(tip.dx + 8, tip.dy + 18)
      ..close();
    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.25), 4, false);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawCircle(tip.translate(0, 6), 3, Paint()..color = Colors.white.withValues(alpha: 0.9));
  }

  @override
  bool shouldRepaint(covariant _TargetArrowPainter oldDelegate) => oldDelegate.verified != verified;
}