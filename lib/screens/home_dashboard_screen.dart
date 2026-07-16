import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/user_profile.dart';
import 'tasks_screen.dart'; 
import 'site_map_screen.dart';
import 'profile_screen.dart';
import 'notifications_screen.dart';
import 'updates_screen.dart';

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
  
  static const Color red = Color(0xFFE23B4E);
  static const Color line = Color(0x12141628); // ~rgba(20,22,40,0.07)
  
  static TextStyle poppins(double size, {FontWeight w = FontWeight.w600, Color? c, double? h, double? ls}) => 
      GoogleFonts.poppins(fontSize: size, fontWeight: w, color: c ?? ink, height: h ?? 1.2, letterSpacing: ls);
      
  static TextStyle inter(double size, {FontWeight w = FontWeight.w400, Color? c, double? h}) => 
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: c ?? ink2, height: h ?? 1.5);
      
  static TextStyle jetBrains(double size, {FontWeight w = FontWeight.w500, Color? c, double? ls}) => 
      GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: w, color: c ?? ink3, letterSpacing: ls);
}

/// ==================================================================
/// SCREEN — HOME DASHBOARD 
/// ==================================================================
class HomeDashboardScreen extends StatefulWidget {
  final UserProfile profile;
  const HomeDashboardScreen({super.key, required this.profile});

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  int _currentNavIndex = 0;
  int _currentTabIndex = 0;

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
      return "${parts[0][0]}. ${parts[1]}";
    }
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final initials = _getInitials(widget.profile.fullName);
    final displayName = _getFirstNameInitialAndLastName(widget.profile.fullName);

    return Scaffold(
      backgroundColor: InsightTheme.bg,
      extendBody: true, // Allows content to scroll under floating nav bar
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ----------------------------------------------------
              // 1. TOP BAR (Profile & Notifications)
              // ----------------------------------------------------
              Row(
                children: [
                  Container(
                    width: 42, height: 42,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [InsightTheme.blue1, InsightTheme.blue2],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(initials, style: InsightTheme.poppins(14, w: FontWeight.w700, c: Colors.white)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Hey, $displayName', style: InsightTheme.inter(13, w: FontWeight.w500)),
                        Text('Welcome Back', style: InsightTheme.poppins(17, w: FontWeight.w700)),
                      ],
                    ),
                  ),
                  _NotificationBtn(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ----------------------------------------------------
              // 2. TABS
              // ----------------------------------------------------
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                child: Row(
                  children: [
                    _TabPill(text: "Today", isActive: _currentTabIndex == 0, onTap: () => setState(() => _currentTabIndex = 0)),
                    const SizedBox(width: 8),
                    _TabPill(text: "This week", isActive: _currentTabIndex == 1, onTap: () => setState(() => _currentTabIndex = 1)),
                    const SizedBox(width: 8),
                    _TabPill(text: "All", isActive: _currentTabIndex == 2, onTap: () => setState(() => _currentTabIndex = 2)),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ----------------------------------------------------
              // 3. METRICS ROW
              // ----------------------------------------------------
              Row(
                children: [
                  Expanded(child: _MetricCard(icon: Icons.calendar_today_outlined, value: '4', label: 'Due today')),
                  const SizedBox(width: 10),
                  Expanded(child: _MetricCard(icon: Icons.map_outlined, value: '12', label: 'This week')),
                  const SizedBox(width: 10),
                  Expanded(child: _MetricCard(icon: Icons.check_circle_outline, value: '92%', label: 'Compliance')),
                ],
              ),
              const SizedBox(height: 28),

              // ----------------------------------------------------
              // 4. NEXT ASSIGNMENT HERO CARD
              // ----------------------------------------------------
              const _SectionLabel(title: "NEXT ASSIGNMENT"),
              const SizedBox(height: 12),
              _HeroCard(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TasksScreen(profile: widget.profile))),
              ),
              const SizedBox(height: 28),

              // ----------------------------------------------------
              // 5. QUICK ACTIONS
              // ----------------------------------------------------
              const _SectionLabel(title: "QUICK ACTIONS"),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.play_circle_outline_rounded,
                      title: 'Start next inspection',
                      subtitle: 'GPS check required',
                      onTap: () {},
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.calendar_month_outlined,
                      title: 'Full schedule',
                      subtitle: '7 visits this week',
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TasksScreen(profile: widget.profile))),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      
      // ----------------------------------------------------
      // 6. FLOATING BOTTOM NAVIGATION (Glassmorphic)
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
                      onTap: () => setState(() => _currentNavIndex = 0)
                    ),
                    _BottomNavItem(
                      icon: Icons.assignment_outlined, label: 'Tasks', isActive: _currentNavIndex == 1, 
                      onTap: () { setState(() => _currentNavIndex = 1); Navigator.of(context).push(MaterialPageRoute(builder: (_) => TasksScreen(profile: widget.profile))); }
                    ),
                    _BottomNavItem(
                      icon: Icons.sync_rounded, label: 'Updates', isActive: _currentNavIndex == 3, 
                      onTap: () { setState(() => _currentNavIndex = 3); Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UpdatesScreen())); }
                    ),
                    _BottomNavItem(
                      icon: Icons.person_outline_rounded, label: 'Profile', isActive: _currentNavIndex == 4, 
                      onTap: () { setState(() => _currentNavIndex = 4); Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(profile: widget.profile))); }
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

