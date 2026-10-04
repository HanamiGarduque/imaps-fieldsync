import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';

import '../services/location_service.dart';
import '../services/supabase_service.dart';
import 'capture_photo_screen.dart';
import 'tasks_screen.dart';
import 'inspection_progress.dart';

import '../theme/insight_theme.dart';

/// ==================================================================
/// SCREEN 8 — GPS VERIFICATION
/// ==================================================================
class GpsVerificationScreen extends StatefulWidget {
  final TaskItem task;
  const GpsVerificationScreen({super.key, required this.task});

  @override
  State<GpsVerificationScreen> createState() => _GpsVerificationScreenState();
}

class _GpsVerificationScreenState extends State<GpsVerificationScreen> {
  // Within this many meters of the parcel's declared point location counts
  // as "on site". supabase_parcels.geom is a single Point (confirmed via
  // ST_GeometryType), not a boundary polygon — so this is distance-to-pin,
  // not distance-to-polygon-edge.
  // Distance is 0 whenever the device is already inside the polygon.
  static const double _rangeThresholdMeters = 30.0;

  bool _loading = true;
  bool _submitting = false;
  String? _error;

  double? _distance;
  double? _accuracy;
  double? _latitude;
  double? _longitude;

  bool get _verified =>
      _distance != null && _distance! <= _rangeThresholdMeters;

  @override
  void initState() {
    super.initState();
    _checkLocation();
  }

  Future<void> _checkLocation() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (widget.task.parcelId == null) {
        throw Exception('No parcel linked to this task.');
      }

      final Position pos = await LocationService.getCurrentLocation();
      final double distance = await SupabaseService.getDistanceToParcelBoundary(
        parcelId: widget.task.parcelId!,
        latitude: pos.latitude,
        longitude: pos.longitude,
      );

      if (!mounted) return;
      setState(() {
        _latitude = pos.latitude;
        _longitude = pos.longitude;
        _accuracy = pos.accuracy;
        _distance = distance;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _startInspection() async {
    if (!_verified || _latitude == null || _longitude == null || _submitting) {
      return;
    }

    setState(() => _submitting = true);
    try {
      await SupabaseService.confirmGpsOnSite(
        jobId: widget.task.id,
        latitude: _latitude!,
        longitude: _longitude!,
        accuracyMeters: _accuracy ?? 0,
      );

      if (!mounted) return;
      HapticFeedback.selectionClick();
      InspectionProgress.instance.markStepComplete(2);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => CapturePhotoScreen(task: widget.task)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save GPS check-in: $e')),
      );
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
          // ----------------------------------------------------
          // BACKGROUND GRADIENT BLOBS
          // ----------------------------------------------------
          Positioned(
            top: -60,
            right: -60,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: InsightTheme.blue1.withOpacity(0.20),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            left: -80,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: InsightTheme.blue1.withOpacity(0.10),
                ),
              ),
            ),
          ),

