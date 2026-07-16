import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/user_profile.dart';
import 'parcel_detail_screen.dart'; // Preserved routing
import 'home_dashboard_screen.dart';
import 'updates_screen.dart';
import 'profile_screen.dart';

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
  
  static const Color green = Color(0xFF12A150);
  static const Color greenTint = Color(0xFFE3F8EC);
  static const Color greenInk = Color(0xFF0D7A3C);
  
  static const Color line = Color(0x12141628); // ~rgba(20,22,40,0.07)
  
  static TextStyle poppins(double size, {FontWeight w = FontWeight.w600, Color? c, double? h, double? ls}) => 
      GoogleFonts.poppins(fontSize: size, fontWeight: w, color: c ?? ink, height: h ?? 1.2, letterSpacing: ls);
      
  static TextStyle inter(double size, {FontWeight w = FontWeight.w400, Color? c, double? h}) => 
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: c ?? ink2, height: h ?? 1.5);
}

/// ==================================================================
/// MODEL (100% Original - Preserved)
/// ==================================================================
class TaskItem {
  final String name;
  final String location;
  final String parcels; // Used as time/subtitle
  final String status;
  final String inspectionNo;

  TaskItem({
    required this.name,
    required this.location,
    required this.parcels,
    required this.status,
    required this.inspectionNo,
  });
}

/// ==================================================================
/// TASKS SCREEN (Matches Prototype Screen 5)
/// ==================================================================
class TasksScreen extends StatefulWidget {
  final UserProfile profile;

  const TasksScreen({super.key, required this.profile});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  int _currentNavIndex = 1; // 1 = Tasks
  int _currentTabIndex = 1; // Default to 'Ongoing 1' as per prototype

  @override
  Widget build(BuildContext context) {
    // Exact Content Mapped to the Original Model to match visuals
    final heroTask = TaskItem(
      name: 'Applicant 4',
      location: 'Warehouse 7',
      parcels: 'Industrial Park · Checklist in progress',
      status: 'Ongoing · 60%',
      inspectionNo: 'FI-004',
    );

    final gridTasks = [
      TaskItem(
        name: 'Applicant 1',
        location: 'Lot 22-B, Maligaya',
        parcels: '1:30 PM',
        status: 'Pending',
        inspectionNo: 'FI-001',
      ),
      TaskItem(
        name: 'Applicant 2',
        location: 'Unit 4, Rizal Complex',
        parcels: '3:00 PM',
        status: 'Pending',
        inspectionNo: 'FI-002',
      ),
      TaskItem(
        name: 'Applicant 3',
        location: '45 Acacia St.',
        parcels: 'Tomorrow, 9 AM',
        status: 'Scheduled',
        inspectionNo: 'FI-003',
      ),
      TaskItem(
        name: 'Applicant 5',
        location: '12 Mabini Ave.',
        parcels: 'Yesterday',
        status: 'Done',
        inspectionNo: 'FI-005',
      ),
    ];

    return Scaffold(
      backgroundColor: InsightTheme.bg,
      extendBody: true, // Content scrolls behind bottom nav
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ----------------------------------------------------
              // 1. TOP BAR (Title & Filter Icon)
              // ----------------------------------------------------
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'My Tasks',
                    style: InsightTheme.poppins(20, w: FontWeight.w700),
                  ),
                  _TopIconBtn(icon: Icons.filter_list_rounded, onTap: () {}),
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
                    _TabPill(text: "Pending 3", isActive: _currentTabIndex == 0, onTap: () => setState(() => _currentTabIndex = 0)),
                    const SizedBox(width: 8),
                    _TabPill(text: "Ongoing 1", isActive: _currentTabIndex == 1, onTap: () => setState(() => _currentTabIndex = 1)),
                    const SizedBox(width: 8),
                    _TabPill(text: "Scheduled 4", isActive: _currentTabIndex == 2, onTap: () => setState(() => _currentTabIndex = 2)),
                    const SizedBox(width: 8),
                    _TabPill(text: "Completed 12", isActive: _currentTabIndex == 3, onTap: () => setState(() => _currentTabIndex = 3)),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ----------------------------------------------------
              // 3. ONGOING HERO CARD
              // ----------------------------------------------------
              _HeroTaskCard(
                task: heroTask,
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.push(context, MaterialPageRoute(builder: (_) => ParcelDetailScreen(task: heroTask)));
                },
              ),
              const SizedBox(height: 16),

