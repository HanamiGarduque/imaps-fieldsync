import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/user_profile.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'parcel_detail_screen.dart';

/// ==================================================================
/// AWARD-WINNING DESIGN TOKENS
/// ==================================================================
class AppColors {
  // Premium Gradient Header (Deep Indigo to Vibrant Purple)
  static const headerDark = Color(0xFF0F172A);
  static const headerAccent = Color(0xFF4F46E5);
  
  // Clean Workspace Background
  static const bgLight = Color(0xFFF8FAFC);
  static const surface = Colors.white;
  
  // Status Colors (Soft & Accessible)
  static const statusAssigned = Color(0xFFF59E0B);
  static const statusAssignedBg = Color(0xFFFEF3C7);
  static const statusProgress = Color(0xFF10B981);
  static const statusProgressBg = Color(0xFFD1FAE5);
  
  // Typography Hierarchy
  static const textDark = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF475569);
  static const textMuted = Color(0xFF94A3B8);
  static const divider = Color(0xFFE2E8F0);
}

class AppText {
  // Plus Jakarta Sans provides an incredibly premium, modern tech aesthetic
  static TextStyle display(double size, {FontWeight w = FontWeight.w700, Color? c, double? ls}) => 
      GoogleFonts.plusJakartaSans(fontSize: size, fontWeight: w, color: c ?? Colors.white, letterSpacing: ls ?? -0.5);
      
  static TextStyle body(double size, {FontWeight w = FontWeight.w400, Color? c}) => 
      GoogleFonts.plusJakartaSans(fontSize: size, fontWeight: w, color: c ?? AppColors.textSecondary);
      
  static TextStyle label(double size, {FontWeight w = FontWeight.w700, Color? c, double? ls}) => 
      GoogleFonts.plusJakartaSans(fontSize: size, fontWeight: w, color: c ?? AppColors.textMuted, letterSpacing: ls ?? 1.2);
}

/// ==================================================================
/// MODELS (Preserved exactly)
/// ==================================================================
class TaskItem {
  final String name;
  final String location;
  final String parcels;
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
/// PREMIUM TASKS SCREEN
/// ==================================================================
class TasksScreen extends StatelessWidget {
  final UserProfile profile;

  const TasksScreen({super.key, required this.profile});

  Future<void> _handleLogout(BuildContext context) async {
    HapticFeedback.mediumImpact();
    await AuthService.signOut();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 100% Original Dummy Data Preserved
    final assigned = [
      TaskItem(
        name: 'Maria Santos',
        location: 'San Roque',
        parcels: '2 parcels',
        status: 'Assigned',
        inspectionNo: 'FI-20260608001',
      ),
      TaskItem(
        name: 'Ralph Ramos',
        location: 'Malaya',
        parcels: '2 parcels',
        status: 'Assigned',
        inspectionNo: 'FI-20260608002',
      ),
    ];

    final inProgress = [
      TaskItem(
        name: 'Juan Rodriguez',
        location: 'Alupay',
        parcels: '3 parcels',
        status: 'In Progress',
        inspectionNo: 'FI-20260608003',
      ),
    ];

    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: Column(
        children: [
          // 1. FLAWLESS OVERLAP ARCHITECTURE
          // This Stack guarantees the search bar perfectly overlaps the boundary
          // without pushing into the text below it.
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              // The Premium Gradient Header
              Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.headerDark, AppColors.headerAccent],
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(32),
                    bottomRight: Radius.circular(32),
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    // 56px bottom padding gives the header breathing room
                    // ABOVE where the search bar will cut across it.
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 56),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top Navigation Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 8, height: 8,
                                  decoration: BoxDecoration(
                                    color: Colors.greenAccent, 
                                    shape: BoxShape.circle,
                                    boxShadow: [BoxShadow(color: Colors.greenAccent.withValues(alpha: 0.5), blurRadius: 8)],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text('iMAPS-FieldSync', style: AppText.body(13, c: Colors.white, w: FontWeight.w600)),
                              ],
                            ),
                            Row(
                              children: [
                                // Sleek Glass Pill
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                                  ),
                                  child: Text('Offline Mode', style: AppText.body(11, c: Colors.white, w: FontWeight.w600)),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.logout_rounded, color: Colors.white70, size: 22),
                                  onPressed: () => _handleLogout(context),
                                  constraints: const BoxConstraints(),
                                  padding: EdgeInsets.zero,
                                ),
                              ],
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 32),
                        
                        Text('My Tasks', style: AppText.display(32)),
                        const SizedBox(height: 4),
                        Text(
                          'Welcome back, ${profile.fullName}',
                          style: AppText.body(15, c: Colors.white.withValues(alpha: 0.7)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              
              // Floating Search Bar positioned exactly halfway over the edge
              Positioned(
                bottom: -28, // Exactly half of the 56px container height
                left: 24,
                right: 24,
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.headerDark.withValues(alpha: 0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: TextField(
                    style: AppText.body(15, c: AppColors.textDark, w: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: 'Search Inspection No. or Applicant...',
                      hintStyle: AppText.body(14, c: AppColors.textMuted),
                      prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 18),
                    ),
                  ),
                ),
              ),
            ],
          ),
          
          // Space to clear the bottom half of the search bar + top padding for the list
          const SizedBox(height: 48),

          // 2. Beautifully Structured Task List
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              physics: const BouncingScrollPhysics(),
              children: [
                _StaggeredReveal(
                  delay: 100,
                  child: Text('ASSIGNED', style: AppText.label(12, c: AppColors.headerAccent)),
                ),
                const SizedBox(height: 12),
                ...assigned.map((task) => _StaggeredReveal(delay: 200, child: _PremiumTaskCard(task: task))),
                
                const SizedBox(height: 28),
                
                _StaggeredReveal(
                  delay: 300,
                  child: Text('IN PROGRESS', style: AppText.label(12, c: AppColors.headerAccent)),
                ),
                const SizedBox(height: 12),
                ...inProgress.map((task) => _StaggeredReveal(delay: 400, child: _PremiumTaskCard(task: task))),
                
                const SizedBox(height: 40), // Safe scroll space at bottom
              ],
            ),
          ),
        ],
      ),
      
      // 3. Premium Bottom Navigation
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          boxShadow: [
            BoxShadow(color: AppColors.headerDark.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, -4)),
          ],
        ),
        child: SafeArea(
          top: false,
          child: BottomNavigationBar(
            currentIndex: 0,
            backgroundColor: AppColors.surface,
            selectedItemColor: AppColors.headerAccent,
            unselectedItemColor: AppColors.textMuted,
            selectedLabelStyle: AppText.label(10, c: AppColors.headerAccent, ls: 0.5),
            unselectedLabelStyle: AppText.label(10, c: AppColors.textMuted, ls: 0.5),
            type: BottomNavigationBarType.fixed,
            elevation: 0,
            items: const [
              BottomNavigationBarItem(icon: Padding(padding: EdgeInsets.only(bottom: 6, top: 8), child: Icon(Icons.space_dashboard_rounded, size: 22)), label: 'TASKS'),
              BottomNavigationBarItem(icon: Padding(padding: EdgeInsets.only(bottom: 6, top: 8), child: Icon(Icons.grid_view_rounded, size: 22)), label: 'SERVICES'),
              BottomNavigationBarItem(icon: Padding(padding: EdgeInsets.only(bottom: 6, top: 8), child: Icon(Icons.notifications_none_rounded, size: 22)), label: 'ALERTS'),
              BottomNavigationBarItem(icon: Padding(padding: EdgeInsets.only(bottom: 6, top: 8), child: Icon(Icons.person_outline_rounded, size: 22)), label: 'PROFILE'),
            ],
          ),
        ),
      ),
    );
  }
}

