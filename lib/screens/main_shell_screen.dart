import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../widgets/insight_bottom_nav.dart';
import 'home_dashboard_screen.dart';
import 'tasks_screen.dart';
import 'updates_screen.dart';
import 'profile_screen.dart';

/// Single persistent shell for the 4 primary tabs. Replaces the old
/// pattern where every tab screen called Navigator.pushReplacement on
/// every tap — that destroyed and rebuilt the entire page each time
/// (visible flash/lag, lost scroll position, refetched data).
///
/// IndexedStack keeps all 4 pages mounted simultaneously; switching tabs
/// is just an index change, so state, scroll position, and in-flight
/// data are preserved instantly with zero rebuild.
class MainShellScreen extends StatefulWidget {
  final UserProfile profile;
  const MainShellScreen({super.key, required this.profile});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _currentIndex = 0;

  static const _items = [
    InsightNavItem(icon: Icons.home_rounded, label: 'Home'),
    InsightNavItem(icon: Icons.assignment_outlined, label: 'Tasks'),
    InsightNavItem(icon: Icons.sync_rounded, label: 'Updates'),
    InsightNavItem(icon: Icons.person_outline_rounded, label: 'Profile'),
  ];

  late final List<Widget> _pages = [
    HomeDashboardScreen(profile: widget.profile, showBottomNav: false),
    TasksScreen(profile: widget.profile, showBottomNav: false),
    UpdatesScreen(profile: widget.profile, showBottomNav: false),
    ProfileScreen(profile: widget.profile, showBottomNav: false),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _currentIndex, children: _pages),
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