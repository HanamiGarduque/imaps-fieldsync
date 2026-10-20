import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState;
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/auth_failure.dart';
import '../services/supabase_service.dart';
import '../theme/insight_theme.dart';
import '../../modules/auth_startup/services/auto_lock_controller.dart';
import '../../modules/auth_startup/services/secure_prefs_service.dart';
import '../widgets/sensitive_screen.dart';
import '../services/sync_outbox_service.dart';
import '../services/db_helper.dart';
import '../services/report_submission_service.dart';
import '../widgets/insight_bottom_nav.dart';
import '../widgets/sync_progress_banner.dart';
import '../widgets/offline_banner.dart';
import '../widgets/quick_actions_sheet.dart';
import '../../modules/auth_startup/screens/app_resume_lock_screen.dart';
import '../../modules/auth_startup/screens/splash_screen.dart' show LoginScreen;
import '../../modules/analytics_dashboard/screens/home_dashboard_screen.dart';
import '../../modules/tasks/screens/tasks_screen.dart';
import 'package:imaps_fieldsync/modules/offline_sync/screens/updates_screen.dart';
import '../../modules/profile_settings/screens/profile_screen.dart';
import '../../modules/profile_settings/screens/profile_edit_screen.dart';
import '../../modules/profile_settings/screens/notifications_screen.dart';
import '../../modules/inspection/screens/site_map_preview_screen.dart';
import '../../modules/inspection/screens/compass_preview_screen.dart';

/// Single shell for the 4 primary tabs with fluid tab transitions
/// and per-visit spring entrance animations.
class MainShellScreen extends StatefulWidget {
  final UserProfile profile;
  final int initialIndex;

  final bool offlineSession;

  const MainShellScreen({
    super.key,
    required this.profile,
    this.initialIndex = 0,
    this.offlineSession = false,
  });

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  late int _currentIndex;
  late UserProfile _currentProfile;

  // ── Network connectivity state ──────────────────────────────────────────
  late bool _isOnline;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<AuthState>? _authSubscription;
  bool _sessionRedirecting = false;

