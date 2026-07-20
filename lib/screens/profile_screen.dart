import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/feature_flags.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/user_profile.dart';
import '../models/dashboard_stats.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import 'login_screen.dart'; 
import 'home_dashboard_screen.dart';
import 'tasks_screen.dart';
import 'updates_screen.dart';
import 'profile_edit_screen.dart';
import 'about_insight_screen.dart';
import 'quick_unlock_setup_screen.dart';
import 'terms_privacy_screen.dart'; // Restored import for Terms & Privacy
import '../widgets/insight_bottom_nav.dart';
import '../widgets/insight_page_transition.dart';
import '../widgets/dashboard_widgets.dart';

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
  
  static const Color amber = Color(0xFFFFB700);
  static const Color green = Color(0xFF10B981);
  static const Color coral = Color(0xFFE23B4E);
  
  static const Color line = Color(0x12141628); 
  
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
  final bool showBottomNav;
  const ProfileScreen({super.key, required this.profile, this.showBottomNav = true});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _currentNavIndex = 3;
  late UserProfile _currentProfile;

  InspectorDashboardStats _stats = InspectorDashboardStats.empty();
  bool _isLoadingStats = true;
  bool _hasStatsError = false;

  @override
  void initState() {
    super.initState();
    _currentProfile = widget.profile;
    _refreshProfileFromServer();
    _loadStats();
  }

  /// Safety net: widget.profile is whatever the caller had in memory when
  /// this screen was pushed, which can be a beat stale (e.g. right after
  /// login, or if a prior screen held onto an older copy). This re-fetches
  /// the row that's actually in Supabase right now so the header never
  /// shows outdated name/role/avatar without needing an app reload.
  Future<void> _refreshProfileFromServer() async {
    final fresh = await SupabaseService.fetchMyProfile();
    if (fresh != null && mounted) {
      setState(() => _currentProfile = UserProfile.fromMap(fresh));
    }
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoadingStats = true;
      _hasStatsError = false;
    });
    try {
      final jobs = await SupabaseService.fetchMyJobs();
      final tasks = jobs.map((j) => TaskItem.fromJob(j)).toList();
      final stats = InspectorDashboardStats.fromTasks(tasks);

      if (mounted) {
        setState(() {
          _stats = stats;
          _isLoadingStats = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingStats = false;
          _hasStatsError = true;
        });
      }
    }
  }

  Future<void> _openEditScreen() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileEditScreen(profile: _currentProfile),
      ),
    );

    if (result != null && result is UserProfile && mounted) {
      setState(() {
        _currentProfile = result;
      });
    }
  }

  Future<void> _handleSignOut(BuildContext context) async {
    HapticFeedback.mediumImpact();
    await AuthService.signOut();
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

    final initials = _getInitials(_currentProfile.fullName);
    final displayName = _getFirstNameInitialAndLastName(_currentProfile.fullName);
    
    final currentUser = SupabaseService.client.auth.currentUser;
    final userEmail = currentUser?.email ?? 'No email found';
    final positionLabel = _currentProfile.isAdmin ? 'Administrator' : 'Zoning Officer I';

    return Scaffold(
      backgroundColor: InsightTheme.bg,
      extendBody: true, 
      body: Stack(
        children: [
          // Background Blobs for Premium Feel
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

          SafeArea(
            bottom: false,
            // Removed the redundant Column and Padding header entirely
            child: RefreshIndicator(
              color: InsightTheme.blue1,
              onRefresh: () async {
                await Future.wait([
                  _refreshProfileFromServer(),
                  _loadStats(),
                ]);
              },
              child: ListView(
              // Added slightly more top padding so the card breathes below the status bar
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              children: [
                // 1. IDENTITY CARD
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                  decoration: BoxDecoration(
                    color: InsightTheme.surface.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(color: Color(0x08141628), blurRadius: 30, offset: Offset(0, 10)),
                    ],
                  ),
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: _openEditScreen,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: InsightTheme.blueTint,
                              shape: BoxShape.circle,
                              border: Border.all(color: InsightTheme.blue1.withOpacity(0.1)),
                            ),
                            child: const Icon(Icons.edit_outlined, size: 16, color: InsightTheme.blueInk),
                          ),
                        ),
                      ),
                      
                      Container(
                            width: 86, height: 86,
                            margin: const EdgeInsets.only(top: 4, bottom: 16),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [InsightTheme.blue1, InsightTheme.blue2],
                                begin: Alignment.topLeft, end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(color: InsightTheme.blue1.withOpacity(0.35), blurRadius: 20, offset: const Offset(0, 8))
                              ],
                              border: Border.all(color: Colors.white, width: 3.5),
                              image: _currentProfile.avatarUrl != null
                                  ? DecorationImage(image: NetworkImage(_currentProfile.avatarUrl!), fit: BoxFit.cover)
                                  : null,
                            ),
                            alignment: Alignment.center,
                            child: _currentProfile.avatarUrl == null
                                ? Text(initials, style: InsightTheme.poppins(28, w: FontWeight.w700, c: Colors.white))
                                : null,
                          ),
                      
                      Text(displayName, style: InsightTheme.poppins(20, w: FontWeight.w700)),
                      const SizedBox(height: 10),
                      
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: InsightTheme.blue1.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: InsightTheme.blue1.withOpacity(0.15)),
                        ),
                        child: Text(
                          positionLabel.toUpperCase(),
                          style: InsightTheme.jetBrains(10, w: FontWeight.w600, c: InsightTheme.blueInk, ls: 0.8),
                        ),
                      ),
                      
                      const SizedBox(height: 18),
                      
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.email_outlined, size: 15, color: InsightTheme.ink3),
                          const SizedBox(width: 8),
                          Text(userEmail, style: InsightTheme.inter(13, w: FontWeight.w500, c: InsightTheme.ink2)),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),

                // 2. QUICK STATS ROW (Tasks Today/Pending, Completed Inspections)
                Row(
                  children: [
                    _buildStatCard(
                      'Tasks Today / Pending',
                      _isLoadingStats ? '—' : '${_stats.tasksTodayOrPendingCount}',
                      Icons.assignment_outlined,
                      InsightTheme.amber,
                    ),
                    const SizedBox(width: 16),
                    _buildStatCard(
                      'Completed Inspections',
                      _isLoadingStats ? '—' : '${_stats.completedCount}',
                      Icons.check_circle_outline_rounded,
                      InsightTheme.green,
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // 3. ANALYTICS DASHBOARD GRID
                if (_hasStatsError)
                  _dashboardErrorCard()
                else if (_isLoadingStats)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
                  )
                else ...[
                  // Left: wide gauge card. Right: trend on top, heatmap +
                  // zoning breakdown stacked below. On narrow phones this
                  // just stacks vertically since each card is full-width.
                  _dashboardCard(
                    child: CompletionGaugeCard(
                      rate: _stats.completionRate,
                      totalApplications: _stats.totalAssigned,
                      activeWorkload: _stats.activeWorkloadCount,
                      trackColor: InsightTheme.surface2,
                      fillColor: InsightTheme.blue1,
                      textColor: InsightTheme.ink,
                      mutedTextColor: InsightTheme.ink2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _dashboardCard(
                    child: WeeklyTrendCard(
                      points: _stats.weeklyTrend,
                      barColor: InsightTheme.blue1,
                      textColor: InsightTheme.ink,
                      mutedTextColor: InsightTheme.ink2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _dashboardCard(
                          child: ActivityHeatmapCard(
                            activeDays: _stats.activeDaysThisMonth,
                            month: _stats.currentMonth,
                            year: _stats.currentYear,
                            activeColor: InsightTheme.green,
                            inactiveColor: InsightTheme.surface2,
                            textColor: InsightTheme.ink,
                            mutedTextColor: InsightTheme.ink2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _dashboardCard(
                          child: ZoningTypeBreakdownCard(
                            entries: _stats.typeBreakdown,
                            barColor: InsightTheme.blue1,
                            trackColor: InsightTheme.surface2,
                            textColor: InsightTheme.ink,
                            mutedTextColor: InsightTheme.ink2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 24),

                // 4. UNIFIED ACTION CARD
                Container(
                  decoration: BoxDecoration(
                    color: InsightTheme.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: InsightTheme.line),
                    boxShadow: const [
                      BoxShadow(color: Color(0x04141628), blurRadius: 10, offset: Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    children: [
                      _ActionTile(
                        icon: Icons.info_outline_rounded,
                        title: 'About InSight',
                        subtitle: 'Version 1.0.0',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const AboutInsightScreen()),
                          );
                        },
                      ),
                      const Divider(height: 1, color: InsightTheme.line, indent: 64, endIndent: 20),
                      
                      // RESTORED: Terms and Privacy Policy Action Tile
                      _ActionTile(
                        icon: Icons.shield_outlined,
                        title: 'Privacy Policy',
                        subtitle: 'Legal information & policies',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const TermsPrivacyScreen()),
                          );
                        },
                      ),
                      const Divider(height: 1, color: InsightTheme.line, indent: 64, endIndent: 20),
                      
                      if (kQuickUnlockEnabled) ...[
                        _ActionTile(
                          icon: Icons.fingerprint,
                          title: 'Quick Unlock',
                          subtitle: 'Biometric / pattern',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => QuickUnlockSetupScreen(userEmail: userEmail)),
                            );
                          },
                        ),
                        const Divider(height: 1, color: InsightTheme.line, indent: 64, endIndent: 20),
                      ],

                      _ActionTile(
                        icon: Icons.logout_rounded,
                        title: 'Sign out',
                        isDestructive: true,
                        onTap: () => _handleSignOut(context),
                      ),
                    ],
                  ),
                ),
              ],
              ),
            ),
          ),
        ],
      ),

      bottomNavigationBar: !widget.showBottomNav ? null : InsightBottomNav(
        currentIndex: _currentNavIndex,
        items: const [
          InsightNavItem(icon: Icons.home_rounded, label: 'Home'),
          InsightNavItem(icon: Icons.assignment_outlined, label: 'Tasks'),
          InsightNavItem(icon: Icons.sync_rounded, label: 'Updates'),
          InsightNavItem(icon: Icons.person_outline_rounded, label: 'Profile'),
        ],
        onTap: (i) {
          if (i == _currentNavIndex) return;
          setState(() => _currentNavIndex = i);
          switch (i) {
            case 0:
              Navigator.of(context).pushReplacement(insightTabRoute(HomeDashboardScreen(profile: _currentProfile)));
              break;
            case 1:
              Navigator.of(context).pushReplacement(insightTabRoute(TasksScreen(profile: _currentProfile)));
              break;
            case 2:
              Navigator.of(context).pushReplacement(insightTabRoute(UpdatesScreen(profile: _currentProfile)));
              break;
          }
        },
      ),
    );
  }

  // WIDGET: Dashboard card shell (consistent padding/border/shadow around
  // each analytics widget so the widgets themselves stay layout-agnostic).
  Widget _dashboardCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: InsightTheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: InsightTheme.line),
        boxShadow: const [
          BoxShadow(color: Color(0x04141628), blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: child,
    );
  }

  Widget _dashboardErrorCard() {
    return _dashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: InsightTheme.coral, size: 18),
              const SizedBox(width: 8),
              Text('Couldn\'t load your analytics', style: InsightTheme.inter(13, w: FontWeight.w600, c: InsightTheme.ink)),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _loadStats,
            child: Text('Tap to retry', style: InsightTheme.inter(12.5, w: FontWeight.w600, c: InsightTheme.blueInk)),
          ),
        ],
      ),
    );
  }

  // WIDGET: Stat Card
  Widget _buildStatCard(String title, String count, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: InsightTheme.surface.withOpacity(0.9),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: InsightTheme.line),
          boxShadow: const [
            BoxShadow(color: Color(0x04141628), blurRadius: 10, offset: Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 16),
            Text(count, style: InsightTheme.poppins(24, w: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(title, style: InsightTheme.inter(11.5, w: FontWeight.w500, c: InsightTheme.ink2)),
          ],
        ),
      ),
    );
  }
}

// WIDGET: Unified Action Tile
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool isDestructive;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.isDestructive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fgColor = isDestructive ? InsightTheme.coral : InsightTheme.ink;
    final iconBgColor = isDestructive ? InsightTheme.coral.withOpacity(0.1) : InsightTheme.blueTint;
    final iconColor = isDestructive ? InsightTheme.coral : InsightTheme.blueInk;

    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: iconBgColor, borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: InsightTheme.inter(14, w: FontWeight.w600, c: fgColor)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: InsightTheme.inter(11.5, c: InsightTheme.ink3)),
                  ]
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: InsightTheme.ink3.withOpacity(0.5), size: 20),
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