/// UI/UX Award-Winning Card Component
class _PremiumTaskCard extends StatelessWidget {
  final TaskItem task;
  const _PremiumTaskCard({required this.task});

  Color get _statusColor => task.status == 'Assigned' ? AppColors.statusAssigned : AppColors.statusProgress;
  Color get _statusBg => task.status == 'Assigned' ? AppColors.statusAssignedBg : AppColors.statusProgressBg;

  @override
  Widget build(BuildContext context) {
    // Generate initials for the avatar
    final initials = task.name.trim().split(' ').map((e) => e[0]).take(2).join('');

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ParcelDetailScreen(task: task)),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.divider.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: AppColors.headerDark.withValues(alpha: 0.03), 
              blurRadius: 10, 
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Modern Circular Avatar
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.headerAccent.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        initials,
                        style: AppText.body(16, c: AppColors.headerAccent, w: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  
                  // Name and Location
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.name,
                          style: AppText.display(16, c: AppColors.textDark, ls: 0),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.location_on_rounded, color: AppColors.textMuted, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              task.location,
                              style: AppText.body(13, c: AppColors.textSecondary, w: FontWeight.w500),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  // Status Pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _statusBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      task.status.toUpperCase(),
                      style: AppText.label(10, c: _statusColor, ls: 0.5),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 20),
              
              // Bottom Data Tags
              Row(
                children: [
                  _DataTag(icon: Icons.layers_outlined, text: task.parcels),
                  const SizedBox(width: 12),
                  _DataTag(icon: Icons.tag_rounded, text: task.inspectionNo),
                  const Spacer(),
                  // Premium Action Indicator
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.bgLight,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: const Icon(Icons.arrow_forward_rounded, color: AppColors.headerAccent, size: 16),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DataTag extends StatelessWidget {
  final IconData icon;
  final String text;
  const _DataTag({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.bgLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 14),
          const SizedBox(width: 6),
          Text(text, style: AppText.body(12, c: AppColors.textSecondary, w: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// ==================================================================
/// ANIMATIONS
/// ==================================================================
class _StaggeredReveal extends StatefulWidget {
  final Widget child;
  final int delay;
  const _StaggeredReveal({required this.child, required this.delay});
  @override
  State<_StaggeredReveal> createState() => _StaggeredRevealState();
}

class _StaggeredRevealState extends State<_StaggeredReveal> {
  bool _visible = false;
  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) setState(() => _visible = true);
    });
  }
  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 600),
      opacity: _visible ? 1.0 : 0.0,
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _visible ? 0 : 15, 0),
        child: widget.child,
      ),
    );
  }
}