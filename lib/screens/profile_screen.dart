import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/user_profile.dart';
import '../services/auth_service.dart'; // Preserved real service
import 'login_screen.dart'; // Preserved
import 'home_dashboard_screen.dart';
import 'tasks_screen.dart';
import 'updates_screen.dart';
import 'profile_edit_screen.dart'; // Imported the edit screen

/// ==================================================================
/// THEME COLORS & TOKENS (InSight Blue Glass & Gradient Theme)
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
  
  static const Color amberTint = Color(0xFFFEF3DE);
  static const Color amberInk = Color(0xFFA66C00);
  
  static const Color line = Color(0x12141628); // ~rgba(20,22,40,0.07)
  static const Color lineStrong = Color(0x21141628); // ~rgba(20,22,40,0.13)
  
  static TextStyle poppins(double size, {FontWeight w = FontWeight.w600, Color? c, double? h, double? ls}) => 
      GoogleFonts.poppins(fontSize: size, fontWeight: w, color: c ?? ink, height: h ?? 1.2, letterSpacing: ls);
      
  static TextStyle inter(double size, {FontWeight w = FontWeight.w400, Color? c, double? h}) => 
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: c ?? ink2, height: h ?? 1.5);
      
  static TextStyle jetBrains(double size, {FontWeight w = FontWeight.w500, Color? c, double? ls}) => 
      GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: w, color: c ?? ink3, letterSpacing: ls);
}

/// ==================================================================
/// SCREEN 17 — PROFILE
/// ==================================================================
class ProfileScreen extends StatefulWidget {
  final UserProfile profile;
  const ProfileScreen({super.key, required this.profile});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _currentNavIndex = 4; // 4 = Profile

  Future<void> _handleSignOut(BuildContext context) async {
    HapticFeedback.mediumImpact();
    await AuthService.signOut(); // Preserved business logic
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  String _getInitials(String name) {
    if (name.trim().isEmpty) return "JR";
    List<String> parts = name.trim().split(' ');
    if (parts.length > 1) {
      return "${parts[0][0]}${parts[1][0]}".toUpperCase();
    }
    return parts[0].substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  String _getFirstNameInitialAndLastName(String name) {
    if (name.trim().isEmpty) return "J. Reyes";
    List<String> parts = name.trim().split(' ');
    if (parts.length > 1) {
      return "${parts[0][0]}. ${parts.sublist(1).join(' ')}";
    }
    return name;
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    final initials = _getInitials(widget.profile.fullName);
    final displayName = _getFirstNameInitialAndLastName(widget.profile.fullName);
    final inspectorId = widget.profile.id.isNotEmpty ? widget.profile.id : 'INSP-0245';

    return Scaffold(
      backgroundColor: InsightTheme.bg,
      extendBody: true, // Content scrolls behind bottom nav
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
            bottom: false,
            child: Column(
              children: [
                // TOP BAR
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Profile',
                          style: InsightTheme.poppins(22, w: FontWeight.w700, c: InsightTheme.ink),
                        ),
                      ),
                    ],
                  ),
                ),

                // SCROLLABLE LIST
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      // PROFILE HEADER
                      Row(
                        children: [
                          Container(
                            width: 52, height: 52,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [InsightTheme.blue1, InsightTheme.blue2],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              initials, 
                              style: InsightTheme.poppins(16, w: FontWeight.w700, c: Colors.white)
                            ),
                          ),
                          const SizedBox(width: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(displayName, style: InsightTheme.inter(15, w: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text('Inspector ID · $inspectorId', style: InsightTheme.inter(11.5, c: InsightTheme.ink2)),
                            ],
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 32),

                      // COMBINED OPTIONS LIST
                      _ProfileListRow(
                        icon: Icons.person_outline_rounded,
                        title: 'Personal information',
                        isLast: false,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProfileEditScreen(profile: widget.profile),
                            ),
                          );
                        },
                      ),
                      _ProfileListRow(
                        icon: Icons.notifications_none_rounded,
                        title: 'Notifications',
                        isAmber: true,
                        isLast: false,
                        onTap: () {},
                      ),
                      _ProfileListRow(
                        icon: Icons.info_outline_rounded,
                        title: 'About InSight',
                        subtitle: 'v1.0.0',
                        isLast: true,
                        onTap: () {},
                      ),

                      const SizedBox(height: 32),

                      // SIGN OUT BUTTON
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton(
                          onPressed: () => _handleSignOut(context),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: InsightTheme.surface,
                            side: const BorderSide(color: InsightTheme.blue1, width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          child: Text(
                            'Sign out',
                            style: InsightTheme.inter(13.5, w: FontWeight.w600, c: InsightTheme.blueInk),
                          ),
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

      // ----------------------------------------------------
      // FLOATING BOTTOM NAVIGATION (Glassmorphic)
      // ----------------------------------------------------
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.65)),
                  boxShadow: const [
                    BoxShadow(color: Color(0x0A000000), blurRadius: 2, offset: Offset(0, 1)),
                    BoxShadow(color: Color(0x1A000000), blurRadius: 32, offset: Offset(0, 16)),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _BottomNavItem(
                      icon: Icons.home_rounded, label: 'Home', isActive: _currentNavIndex == 0, 
                      onTap: () { setState(() => _currentNavIndex = 0); Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HomeDashboardScreen(profile: widget.profile))); }
                    ),
                    _BottomNavItem(
                      icon: Icons.assignment_outlined, label: 'Tasks', isActive: _currentNavIndex == 1, 
                      onTap: () { setState(() => _currentNavIndex = 1); Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => TasksScreen(profile: widget.profile))); }
                    ),
                    _BottomNavItem(
                      icon: Icons.sync_rounded, label: 'Updates', isActive: _currentNavIndex == 3, 
                      onTap: () { setState(() => _currentNavIndex = 3); Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const UpdatesScreen())); }
                    ),
                    _BottomNavItem(
                      icon: Icons.person_outline_rounded, label: 'Profile', isActive: _currentNavIndex == 4, 
                      onTap: () => setState(() => _currentNavIndex = 4)
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

class _ProfileListRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool isAmber;
  final bool isLast;
  final VoidCallback onTap;

  const _ProfileListRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.isAmber = false,
    this.isLast = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: isLast ? null : const Border(bottom: BorderSide(color: InsightTheme.line)),
        ),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: isAmber ? InsightTheme.amberTint : InsightTheme.blueTint,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                icon, 
                size: 18, 
                color: isAmber ? InsightTheme.amberInk : InsightTheme.blueInk
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: InsightTheme.inter(13.5, w: FontWeight.w600, c: InsightTheme.ink)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: InsightTheme.inter(11.5, c: InsightTheme.ink2)),
                  ]
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: InsightTheme.ink3, size: 20),
          ],
        ),
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
        padding: EdgeInsets.symmetric(horizontal: isActive ? 16 : 10, vertical: 10),
        decoration: BoxDecoration(
          gradient: isActive ? const LinearGradient(
            colors: [InsightTheme.blue1, InsightTheme.blue2],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ) : null,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isActive ? [
            BoxShadow(color: InsightTheme.blue1.withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 6))
          ] : [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isActive ? Colors.white : InsightTheme.ink3, size: 20),
            const SizedBox(height: 4),
            Text(
              label, 
              style: InsightTheme.inter(
                10, 
                w: FontWeight.w600, 
                c: isActive ? Colors.white : InsightTheme.ink3
              ),
            ),
          ],
        ),
      ),
    );
  }
}