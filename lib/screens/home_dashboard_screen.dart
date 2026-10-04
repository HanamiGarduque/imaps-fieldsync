import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/user_profile.dart';
import 'tasks_screen.dart'; 
import 'site_map_screen.dart';
import 'profile_screen.dart';
import 'notifications_screen.dart';
import 'updates_screen.dart';
import 'profile_edit_screen.dart'; 

import '../theme/insight_theme.dart';

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
  
  late PageController _pageController;
  int _currentCardIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.85);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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
      extendBody: true, 
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 12, bottom: 200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ----------------------------------------------------
              // 1. TOP BAR (Profile & Notifications)
              // ----------------------------------------------------
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => ProfileEditScreen(profile: widget.profile)),
                        );
                      },
                      child: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [InsightTheme.blue1, InsightTheme.blue2],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(color: InsightTheme.blue1.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))
                          ]
                        ),
                        alignment: Alignment.center,
                        child: Text(initials, style: InsightTheme.poppins(14, w: FontWeight.w700, c: Colors.white)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Hey, $displayName', style: InsightTheme.inter(11, w: FontWeight.w500)),
                          Text('Welcome Back', style: InsightTheme.poppins(16, w: FontWeight.w700)),
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
              ),
              const SizedBox(height: 32), 

              // ----------------------------------------------------
              // 2. NEXT ASSIGNMENTS (Carousel)
              // ----------------------------------------------------
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _SectionLabel(
                  title: "NEXT ASSIGNMENTS",
                  trailing: GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => TasksScreen(profile: widget.profile)));
                    },
                    child: Text(
                      'See All',
                      style: InsightTheme.inter(11, w: FontWeight.w600, c: InsightTheme.blue1),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              
              SizedBox(
                height: 195, 
                child: PageView(
                  controller: _pageController,
                  clipBehavior: Clip.none,
                  onPageChanged: (int index) {
                    setState(() {
                      _currentCardIndex = index;
                    });
                  },
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      child: _HeroCard(
                        date: 'Scheduled · Jul 20, 2026',
                        location: 'Lot 22-B, Brgy. Maligaya',
                        description: 'Residential reclassification review',
                        bgIcon: Icons.home_rounded, // Consistent residential watermark
                        smallIcon: Icons.home_rounded, // Consistent residential indicator
                        gradientColors: const [InsightTheme.blue1, InsightTheme.blue2],
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TasksScreen(profile: widget.profile))),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      child: _HeroCard(
                        date: 'Scheduled · Jul 22, 2026',
                        location: 'Block 4, Downtown Center',
                        description: 'Commercial zoning compliance check',
                        bgIcon: Icons.location_city_rounded, // Consistent commercial building watermark
                        smallIcon: Icons.location_city_rounded, // Consistent commercial building indicator
                        gradientColors: const [InsightTheme.blue1, InsightTheme.blue2],
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TasksScreen(profile: widget.profile))),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(2, (index) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    height: 5,
                    width: _currentCardIndex == index ? 20 : 6,
                    decoration: BoxDecoration(
                      color: _currentCardIndex == index ? InsightTheme.blue1 : InsightTheme.ink3.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 32),

              // ----------------------------------------------------
              // 3. QUICK ACTIONS (Sleek Circular Icons)
              // ----------------------------------------------------
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: _SectionLabel(title: "QUICK ACTIONS"),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _QuickActionIcon(
                      icon: Icons.play_arrow_rounded, 
                      label: 'Inspect',
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TasksScreen(profile: widget.profile)))
                    ),
                    _QuickActionIcon(
                      icon: Icons.calendar_month_rounded, 
                      label: 'Schedule',
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TasksScreen(profile: widget.profile)))
                    ),
                    _QuickActionIcon(
                      icon: Icons.cloud_sync_rounded, 
                      label: 'Sync',
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => UpdatesScreen(profile: widget.profile))) 
                    ),
                    _QuickActionIcon(
                      icon: Icons.badge_rounded, 
                      label: 'Profile',
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(profile: widget.profile)))
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 36),

              // ----------------------------------------------------
              // 4. RECENT ACTIVITY (Inspector Focus)
              // ----------------------------------------------------
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: _SectionLabel(title: "RECENT ACTIVITY"),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    _ActivityTile(
                      icon: Icons.check_circle_outline_rounded,
                      title: 'Inspection Completed',
                      subtitle: 'Lot 22-B, Brgy. Maligaya',
                      time: '15 mins ago',
                      isRecent: true,
                    ),
                    const SizedBox(height: 12),
                    _ActivityTile(
                      icon: Icons.trending_flat_rounded,
                      title: 'Moved to Step 2: Site Verification',
                      subtitle: 'Block 4, Downtown Center',
                      time: '1 hour ago',
                      isRecent: false,
                    ),
                    const SizedBox(height: 12),
                    _ActivityTile(
                      icon: Icons.cloud_done_outlined,
                      title: 'Offline Reports Synced',
                      subtitle: '2 tasks uploaded to server',
                      time: '3 hours ago',
                      isRecent: false,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      
      // ----------------------------------------------------
      // 5. FLOATING BOTTOM NAVIGATION 
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
                      onTap: () => setState(() => _currentNavIndex = 0)
                    ),
                    _BottomNavItem(
                      icon: Icons.assignment_outlined, label: 'Tasks', isActive: _currentNavIndex == 1, 
                      onTap: () { setState(() => _currentNavIndex = 1); Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => TasksScreen(profile: widget.profile))); }
                    ),
                    _BottomNavItem(
                      icon: Icons.sync_rounded, label: 'Updates', isActive: _currentNavIndex == 3, 
                      onTap: () { setState(() => _currentNavIndex = 3); Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => UpdatesScreen(profile: widget.profile))); } 
                    ),
                    _BottomNavItem(
                      icon: Icons.person_outline_rounded, label: 'Profile', isActive: _currentNavIndex == 4, 
                      onTap: () { setState(() => _currentNavIndex = 4); Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ProfileScreen(profile: widget.profile))); }
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
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white),
          boxShadow: const [BoxShadow(color: InsightTheme.line, blurRadius: 10, offset: Offset(0, 3))],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.notifications_none_rounded, color: InsightTheme.ink, size: 18),
            Positioned(
              right: 8, top: 8,
              child: Container(
                width: 6, height: 6,
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

class _SectionLabel extends StatelessWidget {
  final String title;
  final Widget? trailing; 

  const _SectionLabel({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title, 
          style: InsightTheme.poppins(12, w: FontWeight.w700, ls: 1.0, c: InsightTheme.ink2),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  final String date;
  final String location;
  final String description;
  final IconData bgIcon;
  final IconData smallIcon;
  final List<Color> gradientColors;
  final VoidCallback onTap;

  const _HeroCard({
    required this.date,
    required this.location,
    required this.description,
    required this.bgIcon,
    required this.smallIcon,
    required this.gradientColors,
    required this.onTap
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(color: gradientColors.last.withOpacity(0.3), blurRadius: 18, offset: const Offset(0, 8))
          ],
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            // Decorative Background Icon matching the application type
            Positioned(
              right: -20, bottom: -10,
              child: Icon(
                bgIcon, 
                size: 110, 
                color: Colors.white.withOpacity(0.12)
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.15)),
                      ),
                      child: Text(
                        date, 
                        style: InsightTheme.inter(10, w: FontWeight.w600, c: Colors.white)
                      ),
                    ),
                    // Small Indicator Icon matching the application type
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.2)),
                      ),
                      child: Icon(smallIcon, color: Colors.white, size: 16),
                    )
                  ],
                ),
                const SizedBox(height: 18),
                Text(location, style: InsightTheme.poppins(16, w: FontWeight.w700, c: Colors.white)),
                const SizedBox(height: 2),
                Text(
                  description, 
                  style: InsightTheme.inter(11, c: Colors.white.withOpacity(0.85)),
                  maxLines: 1, 
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 4))
                      ]
                    ),
                    child: Text(
                      'View Task',
                      style: InsightTheme.poppins(11, w: FontWeight.w700, c: gradientColors.first, ls: 0.5),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionIcon({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: InsightTheme.surface,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: InsightTheme.line, blurRadius: 14, offset: const Offset(0, 6))
              ],
            ),
            child: Center(
              child: Icon(icon, size: 24, color: InsightTheme.blueInk),
            ),
          ),
          const SizedBox(height: 10),
          Text(label, style: InsightTheme.inter(11, w: FontWeight.w600, c: InsightTheme.ink)),
        ],
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String time;
  final bool isRecent;

  const _ActivityTile({
    required this.icon, required this.title, required this.subtitle, required this.time, this.isRecent = false
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: InsightTheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: InsightTheme.line, blurRadius: 12, offset: Offset(0, 6))],
      ),
      child: Row(
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: isRecent ? InsightTheme.blueTint : InsightTheme.surface2,
              shape: BoxShape.circle, 
            ),
            child: Icon(
              icon, 
              size: 20, 
              color: isRecent ? InsightTheme.blueInk : InsightTheme.ink2
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title, 
                  style: InsightTheme.poppins(12.5, w: FontWeight.w600, c: InsightTheme.ink),
                  maxLines: 2,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(subtitle, style: InsightTheme.inter(11, w: FontWeight.w500, c: InsightTheme.ink2)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Container(width: 3, height: 3, decoration: const BoxDecoration(color: InsightTheme.ink3, shape: BoxShape.circle)),
                    ),
                    Text(time, style: InsightTheme.inter(11, w: FontWeight.w500, c: InsightTheme.ink3)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, color: InsightTheme.ink3, size: 22),
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