import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../../modules/auth_startup/services/biometric_service.dart';
import '../../modules/auth_startup/services/secure_prefs_service.dart';
import '../services/sync_outbox_service.dart';
import '../widgets/insight_bottom_nav.dart';
import '../widgets/sync_progress_banner.dart';
import '../widgets/quick_actions_sheet.dart';
import '../../modules/auth_startup/screens/app_resume_lock_screen.dart';
import '../../modules/analytics_dashboard/screens/home_dashboard_screen.dart';
import '../../modules/tasks/screens/tasks_screen.dart';
import 'package:imaps_fieldsync/modules/offline_sync/screens/updates_screen.dart';
import '../../modules/profile_settings/screens/profile_screen.dart';
import '../../modules/profile_settings/screens/profile_edit_screen.dart';
import '../../modules/profile_settings/screens/notifications_screen.dart';
import '../../modules/inspection/screens/site_map_preview_screen.dart';
import '../../modules/inspection/screens/compass_preview_screen.dart';
import '../theme/insight_theme.dart';

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
  late UserProfile _currentProfile;

  // ── App-resume lock (see AUTH_SECURITY_MASTER_DOC.md §5d) ───────────────
  // _pausedAt is set the moment the app leaves the foreground and cleared
  // the next time it resumes — it only needs to survive within this one
  // process lifetime, since a full app kill already goes through the
  // splash-screen/session-check flow separately (see splash_screen.dart).
  DateTime? _pausedAt;
  bool _lockShowing = false;
  Timer? _idleLockTimer;
  int _idleTimerGeneration = 0;

  // ── Quick Actions sheet ───────────────────────────────────────────────
  bool _quickActionsOpen = false;
  bool _profileAnalyticsRequested = false;

  // ── Tasks-tab badge ──────────────────────────────────────────────────
  // ASSUMPTION (flagged to Master — no existing "new since last viewed"
  // signal exists for tasks; see roadmap open item): this is a session-only
  // proxy, not a persisted "unseen task" concept. The dot shows until the
  // inspector opens the Tasks tab once this session, then clears and stays
  // cleared until the app restarts. A real "new insert" signal would need
  // a small data-layer addition — flagged separately, not done here.
  bool _tasksVisitedThisSession = false;

  static const _items = [
    InsightNavItem(icon: Icons.home_rounded, label: 'Home'),
    InsightNavItem(icon: Icons.assignment_outlined, label: 'Tasks'),
    InsightNavItem(icon: Icons.sync_rounded, label: 'Sync'),
    InsightNavItem(icon: Icons.person_outline_rounded, label: 'Profile'),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _currentProfile = widget.profile;
    _tasksVisitedThisSession = _currentIndex == 1;
    WidgetsBinding.instance.addObserver(this);
    _resetIdleLockTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _idleLockTimer?.cancel();
    super.dispose();
  }

  void _resetIdleLockTimer([PointerEvent? _]) {
    _idleTimerGeneration++;
    _idleLockTimer?.cancel();
    _idleLockTimer = null;
    if (_lockShowing) return;
    _scheduleIdleLockTimer(_idleTimerGeneration);
  }

  Future<void> _scheduleIdleLockTimer(int generation) async {
    final requireOnOpen = await SecurePrefsService.getBioRequireOnOpen();
    final mins = await SecurePrefsService.getBioAutoLockMins();
    if (!mounted || generation != _idleTimerGeneration || _lockShowing || !requireOnOpen || mins <= 0) {
      return;
    }

    _idleLockTimer = Timer(Duration(minutes: mins), _showIdleLock);
  }

  Future<void> _showIdleLock() async {
    if (!mounted || _lockShowing) {
      return;
    }
    final requireOnOpen = await SecurePrefsService.getBioRequireOnOpen();
    final mins = await SecurePrefsService.getBioAutoLockMins();
    final enrolled = await BiometricService.isEnrolled();
    final confirmed = await BiometricService.isConfirmed();
    if (!mounted || !requireOnOpen || mins <= 0 || !enrolled || !confirmed) {
      return;
    }

    _lockShowing = true;
    _idleLockTimer?.cancel();
    _idleLockTimer = null;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AppResumeLockScreen(),
        fullscreenDialog: true,
      ),
    );
    _lockShowing = false;
    _resetIdleLockTimer();
  }

  void _toggleQuickActions() {
    setState(() => _quickActionsOpen = !_quickActionsOpen);
  }

  void _closeQuickActions() {
    if (_quickActionsOpen) setState(() => _quickActionsOpen = false);
  }

  void _openTab(int index) {
    if (index == 1) _tasksVisitedThisSession = true;
    setState(() => _currentIndex = index);
  }

  Future<void> _openProfileEdit() async {
    final result = await Navigator.of(context).push<UserProfile?>(
      MaterialPageRoute(builder: (_) => ProfileEditScreen(profile: _currentProfile)),
    );
    if (result != null && mounted) {
      setState(() => _currentProfile = result);
    }
  }

  List<QuickAction> _buildQuickActions() {
    // Exact 5 actions and order from the approved reference. "Site map"
    // and "Compass" intentionally open the new standalone preview screens
    // (not the task-bound wizard steps) — see
    // site_map_preview_screen.dart / compass_preview_screen.dart.
    return [
      QuickAction(
        icon: Icons.map_outlined,
        title: 'Map',
        subtitle: 'Navigate your current location',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SiteMapPreviewScreen()),
        ),
      ),
      QuickAction(
        icon: Icons.explore_outlined,
        title: 'Compass',
        subtitle: 'Determine your orientation',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const StandaloneCompassScreen()),
        ),
      ),
      QuickAction(
        icon: Icons.bar_chart_rounded,
        title: 'Analytics overview',
        subtitle: 'Track performance metrics',
        onTap: () {
          setState(() => _profileAnalyticsRequested = true);
          _openTab(3);
        },
      ),
      QuickAction(
        icon: Icons.history_rounded,
        title: 'Sync history',
        subtitle: 'View synchronization activity',
        // Deep-links straight into the Notifications screen's "Sync" mode
        // (initialMode: 1) — per Master's correction, this belongs on the
        // Notifications page's Synchronization History section, not the
        // separate Sync Center (UpdatesScreen).
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NotificationsScreen(initialMode: 1)),
        ),
      ),
      QuickAction(
        icon: Icons.edit_outlined,
        title: 'Edit profile',
        subtitle: 'Update your personal details',
        onTap: () => _openProfileEdit(),
      ),
    ];
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
      _idleLockTimer?.cancel();
      _idleLockTimer = null;
      _pausedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      _maybeShowResumeLock();
      _resetIdleLockTimer();
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

    // New request: don't gate behind an unconfirmed biometric — someone
    // who just enrolled but hasn't done their one confirmation password
    // login yet would otherwise get locked out with no way through (this
    // lock screen has no password field by design). See
    // BiometricService.isConfirmed() / splash_screen.dart's cold-start gate
    // for the matching check.
    final confirmed = await BiometricService.isConfirmed();
    if (!confirmed) return;

    final mins = await SecurePrefsService.getBioAutoLockMins();
    // The stored values are -1=immediately, 0=never, or 1/5/10 minutes.
    final elapsed = DateTime.now().difference(pausedAt);
    final shouldLock = SecurePrefsService.shouldLockAfterElapsed(
      minutes: mins,
      elapsed: elapsed,
    );
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
          profile: _currentProfile,
          onNavigateToTab: _openTab,
          onProfileUpdated: (profile) => setState(() => _currentProfile = profile),
        );
      case 1:
        return TasksScreen(
          key: ValueKey('tasks_tab_$index'),
          profile: _currentProfile,
        );
      case 2:
        return UpdatesScreen(
          key: ValueKey('updates_tab_$index'),
          profile: _currentProfile,
        );
      case 3:
        return ProfileScreen(
          key: ValueKey('profile_tab_$index'),
          profile: _currentProfile,
          initialAnalyticsOpen: _profileAnalyticsRequested,
          onAnalyticsHandled: () => setState(() => _profileAnalyticsRequested = false),
          onProfileUpdated: (profile) => setState(() => _currentProfile = profile),
        );
      default:
        return HomeDashboardScreen(
          key: ValueKey('home_tab_$index'),
          profile: _currentProfile,
          onNavigateToTab: _openTab,
          onProfileUpdated: (profile) => setState(() => _currentProfile = profile),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _resetIdleLockTimer,
      child: Scaffold(
        extendBody: true,
        body: Stack(
        children: [
          // ── Ambient mesh blur background ──────────────────────────────
          // Same blurred-blob pattern already established in
          // site_map_screen.dart / gps_verification_screen.dart (blue,
          // two soft circles) — reused here behind the whole shell for
          // consistency rather than inventing a new background treatment.
          Positioned(
            top: -80, right: -80,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: Container(
                decoration: BoxDecoration(shape: BoxShape.circle, color: InsightTheme.blue1.withValues(alpha: 0.16)),
              ),
            ),
          ),
          Positioned(
            bottom: -100, left: -100,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: Container(
                width: 260, height: 260,
                decoration: BoxDecoration(shape: BoxShape.circle, color: InsightTheme.blue2.withValues(alpha: 0.10)),
              ),
            ),
          ),

          // ── Main content — blurs + scales down slightly while Quick
          // Actions is open (the reference's "Main Content Focus Effect"),
          // visibly act on.
          AnimatedScale(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            scale: _quickActionsOpen ? 0.95 : 1.0,
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              tween: Tween(begin: 0, end: _quickActionsOpen ? 6.0 : 0.0),
              builder: (context, blurSigma, child) {
                return ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                  child: child,
                );
              },
              child: Column(
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
            ),
          ),

          // ── Backdrop — actual gaussian blur (not just a dim scrim) over
          // whatever's behind the Quick Actions sheet, per the reference.
          // Ignored entirely when closed so it never intercepts normal
          // taps on the page underneath.
          IgnorePointer(
            ignoring: !_quickActionsOpen,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity: _quickActionsOpen ? 1 : 0,
              child: GestureDetector(
                onTap: _closeQuickActions,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                  child: Container(color: Colors.black.withValues(alpha: 0.22)),
                ),
              ),
            ),
          ),

          // Quick Actions sheet — floats just above the nav row, matching
          // the approved reference position/shape (explicit theme-lock
          // override for this one element — see quick_actions_sheet.dart).
          // Mounted/unmounted with the open state so its internal
          // staggered row animation replays every time it's opened.
          Positioned(
            left: 16,
            right: 16,
            bottom: 190, // raised — the trigger now sits above the rail,
                         // not beside it, so the sheet needs more
                         // clearance to avoid overlapping the trigger.
            child: IgnorePointer(
              ignoring: !_quickActionsOpen,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                offset: _quickActionsOpen ? Offset.zero : const Offset(0, 0.08),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  opacity: _quickActionsOpen ? 1 : 0,
                  child: _quickActionsOpen
                      ? QuickActionsSheet(
                          key: const ValueKey('quick_actions_open'),
                          actions: _buildQuickActions(),
                          onClose: _closeQuickActions,
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ],
        ),

        bottomNavigationBar: ValueListenableBuilder<SyncProgress?>(
        valueListenable: SyncOutboxService.progress,
        builder: (context, syncProgress, _) {
          final items = [
            _items[0],
            InsightNavItem(
              icon: _items[1].icon,
              label: _items[1].label,
              showBadge: !_tasksVisitedThisSession,
            ),
            InsightNavItem(
              icon: _items[2].icon,
              label: _items[2].label,
              showBadge: syncProgress != null,
            ),
            _items[3],
          ];
          return InsightBottomNav(
            currentIndex: _currentIndex,
            items: items,
            isQuickActionsOpen: _quickActionsOpen,
            onQuickActionsTap: _toggleQuickActions,
            onTap: (i) {
              _closeQuickActions();
              if (i == _currentIndex) return;
              _openTab(i);
            },
          );
        },
        ),
      ),
    );
  }
}