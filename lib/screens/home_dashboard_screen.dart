import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../models/user_profile.dart';
import '../services/supabase_service.dart';
import '../services/db_helper.dart';
import 'tasks_screen.dart';
import 'parcel_detail_screen.dart';
import 'profile_screen.dart';
import 'notifications_screen.dart';
import 'updates_screen.dart';
import 'profile_edit_screen.dart'; 

/// ==================================================================
/// THEME COLORS & TOKENS 
/// ==================================================================
class InsightTheme {
  static const Color bg = Color(0xFFF4F6FB); 
  static const Color surface = Colors.white;
  
  static const Color ink = Color(0xFF0F111A);
  static const Color ink2 = Color(0xFF595E73);
  static const Color ink3 = Color(0xFF969CB3);
  
  static const Color blue1 = Color(0xFF3563FF);
  static const Color blue2 = Color(0xFF0F32CA);
  static const Color blueTint = Color(0xFFE4EBFF);
  static const Color blueInk = Color(0xFF1336B8);
  
  static const Color red = Color(0xFFE23B4E);
  static const Color green = Color(0xFF22C55E);
  static const Color orange = Color(0xFFF59E0B);
  
  static const Color line = Color(0x15141628); 
  
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

  late PageController _pageController;
  int _currentCardIndex = 0;

  List<TaskItem> _upcomingTasks = [];
  bool _isLoadingTasks = true;

  List<Map<String, dynamic>> _recentActivity = [];
  bool _isLoadingActivity = true;
  int _unreadCount = 0;