          // ----------------------------------------------------
          // MAIN CONTENT
          // ----------------------------------------------------
          SafeArea(
            child: Column(
              children: [
                // TOP BAR
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      _GlassBackButton(onTap: () => Navigator.pop(context)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'GPS verification',
                          style: InsightTheme.poppins(17, w: FontWeight.w700, c: InsightTheme.ink),
                        ),
                      ),
                    ],
                  ),
                ),

                // PROGRESS BAR
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 6,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: InsightTheme.surface2,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: 0.333, // 33.3% Step 2 of 6
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [InsightTheme.blue1, InsightTheme.blue2],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text('STEP 2 OF 6', style: InsightTheme.jetBrains(10, w: FontWeight.w700, c: InsightTheme.blueInk, ls: 0.5)),
                          Text(' — GPS verification', style: InsightTheme.jetBrains(10, c: InsightTheme.ink3, ls: 0.5)),
                        ],
                      ),
                    ],
                  ),
                ),

                // DIAL WIDGET (CENTER)
                Expanded(
                  child: Center(
                    child: _loading
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(color: InsightTheme.blue1),
                              const SizedBox(height: 16),
                              Text('Getting your location...', style: InsightTheme.inter(13, c: InsightTheme.ink2)),
                            ],
                          )
                        : _error != null
                            ? Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 32),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.location_off_rounded, size: 40, color: InsightTheme.ink3),
                                    const SizedBox(height: 12),
                                    Text(
                                      _error!,
                                      textAlign: TextAlign.center,
                                      style: InsightTheme.inter(13, c: InsightTheme.ink2),
                                    ),
                                    const SizedBox(height: 16),
                                    OutlinedButton(
                                      onPressed: _checkLocation,
                                      child: const Text('Try again'),
                                    ),
                                  ],
                                ),
                              )
                            : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 230,
                          height: 230,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Circular Tick Marks
                              SizedBox(
                                width: 230,
                                height: 230,
                                child: CustomPaint(painter: _DialTicksPainter()),
                              ),
                              // Glowing Indicator Dash
                              Positioned(
                                top: 6,
                                child: Container(
                                  width: 5,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: _verified
                                          ? [InsightTheme.blue1, InsightTheme.blue2]
                                          : const [Color(0xFFE0A526), Color(0xFFB9821A)],
                                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                                    ),
                                    borderRadius: BorderRadius.circular(3),
                                    boxShadow: [
                                      BoxShadow(color: (_verified ? InsightTheme.blue1 : const Color(0xFFE0A526)).withOpacity(0.6), blurRadius: 10),
                                    ],
                                  ),
                                ),
                              ),
                              // Center Elevated Circle
                              Container(
                                width: 150,
                                height: 150,
                                decoration: BoxDecoration(
                                  color: InsightTheme.surface,
                                  shape: BoxShape.circle,
                                  boxShadow: const [
                                    BoxShadow(color: Color(0x1A141628), blurRadius: 40, offset: Offset(0, 20)),
                                  ],
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      _distance != null ? '${_distance!.round()}m' : '--',
                                      style: InsightTheme.poppins(32, w: FontWeight.w800),
                                    ),
                                    Text('from site', style: InsightTheme.inter(11, w: FontWeight.w500)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        // Dial Range Labels
                        SizedBox(
                          width: 230,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('0m', style: InsightTheme.jetBrains(10)),
                              Text('100m', style: InsightTheme.jetBrains(10)),
                            ],
                          ),
                        ),
                        if (!_verified) ...[
                          const SizedBox(height: 10),
                          TextButton.icon(
                            onPressed: _checkLocation,
                            icon: const Icon(Icons.refresh_rounded, size: 16, color: InsightTheme.blueInk),
                            label: Text('Recheck location', style: InsightTheme.inter(12.5, w: FontWeight.w600, c: InsightTheme.blueInk)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // GLASS BOTTOM READOUT
                if (!_loading && _error == null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white.withOpacity(0.65)),
                          boxShadow: const [BoxShadow(color: Color(0x14141628), blurRadius: 26, offset: Offset(0, 10))],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _ReadoutItem(
                              icon: Icons.map_outlined,
                              value: _distance != null ? '${_distance!.round()}m' : '--',
                              label: 'DISTANCE',
                              isGreen: false,
                            ),
                            Container(width: 1, height: 36, color: InsightTheme.lineStrong),
                            _ReadoutItem(
                              icon: Icons.gps_fixed_rounded,
                              value: _accuracy != null ? '±${_accuracy!.round()}m' : '--',
                              label: 'ACCURACY',
                              isGreen: false,
                            ),
                            Container(width: 1, height: 36, color: InsightTheme.lineStrong),
                            _ReadoutItem(
                              icon: _verified ? Icons.check_rounded : Icons.error_outline_rounded,
                              value: _verified ? 'Verified' : 'Too far',
                              label: 'STATUS',
                              isGreen: _verified,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // START INSPECTION BUTTON
                if (!_loading && _error == null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: ElevatedButton(
                    onPressed: (_verified && !_submitting) ? _startInspection : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      backgroundColor: Colors.transparent, 
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ).copyWith(
                      elevation: WidgetStateProperty.all(0),
                    ),
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _verified
                              ? const [InsightTheme.blue1, InsightTheme.blue2]
                              : [InsightTheme.ink3, InsightTheme.ink3],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: _verified
                            ? [BoxShadow(color: InsightTheme.blue1.withOpacity(0.32), blurRadius: 22, offset: const Offset(0, 10))]
                            : [],
                      ),
                      child: Container(
                        alignment: Alignment.center,
                        constraints: const BoxConstraints(minHeight: 50),
                        child: _submitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                              )
                            : Text(
                                _verified ? 'Continue to photo evidence' : 'Get closer to the site',
                                style: InsightTheme.poppins(14.5, w: FontWeight.w600, c: Colors.white),
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
    );
  }
}

/// ==================================================================
/// COMPONENT WIDGETS
/// ==================================================================

class _ReadoutItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final bool isGreen;

  const _ReadoutItem({
    required this.icon,
    required this.value,
    required this.label,
    required this.isGreen,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: isGreen ? InsightTheme.greenTint : InsightTheme.blueTint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 14, color: isGreen ? InsightTheme.greenInk : InsightTheme.blueInk),
          ),
          const SizedBox(height: 8),
          Text(
            value, 
            style: InsightTheme.poppins(13, w: FontWeight.w700, c: isGreen ? InsightTheme.greenInk : InsightTheme.ink)
          ),
          const SizedBox(height: 2),
          Text(label, style: InsightTheme.jetBrains(8.5, ls: 0.5)),
        ],
      ),
    );
  }
}

class _DialTicksPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = InsightTheme.lineStrong.withOpacity(0.4)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final innerRadius = radius - 14;

    const int tickCount = 40;
    
    for (int i = 0; i < tickCount; i++) {
      // Don't draw the very top tick (index 30 if starting from right) so the blue dash can sit there
      // We start at 0 radians (right side), so top is at 3pi/2 which is index 30.
      if (i == 30) continue; 
      
      final angle = (i * 2 * math.pi) / tickCount;
      final start = Offset(
        center.dx + innerRadius * math.cos(angle),
        center.dy + innerRadius * math.sin(angle)
      );
      final end = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle)
      );
      
      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _GlassBackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _GlassBackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.5),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Colors.white.withOpacity(0.65)),
          boxShadow: const [BoxShadow(color: Color(0x0F141628), blurRadius: 14, offset: Offset(0, 4))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: const Center(
              child: Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: InsightTheme.ink),
            ),
          ),
        ),
      ),
    );
  }
}