              // ----------------------------------------------------
              // 4. TASK GRID
              // ----------------------------------------------------
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.15,
                ),
                itemCount: gridTasks.length,
                itemBuilder: (context, index) {
                  return _GridTaskCard(
                    task: gridTasks[index],
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.push(context, MaterialPageRoute(builder: (_) => ParcelDetailScreen(task: gridTasks[index])));
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),

      // ----------------------------------------------------
      // 5. FLOATING BOTTOM NAVIGATION (Glassmorphic)
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
                      onTap: () { 
                        setState(() => _currentNavIndex = 0); 
                        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HomeDashboardScreen(profile: widget.profile))); 
                      }
                    ),
                    _BottomNavItem(
                      icon: Icons.assignment_outlined, label: 'Tasks', isActive: _currentNavIndex == 1, 
                      onTap: () => setState(() => _currentNavIndex = 1)
                    ),
                    _BottomNavItem(
                      icon: Icons.sync_rounded, label: 'Updates', isActive: _currentNavIndex == 3, 
                      onTap: () { 
                        setState(() => _currentNavIndex = 3); 
                        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const UpdatesScreen())); 
                      }
                    ),
                    _BottomNavItem(
                      icon: Icons.person_outline_rounded, label: 'Profile', isActive: _currentNavIndex == 4, 
                      onTap: () { 
                        setState(() => _currentNavIndex = 4); 
                        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ProfileScreen(profile: widget.profile))); 
                      }
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

class _TopIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _TopIconBtn({required this.icon, required this.onTap});

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
        child: Icon(icon, color: InsightTheme.ink, size: 22),
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

class _HeroTaskCard extends StatelessWidget {
  final TaskItem task;
  final VoidCallback onTap;

  const _HeroTaskCard({required this.task, required this.onTap});

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
            // Decorative background circle
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
                        task.status, 
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
                      child: const Icon(Icons.bookmark_outline_rounded, color: Colors.white, size: 18),
                    )
                  ],
                ),
                const SizedBox(height: 36),
                Text(task.location, style: InsightTheme.poppins(18, w: FontWeight.w700, c: Colors.white)),
                const SizedBox(height: 6),
                Text(task.parcels, style: InsightTheme.inter(12, c: Colors.white.withOpacity(0.85))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GridTaskCard extends StatelessWidget {
  final TaskItem task;
  final VoidCallback onTap;

  const _GridTaskCard({required this.task, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bool isDone = task.status == 'Done';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: InsightTheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: InsightTheme.line),
          boxShadow: const [BoxShadow(color: InsightTheme.line, blurRadius: 2, offset: Offset(0, 1))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Icon Container
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: isDone ? InsightTheme.greenTint : InsightTheme.blueTint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.bookmark_outline_rounded, 
                    size: 16, 
                    color: isDone ? InsightTheme.greenInk : InsightTheme.blueInk
                  ),
                ),
                // Status Pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isDone ? InsightTheme.greenTint : InsightTheme.surface2,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    task.status,
                    style: InsightTheme.inter(
                      10, 
                      w: FontWeight.w600, 
                      c: isDone ? InsightTheme.greenInk : InsightTheme.ink2
                    ),
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.location, 
                  style: InsightTheme.inter(13, w: FontWeight.w600, c: InsightTheme.ink),
                  maxLines: 1, 
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  task.parcels, 
                  style: InsightTheme.inter(11.5, c: InsightTheme.ink2),
                  maxLines: 1, 
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
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