import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/user_profile.dart';
import 'home_dashboard_screen.dart';
import 'tasks_screen.dart';
import 'profile_screen.dart';

import '../theme/insight_theme.dart';

/// ==================================================================
/// SCREEN — SYNC UPDATES
/// ==================================================================
class UpdatesScreen extends StatefulWidget {
  final UserProfile profile;
  const UpdatesScreen({super.key, required this.profile});

  @override
  State<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends State<UpdatesScreen> {
  int _currentNavIndex = 3; 
  int _currentTabIndex = 0; 

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    return Scaffold(
      backgroundColor: InsightTheme.bg,
      extendBody: true, 
      body: Stack(
        children: [
          // BACKGROUND GRADIENT BLOBS
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

          // MAIN CONTENT
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // TOP BAR (Arrow removed, Title enlarged slightly, Clear log converted to icon)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Sync updates', style: InsightTheme.poppins(22, w: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text('Keep every field visit backed up', style: InsightTheme.inter(12, c: InsightTheme.ink2)),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => HapticFeedback.lightImpact(),
                        child: Container(
                          width: 42, height: 42,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white),
                            boxShadow: const [BoxShadow(color: InsightTheme.line, blurRadius: 10, offset: Offset(0, 3))],
                          ),
                          child: const Center(
                            child: Icon(Icons.delete_outline_rounded, size: 20, color: InsightTheme.redInk),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),

                // SYNC STATUS HERO
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                      gradient: const LinearGradient(
                        colors: [InsightTheme.blue1, InsightTheme.blue2],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(color: InsightTheme.blue1.withOpacity(0.30), blurRadius: 30, offset: const Offset(0, 16)),
                      ],
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: Stack(
                      children: [
                        Positioned(
                          right: -40, top: -40,
                          child: Container(
                            width: 140, height: 140,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.08)),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 38, height: 38,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.22),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.wifi_rounded, color: Colors.white, size: 19),
                                ),
                                const SizedBox(width: 10),
                                Text('All caught up online', style: InsightTheme.poppins(14, w: FontWeight.w700, c: Colors.white)),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Row(
                              children: const [
                                Expanded(child: _SyncStat(value: '3', label: 'Synced today')),
                                Expanded(child: _SyncStat(value: '1', label: 'Pending')),
                                Expanded(child: _SyncStat(value: '5', label: 'Photos backed up')),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // TABS
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      _TabPill(text: "All", isActive: _currentTabIndex == 0, onTap: () => setState(() => _currentTabIndex = 0)),
                      const SizedBox(width: 8),
                      _TabPill(text: "Pending sync · 1", isActive: _currentTabIndex == 1, onTap: () => setState(() => _currentTabIndex = 1)),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // SYNC LOG LIST 
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 200),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      if (_currentTabIndex == 0) ...[
                        const _UpdateCard(
                          icon: Icons.cloud_done_rounded,
                          title: 'Sync completed',
                          subtitle: 'Warehouse 7 inspection data and 5 photos uploaded to iMAPS.',
                          time: 'Just now',
                          iconBgColor: InsightTheme.greenTint,
                          iconColor: InsightTheme.greenInk,
                          isUnread: true,
                        ),
                        const _UpdateCard(
                          icon: Icons.cloud_sync_rounded,
                          title: 'Pending sync',
                          subtitle: 'Unit 4, Rizal Complex saved locally. Waiting for stable connection.',
                          time: '15m ago',
                          iconBgColor: InsightTheme.amberTint,
                          iconColor: InsightTheme.amberInk,
                          isUnread: true,
                        ),
                        const _UpdateCard(
                          icon: Icons.cloud_done_rounded,
                          title: 'Sync completed',
                          subtitle: 'Lot 22-B, Brgy. Maligaya checklist uploaded.',
                          time: '2h ago',
                          iconBgColor: InsightTheme.greenTint,
                          iconColor: InsightTheme.greenInk,
                        ),
                        const _UpdateCard(
                          icon: Icons.wifi_rounded,
                          title: 'Online mode restored',
                          subtitle: 'Connection re-established. Background sync initialized.',
                          time: '3h ago',
                          iconBgColor: InsightTheme.blueTint,
                          iconColor: InsightTheme.blueInk,
                        ),
                      ] else ...[
                        const _UpdateCard(
                          icon: Icons.cloud_sync_rounded,
                          title: 'Pending sync',
                          subtitle: 'Unit 4, Rizal Complex saved locally. Waiting for stable connection.',
                          time: '15m ago',
                          iconBgColor: InsightTheme.amberTint,
                          iconColor: InsightTheme.amberInk,
                          isUnread: true,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),

      // ----------------------------------------------------
      // FLOATING BOTTOM NAVIGATION 
      // ----------------------------------------------------
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
                  color: Colors.white.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.65)),
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
                      onTap: () {
                        setState(() => _currentNavIndex = 0);
                        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HomeDashboardScreen(profile: widget.profile)));
                      },
                    ),
                    _BottomNavItem(
                      icon: Icons.assignment_outlined, label: 'Tasks', isActive: _currentNavIndex == 1,
                      onTap: () {
                        setState(() => _currentNavIndex = 1);
                        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => TasksScreen(profile: widget.profile)));
                      },
                    ),
                    _BottomNavItem(
                      icon: Icons.sync_rounded, label: 'Updates', isActive: _currentNavIndex == 3,
                      onTap: () => setState(() => _currentNavIndex = 3),
                    ),
                    _BottomNavItem(
                      icon: Icons.person_outline_rounded, label: 'Profile', isActive: _currentNavIndex == 4,
                      onTap: () {
                        setState(() => _currentNavIndex = 4);
                        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ProfileScreen(profile: widget.profile)));
                      },
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