  bool _isOnline = true;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.85); 
    
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      if (mounted) {
        setState(() {
          _isOnline = !results.contains(ConnectivityResult.none);
        });
      }
    });

    _loadUpcomingTasks();
    _loadRecentActivity();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _connectivitySubscription.cancel();
    super.dispose();
  }

  Future<void> _loadUpcomingTasks() async {
    setState(() => _isLoadingTasks = true);
    List<TaskItem> tasks = [];
    try {
      final dynamic connectivityResult = await Connectivity().checkConnectivity();
      final bool hasConnection;
      if (connectivityResult is ConnectivityResult) {
        hasConnection = connectivityResult != ConnectivityResult.none;
      } else if (connectivityResult is List) {
        hasConnection = connectivityResult
            .cast<ConnectivityResult>()
            .any((status) => status != ConnectivityResult.none);
      } else {
        hasConnection = false;
      }

      if (hasConnection) {
        final jobs = await SupabaseService.fetchMyJobs();
        tasks = jobs.map((j) => TaskItem.fromJob(j)).toList();
      } else {
        final localJobs = await DBHelper.getCachedJobs();
        tasks = localJobs.map((j) => TaskItem.fromJob({
              'id': j['id'],
              'supabase_parcel_id': j['supabase_parcel_id'],
              'status': j['status'],
              'local_inspection_id': j['local_inspection_id'],
              'scheduled_date': j['scheduled_date'],
              'deadline_date': j['deadline_date'],
              'is_self_scheduled': j['is_self_scheduled'] == 1,
              'supabase_zoning_applications': {
                'applicant_name': j['applicant_name'],
                'barangay': j['barangay'],
                'reference_number': j['reference_number'],
                'application_type': j['application_type'],
              }
            })).toList();
      }
    } catch (e) {
      debugPrint('Error loading tasks: $e');
    }

    final upcoming = tasks.where((t) => t.category != 'Completed').toList()
      ..sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));

    if (mounted) {
      setState(() {
        _upcomingTasks = upcoming.take(4).toList(); 
        _isLoadingTasks = false;
      });
    }
  }

  Future<void> _loadRecentActivity() async {
    setState(() => _isLoadingActivity = true);
    try {
      final activity = await SupabaseService.fetchRecentActivity(limit: 5);
      final unread = await SupabaseService.fetchUnreadActivityCount();
      if (mounted) {
        setState(() {
          _recentActivity = activity;
          _unreadCount = unread;
          _isLoadingActivity = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading activity: $e');
      if (mounted) setState(() => _isLoadingActivity = false);
    }
  }

  static const _monthNames = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

  String _formatScheduledDate(String isoDate) {
    try {
      final d = DateTime.parse(isoDate);
      return '${_monthNames[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) {
      return isoDate;
    }
  }

  String _timeAgo(String? isoTimestamp) {
    if (isoTimestamp == null) return '';
    try {
      final then = DateTime.parse(isoTimestamp).toLocal();
      final diff = DateTime.now().difference(then);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return _formatScheduledDate(then.toIso8601String());
    } catch (_) {
      return '';
    }
  }

  Map<String, dynamic> _eventTheme(String eventType) {
    switch (eventType) {
      case 'inspection_completed':
        return {'icon': Icons.check_circle_rounded, 'color': InsightTheme.green};
      case 'rework_started':
        return {'icon': Icons.refresh_rounded, 'color': InsightTheme.orange};
      case 'photos_synced':
        return {'icon': Icons.cloud_done_rounded, 'color': InsightTheme.blue1};
      case 'gps_confirmed':
        return {'icon': Icons.gps_fixed_rounded, 'color': InsightTheme.blueInk};
      default:
        return {'icon': Icons.notifications_rounded, 'color': InsightTheme.ink3};
    }
  }

  String _getInitials(String name) {
    if (name.trim().isEmpty) return "JR";
    List<String> parts = name.trim().split(' ');
    if (parts.length > 1) return "${parts[0][0]}${parts[1][0]}".toUpperCase();
    return parts[0].substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  String _getFirstNameInitialAndLastName(String name) {
    if (name.trim().isEmpty) return "J. Reyes";
    List<String> parts = name.trim().split(' ');
    if (parts.length > 1) return "${parts[0][0]}. ${parts[1]}";
    return name;
  }

  String _formatShortId(String fullId) {
    if (fullId.length > 8) return fullId.substring(0, 8).toUpperCase();
    return fullId.toUpperCase();
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
              // 1. TOP BAR
              // ----------------------------------------------------
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileEditScreen(profile: widget.profile)));
                      },
                      child: Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: InsightTheme.surface,
                          border: Border.all(color: InsightTheme.line, width: 1.5),
                          boxShadow: const [BoxShadow(color: Color(0x05000000), blurRadius: 10, offset: Offset(0, 4))],
                        ),
                        alignment: Alignment.center,
                        child: Text(initials, style: InsightTheme.poppins(14, w: FontWeight.w700, c: InsightTheme.blue2)),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('WELCOME BACK,', style: InsightTheme.jetBrains(10, w: FontWeight.w700, c: InsightTheme.blue1, ls: 1.5)),
                          const SizedBox(height: 1),
                          Text(displayName, style: InsightTheme.poppins(18, w: FontWeight.w700, ls: -0.5, c: InsightTheme.ink)),
                        ],
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.only(right: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _isOnline ? InsightTheme.green.withOpacity(0.12) : InsightTheme.red.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 6, height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isOnline ? InsightTheme.green : InsightTheme.red,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(_isOnline ? 'ONLINE' : 'OFFLINE', 
                               style: InsightTheme.jetBrains(10, w: FontWeight.w700, c: _isOnline ? InsightTheme.green : InsightTheme.red)),
                        ],
                      ),
                    ),
                    _NotificationBtn(
                      hasUnread: _unreadCount > 0,
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
                        // Notifications screen marks things read on its own
                        // timeline — resync the badge once the inspector
                        // backs out of it instead of leaving it stale.
                        _loadRecentActivity();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 36), 

              // ----------------------------------------------------
              // 2. ACTIVE ASSIGNMENTS
              // ----------------------------------------------------
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _SectionLabel(
                  title: "ACTIVE ASSIGNMENTS",
                  trailing: GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TasksScreen(profile: widget.profile))),
                    child: Text('See All', style: InsightTheme.inter(11, w: FontWeight.w600, c: InsightTheme.blue1)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              SizedBox(
                height: 170, // Shrunk to perfectly match the removed bottom elements 
                child: _isLoadingTasks
                    ? const Center(child: CircularProgressIndicator())
                    : _upcomingTasks.isEmpty
                        ? Center(
                            child: Text(
                              'No active assignments.',
                              style: InsightTheme.inter(12, c: InsightTheme.ink2),
                            ),
                          )
                        : PageView.builder(
                            controller: _pageController,
                            itemCount: _upcomingTasks.length,
                            clipBehavior: Clip.none,
                            onPageChanged: (index) => setState(() => _currentCardIndex = index),
                            itemBuilder: (context, index) {
                              return AnimatedBuilder(
                                animation: _pageController,
                                builder: (context, child) {
                                  double value = 1.0;
                                  if (_pageController.position.haveDimensions) {
                                    value = _pageController.page! - index;
                                    value = (1 - (value.abs() * 0.1)).clamp(0.9, 1.0);
                                  } else {
                                    value = (index == 0) ? 1.0 : 0.9;
                                  }
                                  
                                  return Center(
                                    child: SizedBox(
                                      height: Curves.easeOut.transform(value) * 170,
                                      width: double.infinity,
                                      child: child,
                                    ),
                                  );
                                },
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 6),
                                  child: _ActiveAssignmentCard(
                                    inspectionId: _formatShortId(_upcomingTasks[index].id),
                                    date: _upcomingTasks[index].scheduledDate.isNotEmpty
                                        ? _formatScheduledDate(_upcomingTasks[index].scheduledDate)
                                        : _upcomingTasks[index].category,
                                    location: _upcomingTasks[index].location,
                                    description: _upcomingTasks[index].applicationType?.isNotEmpty == true
                                        ? _upcomingTasks[index].applicationType!
                                        : _upcomingTasks[index].landUseClass,
                                    onTap: () => Navigator.of(context).push(
                                        MaterialPageRoute(builder: (_) => ParcelDetailScreen(task: _upcomingTasks[index]))),
                                  ),
                                ),
                              );
                            },
                          ),
              ),
              const SizedBox(height: 24),

              if (_upcomingTasks.length > 1)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_upcomingTasks.length, (index) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      height: 6,
                      width: _currentCardIndex == index ? 24 : 8,
                      decoration: BoxDecoration(
                        color: _currentCardIndex == index ? InsightTheme.blue1 : InsightTheme.ink3.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    );
                  }),
                ),
              const SizedBox(height: 36),

              // ----------------------------------------------------
              // 3. QUICK ACTIONS
              // ----------------------------------------------------
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: _SectionLabel(title: "QUICK ACTIONS"),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _QuickActionBtn(icon: Icons.play_arrow_rounded, label: 'Inspect', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TasksScreen(profile: widget.profile)))),
                    _QuickActionBtn(icon: Icons.calendar_month_rounded, label: 'Schedule', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TasksScreen(profile: widget.profile)))),
                    _QuickActionBtn(icon: Icons.cloud_sync_rounded, label: 'Sync', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => UpdatesScreen(profile: widget.profile)))),
                    _QuickActionBtn(icon: Icons.badge_rounded, label: 'Profile', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(profile: widget.profile)))),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // ----------------------------------------------------
              // 4. RECENT ACTIVITY
              // ----------------------------------------------------
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: _SectionLabel(title: "RECENT ACTIVITY"),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _isLoadingActivity
                    ? const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: CircularProgressIndicator()))
                    : _recentActivity.isEmpty
                        ? Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('No recent activity yet.', style: InsightTheme.inter(12, c: InsightTheme.ink2)))
                        : Stack(
                            children: [
                              Positioned(
                                left: 19, top: 12, bottom: 16,
                                child: Container(width: 2, color: InsightTheme.ink3.withOpacity(0.15)),
                              ),
                              Column(
                                children: List.generate(_recentActivity.length, (i) {
                                  final themeInfo = _eventTheme(_recentActivity[i]['event_type'] as String? ?? '');
                                  return _TimelineActivityTile(
                                    icon: themeInfo['icon'],
                                    color: themeInfo['color'],
                                    title: _recentActivity[i]['title'] as String? ?? 'Update',
                                    subtitle: _recentActivity[i]['subtitle'] as String? ?? '',
                                    time: _timeAgo(_recentActivity[i]['occurred_at'] as String?),
                                  );
                                }),
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
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.8)),
                  boxShadow: const [
                    BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 2)),
                    BoxShadow(color: Color(0x15000000), blurRadius: 24, offset: Offset(0, 12)),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _BottomNavItem(icon: Icons.home_rounded, label: 'Home', isActive: _currentNavIndex == 0, onTap: () => setState(() => _currentNavIndex = 0)),
                    _BottomNavItem(icon: Icons.assignment_outlined, label: 'Tasks', isActive: _currentNavIndex == 1, onTap: () { setState(() => _currentNavIndex = 1); Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => TasksScreen(profile: widget.profile))); }),
                    _BottomNavItem(icon: Icons.sync_rounded, label: 'Updates', isActive: _currentNavIndex == 3, onTap: () { setState(() => _currentNavIndex = 3); Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => UpdatesScreen(profile: widget.profile))); }),
                    _BottomNavItem(icon: Icons.person_outline_rounded, label: 'Profile', isActive: _currentNavIndex == 4, onTap: () { setState(() => _currentNavIndex = 4); Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ProfileScreen(profile: widget.profile))); }),
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
  final bool hasUnread;
  const _NotificationBtn({required this.onTap, this.hasUnread = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: InsightTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: InsightTheme.line, width: 1.5),
          boxShadow: const [BoxShadow(color: Color(0x05000000), blurRadius: 10, offset: Offset(0, 4))],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.notifications_outlined, color: InsightTheme.ink, size: 22),
            if (hasUnread)
              Positioned(
                right: 10, top: 10,
                child: Container(
                  width: 7, height: 7,
                  decoration: BoxDecoration(color: InsightTheme.red, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
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
        Text(title, style: InsightTheme.poppins(12, w: FontWeight.w700, ls: 1.2, c: InsightTheme.ink3)),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _ActiveAssignmentCard extends StatelessWidget {
  final String inspectionId;
  final String date;
  final String location;
  final String description;
  final VoidCallback onTap;

  const _ActiveAssignmentCard({
    required this.inspectionId, required this.date, required this.location, required this.description, required this.onTap
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [InsightTheme.blue1, InsightTheme.blue2],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(color: InsightTheme.blue1.withOpacity(0.35), blurRadius: 16, offset: const Offset(0, 8))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            // Top Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('INSPECTION ID: $inspectionId', style: InsightTheme.jetBrains(11, w: FontWeight.w700, c: Colors.white, ls: 0.5)),
                ),
                Text(date, style: InsightTheme.jetBrains(11, w: FontWeight.w600, c: Colors.white.withOpacity(0.8))),
              ],
            ),
            const SizedBox(height: 18), 
            
            // Site Data
            Text('INSPECTION SITE', style: InsightTheme.inter(10, w: FontWeight.w600, c: Colors.white.withOpacity(0.6), h: 1.0)),
            const SizedBox(height: 4),
            Text(location, style: InsightTheme.poppins(15, w: FontWeight.w700, c: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
            
            const SizedBox(height: 12), 
            
            // Type Data with right-aligned Arrow
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('APPLICATION TYPE', style: InsightTheme.inter(10, w: FontWeight.w600, c: Colors.white.withOpacity(0.6), h: 1.0)),
                      const SizedBox(height: 4),
                      Text(description, style: InsightTheme.inter(12, w: FontWeight.w500, c: Colors.white.withOpacity(0.95)), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Container(
                  width: 26, height: 26,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8), 
                  ),
                  child: const Icon(Icons.chevron_right_rounded, size: 16, color: InsightTheme.blue2),
                )
              ],
            )
          ],
        ),
      ),
    );
  }
}

