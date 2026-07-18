import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/user_profile.dart';
import 'home_dashboard_screen.dart';
import 'tasks_screen.dart';
import 'profile_screen.dart';

/// ==================================================================
/// THEME COLORS & TOKENS
/// ==================================================================
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

  static const Color green = Color(0xFF10B981);
  static const Color greenTint = Color(0xFFE3F8EC);
  static const Color greenInk = Color(0xFF0D7A3C);

  static const Color amber = Color(0xFFFFB700);
  static const Color amberTint = Color(0xFFFEF3DE);
  static const Color amberInk = Color(0xFFA66C00);

  static const Color line = Color(0x12141628);
  static const Color lineStrong = Color(0x21141628);

  static TextStyle poppins(double size, {FontWeight w = FontWeight.w600, Color? c, double? h, double? ls}) =>
      GoogleFonts.poppins(fontSize: size, fontWeight: w, color: c ?? ink, height: h ?? 1.2, letterSpacing: ls);

  static TextStyle inter(double size, {FontWeight w = FontWeight.w400, Color? c, double? h}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: c ?? ink2, height: h ?? 1.5);

  static TextStyle jetBrains(double size, {FontWeight w = FontWeight.w500, Color? c, double? ls}) =>
      GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: w, color: c ?? ink3, letterSpacing: ls);
}

/// ==================================================================
/// SCREEN — SYNC UPDATES (Premium Enterprise Edition)
/// ==================================================================
class UpdatesScreen extends StatefulWidget {
  final UserProfile profile;
  const UpdatesScreen({super.key, required this.profile});