class _SyncStat extends StatelessWidget {
  final String value;
  final String label;
  const _SyncStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: InsightTheme.poppins(20, w: FontWeight.w800, c: Colors.white)),
        const SizedBox(height: 2),
        Text(label, style: InsightTheme.inter(10.5, c: Colors.white.withOpacity(0.85))),
      ],
    );
  }
}

class _UpdateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String time;
  final Color iconBgColor;
  final Color iconColor;
  final bool isUnread;

  const _UpdateCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.time,
    required this.iconBgColor,
    required this.iconColor,
    this.isUnread = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => HapticFeedback.lightImpact(),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: InsightTheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: InsightTheme.line),
            boxShadow: const [BoxShadow(color: Color(0x0A141628), blurRadius: 12, offset: Offset(0, 6))],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(color: iconBgColor, borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, size: 19, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(title, style: InsightTheme.inter(13.5, w: FontWeight.w600, c: InsightTheme.ink))),
                        if (isUnread)
                          Container(
                            width: 8, height: 8,
                            margin: const EdgeInsets.only(left: 6),
                            decoration: const BoxDecoration(color: InsightTheme.blue1, shape: BoxShape.circle),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(subtitle, style: InsightTheme.inter(11.5, c: InsightTheme.ink2)),
                    const SizedBox(height: 6),
                    Text(time, style: InsightTheme.inter(10.5, w: FontWeight.w600, c: InsightTheme.ink3)),
                  ],
                ),
              ),
            ],
          ),
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
          style: InsightTheme.inter(12, w: FontWeight.w600, c: isActive ? Colors.white : InsightTheme.ink2),
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
        padding: EdgeInsets.symmetric(horizontal: isActive ? 14 : 10, vertical: 10),
        decoration: BoxDecoration(
          gradient: isActive ? const LinearGradient(
            colors: [InsightTheme.blue1, InsightTheme.blue2],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ) : null,
          borderRadius: BorderRadius.circular(14),
          boxShadow: isActive ? [
            BoxShadow(color: InsightTheme.blue1.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))
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