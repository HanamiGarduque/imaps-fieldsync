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
import '../services/supabase_service.dart';
import '../services/sync_outbox_service.dart';
import '../providers/inspection_provider.dart';
import 'capture_photo_screen.dart';
import 'tasks_screen.dart';
import 'inspection_progress.dart';
import '../widgets/exit_confirm_dialog.dart';

import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/db_helper.dart';
import '../services/spatial_offline_service.dart';

class InsightTheme {
  static const Color bg = Color(0xFFF2F4FB);
  static const Color surface = Colors.white;
  static const Color surface2 = Color(0xFFEEF1FC);
  static const Color ink = Color(0xFF12141F);
  static const Color ink2 = Color(0xFF666C82);
  static const Color ink3 = Color(0xFFA2A7BC);
  static const Color blue1 = Color(0xFF3D6BFF);
  static const Color blue2 = Color(0xFF0B2FBF);
  static const Color blueTint = Color(0xFFE7EDFF);
  static const Color blueInk = Color(0xFF1A3FC4);
  static const Color greenTint = Color(0xFFE3F8EC);
  static const Color greenInk = Color(0xFF0D7A3C);
  static const Color line = Color(0x1A141628); 
  static const Color lineStrong = Color(0x2A141628); 
  
  static TextStyle poppins(double size, {FontWeight w = FontWeight.w600, Color? c, double? h, double? ls}) => GoogleFonts.poppins(fontSize: size, fontWeight: w, color: c ?? ink, height: h ?? 1.2, letterSpacing: ls);
  static TextStyle inter(double size, {FontWeight w = FontWeight.w400, Color? c, double? h, double? ls}) => GoogleFonts.inter(fontSize: size, fontWeight: w, color: c ?? ink2, height: h ?? 1.5, letterSpacing: ls);
  static TextStyle jetBrains(double size, {FontWeight w = FontWeight.w500, Color? c, double? ls}) => GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: w, color: c ?? ink3, letterSpacing: ls);
}

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
final online = connectivityResult is List
    ? (connectivityResult as List).any((r) => r != ConnectivityResult.none)
    : connectivityResult != ConnectivityResult.none;

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
      final dist = await SupabaseService.getDistanceToParcelBoundary(
        parcelId: widget.task.parcelId!,
        latitude: pos.latitude,
        longitude: pos.longitude,
      );
      final parcel = await SupabaseService.fetchParcelDetails(widget.task.parcelId!);
      double? bearing;
      if (parcel != null && parcel['latitude'] != null && parcel['longitude'] != null) {
        bearing = _bearingBetween(pos.latitude, pos.longitude, parcel['latitude'], parcel['longitude']);
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
    InspectionProgress.instance.markStepComplete(2);
    setState(() => _submitting = false);
    Navigator.push(context, MaterialPageRoute(builder: (_) => CapturePhotoScreen(task: widget.task)));
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    return PopScope(
      canPop: InspectionProgress.instance.currentStep > 1,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          SupabaseService.markJobOngoing(widget.task.id);
          return;
        }
        handleInspectionExit(
          context,
          onSaveProgress: () => SupabaseService.markJobOngoing(widget.task.id),
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      _GlassBackButton(onTap: () => handleInspectionExit(
                        context,
                        onSaveProgress: () => SupabaseService.markJobOngoing(widget.task.id),
                      )),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('GPS Verification', style: InsightTheme.poppins(17, w: FontWeight.w700)),
                            Text(widget.task.location, style: InsightTheme.inter(12, c: InsightTheme.ink2), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 6, decoration: BoxDecoration(color: InsightTheme.surface2, borderRadius: BorderRadius.circular(4)),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft, widthFactor: 2/6,
                          child: Container(decoration: BoxDecoration(gradient: const LinearGradient(colors: [InsightTheme.blue1, InsightTheme.blue2]), borderRadius: BorderRadius.circular(4))),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text('STEP 2 OF 6', style: InsightTheme.jetBrains(10, w: FontWeight.w700, c: InsightTheme.blueInk, ls: 0.5)),
                          Text(' — VERIFY COORDINATES', style: InsightTheme.jetBrains(10, c: InsightTheme.ink3, ls: 0.5)),
                        ],
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: Center(
                    child: _loading
                        ? Column(mainAxisSize: MainAxisSize.min, children: [const CircularProgressIndicator(color: InsightTheme.blue1), const SizedBox(height: 16), Text('Acquiring satellite lock...', style: InsightTheme.inter(13, c: InsightTheme.ink2))])
                        : _error != null
                            ? Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.location_off_rounded, size: 40, color: InsightTheme.ink3), const SizedBox(height: 12), Text(_error!, textAlign: TextAlign.center, style: InsightTheme.inter(13, c: InsightTheme.ink2)), const SizedBox(height: 16), OutlinedButton(onPressed: _checkLocation, child: const Text('Try again'))])
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 268, height: 268,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Container(
                                          width: 250, height: 250,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(color: InsightTheme.blue1.withValues(alpha: 0.22), blurRadius: 46, spreadRadius: 4),
                                            ],
                                          ),
                                        ),
                                        AnimatedRotation(
                                          turns: _heading != null ? -(_heading! / 360) : 0,
                                          duration: const Duration(milliseconds: 180),
                                          curve: Curves.linear,
                                          child: CustomPaint(size: const Size(250, 250), painter: _CompassRingPainter(verified: _verified)),
                                        ),
                                        if (_heading != null && _bearingToParcel != null)
                                          Transform.rotate(
                                            angle: ((_bearingToParcel! - _heading!) * math.pi / 180.0),
                                            child: CustomPaint(size: const Size(250, 250), painter: _TargetArrowPainter(verified: _verified)),
                                          ),
                                        Positioned(
                                          top: 2,
                                          child: CustomPaint(size: const Size(18, 14), painter: _ForwardMarkerPainter(verified: _verified)),
                                        ),
                                        Container(
                                          width: 148, height: 148,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: LinearGradient(
                                              colors: _verified ? const [InsightTheme.blue1, InsightTheme.blue2] : [InsightTheme.blue1.withValues(alpha: 0.85), InsightTheme.blue2],
                                              begin: Alignment.topLeft, end: Alignment.bottomRight,
                                            ),
                                            boxShadow: [BoxShadow(color: InsightTheme.blue2.withValues(alpha: 0.35), blurRadius: 26, offset: const Offset(0, 12))],
                                            border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2),
                                          ),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(_headingCardinal, style: InsightTheme.poppins(15, w: FontWeight.w700, c: Colors.white.withValues(alpha: 0.9), ls: 1.5)),
                                              const SizedBox(height: 2),
                                              Text(_heading != null ? '${_heading!.round()}°' : '--°', style: InsightTheme.poppins(34, w: FontWeight.w800, c: Colors.white)),
                                              const SizedBox(height: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                                                child: Text(_distance != null ? '${_distance!.round()}m from site' : '-- from site', style: InsightTheme.inter(10.5, w: FontWeight.w600, c: Colors.white)),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  if (_latitude != null && _longitude != null)
                                    Text(
                                      "${_formatCoord(_latitude!, 'NS')}   ${_formatCoord(_longitude!, 'EW')}",
                                      style: InsightTheme.jetBrains(11.5, w: FontWeight.w600, c: InsightTheme.ink2, ls: 0.4),
                                    ),
                                  const SizedBox(height: 8),
                                  if (_bearingToParcel != null) Text(_bearingLabel, style: InsightTheme.poppins(14, w: FontWeight.w700, c: InsightTheme.blueInk)),
                                  const SizedBox(height: 10),
                                  if (_isLive || _heading != null)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
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
                
                if (!_loading && _error == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white.withValues(alpha: 0.65)), boxShadow: const [BoxShadow(color: Color(0x14141628), blurRadius: 26, offset: Offset(0, 10))]),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _ReadoutItem(icon: Icons.map_outlined, value: '${_distance?.round() ?? '--'}m', label: 'DISTANCE', isGreen: false),
                              Container(width: 1, height: 36, color: InsightTheme.lineStrong),
                              _ReadoutItem(icon: Icons.gps_fixed_rounded, value: '±${_accuracy?.round() ?? '--'}m', label: 'ACCURACY', isGreen: false),
                              Container(width: 1, height: 36, color: InsightTheme.lineStrong),
                              _ReadoutItem(icon: _verified ? Icons.check_rounded : Icons.error_outline_rounded, value: _verified ? 'Verified' : 'Too far', label: 'STATUS', isGreen: _verified),
                            ],
                          ),
                        ),
                      ),
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
                            : Text(_verified ? 'Confirm & Continue' : 'Get closer to the site', style: InsightTheme.poppins(15, w: FontWeight.w600, c: Colors.white)),
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
    );
  }
}

class _ReadoutItem extends StatelessWidget {
  final IconData icon; final String value; final String label; final bool isGreen;
  const _ReadoutItem({required this.icon, required this.value, required this.label, required this.isGreen});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: isGreen ? InsightTheme.greenTint : InsightTheme.blueTint, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 16, color: isGreen ? InsightTheme.greenInk : InsightTheme.blueInk),
          ),
          const SizedBox(height: 8),
          Text(value, style: InsightTheme.poppins(14, w: FontWeight.w700, c: isGreen ? InsightTheme.greenInk : InsightTheme.ink)),
          const SizedBox(height: 2),
          Text(label, style: InsightTheme.jetBrains(9, c: InsightTheme.ink2)),
        ],
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

class _GlassBackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _GlassBackButton({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42, height: 42,
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withValues(alpha: 0.65)), boxShadow: const [BoxShadow(color: Color(0x0F141628), blurRadius: 10, offset: Offset(0, 4))]),
        child: ClipRRect(borderRadius: BorderRadius.circular(14), child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12), child: const Center(child: Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: InsightTheme.ink))))),
      ),
    );
  }
}