class _NotificationBtn extends StatelessWidget {
  final VoidCallback onTap;
  const _NotificationBtn({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42, height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.65)),
          boxShadow: const [BoxShadow(color: InsightTheme.line, blurRadius: 14, offset: Offset(0, 4))],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.notifications_none_rounded, color: InsightTheme.ink, size: 22),
            Positioned(
              right: 10, top: 10,
              child: Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: InsightTheme.red, 
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5)
                ),
              ),
            )
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

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _MetricCard({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: InsightTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: InsightTheme.line),
        boxShadow: const [BoxShadow(color: InsightTheme.line, blurRadius: 2, offset: Offset(0, 1))],
      ),
      child: Column(
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: InsightTheme.blueTint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: InsightTheme.blueInk),
          ),
          const SizedBox(height: 10),
          Text(value, style: InsightTheme.poppins(18, w: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label, style: InsightTheme.inter(10, w: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String title;
  const _SectionLabel({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 12, height: 2,
          decoration: BoxDecoration(
            color: InsightTheme.blue1,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title, 
          style: InsightTheme.jetBrains(10, w: FontWeight.w600, ls: 1.2),
        ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  final VoidCallback onTap;
  const _HeroCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: const LinearGradient(
            colors: [InsightTheme.blue1, InsightTheme.blue2],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(color: InsightTheme.blue1.withOpacity(0.30), blurRadius: 32, offset: const Offset(0, 16))
          ],
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            // Decorative subtle background circle
            Positioned(
              right: -50, top: -50,
              child: Container(
                width: 160, height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.08),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Scheduled · 1:30 PM', 
                        style: InsightTheme.inter(10, w: FontWeight.w600, c: Colors.white)
                      ),
                    ),
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.22),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.3)),
                      ),
                      child: const Icon(Icons.map_outlined, color: Colors.white, size: 18),
                    )
                  ],
                ),
                const SizedBox(height: 36),
                Text('Lot 22-B, Brgy. Maligaya', style: InsightTheme.poppins(18, w: FontWeight.w700, c: Colors.white)),
                const SizedBox(height: 6),
                Text('Residential reclassification review', style: InsightTheme.inter(12, c: Colors.white.withOpacity(0.85))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon, required this.title, required this.subtitle, required this.onTap
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: InsightTheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: InsightTheme.line),
          boxShadow: const [BoxShadow(color: InsightTheme.line, blurRadius: 2, offset: Offset(0, 1))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: InsightTheme.blueTint,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: InsightTheme.blueInk),
            ),
            const SizedBox(height: 14),
            Text(title, style: InsightTheme.inter(13.5, w: FontWeight.w600, c: InsightTheme.ink)),
            const SizedBox(height: 4),
            Text(subtitle, style: InsightTheme.inter(11.5, c: InsightTheme.ink2)),
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