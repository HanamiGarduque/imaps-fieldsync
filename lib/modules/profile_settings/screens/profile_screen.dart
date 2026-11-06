import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection, ScrollCacheExtent;
import '../../../core/widgets/sensitive_screen.dart';
import 'package:flutter/services.dart';

import '../../../core/models/user_profile.dart';
import '../models/dashboard_stats.dart';
import '../models/analytics_activity_range.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/db_helper.dart';
import '../../interactive_guide/guide_host.dart';
import '../../interactive_guide/guide_preferences.dart';
import '../../interactive_guide/guide_read_only_data.dart';
import '../../interactive_guide/guide_targets.dart';
import '../../../core/services/supabase_service.dart';
import '../../auth_startup/screens/splash_screen.dart' show LoginScreen;
import '../../auth_startup/services/auto_lock_controller.dart';
import '../../auth_startup/services/screen_protection_service.dart';
import '../../tasks/screens/tasks_screen.dart' show TaskItem;
import 'profile_edit_screen.dart';
import 'about_insight_screen.dart';
import '../../auth_startup/screens/security_settings_screen.dart';
import 'policy_document_screen.dart';
import 'policy_documents.dart';
import 'reports_support_screen.dart';
import 'help_faq_screen.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/profile_action_sections.dart';
export '../widgets/profile_action_sections.dart' show ProfileIdentityCard;
import '../../../core/widgets/motion/spring_entrance.dart';
import '../../../core/widgets/imaps_loading_indicator.dart';
import '../../../core/widgets/insight_bottom_nav.dart'
    show kInsightBottomNavReserve;
import '../../../core/services/app_info_service.dart';

import '../../../core/theme/insight_theme.dart';
import '../../../core/layout/responsive_layout.dart';

/// ==================================================================
/// SCREEN 17 — PROFILE
/// ==================================================================
class ProfileScreen extends StatefulWidget {
  final UserProfile profile;
  final GuideReadOnlyData? walkthrough;
  final bool initialAnalyticsOpen;
  final VoidCallback? onAnalyticsHandled;
  final ValueChanged<UserProfile>? onProfileUpdated;
  final Future<void> Function(GuideReplayRequest)? onReplayGuide;

