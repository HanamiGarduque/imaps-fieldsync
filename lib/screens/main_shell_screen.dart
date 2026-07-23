import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../widgets/insight_bottom_nav.dart';
import '../widgets/sync_progress_banner.dart';
import 'home_dashboard_screen.dart';
import 'tasks_screen.dart';
import 'updates_screen.dart';
import 'profile_screen.dart';

/// Single shell for the 4 primary tabs with fluid tab transitions
/// and per-visit spring entrance animations.
class MainShellScreen extends StatefulWidget {
  final UserProfile profile;
  final int initialIndex;

  const MainShellScreen({
    super.key,
    required this.profile,
    this.initialIndex = 0,
  });

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  late int _currentIndex;

  static const _items = [
    InsightNavItem(icon: Icons.home_rounded, label: 'Home'),
    InsightNavItem(icon: Icons.assignment_outlined, label: 'Tasks'),
    InsightNavItem(icon: Icons.sync_rounded, label: 'Updates'),
    InsightNavItem(icon: Icons.person_outline_rounded, label: 'Profile'),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  Widget _buildPage(int index) {
    switch (index) {
      case 0:
        return HomeDashboardScreen(
          key: ValueKey('home_tab_$index'),
          profile: widget.profile,
          showBottomNav: false,
        );
      case 1:
        return TasksScreen(
          key: ValueKey('tasks_tab_$index'),
          profile: widget.profile,
          showBottomNav: false,
        );
      case 2:
        return UpdatesScreen(
          key: ValueKey('updates_tab_$index'),
          profile: widget.profile,
          showBottomNav: false,
        );
      case 3:
        return ProfileScreen(
          key: ValueKey('profile_tab_$index'),
          profile: widget.profile,
          showBottomNav: false,
        );
      default:
        return HomeDashboardScreen(
          key: ValueKey('home_tab_$index'),
          profile: widget.profile,
          showBottomNav: false,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Column(
        children: [
          // Phase 5: compact sync progress banner — shown on Home/Tasks/
          // Profile tabs. Hidden on the Updates tab (index 2) since the
          // Sync Center already renders its own detailed progress line;
          // showing both at once would be a redundant duplicate.
          if (_currentIndex != 2) const SyncProgressBanner(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 450),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.05),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: _buildPage(_currentIndex),
            ),
          ),
        ],
      ),

      bottomNavigationBar: InsightBottomNav(
        currentIndex: _currentIndex,
        items: _items,
        onTap: (i) {
          if (i == _currentIndex) return;
          setState(() => _currentIndex = i);
        },
      ),
    );
  }
}