  void _checkSessionAccess() {
    if (!mounted || _sessionRedirecting) return;
    final refused = AuthService.profileRefusedOwner.value == _inspectorId;
    if (AuthService.isLoggedIn &&
        DBHelper.currentInspectorId == _inspectorId && !refused) {
      return;
    }
    _sessionRedirecting = true;
    AutoLockController.instance.stop();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen(initialFailure: refused
          ? AuthFailure.profileUnavailable : AuthFailure.sessionRestoreFailed)),
      (_) => false,
    );
  }

  // ── Quick Actions sheet ───────────────────────────────────────────────
  bool _quickActionsOpen = false;
  bool _profileAnalyticsRequested = false;

  // ── Tasks-tab badge ──────────────────────────────────────────────────
  // The dot means NEW / UNSEEN TASK ASSIGNMENT — nothing else.
  //
  // Historically this was `!_tasksVisitedThisSession`: a session-only flag with
  // no relationship to any task, so the dot appeared on every cold start even
  // with nothing assigned and stayed until the inspector happened to open
  // Tasks. It now compares the CURRENT awaiting assignments against the
  // persisted set this inspector has already opened, so an old pending task
  // cannot resurrect the dot and a genuinely new one always raises it.
  //
  // Acknowledgement is stored per authenticated user id in SecurePrefsService,
  // which is why Inspector A's seen state can never suppress Inspector B's
  // badge on a shared device. No SQLite and no Supabase schema is involved.
  Set<String> _awaitingTaskIds = const {};
  Set<String> _acknowledgedTaskIds = const {};

  /// The authenticated user id used to namespace acknowledgement. This is the
  /// Supabase auth UUID that `profiles.id` carries — the same identity
  /// LocalDataGuardService uses for local-data ownership.
  String get _inspectorId => _currentProfile.id;

  /// Rebuilds the badge inputs from the existing local cache plus the persisted
  /// acknowledgement set. No schema change, no network call.
  Future<void> _refreshTaskAttention() async {
    Set<String> awaiting;
    try {
      final rows = await DBHelper.getCachedJobs();
      awaiting = rows
          .where((r) => r['id'] != null)
          .where((r) => kAwaitingTaskStatuses.contains(r['status']))
          .map((r) => r['id'].toString())
          .toSet();
    } catch (_) {
      // A cache read failure must never strand the dot in a visible state.
      awaiting = const {};
    }

    var acknowledged = const <String>{};
    try {
      acknowledged = await SecurePrefsService.getAcknowledgedTaskIds(
        _inspectorId,
      );
    } catch (_) {
      // Unreadable preference → treat everything as unseen rather than
      // silently hiding a genuinely new assignment.
    }

    if (!mounted) return;
    // Drop acknowledgements for work that is no longer awaiting (completed,
    // reassigned, removed) so the stored set cannot grow forever. Trivial, and
    // scoped to this inspector only.
    final stale = acknowledged.difference(awaiting);
    if (stale.isNotEmpty) {
      acknowledged = acknowledged.difference(stale);
      try {
        await SecurePrefsService.setAcknowledgedTaskIds(
          _inspectorId,
          acknowledged,
          pruneTo: awaiting,
        );
      } catch (_) {
        // Non-fatal: the badge is already correct from the in-memory set.
      }
    }

    setState(() {
      _awaitingTaskIds = awaiting;
      _acknowledgedTaskIds = acknowledged;
    });
  }

  /// Opening the Tasks tab is the acknowledgement gesture: everything awaiting
  /// right now has been seen. Persisted per inspector, so it survives restart.
  Future<void> _acknowledgeAwaitingTasks() async {
    final ids = _awaitingTaskIds;
    if (ids.isEmpty) return;
    _acknowledgedTaskIds = {..._acknowledgedTaskIds, ...ids};
    try {
      await SecurePrefsService.acknowledgeTasks(_inspectorId, ids);
    } catch (_) {
      // Non-fatal: the in-memory state already clears the dot for this
      // session; it simply may reappear after a restart.
    }
  }

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
    _authSubscription = SupabaseService.client.auth.onAuthStateChange
        .listen((_) => _checkSessionAccess(), onError: (Object _) => _checkSessionAccess());
    AuthService.profileRefusedOwner.addListener(_checkSessionAccess);
    _isOnline = !widget.offlineSession;
    _refreshTaskAttention();
    _checkInitialConnectivity();
    // Reports & Support queue: recover any interrupted send, then let the
    // queue try once. Fire-and-forget so app startup never waits on the
    // network, and completely separate from the inspection SyncOutbox.
    unawaited(_serviceReportsQueue());
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      if (mounted) {
        final online = results.any((r) => r != ConnectivityResult.none);
        if (_isOnline != online) {
          setState(() {
            _isOnline = online;
          });
          if (online) unawaited(_serviceReportsQueue());
        }
      }
    });
    _startAutoLock();
  }

  Future<void> _checkInitialConnectivity() async {
    final online = await AuthService.hasConnectivity();
    if (mounted && _isOnline != online) {
      setState(() => _isOnline = online);
    }
  }

  /// A row persisted as `sending` means the previous process died mid-request,
  /// so its outcome is unknowable: it becomes `delivery_unknown` and is never
  /// resent automatically. Only then are genuinely retryable rows attempted,
  /// serially.
  Future<void> _serviceReportsQueue() async {
    try {
      await ReportQueueService.recoverInterruptedSends();
      await ReportQueueService.processPending();
    } catch (e) {
      // Reporting retry must never take the shell down and must never loop.
      // The row simply stays in its current transport state.
      debugPrint('[REPORTS] queue service skipped: $e');
    }
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _authSubscription?.cancel();
    AuthService.profileRefusedOwner.removeListener(_checkSessionAccess);
    AutoLockController.instance.stop();
    super.dispose();
  }

  Future<void> _startAutoLock() async {
    final policy = await AutoLockPolicy.load();
    if (!mounted) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    AutoLockController.instance.start(
      policy: policy,
      onLockRequested: _presentAutoLock,
      backgrounded: lifecycle == AppLifecycleState.paused ||
          lifecycle == AppLifecycleState.hidden,
    );
  }

  Future<void> _presentAutoLock() async {
    if (!mounted) return;
    // Let the current lifecycle callback/frame finish before pushing.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AppResumeLockScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  void _toggleQuickActions() {
    setState(() => _quickActionsOpen = !_quickActionsOpen);
  }

  void _closeQuickActions() {
    if (_quickActionsOpen) setState(() => _quickActionsOpen = false);
  }

  void _openTab(int index) {
    setState(() => _currentIndex = index);
    // Tasks/Home repopulate `local_jobs` on refresh, so re-read the badge
    // inputs whenever the inspector moves through the tab that owns that data.
    if (index == 1) {
      _acknowledgeAwaitingTasks();
      _refreshTaskAttention();
    }
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
    return Scaffold(
        extendBody: true,
        body: Stack(
        children: [
          // Decorative ambient mesh-blur circles were removed from here.
          // They were two large blurred blue discs sitting behind every page in
          // the shell, which made the background treatment inconsistent with the
          // clean neutral pages and read as a glow halo rather than content.
          // Each page already paints its own opaque `InsightTheme.bg`
          // Scaffold background, so nothing is left showing through and no new
          // background token was needed — the pages simply share one plain
          // surface now.

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
                    // Real-time "Offline mode" banner shown whenever the device
                    // has no network connectivity. Automatically hidden when
                    // connectivity returns to reclaim vertical space.
                    if (!_isOnline) const OfflineBanner(),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 450),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        layoutBuilder: (current, previous) => Stack(
                          alignment: Alignment.center,
                          children: [
                            for (final child in previous)
                              SensitiveScreenVisibility(
                                visible: false,
                                child: child,
                              ),
                            ?current,
                          ],
                        ),
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
                        // One shared rule for all four tabs: the banner above
                        // already cleared the status bar, so the page beneath
                        // must not clear it a second time. Online there is no
                        // banner and the page keeps its own single inset.
                        child: PageUnderOfflineBanner(
                          isOnline: _isOnline,
                          child: _buildPage(_currentIndex),
                        ),
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
          QuickActionsOverlay(
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
                          fillAvailableSpace: true,
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
              // NEW / UNSEEN assignment only — never a bare session flag and
              // never a pending count. An assignment already opened stays
              // acknowledged across restarts.
              showBadge: shouldShowTasksAttentionDot(
                awaitingTaskIds: _awaitingTaskIds,
                acknowledgedTaskIds: _acknowledgedTaskIds,
              ),
            ),
            InsightNavItem(
              icon: _items[2].icon,
              label: _items[2].label,
              showBadge: syncProgress != null,
              // Amber is reserved for "needs attention"; running progress is blue.
              badgeColor: InsightTheme.blue1,
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
    );
  }
}