  const ProfileScreen({
    super.key,
    required this.profile,
    this.walkthrough,
    this.initialAnalyticsOpen = false,
    this.onAnalyticsHandled,
    this.onProfileUpdated,
    this.onReplayGuide,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin, SpringEntrance {
  late UserProfile _currentProfile;

  InspectorDashboardStats _stats = InspectorDashboardStats.empty();
  bool _isLoadingStats = true;
  bool _hasStatsError = false;

  // Analytics section state — tab index (0=Bars, 1=Activity, 2=Gauge, 3=Sectors)
  // and timeframe toggle (week/month). Replaces the old PageView approach
  // with a single card containing an internal segmented tab bar, matching
  // the HTML reference design exactly.
  int _analyticsTabIndex = 0;
  bool _analyticsIsWeek = true;
  final GlobalKey _analyticsSectionKey = GlobalKey();
  bool _identityCompact = false;
  bool _helpOpening = false;

  @override
  void initState() {
    super.initState();
    _currentProfile = widget.profile;
    _refreshProfileFromServer();
    _loadStats();
    if (widget.initialAnalyticsOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _analyticsSectionKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            alignment: 0.1,
          );
        }
        widget.onAnalyticsHandled?.call();
      });
    }
  }

  @override
  void dispose() {
    disposeSpringEntrance();
    super.dispose();
  }

  /// Safety net: widget.profile is whatever the caller had in memory when
  /// this screen was pushed, which can be a beat stale (e.g. right after
  /// login, or if a prior screen held onto an older copy). This re-fetches
  /// the row that's actually in Supabase right now so the header never
  /// shows outdated name/role/avatar without needing an app reload.
  Future<void> _refreshProfileFromServer() async {
    if (widget.walkthrough != null) return;
    final fresh = await SupabaseService.fetchMyProfile();
    if (fresh != null && mounted) {
      final refreshedProfile = UserProfile.fromMap(fresh);
      setState(() => _currentProfile = refreshedProfile);
      widget.onProfileUpdated?.call(refreshedProfile);
    }
  }

  Future<void> _loadStats() async {
    final walkthrough = widget.walkthrough;
    if (walkthrough != null) {
      _stats = InspectorDashboardStats.fromTasks(walkthrough.jobs.map(TaskItem.fromCachedJob).toList());
      _isLoadingStats = false;
      _hasStatsError = walkthrough.unavailable.contains(GuideDataSection.tasks);
      return;
    }
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
    if (widget.walkthrough != null) return;
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
      widget.onProfileUpdated?.call(result);
    }
  }

  Future<void> _openHelp() async {
    if (widget.walkthrough != null) return;
    if (_helpOpening) return;
    _helpOpening = true;
    final owner = _currentProfile.id;
    final route = ModalRoute.of(context);
    final protection = ScreenProtectionScope.maybeOf(context) ?? ScreenProtectionService.instance;
    bool sameOwner() => mounted && _currentProfile.id == owner &&
      AuthService.isLoggedIn && DBHelper.currentInspectorId == owner &&
      SupabaseService.client.auth.currentUser?.id == owner &&
      AuthService.profileRefusedOwner.value != owner;
    bool canOpen() => sameOwner() && route?.isCurrent == true &&
      !AutoLockController.instance.isLocked && protection.foreground &&
      !protection.mustObscure && !protection.nativeFailure &&
      (WidgetsBinding.instance.lifecycleState == null || WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);
    try {
      GuideRecord? record;
      try {
        record = await GuidePreferences().read(owner);
      } catch (_) {
        // Unreadable guide metadata still permits manual replay.
      }
      HelpFaqSnapshot? origin;
      var reopenGuide = false;
      var language = record?.language ?? GuideLanguage.english;
      while (canOpen() && !protection.transitioning && !protection.hasPopup) {
        if (!mounted) return;
        final request = await Navigator.of(context).push<HelpGuideReplay>(MaterialPageRoute(
          builder: (_) => HelpFaqScreen(origin: origin, reopenGuide: reopenGuide,
            initialGuideLanguage: language, hasPreviousOffer: record != null || reopenGuide)));
        // A popped Help route can return before native protection acknowledges
        // the shell. Its readiness queue must retain the first Start/Replay.
        if (!sameOwner() || route?.isCurrent != true || request == null || widget.onReplayGuide == null) return;
        await widget.onReplayGuide!(request);
        if (!canOpen()) return;
        origin = request.origin;
        language = request.language;
        reopenGuide = true;
      }
    } finally {
      _helpOpening = false;
    }
  }

  /// Shows the "Log out" confirmation modal. Required per the destructive-
  /// action rule (specific-labeled buttons, no bare Yes/No) — sign out
  /// previously fired with zero confirmation.
  Future<void> _confirmSignOut(BuildContext context) async {
    if (widget.walkthrough != null) return;
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        // Declared here (not inside StatefulBuilder's builder) so it
        // survives across setDialogState() calls for the life of this
        // dialog instance.
        bool isLoggingOut = false;

        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Dialog(
              backgroundColor: InsightTheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Log out',
                      style: InsightTheme.urbanist(
                        18,
                        w: FontWeight.w700,
                        c: InsightTheme.ink,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "You'll need to sign in again to continue your inspections.",
                      style: InsightTheme.inter(
                        13.5,
                        c: InsightTheme.ink2,
                        h: 1.4,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: isLoggingOut
                              ? null
                              : () => Navigator.pop(dialogContext),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(60, 44),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                          ),
                          child: Text(
                            'Cancel',
                            style: InsightTheme.inter(
                              14,
                              w: FontWeight.w600,
                              c: InsightTheme.ink2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: isLoggingOut
                              ? null
                              : () async {
                                  setDialogState(() => isLoggingOut = true);
                                  await _performSignOut(dialogContext);
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color.fromARGB(
                              255,
                              234,
                              12,
                              12,
                            ),
                            disabledBackgroundColor: const Color.fromARGB(
                              255,
                              234,
                              12,
                              12,
                            ).withValues(alpha: 0.7),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            minimumSize: const Size(90, 44),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: isLoggingOut
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  'Log out',
                                  style: InsightTheme.inter(
                                    14,
                                    w: FontWeight.w700,
                                    c: Colors.white,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// The actual sign-out flow, triggered once the modal's "Log out" button
  /// has already swapped into its loading state. Business logic here is
  /// untouched from the original _handleSignOut — only the trigger point
  /// (confirmation + loading UI) changed.
  Future<void> _performSignOut(BuildContext dialogContext) async {
    if (widget.walkthrough != null) return;
    HapticFeedback.mediumImpact();

    // Audit log must fire BEFORE signOut() — log_security_event is a
    // SECURITY DEFINER RPC keyed off auth.uid(), so it silently no-ops
    // once there's no authenticated session to attribute the event to.
    //
    // Both are awaited, and navigation happens after: previously this
    // navigated to LoginScreen *before* signOut() completed, leaving a
    // window where AuthService.isLoggedIn could still read true and the
    // biometric button could let someone back in without ever actually
    // checking they were still authenticated. Note: We still preserve
    // biometric enrollment settings on the device so that when the user
    // logs back in, their Security & Protection settings remain active —
    // only the visible session itself needs to be gone before Login shows.
    // AuthService.signOut() doesn't actually call Supabase's real signOut()
    // when biometric is enrolled+confirmed — it just flags the session as
    // hidden (see AUTH_SECURITY_MASTER_DOC.md §14). The real session is
    // never touched, so AuthService.clearSoftLogout() (used by the
    // biometric button) has nothing to restore over the network — it's
    // just un-hiding it.
    try {
      await SupabaseService.logSecurityEvent(
        eventType: 'logout',
        severity: 'info',
      );
    } catch (e) {
      debugPrint('[SIGNOUT] logSecurityEvent error: $e');
    }
    try {
      await AuthService.signOut();
    } catch (e) {
      debugPrint('[SIGNOUT] AuthService.signOut error: $e');
    }

    // Close the confirmation modal first (explicit, root navigator) so it
    // can never linger behind the login screen regardless of navigator
    // nesting elsewhere in the app.
    if (dialogContext.mounted) {
      Navigator.of(dialogContext, rootNavigator: true).pop();
    }

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    final initials = UserProfile.avatarInitials(_currentProfile.fullName);
    final displayName = UserProfile.displayFullName(_currentProfile.fullName);

    final currentUser = SupabaseService.client.auth.currentUser;
    final userEmail = currentUser?.email ?? 'No email found';
    final positionLabel = _currentProfile.isAdmin
        ? 'Administrator'
        : 'Zoning Officer I';

    return SensitiveScreen(
      child: Scaffold(
      backgroundColor: InsightTheme.bg,
      extendBody: true,
      body: Stack(
        children: [
          // The two decorative blurred blue circles that used to sit here were
          // removed so Profile matches the other main pages' plain neutral
          // background. They were page-background ornament only — no blue was
          // removed from any legitimate control on this screen.
          SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final gutter =
                    constraints.maxHeight < InsightBreakpoints.shortHeight
                    ? 4.0
                    : 12.0;
                final usableHeight =
                    constraints.maxHeight -
                    MediaQuery.paddingOf(context).bottom;
                final identityMaxHeight = math.min(
                  constraints.maxHeight,
                  math.max(96.0, (usableHeight - gutter * 2) / 2),
                );
                final identity = GuideTarget(id: 'profile_identity', child: ProfileIdentityCard(
                  compact: _identityCompact,
                  avatarUrl: widget.walkthrough == null ? _currentProfile.avatarUrl : null,
                  initials: initials,
                  displayName: displayName,
                  positionLabel: positionLabel,
                  userEmail: userEmail,
                  onEditTap: _openEditScreen,
                ));
                return RefreshIndicator(
                  color: InsightTheme.blue1,
                  onRefresh: () async {
                    await Future.wait([
                      _refreshProfileFromServer(),
                      _loadStats(),
                    ]);
                  },
                  child: NotificationListener<UserScrollNotification>(
                    onNotification: (notification) {
                      if (notification.depth == 0 &&
                          notification.direction != ScrollDirection.idle) {
                        final compact =
                            notification.direction == ScrollDirection.reverse;
                        if (compact != _identityCompact) {
                          setState(() => _identityCompact = compact);
                        }
                      }
                      return false;
                    },
                    child: CustomScrollView(
                      // ponytail: bounded cache for this short passive document;
                      // explicit section navigation if it grows past 12k dp.
                      scrollCacheExtent: widget.walkthrough == null ? null : const ScrollCacheExtent.pixels(12000),
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      slivers: [
                        PinnedHeaderSliver(
                          child: Container(
                            color: InsightTheme.bg,
                            padding: EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: gutter,
                            ),
                            child: ConstrainedContent.wide(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight: identityMaxHeight,
                                ),
                                child: MediaQuery.disableAnimationsOf(context)
                                    ? identity
                                    : AnimatedSize(
                                        alignment: Alignment.topCenter,
                                        duration: const Duration(
                                          milliseconds: 240,
                                        ),
                                        curve: Curves.easeOutCubic,
                                        child: identity,
                                      ),
                              ),
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            20,
                            4,
                            20,
                            math.max(
                              kInsightBottomNavReserve,
                              MediaQuery.paddingOf(context).bottom,
                            ),
                          ),
                          sliver: SliverList(
                            delegate: SliverChildListDelegate([
                              // 1. QUICK STATS ROW (Tasks Today/Pending, Completed Inspections)
                              // IntrinsicHeight guarantees both cards match the
                              // taller one's height regardless of label wrapping.
                              GuideTarget(id: 'profile_summary', child: IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: SpringSlide(
                                        animation: springFor(1),
                                        beginOffset: const Offset(0, 34),
                                        child: _buildStatCard(
                                          'Pending / Ongoing',
                                          _isLoadingStats
                                              ? '—'
                                              : '${_stats.tasksTodayOrPendingCount}',
                                          Icons.access_time_rounded,
                                          InsightTheme.surface2,
                                          InsightTheme.blue1,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: SpringSlide(
                                        animation: springFor(2),
                                        beginOffset: const Offset(0, 34),
                                        child: _buildStatCard(
                                          'Completed Inspections',
                                          _isLoadingStats
                                              ? '—'
                                              : '${_stats.completedCount}',
                                          Icons.check_circle_outline_rounded,
                                          InsightTheme.blueTint,
                                          InsightTheme.blueInk,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )),

                              const SizedBox(height: 16),

                              // 2. PERFORMANCE ANALYTICS — single card with
                              // internal segmented tab bar (Bars / Activity /
                              // Gauge / Sectors) + Week/Month toggle.
                              // Matches HTML reference design: no PageView swipe,
                              // no separate section label, no dot indicators.
                              if (_hasStatsError)
                                _dashboardErrorCard()
                              else if (_isLoadingStats)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 40),
                                  child: Center(
                                    child: ImapsLoadingIndicator(size: 50),
                                  ),
                                )
                              else
                                KeyedSubtree(
                                  key: _analyticsSectionKey,
                                  child: _analyticsCard(),
                                ),

                              const SizedBox(height: 20),

                              // 3. GROUPED ACTION CARDS — split from one long list
                              // into related groups, with Sign out separated by
                              // whitespace rather than sharing a divider with
                              // neutral settings rows (destructive actions get
                              // visual distance, not just a color change).
                              SpringSlide(
                                animation: springFor(5),
                                beginOffset: const Offset(0, 30),
                                child: ProfileActionSections(
                                  appVersion: AppInfoService.fullVersionString,
                                  onSecurity: widget.walkthrough != null ? null : () => Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => SecuritySettingsScreen(profile: _currentProfile))),
                                  onHelp: _openHelp,
                                  onSupport: widget.walkthrough != null ? null : () => Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => const ReportsSupportScreen())),
                                  onTerms: widget.walkthrough != null ? null : () => Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => const PolicyDocumentScreen(document: termsAndConditionsDocument))),
                                  onPrivacy: widget.walkthrough != null ? null : () => Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => const PolicyDocumentScreen(document: privacyNoticeDocument))),
                                  onStorage: widget.walkthrough != null ? null : () => Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => const PolicyDocumentScreen(document: cookieStoragePolicyDocument))),
                                  onAbout: widget.walkthrough != null ? null : () => Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => const AboutInsightScreen())),
                                  onLogout: () => _confirmSignOut(context),
                                ),
                              ),
                            ]),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),

      // Bottom navigation now lives solely in MainShellScreen (the app
      // shell). This screen no longer renders its own nav bar — see
      // NAVIGATION_REFACTOR.md for why the duplicate, per-page nav bar
      // was removed.
      ),
    );
  }

  // WIDGET: Performance Analytics — single card matching HTML reference.
  // Header: title + subtitle left, Week/Month toggle right.
  // Below: segmented tab bar (Bars / Activity / Gauge / Sectors).
  // Chart body: AnimatedSwitcher fades between chart widgets.
  Widget _analyticsCard() {
    const tabs = [
      (Icons.bar_chart_rounded, 'Bars'),
      (Icons.grid_on_rounded, 'Activity'),
      (Icons.pie_chart_outline_rounded, 'Gauge'),
      (Icons.layers_outlined, 'Sectors'),
    ];

    final chartBody = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: child),
      child: KeyedSubtree(
        key: ValueKey(_analyticsTabIndex),
        child: _buildAnalyticsBody(),
      ),
    );

    // Bounded on wide viewports so a chart card does not stretch to ~1240px.
    // Phone portrait (390) is under the cap and lays out exactly as before.
    return ConstrainedContent.wide(
      child: GuideTarget(id: 'profile_analytics', child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: InsightTheme.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: kCardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header row ──────────────────────────────────────────────
            LayoutBuilder(builder: (context, constraints) {
              final heading = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Performance Analytics',
                        style: InsightTheme.urbanist(
                          15,
                          w: FontWeight.w700,
                          c: InsightTheme.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'MPDO Field Operational Metrics',
                        style: InsightTheme.inter(12, c: InsightTheme.ink2),
                      ),
                    ],
                  );
                // Week / Month toggle pills
                final timeframe = Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: InsightTheme.surface2,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _timeframePill(
                        'Week',
                        _analyticsIsWeek,
                        () => setState(() => _analyticsIsWeek = true),
                      ),
                      _timeframePill(
                        'Month',
                        !_analyticsIsWeek,
                        () => setState(() => _analyticsIsWeek = false),
                      ),
                    ],
                  ),
                );
              return MediaQuery.textScalerOf(context).scale(15) > 22 && constraints.maxWidth < 600
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [heading, const SizedBox(height: 8), timeframe])
                : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: heading), timeframe]);
            }),

            const SizedBox(height: 14),

            // ── Segmented tab bar ────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: InsightTheme.surface2,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  for (int i = 0; i < tabs.length; i++)
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _analyticsTabIndex = i),
                        behavior: HitTestBehavior.opaque,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          constraints: const BoxConstraints(minHeight: 44),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: _analyticsTabIndex == i
                                ? InsightTheme.surface
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: _analyticsTabIndex == i
                                ? const [
                                    BoxShadow(
                                      color: Color(0x0A141628),
                                      blurRadius: 6,
                                      offset: Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                tabs[i].$1,
                                size: 16,
                                color: _analyticsTabIndex == i
                                    ? InsightTheme.blueInk
                                    : InsightTheme.ink2,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                tabs[i].$2,
                                style: InsightTheme.inter(
                                  12,
                                  w: _analyticsTabIndex == i
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  c: _analyticsTabIndex == i
                                      ? InsightTheme.blueInk
                                      : InsightTheme.ink2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ── Chart body ───────────────────────────────────────────────
            // IMPORTANT: the Activity calendar must size to its own content. A fixed
            // parent height clips the grid when the month spans more rows than the
            // assumed 340px placeholder. The other charts DO need a bounded height:
            // their chart area is an Expanded, which throws in an unbounded Column.
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              height: _analyticsTabIndex == 1 ? null : 250.0 *
                (widget.walkthrough == null ? 1 : math.max(1, MediaQuery.textScalerOf(context).scale(12) / 12)),
              child: chartBody,
            ),
          ],
        ),
      )),
    );
  }

  Widget _timeframePill(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? InsightTheme.blue1 : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: InsightTheme.inter(
            12,
            w: FontWeight.w700,
            c: active ? InsightTheme.surface : InsightTheme.ink2,
          ),
        ),
      ),
    );
  }

  Widget _buildAnalyticsBody() {
    // One range drives ALL four tabs. Built once per build so Bars, Activity,
    // Gauge and Sectors can never disagree about what period is selected.
    final range = AnalyticsActivityRange.selected(
      range: _analyticsIsWeek ? AnalyticsRange.week : AnalyticsRange.month,
      now: DateTime.now(),
      activeDays: _stats.activeSubmissionDates,
    );
    final periodLabel = _analyticsIsWeek ? 'Week' : 'Month';

    switch (_analyticsTabIndex) {
      case 0:
        // Week: daily counts. Month: weekly totals within the same exact range.
        return WeeklyTrendCard(
          points: _stats.submissionTrendFor(range.days),
          barColor: InsightTheme.blue1,
          textColor: InsightTheme.ink,
          mutedTextColor: InsightTheme.ink2,
          periodLabel: periodLabel,
        );
      case 1:
        return ActivityHeatmapCard(
          activityRange: range,
          activeColor: InsightTheme.green,
          inactiveColor: InsightTheme.surface2,
          textColor: InsightTheme.ink,
          mutedTextColor: InsightTheme.ink2,
        );
      case 2:
        // Completion Goals: scheduled-cohort rate for the selected period.
        // A period with nothing scheduled renders N/A, not a confident 0%.
        return CompletionGaugeCard(
          rate: _stats.completionRate,
          totalApplications: _stats.totalAssigned,
          activeWorkload: _stats.activeWorkloadCount,
          trackColor: InsightTheme.surface2,
          fillColor: InsightTheme.blue1,
          textColor: InsightTheme.ink,
          mutedTextColor: InsightTheme.ink2,
          periodMetrics: range.metricsFor(_stats.scheduledCohort),
          periodLabel: periodLabel,
        );
      case 3:
      default:
        // Zoning Distribution: only inspections completed inside the range.
        // Scheduling plays no part here, and pending work is excluded.
        return ZoningTypeBreakdownCard(
          entries: _stats.completedTypeBreakdownFor(range.days),
          periodLabel: periodLabel,
          barColor: InsightTheme.blue1,
          trackColor: InsightTheme.surface2,
          textColor: InsightTheme.ink,
          mutedTextColor: InsightTheme.ink2,
          segmentColors: const [
            InsightTheme.blue1,
            InsightTheme.green,
            InsightTheme.amber,
            InsightTheme.coral,
            InsightTheme.blueInk,
          ],
        );
    }
  }

  // WIDGET: Dashboard card shell (consistent padding/border/shadow around
  // each analytics widget so the widgets themselves stay layout-agnostic).
  // WIDGET: Dashboard card shell — plain container, no Expanded wrapper.
  // Charts self-size via their own Column/mainAxisSize now that they live
  // inside an AnimatedSwitcher rather than a fixed-height PageView.
  Widget _dashboardCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: InsightTheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: kCardShadow,
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
              const Icon(
                Icons.error_outline_rounded,
                color: InsightTheme.coral,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Couldn\'t load your analytics',
                style: InsightTheme.urbanist(
                  14,
                  w: FontWeight.w600,
                  c: InsightTheme.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _loadStats,
            behavior: HitTestBehavior.opaque,
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              alignment: Alignment.centerLeft,
              child: Text(
                'Tap to retry',
                style: InsightTheme.inter(
                  13,
                  w: FontWeight.w700,
                  c: InsightTheme.blueInk,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // WIDGET: Stat Card — matches HTML reference: clean white surface card,
  // neutral icon chip (surface2 for pending, blueTint for completed),
  // no color tinting on the card background itself.
  Widget _buildStatCard(
    String title,
    String count,
    IconData icon,
    Color iconBg,
    Color iconFg,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: InsightTheme.surface,
        borderRadius: InsightTheme.roundedMd,
        border: Border.all(color: InsightTheme.line, width: 1),
        boxShadow: kCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: iconFg),
          ),
          const SizedBox(height: 8),
          Text(
            count,
            style: InsightTheme.urbanist(
              26,
              w: FontWeight.w800,
              c: InsightTheme.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: InsightTheme.inter(
              12,
              w: FontWeight.w600,
              c: InsightTheme.ink2,
            ),
          ),
        ],
      ),
    );
  }
}
