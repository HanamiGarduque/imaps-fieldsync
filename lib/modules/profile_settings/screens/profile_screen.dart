import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/models/user_profile.dart';
import '../models/dashboard_stats.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../auth_startup/screens/splash_screen.dart' show LoginScreen;
import '../../tasks/screens/tasks_screen.dart' show TaskItem;
import 'profile_edit_screen.dart';
import 'about_insight_screen.dart';
import '../../auth_startup/screens/security_settings_screen.dart';
import 'terms_privacy_screen.dart';
import 'diagnostics_screen.dart';
import '../widgets/dashboard_widgets.dart';
import '../../../core/widgets/motion/spring_entrance.dart';


import '../../../core/theme/insight_theme.dart';

/// ==================================================================
/// SCREEN 17 — PROFILE
/// ==================================================================
class ProfileScreen extends StatefulWidget {
  final UserProfile profile;
  const ProfileScreen({super.key, required this.profile});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with TickerProviderStateMixin, SpringEntrance {
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

  // Drives the identity header's expand<->collapse crossfade as the user
  // scrolls — see _IdentityHeaderDelegate. Tracked in the scroll controller
  // (not a NotificationListener) since that's the more direct signal for a
  // SliverPersistentHeader tied to a single CustomScrollView.
  final ScrollController _scrollController = ScrollController();

  static const double _expandedHeaderHeight = 220.0;
  static const double _collapsedHeaderHeight = 78.0;

  @override
  void initState() {
    super.initState();
    _currentProfile = widget.profile;
    _refreshProfileFromServer();
    _loadStats();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    disposeSpringEntrance();
    super.dispose();
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

  /// Shows the "Log out" confirmation modal. Required per the destructive-
  /// action rule (specific-labeled buttons, no bare Yes/No) — sign out
  /// previously fired with zero confirmation.
  Future<void> _confirmSignOut(BuildContext context) async {
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Log out', style: InsightTheme.urbanist(18, w: FontWeight.w700, c: InsightTheme.ink)),
                    const SizedBox(height: 10),
                    Text(
                      "You'll need to sign in again to continue your inspections.",
                      style: InsightTheme.inter(13.5, c: InsightTheme.ink2, h: 1.4),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: isLoggingOut ? null : () => Navigator.pop(dialogContext),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(60, 44),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                          child: Text('Cancel', style: InsightTheme.inter(14, w: FontWeight.w600, c: InsightTheme.ink2)),
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
                            backgroundColor: InsightTheme.coral,
                            disabledBackgroundColor: InsightTheme.coral.withOpacity(0.7),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            minimumSize: const Size(90, 44),
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: isLoggingOut
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                                )
                              : Text('Log out', style: InsightTheme.inter(14, w: FontWeight.w700, c: Colors.white)),
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
      await SupabaseService.logSecurityEvent(eventType: 'logout', severity: 'info');
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
            child: RefreshIndicator(
              color: InsightTheme.blue1,
              onRefresh: () async {
                await Future.wait([
                  _refreshProfileFromServer(),
                  _loadStats(),
                ]);
              },
              // CustomScrollView + a pinned SliverPersistentHeader replaces
              // the plain ListView so the identity card can collapse into a
              // compact bar on scroll and expand back at the top — see
              // _IdentityHeaderDelegate.
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                slivers: [
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _IdentityHeaderDelegate(
                      expandedHeight: _expandedHeaderHeight,
                      collapsedHeight: _collapsedHeaderHeight,
                      avatarUrl: _currentProfile.avatarUrl,
                      initials: initials,
                      displayName: displayName,
                      positionLabel: positionLabel,
                      userEmail: userEmail,
                      onEditTap: _openEditScreen,
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 140),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        // 1. QUICK STATS ROW (Tasks Today/Pending, Completed Inspections)
                        // IntrinsicHeight guarantees both cards match the
                        // taller one's height regardless of label wrapping.
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: SpringSlide(
                                  animation: springFor(1),
                                  beginOffset: const Offset(0, 34),
                                  child: _buildStatCard(
                                    'Pending / Ongoing',
                                    _isLoadingStats ? '—' : '${_stats.tasksTodayOrPendingCount}',
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
                                    _isLoadingStats ? '—' : '${_stats.completedCount}',
                                    Icons.check_circle_outline_rounded,
                                    InsightTheme.blueTint,
                                    InsightTheme.blueInk,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

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
                            child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
                          )
                        else
                          _analyticsCard(),

                        const SizedBox(height: 24),

                        // 3. GROUPED ACTION CARDS — split from one long list
                        // into related groups, with Sign out separated by
                        // whitespace rather than sharing a divider with
                        // neutral settings rows (destructive actions get
                        // visual distance, not just a color change).
                        SpringSlide(
                          animation: springFor(5),
                          beginOffset: const Offset(0, 30),
                          child: Column(
                            children: [
                              _actionGroupCard([
                                _ActionTile(
                                  icon: Icons.fingerprint_rounded,
                                  title: 'Security & Biometrics',
                                  subtitle: 'Biometric login, auto-lock & protection',
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => SecuritySettingsScreen(profile: _currentProfile),
                                      ),
                                    );
                                  },
                                ),
                                _ActionTile(
                                  icon: Icons.flag_outlined,
                                  title: 'Diagnostics & Support',
                                  subtitle: 'Report an issue to the MPDO team',
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => const DiagnosticsScreen()),
                                    );
                                  },
                                ),
                              ]),
                              const SizedBox(height: 16),
                              _actionGroupCard([
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
                                _ActionTile(
                                  icon: Icons.info_outline_rounded,
                                  title: 'About iMAPS',
                                  subtitle: 'Version 1.0.0',
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => const AboutInsightScreen()),
                                    );
                                  },
                                ),
                              ]),
                              const SizedBox(height: 16),
                              _actionGroupCard([
                                _ActionTile(
                                  icon: Icons.logout_rounded,
                                  title: 'Sign out',
                                  isDestructive: true,
                                  onTap: () => _confirmSignOut(context),
                                ),
                              ]),
                            ],
                          ),
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),

      // Bottom navigation now lives solely in MainShellScreen (the app
      // shell). This screen no longer renders its own nav bar — see
      // NAVIGATION_REFACTOR.md for why the duplicate, per-page nav bar
      // was removed.
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
      transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
      child: KeyedSubtree(
        key: ValueKey(_analyticsTabIndex),
        child: _buildAnalyticsBody(),
      ),
    );

    return Container(
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Performance Analytics',
                        style: InsightTheme.urbanist(15, w: FontWeight.w700, c: InsightTheme.ink)),
                    const SizedBox(height: 2),
                    Text('MPDO Field Operational Metrics',
                        style: InsightTheme.inter(12, c: InsightTheme.ink2)),
                  ],
                ),
              ),
              // Week / Month toggle pills
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: InsightTheme.surface2,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _timeframePill('Week', _analyticsIsWeek, () => setState(() => _analyticsIsWeek = true)),
                    _timeframePill('Month', !_analyticsIsWeek, () => setState(() => _analyticsIsWeek = false)),
                  ],
                ),
              ),
            ],
          ),

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
                          color: _analyticsTabIndex == i ? InsightTheme.surface : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: _analyticsTabIndex == i
                              ? const [BoxShadow(color: Color(0x0A141628), blurRadius: 6, offset: Offset(0, 2))]
                              : null,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              tabs[i].$1,
                              size: 16,
                              color: _analyticsTabIndex == i ? InsightTheme.blueInk : InsightTheme.ink2,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              tabs[i].$2,
                              style: InsightTheme.inter(
                                12,
                                w: _analyticsTabIndex == i ? FontWeight.w700 : FontWeight.w500,
                                c: _analyticsTabIndex == i ? InsightTheme.blueInk : InsightTheme.ink2,
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
          // Dynamically adjust height: Activity calendar needs 340px, while
          // Gauge, Bars, and Sectors fit compactly in ~250px to eliminate empty space.
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            height: _analyticsTabIndex == 1 ? 340.0 : 250.0,
            child: chartBody,
          ),
        ],
      ),
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
    switch (_analyticsTabIndex) {
      case 0:
        return WeeklyTrendCard(
          points: _stats.weeklyTrend,
          barColor: InsightTheme.blue1,
          textColor: InsightTheme.ink,
          mutedTextColor: InsightTheme.ink2,
        );
      case 1:
        return ActivityHeatmapCard(
          activeDays: _stats.activeDaysThisMonth,
          month: _stats.currentMonth,
          year: _stats.currentYear,
          activeColor: InsightTheme.green,
          inactiveColor: InsightTheme.surface2,
          textColor: InsightTheme.ink,
          mutedTextColor: InsightTheme.ink2,
        );
      case 2:
        return CompletionGaugeCard(
          rate: _stats.completionRate,
          totalApplications: _stats.totalAssigned,
          activeWorkload: _stats.activeWorkloadCount,
          trackColor: InsightTheme.surface2,
          fillColor: InsightTheme.blue1,
          textColor: InsightTheme.ink,
          mutedTextColor: InsightTheme.ink2,
        );
      case 3:
      default:
        return ZoningTypeBreakdownCard(
          entries: _stats.typeBreakdown,
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

  // WIDGET: wraps a set of _ActionTiles as one grouped card, dividers only
  // between tiles sharing that card — never between separate cards (see
  // "visually separate elements with whitespace").
  Widget _actionGroupCard(List<_ActionTile> tiles) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: InsightTheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: kCardShadow,
      ),
      child: Column(
        children: [
          for (int i = 0; i < tiles.length; i++) ...[
            tiles[i],
            if (i != tiles.length - 1)
              const Divider(height: 1, color: InsightTheme.line, indent: 64, endIndent: 20),
          ],
        ],
      ),
    );
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
              const Icon(Icons.error_outline_rounded, color: InsightTheme.coral, size: 18),
              const SizedBox(width: 8),
              Text('Couldn\'t load your analytics', style: InsightTheme.urbanist(14, w: FontWeight.w600, c: InsightTheme.ink)),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _loadStats,
            behavior: HitTestBehavior.opaque,
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              alignment: Alignment.centerLeft,
              child: Text('Tap to retry', style: InsightTheme.inter(13, w: FontWeight.w700, c: InsightTheme.blueInk)),
            ),
          ),
        ],
      ),
    );
  }

  // WIDGET: Stat Card — matches HTML reference: clean white surface card,
  // neutral icon chip (surface2 for pending, blueTint for completed),
  // no color tinting on the card background itself.
  Widget _buildStatCard(String title, String count, IconData icon, Color iconBg, Color iconFg) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: InsightTheme.surface,
        borderRadius: BorderRadius.circular(20),
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
          const SizedBox(height: 14),
          Text(count,
              style: InsightTheme.urbanist(26, w: FontWeight.w800, c: InsightTheme.ink)),
          const SizedBox(height: 2),
          Text(title,
              style: InsightTheme.inter(12, w: FontWeight.w600, c: InsightTheme.ink2),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

/// ==================================================================
/// IDENTITY HEADER — pinned SliverPersistentHeader that crossfades
/// between the full identity card (expanded) and a compact bar
/// (collapsed) as the user scrolls, then restores the full card once
/// they scroll back to the top. Both states are always laid out; only
/// their opacity/hit-testing swaps, which avoids any layout jump.
/// ==================================================================
class _IdentityHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double expandedHeight;
  final double collapsedHeight;
  final String? avatarUrl;
  final String initials;
  final String displayName;
  final String positionLabel;
  final String userEmail;
  final VoidCallback onEditTap;

  _IdentityHeaderDelegate({
    required this.expandedHeight,
    required this.collapsedHeight,
    required this.avatarUrl,
    required this.initials,
    required this.displayName,
    required this.positionLabel,
    required this.userEmail,
    required this.onEditTap,
  });

  @override
  double get minExtent => collapsedHeight;

  @override
  double get maxExtent => expandedHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final range = expandedHeight - collapsedHeight;
    final t = range <= 0 ? 0.0 : (shrinkOffset / range).clamp(0.0, 1.0);

    // Smoothly interpolated values — single widget morphs, no dual-layer
    // overlap artifact. Full card opacity drops to 0 in the first 60% of
    // scroll; compact bar fades in from 40% onward. The two windows overlap
    // briefly in the 40–60% band but each is below 0.5 opacity there, so
    // the visual bleed is imperceptible. ClipRect prevents any overflow
    // from the full card bleeding outside the header bounds during shrink.
    final fullOpacity   = Curves.easeIn.transform((1 - t * 1.4).clamp(0.0, 1.0));
    final compactOpacity = Curves.easeOut.transform(((t - 0.35) / 0.65).clamp(0.0, 1.0));

    // Avatar size interpolates from 56 (expanded) → 36 (collapsed).
    final avatarSize = lerpDouble(56.0, 36.0, t)!;
    final avatarFontSize = lerpDouble(18.0, 12.0, t)!;

    return ClipRect(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
        child: Stack(
          children: [
            // — Compact bar: fades in as user scrolls down —
            Positioned.fill(
              child: Opacity(
                opacity: compactOpacity,
                child: IgnorePointer(
                  ignoring: t < 0.5,
                  child: _CompactIdentityBar(
                    avatarUrl: avatarUrl,
                    initials: initials,
                    displayName: displayName,
                    positionLabel: positionLabel,
                    onEditTap: onEditTap,
                    avatarSize: avatarSize,
                    avatarFontSize: avatarFontSize,
                  ),
                ),
              ),
            ),
            // — Full card: fades out as user scrolls down —
            // OverflowBox lets the card always lay out at the full expanded
            // height so Flutter never measures it against the shrinking
            // header height and emits the "bottom overflowed by N px" warning.
            // ClipRect (above) already clips the visual output, so there is
            // no visible change — only the yellow stripe is gone.
            Positioned.fill(
              child: Opacity(
                opacity: fullOpacity,
                child: IgnorePointer(
                  ignoring: t > 0.5,
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    maxHeight: expandedHeight,
                    child: _FullIdentityCard(
                      avatarUrl: avatarUrl,
                      initials: initials,
                      displayName: displayName,
                      positionLabel: positionLabel,
                      userEmail: userEmail,
                      onEditTap: onEditTap,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _IdentityHeaderDelegate oldDelegate) {
    return oldDelegate.avatarUrl != avatarUrl ||
        oldDelegate.initials != initials ||
        oldDelegate.displayName != displayName ||
        oldDelegate.positionLabel != positionLabel ||
        oldDelegate.userEmail != userEmail ||
        oldDelegate.expandedHeight != expandedHeight ||
        oldDelegate.collapsedHeight != collapsedHeight;
  }
}

/// WIDGET: Circular avatar — gradient fill + initials fallback, shared by
/// both the full and compact identity states so they always agree visually.
class _Avatar extends StatelessWidget {
  final String? avatarUrl;
  final String initials;
  final double size;
  final double fontSize;

  const _Avatar({required this.avatarUrl, required this.initials, this.size = 56, this.fontSize = 18});

  @override
  Widget build(BuildContext context) {
    // Border radius: rounded-2xl at full size (≈ size * 0.286 ≈ 16px for 56px),
    // scales with size so it stays proportional in the compact bar.
    final radius = (size * 0.286).clamp(10.0, 18.0);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          colors: [InsightTheme.blue1, InsightTheme.blue2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: InsightTheme.blue1.withOpacity(0.30),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(color: Colors.white, width: size > 44 ? 2.5 : 2),
        image: avatarUrl != null
            ? DecorationImage(image: NetworkImage(avatarUrl!), fit: BoxFit.cover)
            : null,
      ),
      alignment: Alignment.center,
      child: avatarUrl == null
          ? Text(initials, style: InsightTheme.urbanist(fontSize, w: FontWeight.w800, c: Colors.white))
          : null,
    );
  }
}

/// WIDGET: Full identity card — matches HTML reference exactly:
/// • Avatar is a rounded-2xl gradient square chip (not a circle)
/// • Role shown in a blueTint pill with jetBrains uppercase text
/// • Email row below divider
/// • Edit button: icon + "Edit" text label
class _FullIdentityCard extends StatelessWidget {
  final String? avatarUrl;
  final String initials;
  final String displayName;
  final String positionLabel;
  final String userEmail;
  final VoidCallback onEditTap;

  const _FullIdentityCard({
    required this.avatarUrl,
    required this.initials,
    required this.displayName,
    required this.positionLabel,
    required this.userEmail,
    required this.onEditTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: InsightTheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(color: Color(0x08141628), blurRadius: 20, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Gradient rounded-square avatar chip (matches HTML rounded-2xl)
              _Avatar(avatarUrl: avatarUrl, initials: initials, size: 56, fontSize: 18),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(displayName,
                        style: InsightTheme.urbanist(16, w: FontWeight.w700, c: InsightTheme.ink),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    // Role badge pill — blueTint bg, blueInk jetBrains uppercase
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: InsightTheme.blueTint,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: InsightTheme.blue1.withOpacity(0.18)),
                      ),
                      child: Text(
                        positionLabel.toUpperCase(),
                        style: InsightTheme.mono(12, w: FontWeight.w700, c: InsightTheme.blueInk, ls: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Edit button: icon + "Edit" label, blueTint bg (min 44x44 touch target)
              GestureDetector(
                onTap: onEditTap,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: InsightTheme.blueTint,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: InsightTheme.blue1.withOpacity(0.15)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.person_outline_rounded, size: 16, color: InsightTheme.blueInk),
                      const SizedBox(width: 5),
                      Text('Edit', style: InsightTheme.inter(13, w: FontWeight.w600, c: InsightTheme.blueInk)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: InsightTheme.line),
          const SizedBox(height: 12),
          // Email row
          Row(
            children: [
              const Icon(Icons.mail_outline_rounded, size: 15, color: InsightTheme.ink2),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  userEmail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: InsightTheme.inter(13, w: FontWeight.w500, c: InsightTheme.ink2),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// WIDGET: Compact identity bar shown once the user has scrolled — carries
/// the same avatar/name identity forward instead of leaving a blank gap,
/// echoing the requested "collapses into a slim bar" behavior but themed
/// to this screen's light surface and without a non-functional back arrow
/// (this screen is a bottom-nav tab, not a pushed route — a back affordance
/// that did nothing would violate "never let users guess what happens next").
class _CompactIdentityBar extends StatelessWidget {
  final String? avatarUrl;
  final String initials;
  final String displayName;
  final String positionLabel;
  final VoidCallback onEditTap;
  // Interpolated from the header delegate so the avatar size morphs
  // continuously rather than snapping between two fixed sizes.
  final double avatarSize;
  final double avatarFontSize;

  const _CompactIdentityBar({
    required this.avatarUrl,
    required this.initials,
    required this.displayName,
    required this.positionLabel,
    required this.onEditTap,
    this.avatarSize = 38,
    this.avatarFontSize = 13,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: InsightTheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x08141628), blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          _Avatar(avatarUrl: avatarUrl, initials: initials, size: avatarSize, fontSize: avatarFontSize),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(displayName,
                    style: InsightTheme.urbanist(15, w: FontWeight.w700, c: InsightTheme.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(positionLabel,
                    style: InsightTheme.inter(12, w: FontWeight.w500, c: InsightTheme.ink2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          GestureDetector(
            onTap: onEditTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(7),
              decoration: const BoxDecoration(color: InsightTheme.blueTint, shape: BoxShape.circle),
              child: const Icon(Icons.edit_outlined, size: 16, color: InsightTheme.blueInk),
            ),
          ),
        ],
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
    // Destructive actions (Sign out) use the theme RED — per design
    // feedback the softer coral read as a normal accent, not a warning.
    final fgColor = isDestructive ? InsightTheme.red : InsightTheme.ink;
    final iconColor = isDestructive ? InsightTheme.red : InsightTheme.blueInk;

    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              // Bare icon — the old rounded tinted chip behind each icon was
              // removed per design feedback (icons now sit directly on the
              // card, like the rest of the system's list rows).
              Icon(icon, size: 22, color: iconColor),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: InsightTheme.urbanist(15, w: FontWeight.w600, c: fgColor)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: InsightTheme.inter(12, c: InsightTheme.ink2)),
                    ]
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: InsightTheme.ink3, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}