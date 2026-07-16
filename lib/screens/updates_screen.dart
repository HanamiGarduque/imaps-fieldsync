import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// ==================================================================
/// THEME COLORS & TOKENS
/// ==================================================================
class InsightTheme {
  static const Color bg = Color(0xFFF2F4FB);
  static const Color surface = Colors.white;
  
  static const Color ink = Color(0xFF12141F);
  static const Color ink2 = Color(0xFF666C82);
  static const Color ink3 = Color(0xFFA2A7BC);
  
  static const Color blue1 = Color(0xFF3D6BFF);
  static const Color blue2 = Color(0xFF0B2FBF);
  static const Color blueTint = Color(0xFFE7EDFF);
  static const Color blueInk = Color(0xFF1A3FC4);
  
  static const Color redTint = Color(0xFFFDECEE);
  static const Color redInk = Color(0xFFB72A3B);
  
  static const Color greenTint = Color(0xFFE3F8EC);
  static const Color greenInk = Color(0xFF0D7A3C);
  
  static const Color amberTint = Color(0xFFFEF3DE);
  static const Color amberInk = Color(0xFFA66C00);
  
  static const Color line = Color(0x12141628); 
  
  static TextStyle poppins(double size, {FontWeight w = FontWeight.w600, Color? c, double? h, double? ls}) => 
      GoogleFonts.poppins(fontSize: size, fontWeight: w, color: c ?? ink, height: h ?? 1.2, letterSpacing: ls);
      
  static TextStyle inter(double size, {FontWeight w = FontWeight.w400, Color? c, double? h}) => 
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: c ?? ink2, height: h ?? 1.5);
}

/// ==================================================================
/// SCREEN — SYNC UPDATES
/// ==================================================================
class UpdatesScreen extends StatefulWidget {
  const UpdatesScreen({super.key});

  @override
  State<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends State<UpdatesScreen> {
  int _currentTabIndex = 0; // 0 for All, 1 for Pending Sync

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
            top: -60, right: -60,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                width: 260, height: 260,
                decoration: BoxDecoration(shape: BoxShape.circle, color: InsightTheme.blue1.withOpacity(0.20)),
              ),
            ),
          ),
          Positioned(
            bottom: -80, left: -80,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                width: 220, height: 220,
                decoration: BoxDecoration(shape: BoxShape.circle, color: InsightTheme.blue1.withOpacity(0.10)),
              ),
            ),
          ),

          // ----------------------------------------------------
          // MAIN CONTENT
          // ----------------------------------------------------
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // TOP BAR
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      _GlassBackButton(onTap: () => Navigator.pop(context)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('Sync Updates', style: InsightTheme.poppins(17, w: FontWeight.w700)),
                      ),
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                        },
                        child: Text('Clear log', style: InsightTheme.inter(13.5, w: FontWeight.w600, c: InsightTheme.blueInk)),
                      ),
                    ],
                  ),
                ),

                // TABS
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      _TabPill(
                        text: "All", 
                        isActive: _currentTabIndex == 0, 
                        onTap: () => setState(() => _currentTabIndex = 0)
                      ),
                      const SizedBox(width: 8),
                      _TabPill(
                        text: "Pending Sync · 1", 
                        isActive: _currentTabIndex == 1, 
                        onTap: () => setState(() => _currentTabIndex = 1)
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 14),

                // SYNC LOG LIST
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      _UpdateRow(
                        icon: Icons.cloud_done_rounded,
                        title: 'Sync Completed',
                        subtitle: 'Warehouse 7 inspection data and 5 photos successfully uploaded to iMAPS.',
                        time: 'Just now',
                        iconBgColor: InsightTheme.greenTint,
                        iconColor: InsightTheme.greenInk,
                        isUnread: true,
                      ),
                      _UpdateRow(
                        icon: Icons.cloud_sync_rounded,
                        title: 'Pending Sync',
                        subtitle: 'Unit 4, Rizal Complex saved locally. Waiting for stable connection.',
                        time: '15m ago',
                        iconBgColor: InsightTheme.amberTint,
                        iconColor: InsightTheme.amberInk,
                        isUnread: true,
                      ),
                      _UpdateRow(
                        icon: Icons.cloud_done_rounded,
                        title: 'Sync Completed',
                        subtitle: 'Lot 22-B, Brgy. Maligaya checklist uploaded.',
                        time: '2h ago',
                        iconBgColor: InsightTheme.greenTint,
                        iconColor: InsightTheme.greenInk,
                        isUnread: false,
                      ),
                      _UpdateRow(
                        icon: Icons.wifi_rounded,
                        title: 'Online Mode Restored',
                        subtitle: 'Connection re-established. Background sync initialized.',
                        time: '3h ago',
                        iconBgColor: InsightTheme.blueTint,
                        iconColor: InsightTheme.blueInk,
                        isUnread: false,
                        isLast: true,
                      ),
                    ],
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

class _UpdateRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String time;
  final Color iconBgColor;
  final Color iconColor;
  final bool isUnread;
  final bool isLast;

  const _UpdateRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.time,
    required this.iconBgColor,
    required this.iconColor,
    this.isUnread = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => HapticFeedback.lightImpact(),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: isLast ? null : const Border(bottom: BorderSide(color: InsightTheme.line)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Colored Icon
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 12),
            
            // Text Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: InsightTheme.inter(13.5, w: FontWeight.w600, c: InsightTheme.ink)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: InsightTheme.inter(11.5, c: InsightTheme.ink2)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            
            // Time & Dot Indicator
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(time, style: InsightTheme.inter(11.5, c: InsightTheme.ink2)),
                if (isUnread) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(
                      color: InsightTheme.blue1,
                      shape: BoxShape.circle,
                    ),
                  ),
                ]
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  final String text;
  final bool isActive;
  final VoidCallback onTap;

  const _TabPill({required this.text, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          gradient: isActive ? const LinearGradient(
            colors: [InsightTheme.blue1, InsightTheme.blue2],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ) : null,
          color: isActive ? null : InsightTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: isActive ? null : Border.all(color: InsightTheme.line),
          boxShadow: isActive ? [
            BoxShadow(color: InsightTheme.blue1.withOpacity(0.28), blurRadius: 18, offset: const Offset(0, 8))
          ] : [
            const BoxShadow(color: InsightTheme.line, blurRadius: 2, offset: Offset(0, 1))
          ],
        ),
        child: Text(
          text, 
          style: InsightTheme.inter(
            12, 
            w: FontWeight.w600, 
            c: isActive ? Colors.white : InsightTheme.ink2
          ),
        ),
      ),
    );
  }
}

class _GlassBackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _GlassBackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38, height: 38,
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