class _QuickActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionBtn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60, height: 60,
            decoration: BoxDecoration(
              color: InsightTheme.surface,
              borderRadius: BorderRadius.circular(18), 
              border: Border.all(color: InsightTheme.line, width: 1.5),
              boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 12, offset: Offset(0, 6))],
            ),
            child: Center(child: Icon(icon, size: 26, color: InsightTheme.blueInk)),
          ),
          const SizedBox(height: 8),
          Text(label, style: InsightTheme.inter(11, w: FontWeight.w600, c: InsightTheme.ink2)),
        ],
      ),
    );
  }
}

class _TimelineActivityTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String time;

  const _TimelineActivityTile({
    required this.icon, required this.color, required this.title, required this.subtitle, required this.time,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline Node (Glowing Dot)
          Container(
            width: 40,
            alignment: Alignment.topCenter,
            padding: const EdgeInsets.only(top: 4),
            decoration: const BoxDecoration(color: InsightTheme.bg), 
            child: Container(
              width: 28, height: 28, 
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
                border: Border.all(color: color.withOpacity(0.3), width: 1.5),
              ),
              child: Icon(icon, size: 14, color: color), 
            ),
          ),
          const SizedBox(width: 12),
          
          // Activity Card Content
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), 
              decoration: BoxDecoration(
                color: InsightTheme.surface,
                borderRadius: BorderRadius.circular(12), 
                border: Border.all(color: InsightTheme.line, width: 1.5),
                boxShadow: const [BoxShadow(color: Color(0x05000000), blurRadius: 8, offset: Offset(0, 2))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(title, style: InsightTheme.poppins(12, w: FontWeight.w600, c: InsightTheme.ink), maxLines: 1, overflow: TextOverflow.ellipsis), 
                      ),
                      Text(time, style: InsightTheme.jetBrains(10, w: FontWeight.w600, c: InsightTheme.ink3)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: InsightTheme.inter(11, w: FontWeight.w500, c: InsightTheme.ink2)), 
                ],
              ),
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
        duration: const Duration(milliseconds: 250),
        padding: EdgeInsets.symmetric(horizontal: isActive ? 16 : 12, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? InsightTheme.blue1 : Colors.transparent, 
          borderRadius: BorderRadius.circular(16),
          boxShadow: isActive ? [BoxShadow(color: InsightTheme.blue1.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))] : [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isActive ? Colors.white : InsightTheme.ink3, size: 22),
            const SizedBox(height: 4),
            Text(label, style: InsightTheme.inter(10, w: FontWeight.w700, c: isActive ? Colors.white : InsightTheme.ink3)),
          ],
        ),
      ),
    );
  }
}