  @override
  State<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends State<UpdatesScreen> {
  final int _currentNavIndex = 3; 
  bool _hasPendingItems = true;
  double _syncProgress = 0.0;
  String _transferRate = "4.2 MB/s";
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    if (_hasPendingItems) {
      _startLivePipelineSync();
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  // Real-world automatic background synchronization pipeline simulation
  void _startLivePipelineSync() {
    const duration = Duration(milliseconds: 100);
    _progressTimer = Timer.periodic(duration, (timer) {
      if (!mounted) return;
      
      setState(() {
        if (_syncProgress < 1.0) {
          _syncProgress += 0.025; // Simulates pipeline chunk uploads
          if (_syncProgress >= 0.7) {
            _transferRate = "1.8 MB/s"; // Simulates realistic data throttling near completion
          }
        } else {
          _progressTimer?.cancel();
          _hasPendingItems = false;
          _syncProgress = 0.0;
          _triggerSuccessHaptic();
        }
      });
    });
  }

  void _triggerSuccessHaptic() {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Text('Auto-sync finalized. Field cache clean.', style: InsightTheme.inter(13, c: Colors.white)),
          ],
        ),
        backgroundColor: InsightTheme.greenInk,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    return Scaffold(
      backgroundColor: InsightTheme.bg,
      extendBody: true, 
      body: Stack(
        children: [
          // Background Depth Anchor
          Positioned(
            top: -120, right: -60,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
              child: Container(
                width: 320, height: 320,
                decoration: BoxDecoration(shape: BoxShape.circle, color: InsightTheme.blue1.withValues(alpha: 0.1)),
              ),
            ),
          ),

          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. TOP UTILITY HEADER
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Sync Center', style: InsightTheme.poppins(24, w: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                width: 6, height: 6,
                                decoration: const BoxDecoration(color: InsightTheme.green, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 8),
                              Text('Node Secure · MPDO Server', style: InsightTheme.inter(12, w: FontWeight.w500, c: InsightTheme.ink2)),
                            ],
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            border: Border.all(color: InsightTheme.lineStrong),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('Purge Log', style: InsightTheme.inter(11, w: FontWeight.w600, c: InsightTheme.ink2)),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // 2. LIVE TELEMETRY / STATUS PIPELINE CARD
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24), 
                      gradient: const LinearGradient(
                        colors: [InsightTheme.blue1, InsightTheme.blue2],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(color: InsightTheme.blue1.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _hasPendingItems ? Icons.swap_vertical_circle_outlined : Icons.verified_user_rounded, 
                                  color: _hasPendingItems ? InsightTheme.amber : InsightTheme.green, 
                                  size: 18
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _hasPendingItems ? 'STREAMING DATA PIPELINE...' : 'ALL FIELD CACHE VERIFIED', 
                                  style: InsightTheme.jetBrains(11, w: FontWeight.w600, c: Colors.white, ls: 0.8)
                                ),
                              ],
                            ),
                            if (_hasPendingItems)
                              Text(
                                _transferRate,
                                style: InsightTheme.jetBrains(11, w: FontWeight.w600, c: Colors.white.withValues(alpha: 0.7))
                              )
                          ],
                        ),
                        
                        const SizedBox(height: 20),
                        
                        // Live Structural Progress Bar
                        Container(
                          height: 6,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Stack(
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 100),
                                width: MediaQuery.of(context).size.width * 0.8 * (_hasPendingItems ? _syncProgress : 1.0),
                                decoration: BoxDecoration(
                                  color: _hasPendingItems ? InsightTheme.amber : InsightTheme.green,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 18),
                          child: Divider(height: 1, color: Colors.white12),
                        ),

                        // Tabular Real-World Operational Metrics
                        Row(
                          children: [
                            Expanded(
                              child: _MetricItem(
                                label: 'QUEUE COUNT',
                                value: _hasPendingItems ? '1 Payload' : '0 Clean',
                                labelColor: Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                            Container(width: 1, height: 28, color: Colors.white12),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(left: 16),
                                child: _MetricItem(
                                  label: 'REMAINING SIZE',
                                  value: _hasPendingItems ? '${(12.4 * (1.0 - _syncProgress)).toStringAsFixed(1)} MB' : '0.00 B',
                                  labelColor: Colors.white.withValues(alpha: 0.5),
                                ),
                              ),
                            ),
                            Container(width: 1, height: 28, color: Colors.white12),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(left: 16),
                                child: _MetricItem(
                                  label: 'GATEWAY STATUS',
                                  value: 'ONLINE',
                                  labelColor: Colors.white.withValues(alpha: 0.5),
                                  valueColor: InsightTheme.green,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // 3. TABULAR DATA LOG & TRANSACTION MATRIX
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 140),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      // ACTIVE TRANSMISSION PIPELINE
                      if (_hasPendingItems) ...[
                        Row(
                          children: [
                            Container(width: 3, height: 12, decoration: BoxDecoration(color: InsightTheme.amberInk, borderRadius: BorderRadius.circular(2))),
                            const SizedBox(width: 8),
                            Text('ACTIVE TRANSMISSION QUEUE', style: InsightTheme.jetBrains(10, w: FontWeight.w700, ls: 1.2, c: InsightTheme.ink2)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _LogDataRow(
                          icon: Icons.image_rounded,
                          title: 'Unit 4, Rizal Complex',
                          dataType: '6 High-Res Photos + Field Notes',
                          dataSize: '12.4 MB',
                          statusText: '${(_syncProgress * 100).toInt()}% uploaded',
                          isPending: true,
                        ),
                        const SizedBox(height: 28),
                      ],

                      // AUDIT TRAIL / TRANSACTIONS
                      Row(
                        children: [
                          Container(width: 3, height: 12, decoration: BoxDecoration(color: InsightTheme.ink3, borderRadius: BorderRadius.circular(2))),
                          const SizedBox(width: 8),
                          Text('COMPLETED AUDIT LOG', style: InsightTheme.jetBrains(10, w: FontWeight.w700, ls: 1.2, c: InsightTheme.ink3)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      
                      Container(
                        decoration: BoxDecoration(
                          color: InsightTheme.surface,
                          borderRadius: BorderRadius.circular(16), 
                          border: Border.all(color: InsightTheme.line),
                          boxShadow: const [BoxShadow(color: Color(0x04141628), blurRadius: 10, offset: Offset(0, 4))],
                        ),
                        child: Column(
                          children: [
                            if (!_hasPendingItems) ...[
                               const _LogDataRow(
                                icon: Icons.image_rounded,
                                title: 'Unit 4, Rizal Complex',
                                dataType: '6 High-Res Photos + Field Notes',
                                dataSize: '12.4 MB',
                                statusText: 'Just now',
                                isPending: false,
                              ),
                              const Divider(height: 1, color: InsightTheme.line, indent: 56),
                            ],
                            const _LogDataRow(
                              icon: Icons.text_snippet_rounded,
                              title: 'Warehouse 7 Inspection',
                              dataType: 'Checklist Data & Compliance Report',
                              dataSize: '45 KB',
                              statusText: '14:15 PM',
                              isPending: false,
                            ),
                            const Divider(height: 1, color: InsightTheme.line, indent: 56),
                            const _LogDataRow(
                              icon: Icons.map_rounded,
                              title: 'Lot 22-B, Brgy. Maligaya',
                              dataType: 'GPS Verification Coordinates',
                              dataSize: '12 KB',
                              statusText: '11:30 AM',
                              isPending: false,
                            ),
                            const Divider(height: 1, color: InsightTheme.line, indent: 56),
                            const _LogDataRow(
                              icon: Icons.image_rounded,
                              title: 'Block 12 Enforcement',
                              dataType: '2 Incident Photos',
                              dataSize: '4.8 MB',
                              statusText: 'Yesterday',
                              isPending: false,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),

      // 4. FLOATING BOTTOM NAVIGATION 
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.65)),
                  boxShadow: const [
                    BoxShadow(color: Color(0x0A000000), blurRadius: 2, offset: Offset(0, 1)),
                    BoxShadow(color: Color(0x1A000000), blurRadius: 24, offset: Offset(0, 12)),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _BottomNavItem(
                      icon: Icons.home_rounded, label: 'Home', isActive: _currentNavIndex == 0,
                      onTap: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HomeDashboardScreen(profile: widget.profile))),
                    ),
                    _BottomNavItem(
                      icon: Icons.assignment_outlined, label: 'Tasks', isActive: _currentNavIndex == 1,
                      onTap: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => TasksScreen(profile: widget.profile))),
                    ),
                    _BottomNavItem(
                      icon: Icons.sync_rounded, label: 'Updates', isActive: _currentNavIndex == 3,
                      onTap: () {}, 
                    ),
                    _BottomNavItem(
                      icon: Icons.person_outline_rounded, label: 'Profile', isActive: _currentNavIndex == 4,
                      onTap: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ProfileScreen(profile: widget.profile))),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ==================================================================
/// COMPONENT WIDGETS
/// ==================================================================

class _MetricItem extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final Color labelColor;

  const _MetricItem({required this.label, required this.value, this.valueColor, required this.labelColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: InsightTheme.jetBrains(8.5, c: labelColor, ls: 0.3)),
        const SizedBox(height: 4),
        Text(value, style: InsightTheme.poppins(14, w: FontWeight.w700, c: valueColor ?? Colors.white)),
      ],
    );
  }
}

class _LogDataRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String dataType;
  final String dataSize;
  final String statusText;
  final bool isPending;

  const _LogDataRow({
    required this.icon,
    required this.title,
    required this.dataType,
    required this.dataSize,
    required this.statusText,
    required this.isPending,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: isPending 
        ? BoxDecoration(
            color: InsightTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: InsightTheme.amberTint, width: 2),
            boxShadow: const [BoxShadow(color: Color(0x04141628), blurRadius: 10, offset: Offset(0, 4))],
          )
        : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isPending ? InsightTheme.amberTint : InsightTheme.surface2,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: isPending ? InsightTheme.amberInk : InsightTheme.ink2),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title, 
                        style: InsightTheme.inter(13.5, w: FontWeight.w600, c: InsightTheme.ink),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      dataSize, 
                      style: InsightTheme.jetBrains(10.5, w: FontWeight.w600, c: InsightTheme.ink2)
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(dataType, style: InsightTheme.inter(11.5, c: InsightTheme.ink2), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    Row(
                      children: [
                        if (isPending) ...[
                          const SizedBox(width: 8, height: 8, child: CircularProgressIndicator(strokeWidth: 1.5, color: InsightTheme.amberInk)),
                          const SizedBox(width: 6),
                        ] else ...[
                          const Icon(Icons.check_circle_rounded, size: 10, color: InsightTheme.greenInk),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          statusText, 
                          style: InsightTheme.inter(10.5, w: FontWeight.w500, c: isPending ? InsightTheme.amberInk : InsightTheme.ink3)
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _BottomNavItem({required this.icon, required this.label, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: isActive ? 14 : 10, vertical: 10),
        decoration: BoxDecoration(
          gradient: isActive ? const LinearGradient(
            colors: [InsightTheme.blue1, InsightTheme.blue2],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ) : null,
          borderRadius: BorderRadius.circular(14),
          boxShadow: isActive ? [
            BoxShadow(color: InsightTheme.blue1.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))
          ] : [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isActive ? Colors.white : InsightTheme.ink3, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: InsightTheme.inter(10, w: FontWeight.w600, c: isActive ? Colors.white : InsightTheme.ink3),
            ),
          ],
        ),
      ),
    );
  }
}