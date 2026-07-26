import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/biometric_service.dart';
import '../services/secure_prefs_service.dart';
import '../widgets/insight_bottom_nav.dart';
import '../widgets/sync_progress_banner.dart';
import 'app_resume_lock_screen.dart';
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

class _MainShellScreenState extends State<MainShellScreen> with WidgetsBindingObserver {
  late int _currentIndex;

  // ── App-resume lock (see AUTH_SECURITY_MASTER_DOC.md §5d) ───────────────
  // _pausedAt is set the moment the app leaves the foreground and cleared
  // the next time it resumes — it only needs to survive within this one
  // process lifetime, since a full app kill already goes through the
  // splash-screen/session-check flow separately (see splash_screen.dart).
  DateTime? _pausedAt;
  bool _lockShowing = false;

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
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Deliberately NOT tracking AppLifecycleState.inactive here. On Android,
    // showing the native biometric prompt itself (BiometricPrompt) briefly
    // puts the app into `inactive` — the same transient state used for
    // things like a notification shade pull or an incoming call — even
    // though the user never actually left the app. Treating `inactive` as
    // "backgrounded" meant every biometric prompt anywhere in the app
    // (including Security Settings' "Test/Re-verify Sensor") looked
    // indistinguishable from a real app-switch, which re-triggered this
    // very lock screen right after using biometric for anything —
    // including the lock screen's own auto-prompt, compounding into a
    // loop. `paused`/`hidden` are the states that actually mean "the app
    // is no longer visible," which is the only thing that should count.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _pausedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      _maybeShowResumeLock();
    }
  }

  Future<void> _maybeShowResumeLock() async {
    final pausedAt = _pausedAt;
    _pausedAt = null;
    if (pausedAt == null || _lockShowing) return;

    final requireOnOpen = await SecurePrefsService.getBioRequireOnOpen();
    if (!requireOnOpen) return;

    final enrolled = await BiometricService.isEnrolled();
    if (!enrolled) return; // nothing to gate with if biometric isn't set up

    final mins = await SecurePrefsService.getBioAutoLockMins();
    // Design decision (AUTH_SECURITY_MASTER_DOC.md §5d): the stored value
    // is -1=immediately, 0=no grace period configured/"never" (its
    // original storage comment), or 1/5/10 minutes of grace. With the
    // master switch (bio_require_on_open) already on, an ambiguous/unset
    // grace value defaults to the *strictest* behavior (lock immediately)
    // rather than the most permissive one — so both -1 and 0 lock right
    // away here; only 1/5/10 get an actual grace window.
    final elapsed = DateTime.now().difference(pausedAt);
    final shouldLock = mins <= 0 || elapsed >= Duration(minutes: mins);
    if (!shouldLock || !mounted) return;

    _lockShowing = true;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AppResumeLockScreen(),
        fullscreenDialog: true,
      ),
    );
    _lockShowing = false;
  }

  Widget _buildPage(int index) {
    switch (index) {
      case 0:
        return HomeDashboardScreen(
          key: ValueKey('home_tab_$index'),
          profile: widget.profile,
        );
      case 1:
        return TasksScreen(
          key: ValueKey('tasks_tab_$index'),
          profile: widget.profile,
        );
      case 2:
        return UpdatesScreen(
          key: ValueKey('updates_tab_$index'),
          profile: widget.profile,
        );
      case 3:
        return ProfileScreen(
          key: ValueKey('profile_tab_$index'),
          profile: widget.profile,
        );
      default:
        return HomeDashboardScreen(
          key: ValueKey('home_tab_$index'),
          profile: widget.profile,
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