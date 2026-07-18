import 'dart:ui';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../services/location_service.dart';
import '../services/supabase_service.dart';
import '../providers/inspection_provider.dart';
import 'capture_photo_screen.dart';
import 'tasks_screen.dart';
import 'inspection_progress.dart';

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

  // Live tracking — replaces the old one-shot-only flow. The stream keeps
  // emitting as the inspector walks toward/away from the site; _isLive just
  // reflects whether it's currently active so the UI can show a "Live"
  // badge instead of implying the reading is stale until manually rechecked.
  StreamSubscription<Position>? _positionSub;
  bool _isLive = false;
  // Guards against overlapping distance-RPC calls if position updates
  // arrive faster than a previous recompute finishes.
  bool _recomputing = false;

  bool get _verified => _distance != null && _distance! <= _rangeThresholdMeters;
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
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  Future<void> _checkLocation() async {
    setState(() { _loading = true; _error = null; });
    try {
      if (widget.task.parcelId == null) throw Exception('No parcel linked.');
      final pos = await LocationService.getCurrentLocation();
      final dist = await SupabaseService.getDistanceToParcelBoundary(parcelId: widget.task.parcelId!, latitude: pos.latitude, longitude: pos.longitude);
      final parcel = await SupabaseService.fetchParcelDetails(widget.task.parcelId!);
      double? bearing;
      if (parcel != null && parcel['latitude'] != null && parcel['longitude'] != null) {
        bearing = _bearingBetween(pos.latitude, pos.longitude, parcel['latitude'], parcel['longitude']);
      }
      if (!mounted) return;
      setState(() { _latitude = pos.latitude; _longitude = pos.longitude; _accuracy = pos.accuracy; _distance = dist; _bearingToParcel = bearing; _loading = false; });
      // First fix succeeded — switch over to continuous tracking so the
      // reading keeps updating as the inspector moves, instead of going
      // stale until they tap "Recheck" again.
      _startLiveTracking();
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  /// Subscribes to a continuous position stream (~3–5m distanceFilter) and
  /// recomputes distance/bearing on every emission. Manual "Recheck" still
  /// works as a fallback (e.g. if the stream stalls or errors out) — it just
  /// does a one-shot fetch and restarts the stream on success.
  void _startLiveTracking() {
    if (_isLive) return; // already subscribed, don't double-listen
    _isLive = true;
    _positionSub = LocationService.getPositionStream().listen(
      _onPositionUpdate,
      onError: (Object e) {
        // A transient stream error shouldn't blank out a reading the
        // inspector already has — just drop back to "not live" and let
        // them fall back to manual Recheck.
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
      // Skip this update rather than surfacing an error mid-stream — the
      // next emission will likely succeed, and the last good reading is
      // still shown on screen.
    } finally {
      _recomputing = false;
    }
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
    try {
      await SupabaseService.confirmGpsOnSite(jobId: widget.task.id, latitude: _latitude!, longitude: _longitude!, accuracyMeters: _accuracy ?? 0, locationLabel: widget.task.location);
      if (!mounted) return;
      // Carries the real on-site result forward so Step 5 (Findings) shows
      // the actual distance instead of a hardcoded "Verified"/placeholder.
      context.read<InspectionProvider>().recordGpsVerification(distanceMeters: _distance ?? 0);
      HapticFeedback.selectionClick();
      InspectionProgress.instance.markStepComplete(2);
      Navigator.push(context, MaterialPageRoute(builder: (_) => CapturePhotoScreen(task: widget.task)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    return Scaffold(
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
                      _GlassBackButton(onTap: () => Navigator.pop(context)),
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
                                    width: 240, height: 240,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        CustomPaint(size: const Size(240, 240), painter: _DialTicksPainter()),
                                        Positioned(
                                          top: 6,
                                          child: Container(width: 5, height: 16, decoration: BoxDecoration(gradient: LinearGradient(colors: _verified ? [InsightTheme.blue1, InsightTheme.blue2] : const [Color(0xFFE0A526), Color(0xFFB9821A)], begin: Alignment.topCenter, end: Alignment.bottomCenter), borderRadius: BorderRadius.circular(3), boxShadow: [BoxShadow(color: (_verified ? InsightTheme.blue1 : const Color(0xFFE0A526)).withValues(alpha: 0.6), blurRadius: 10)])),
                                        ),
                                        Container(
                                          width: 140, height: 140,
                                          decoration: const BoxDecoration(color: InsightTheme.surface, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x1A141628), blurRadius: 30, offset: Offset(0, 15))]),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(_distance != null ? '${_distance!.round()}m' : '--', style: InsightTheme.poppins(32, w: FontWeight.w800)),
                                              Text('from site', style: InsightTheme.inter(12, w: FontWeight.w500, c: InsightTheme.ink2)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  if (_bearingToParcel != null) Text(_bearingLabel, style: InsightTheme.poppins(14, w: FontWeight.w700, c: InsightTheme.blueInk)),
                                  const SizedBox(height: 10),
                                  if (_isLive)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
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
                                    ),
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

class _DialTicksPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    canvas.drawCircle(center, radius - 2, Paint()..color = InsightTheme.lineStrong.withValues(alpha: 0.3)..style = PaintingStyle.stroke..strokeWidth = 1.2);
    for (int i = 0; i < 40; i++) {
      if (i == 30) continue;
      final angle = (i * 2 * math.pi) / 40;
      final isCard = i % 10 == 0;
      final tStart = Offset(center.dx + (radius - 14 - (isCard ? 4 : 0)) * math.cos(angle), center.dy + (radius - 14 - (isCard ? 4 : 0)) * math.sin(angle));
      final tEnd = Offset(center.dx + radius * math.cos(angle), center.dy + radius * math.sin(angle));
      canvas.drawLine(tStart, tEnd, Paint()..color = InsightTheme.lineStrong.withValues(alpha: 0.4)..strokeWidth = isCard ? 4 : 3..strokeCap = StrokeCap.round);
    }
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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