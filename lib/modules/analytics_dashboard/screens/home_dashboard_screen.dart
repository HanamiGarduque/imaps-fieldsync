import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../../../core/models/user_profile.dart';
import '../models/activity_event_category.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/db_helper.dart';
import '../../tasks/screens/tasks_screen.dart';
import '../../../core/navigation/parcel_detail_screen.dart';
import '../../profile_settings/screens/notifications_screen.dart';
import '../../profile_settings/screens/profile_edit_screen.dart'; 
import '../../../core/widgets/insight_bottom_nav.dart'; // kInsightBottomNavReserve (scroll padding) only
import '../../../core/layout/responsive_layout.dart';
import '../../../core/widgets/motion/spring_entrance.dart';
import '../../../core/widgets/motion/updating_tile.dart';
import '../../../core/widgets/imaps_loading_indicator.dart';
import '../widgets/active_assignments_folder_card.dart';
import '../../../core/theme/insight_theme.dart';

/// Whether a task belongs in the dashboard's Active Assignments carousel.
/// Uses the same canonical lifecycle categories as My Tasks.
bool isHomeDashboardActiveAssignment(TaskItem task) =>
    task.lifecycleCategory == TaskLifecycleCategory.pending ||
    task.lifecycleCategory == TaskLifecycleCategory.ongoing;

/// The existing dashboard display bucket for a task.
///
/// "Scheduled" remains a visual Pending subsection; it is never returned for
/// Ongoing, Completed, or Unknown lifecycle values.
String? homeDashboardTaskPresentationCategory(TaskItem task) {
  return switch (task.lifecycleCategory) {
    TaskLifecycleCategory.pending =>
      task.pendingSection == PendingTaskSection.scheduled
          ? 'Scheduled'
          : 'Pending',
    TaskLifecycleCategory.ongoing => 'Ongoing',
    TaskLifecycleCategory.completed => 'Completed',
    TaskLifecycleCategory.unknown => null,
  };
}

/// ==================================================================
/// SCREEN — HOME DASHBOARD 
/// ==================================================================
class HomeDashboardScreen extends StatefulWidget {
  final UserProfile profile;
  // Optional — when this screen is hosted inside MainShellScreen, this is
  // wired to the shell's own tab switcher so "See All" / "More details"
  // land on the Tasks tab WITH the bottom nav bar still visible, instead
  // of pushing a second, standalone TasksScreen route. Falls back to a
  // normal Navigator.push (see below) if null, so this screen still works
  // fine if ever used outside the shell.
  final ValueChanged<int>? onNavigateToTab;
  // Optional callback — called when profile is updated externally (e.g.
  // from Edit Profile screen) so the shell can refresh shared profile state.
  final ValueChanged<UserProfile>? onProfileUpdated;
  const HomeDashboardScreen({super.key, required this.profile, this.onNavigateToTab, this.onProfileUpdated});

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen>
    with TickerProviderStateMixin, SpringEntrance {

  late PageController _pageController;

  /// Carousel page width for a given viewport width.
  ///
  /// Portrait keeps the accepted 0.88, so a card still peeks at the next one.
  /// A wider viewport would otherwise turn a single card into a giant
  /// full-bleed banner, so the fraction tightens until a card stays near its
  /// portrait proportion and the next one remains visible.
  static double carouselViewportFraction(double viewportWidth) {
    if (viewportWidth < InsightBreakpoints.mediumWidth) return 0.88;
    if (viewportWidth < InsightBreakpoints.expandedWidth) return 0.46;
    // Wide viewports show more of the next card rather than an enormous one.
    return (420.0 / viewportWidth).clamp(0.22, 0.40);
  }
  int _currentCardIndex = 0;

  List<TaskItem> _upcomingTasks = [];
  // Full, unfiltered task list — separate from _upcomingTasks (which is
  // capped at 6 and excludes Completed for the assignments carousel).
  // Task Completion Flow and the calendar's task-dots both need the
  // complete picture, so this is loaded alongside it in the same fetch
  // rather than issuing a second network/service call.
  List<TaskItem> _allTasks = [];
  // Keep real fetched metadata for selected normal entry; display is read-only.
  Map<String, Map<String, dynamic>> _entryJobs = {};
  bool _isLoadingTasks = true;

  List<Map<String, dynamic>> _recentActivity = [];
  bool _isLoadingActivity = true;
  int _unreadCount = 0;

  // Recent Activity — category filter (All / Tasks / Sync / Reports / Profile).
  // Buckets are owned by ActivityEventCategory so the mapping is testable
  // without a widget tree; filtering happens client-side over the already-fetched
  // batch (see _kRecentActivityLimit below) rather than re-querying per tap.
  String _activityFilter = 'all';

   // The calendar selection is independent of the live Today/Note card.
   final DateTime _now = DateTime.now();
  late DateTime _calendarMonth = DateTime(_now.year, _now.month);
  late int _selectedDay = _now.day;
   bool _showFullCalendar = false;

  bool _isOnline = true;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncCarouselToViewport();
  }

  /// Rebuild the carousel controller when the viewport width class changes, so
  /// a rotation or a resized window gets the right card proportion. The page
  /// index is preserved so the current card stays current.
  void _syncCarouselToViewport() {
    final fraction = carouselViewportFraction(context.responsive.width);
    if ((_carouselFraction - fraction).abs() < 0.001) return;
    final page = _pageController.hasClients && _pageController.page != null
        ? _pageController.page!.toDouble()
        : _currentCardIndex.toDouble();
    _pageController.dispose();
    _pageController = PageController(
      viewportFraction: fraction,
      initialPage: _currentCardIndex,
    );
    _carouselFraction = fraction;
    // Restore the visible page after the new controller has attached. The
    // clamp keeps it inside the list when the task set shrank on refresh.
    final maxPage = (_upcomingTasks.length - 1).clamp(0, double.infinity).toDouble();
    final target = page.clamp(0.0, maxPage);
    if (target == page) return; // already showing the clamped page
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_pageController.hasClients) return;
      _pageController.jumpTo(target);
    });
  }

  double _carouselFraction = 0.88;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.88);
    _checkInitialConnectivity();

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      if (mounted) {
        final online = results.any((r) => r != ConnectivityResult.none);
        if (_isOnline != online) {
          setState(() {
            _isOnline = online;
          });
        }
      }
    });

    _loadUpcomingTasks();
    _loadRecentActivity();
  }

  Future<void> _checkInitialConnectivity() async {
    final online = await AuthService.hasConnectivity();
    if (mounted && _isOnline != online) {
      setState(() => _isOnline = online);
    }
  }


  @override
  void didUpdateWidget(HomeDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If profile was updated externally (e.g., from Edit Profile),
    // refresh the header name and reload recent activity.
    if (oldWidget.profile.fullName != widget.profile.fullName ||
        oldWidget.profile.avatarUrl != widget.profile.avatarUrl) {
      _loadRecentActivity();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _connectivitySubscription.cancel();
    disposeSpringEntrance();
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
        _entryJobs = {for (final job in jobs) job['id'] as String: job};
        tasks = jobs.map((j) => TaskItem.fromJob(j)).toList();
      } else {
        _entryJobs = {};
        final localJobs = await DBHelper.getCachedJobs();
        tasks = localJobs.map(TaskItem.fromCachedJob).toList();
      }
    } catch (e) {
      debugPrint('Error loading tasks: $e');
    }

    final upcoming = tasks.where(isHomeDashboardActiveAssignment).toList()
      ..sort((a, b) {
        final aDate = _calendarDateForTask(a) ?? '9999-12-31';
        final bDate = _calendarDateForTask(b) ?? '9999-12-31';
        return aDate.compareTo(bDate);
      });

    if (mounted) {
      setState(() {
        _allTasks = tasks;
        _upcomingTasks = upcoming.take(6).toList(); 
        _isLoadingTasks = false;
      });
    }
  }

  // Recent Activity shows at most 15 items — filtered client-side into
  // All / Tasks / Sync / Profile once fetched.
  static const int _kRecentActivityLimit = 15;

  Future<void> _loadRecentActivity() async {
    setState(() => _isLoadingActivity = true);
    try {
      final activity = await SupabaseService.fetchRecentActivity(limit: _kRecentActivityLimit);
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
  static const _fullMonthNames = ['January','February','March','April','May','June','July','August','September','October','November','December'];


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
      case 'sync_manual':
      case 'sync_inspection':
      case 'cache_cleared':
        return {'icon': Icons.cloud_done_rounded, 'color': InsightTheme.blue1};
      case 'profile_updated':
        return {'icon': Icons.person_rounded, 'color': InsightTheme.blue1};
      case 'security_updated':
        return {'icon': Icons.security_rounded, 'color': InsightTheme.amber};
      case 'diagnostic_report_submitted':
        return {'icon': Icons.flag_rounded, 'color': InsightTheme.orange};
      case 'report_resolved':
        return {'icon': Icons.check_circle_rounded, 'color': InsightTheme.green};
      case 'report_wont_fix':
        return {'icon': Icons.block_rounded, 'color': InsightTheme.ink3};
      case 'gps_confirmed':
        return {'icon': Icons.gps_fixed_rounded, 'color': InsightTheme.blueInk};
      default:
        return {'icon': Icons.notifications_rounded, 'color': InsightTheme.ink3};
    }
  }

  // Maps each activity_log `event_type` to one of the four filter
  // buckets shown above the timeline. Mirrors the event types actually
  // written by SupabaseService.logActivity() across the app (inspection
  // provider, inspection progress, notification service, GPS confirm,
  // rework) — see core/services/supabase_service.dart.
  String _eventCategory(String eventType) =>
      ActivityEventCategory.categoryFor(eventType);

  // Human-readable label for the category chip on the redesigned Recent
  // Activity tile (Master's Image 3 reference) — one label per bucket in
  // ActivityEventCategory.filters, just capitalized for display.
  String _eventCategoryLabel(String eventType) =>
      ActivityEventCategory.labelFor(_eventCategory(eventType));

  List<Map<String, dynamic>> get _filteredActivity {
    if (_activityFilter == 'all') return _recentActivity;
    return _recentActivity
        .where((a) => _eventCategory(a['event_type'] as String? ?? '') == _activityFilter)
        .toList();
  }

  String _getInitials(String name) {
    if (name.trim().isEmpty) return "JR";
    List<String> parts = name.trim().split(' ');
    if (parts.length > 1) return "${parts[0][0]}${parts[1][0]}".toUpperCase();
    return parts[0].substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  String _greeting(DateTime now) {
    if (now.hour < 12) return 'Good morning';
    if (now.hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  // ----------------------------------------------------------------
  // TASK COMPLETION FLOW — Scheduled / Pending / Ongoing / Completed
  // ----------------------------------------------------------------
  // The visual Scheduled bucket is the scheduled subsection of Pending.
  // Unknown tasks stay outside these normal dashboard buckets.
  Map<String, int> get _completionCounts {
    final counts = {
      'Scheduled': 0,
      'Pending': 0,
      'Ongoing': 0,
      'Completed': 0,
    };
    for (final task in _allTasks) {
      final presentationCategory =
          homeDashboardTaskPresentationCategory(task);
      if (presentationCategory != null) {
        counts[presentationCategory] = counts[presentationCategory]! + 1;
      }
    }
    return counts;
  }

  // Which day-of-month numbers (in `month`) have at least one active task.
  // Pending/Scheduled tasks use their Visit date; Pending/Available Anytime
  // and Ongoing tasks use their admin Deadline date. Unknown and Completed
  // tasks are not represented as active calendar work.
  String? _calendarDateForTask(TaskItem task) {
    switch (task.lifecycleCategory) {
      case TaskLifecycleCategory.pending:
        if (task.pendingSection == PendingTaskSection.scheduled) {
          return task.scheduledDate.isEmpty ? null : task.scheduledDate;
        }
        return task.deadlineDate?.isNotEmpty == true
            ? task.deadlineDate
            : null;
      case TaskLifecycleCategory.ongoing:
        return task.deadlineDate?.isNotEmpty == true
            ? task.deadlineDate
            : null;
      case TaskLifecycleCategory.completed:
      case TaskLifecycleCategory.unknown:
        return null;
    }
  }

  Set<int> _taskDaysInMonth(DateTime month) {
    final days = <int>{};
    for (final t in _allTasks) {
      final calendarDate = _calendarDateForTask(t);
      if (calendarDate == null) continue;
      try {
        final d = DateTime.parse(calendarDate);
        if (d.year == month.year && d.month == month.month) days.add(d.day);
      } catch (_) {}
    }
    return days;
  }

  Map<int, List<TaskItem>> _tasksByDayInMonth(DateTime month) {
    final map = <int, List<TaskItem>>{};
    for (final t in _allTasks) {
      final calendarDate = _calendarDateForTask(t);
      if (calendarDate == null) continue;
      try {
        final d = DateTime.parse(calendarDate);
        if (d.year == month.year && d.month == month.month) {
          map.putIfAbsent(d.day, () => <TaskItem>[]).add(t);
        }
      } catch (_) {}
    }
    for (final items in map.values) {
      items.sort((a, b) {
        final priorityA = _calendarPriorityKey(a);
        final priorityB = _calendarPriorityKey(b);
        if (priorityA != priorityB) return priorityA.compareTo(priorityB);
        return (a.inspectionNo).compareTo(b.inspectionNo);
      });
    }
    return map;
  }

  int _calendarPriorityKey(TaskItem task) {
    return _calendarVisitPriority(task);
  }

  int _calendarVisitPriority(TaskItem task) {
    try {
      final calendarDate = _calendarDateForTask(task);
      if (calendarDate == null) return 2;
      final visit = DateTime.parse(calendarDate);
      final today = DateTime.now();
      final taskDay = DateTime(visit.year, visit.month, visit.day);
      final todayDay = DateTime(today.year, today.month, today.day);
      final daysUntilTask = taskDay.difference(todayDay).inDays;
      if (task.pendingSection == PendingTaskSection.scheduled) {
        if (daysUntilTask <= 1) return 0;
        if (daysUntilTask <= 3) return 1;
      } else {
        if (daysUntilTask <= 1) return 0;
        if (daysUntilTask <= 3) return 1;
      }
    } catch (_) {}
    return 2;
  }

  Color _calendarDotColor(TaskItem task) {
    switch (_calendarVisitPriority(task)) {
      case 0:
        return InsightTheme.red;
      case 1:
        return InsightTheme.orange;
      default:
        return InsightTheme.blue1;
    }
  }

  // Tasks tab index in MainShellScreen's own _items list (see
  // main_shell_screen.dart) — Home=0, Tasks=1, Updates=2, Profile=3.
  static const int _kTasksTabIndex = 1;

  void _goToTasksTab() {
    if (widget.onNavigateToTab != null) {
      widget.onNavigateToTab!(_kTasksTabIndex);
    } else {
      // Fallback when Home isn't hosted inside MainShellScreen.
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => TasksScreen(profile: widget.profile)));
    }
  }

  String _formatShortId(String fullId) {
    if (fullId.length > 8) return fullId.substring(0, 8).toUpperCase();
    return fullId.toUpperCase();
  }

   void _toggleFullCalendar() {
     setState(() => _showFullCalendar = !_showFullCalendar);
  }

  void _onFullCalendarPick(DateTime month, int day) {
    setState(() {
      _calendarMonth = month;
      _selectedDay = day;
    });
  }

  @override
  Widget build(BuildContext context) {
    final initials = _getInitials(widget.profile.fullName);
    final firstName = UserProfile.displayFullName(widget.profile.fullName);
    final greeting = _greeting(_now);
     final tasksByDay = _tasksByDayInMonth(_calendarMonth);

    return Scaffold(
      backgroundColor: InsightTheme.bg,
      extendBody: true, 
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: kInsightBottomNavReserve),
          child: ConstrainedContent.wide(
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ----------------------------------------------------
              // Separate white surfaces follow the v3 section grouping.
              // ----------------------------------------------------
              Container(
                key: const ValueKey('inspector_section'),
                width: double.infinity,
                padding: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: InsightTheme.surface,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ----------------------------------------------------
                    // 1. TOP BAR — avatar left, status + bell right
                    // ----------------------------------------------------
                    SpringSlide(
                      animation: springFor(0),
                      beginOffset: const Offset(0, -32),
                      child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () async {
                              final result = await Navigator.push<UserProfile?>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ProfileEditScreen(profile: widget.profile),
                                ),
                              );
                              if (result != null && mounted) {
                                widget.onProfileUpdated?.call(result);
                              }
                            },
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: InsightTheme.blue1,
                                border: Border.all(color: InsightTheme.blue1, width: 2),
                              ),
                              child: ClipOval(
                                child: widget.profile.avatarUrl != null && widget.profile.avatarUrl!.isNotEmpty
                                    ? Image.network(
                                        widget.profile.avatarUrl!,
                                        width: 44,
                                        height: 44,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) => Center(
                                          child: Text(initials, style: InsightTheme.urbanist(13, w: FontWeight.w700, c: Colors.white)),
                                        ),
                                      )
                                    : Center(
                                        child: Text(initials, style: InsightTheme.urbanist(13, w: FontWeight.w700, c: Colors.white)),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text('FieldSync',
                            style: InsightTheme.urbanist(16, w: FontWeight.w700, c: InsightTheme.ink))),
                          const SizedBox(width: 8),
                          Container(
                            margin: const EdgeInsets.only(right: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: _isOnline ? InsightTheme.greenTint : InsightTheme.redTint,
                              borderRadius: BorderRadius.circular(999),
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
                                Text(_isOnline ? 'Online' : 'Offline',
                                     style: InsightTheme.inter(12, w: FontWeight.w600, c: _isOnline ? InsightTheme.greenInk : InsightTheme.redInk)),
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
                    ),
                    const SizedBox(height: 8),

                    // ----------------------------------------------------
                    // GREETING
                    // ----------------------------------------------------
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SpringSlide(
                        animation: springFor(0),
                        beginOffset: const Offset(0, -20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(greeting, style: InsightTheme.inter(13,
                              w: FontWeight.w500, c: InsightTheme.ink3)),
                            const SizedBox(height: 4),
                            Text(firstName, style: InsightTheme.urbanist(24,
                              w: FontWeight.w700, c: InsightTheme.ink, ls: -0.5)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Container(
                key: const ValueKey('calendar_section'),
                decoration: BoxDecoration(
                  color: InsightTheme.surface,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  children: [

                    // ----------------------------------------------------
                    // SCHEDULE / CALENDAR
                    // ----------------------------------------------------
                     Padding(
                       padding: const EdgeInsets.symmetric(horizontal: 16),
                       child: SpringSlide(
                         animation: springFor(1),
                         beginOffset: const Offset(0, 18),
                         child: _TodayScheduleCard(
                           tasksForDate: (date) => _tasksByDayInMonth(date)[date.day] ?? const <TaskItem>[],
                           dotColorForTask: _calendarDotColor,
                           isLoading: _isLoadingTasks,
                         ),
                       ),
                     ),
                     Center(
                       child: TextButton(
                         onPressed: _toggleFullCalendar,
                         child: Tooltip(
                           message: _showFullCalendar ? 'Hide full calendar' : 'Show full calendar',
                           child: Row(
                             mainAxisSize: MainAxisSize.min,
                             children: [
                               Text('Calendar', style: InsightTheme.inter(12, w: FontWeight.w600, c: InsightTheme.blueInk)),
                               AnimatedRotation(
                                 turns: _showFullCalendar ? 0.5 : 0,
                                 duration: const Duration(milliseconds: 220),
                                 child: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: InsightTheme.blue1),
                               ),
                             ],
                           ),
                         ),
                       ),
                     ),
                     SpringSlide(
                      animation: springFor(1),
                      beginOffset: const Offset(0, 18),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 320),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SizeTransition(
                            sizeFactor: animation,
                            alignment: Alignment(-1, -1),
                            child: SlideTransition(
                              position: Tween<Offset>(begin: const Offset(0, -0.06), end: Offset.zero).animate(animation),
                              child: child,
                            ),
                          ),
                        ),
                        child: _showFullCalendar
                            ? Padding(
                                key: const ValueKey('full_calendar'),
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: _InlineFullCalendarCard(
                                  month: _calendarMonth,
                                  selectedDay: _selectedDay,
                                  taskDaysForMonth: _taskDaysInMonth,
                                  tasksByDayInMonth: tasksByDay,
                                  dotColorForTask: _calendarDotColor,
                                  onPrevMonth: () => setState(() => _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month - 1)),
                                  onNextMonth: () => setState(() => _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1)),
                                  onPick: _onFullCalendarPick,
                                ),
                              )
                             : const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // ----------------------------------------------------
              // 2. ACTIVE ASSIGNMENTS
              // ----------------------------------------------------
              Container(
                key: const ValueKey('assignments_section'),
                padding: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: InsightTheme.surface,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SpringSlide(

                  animation: springFor(1),
                  beginOffset: const Offset(0, 20),
                  child: _SectionLabel(
                    title: "Active Assignments",
                    trailing: _SectionActionButton(label: 'See All', onTap: _goToTasksTab),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              // Relocated here (was floating alone between the calendar and
              // this section, easy to miss). Now reads as the subtitle for
              // what it's actually describing, with more weight so it
              // doesn't get lost.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SpringSlide(
                  animation: springFor(1),
                  beginOffset: const Offset(0, 16),
                  child: Text(
                    "Here's what's on your schedule today.",
                    style: InsightTheme.inter(13, c: InsightTheme.ink3),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              
              SpringSlide(
                animation: springFor(2),
                beginOffset: const Offset(70, 0),
                child: SizedBox(
                height: MediaQuery.textScalerOf(context).scale(244).clamp(244, double.infinity),
                child: _isLoadingTasks
                    ? const Center(child: ImapsLoadingIndicator(size: 50))
                    : _upcomingTasks.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.assignment_outlined, size: 36, color: InsightTheme.ink3),
                                const SizedBox(height: 10),
                                Text(
                                  'No active assignments.',
                                  style: InsightTheme.openSans(13, c: InsightTheme.ink2),
                                ),
                              ],
                            ),
                          )
                        : PageView.builder(
                            controller: _pageController,
                            // Reuses the same controller; only the visible
                            // fraction adapts, so the page index and the
                            // spring-scale effect keep working unchanged.
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
                                    value = (1 - (value.abs() * 0.08)).clamp(0.92, 1.0);
                                  } else {
                                    value = (index == 0) ? 1.0 : 0.92;
                                  }
                                  return Center(
                                    child: SizedBox(
                                      height: Curves.easeOut.transform(value) * MediaQuery.textScalerOf(context).scale(220).clamp(220, double.infinity),
                                      width: double.infinity,
                                      child: child,
                                    ),
                                  );
                                },
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 6),
                                  child: UpdatingTile(
                                    itemKey: _upcomingTasks[index].id,
                                    signature: Object.hash(
                                      _upcomingTasks[index].scheduledDate,
                                      _upcomingTasks[index].location,
                                      _upcomingTasks[index].applicationType,
                                      _upcomingTasks[index].landUseClass,
                                      _upcomingTasks[index].status,
                                    ),
                                    child: ActiveAssignmentsFolderCard(
                                      inspectionId: _formatShortId(_upcomingTasks[index].id),
                                      referenceNo: _upcomingTasks[index].inspectionNo,
                                        date: _calendarDateForTask(_upcomingTasks[index]) != null
                                          ? _formatScheduledDate(_calendarDateForTask(_upcomingTasks[index])!)
                                          : '—',
                                      location: _upcomingTasks[index].location,
                                      applicantName: _upcomingTasks[index].name,
                                      applicationType: _upcomingTasks[index].applicationType?.isNotEmpty == true
                                          ? _upcomingTasks[index].applicationType!
                                          : _upcomingTasks[index].landUseClass,
                                      lifecycleCategory:
                                          _upcomingTasks[index].lifecycleCategory,
                                      pendingSection:
                                          _upcomingTasks[index].pendingSection,
                                      onTap: () => Navigator.of(context).push(
                                          MaterialPageRoute(builder: (_) => ParcelDetailScreen(
                                            task: _upcomingTasks[index],
                                            fetchedJob: _entryJobs[_upcomingTasks[index].id],
                                            relatedRounds: _allTasks.where(_upcomingTasks[index].sameApplicationAs).toList(),
                                          ))),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
              ),
              ),
              const SizedBox(height: 12),

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
                        color: _currentCardIndex == index ? InsightTheme.blue1 : InsightTheme.ink3.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    );
                  }),
                ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ----------------------------------------------------
              // 3. TASK COMPLETION FLOW
              // ----------------------------------------------------
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SpringSlide(
                  animation: springFor(3),
                  beginOffset: const Offset(0, 20),
                  child: _SectionLabel(
                    title: "Task completion flow",
                    trailing: _SectionActionButton(label: 'More details', onTap: _goToTasksTab),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SpringSlide(
                  animation: springFor(4),
                  beginOffset: const Offset(0, 24),
                  // Group container (Pattern A) — the ring chart previously
                  // sat directly on the page background; giving it its own
                  // card lets the shape actually register as a unit.
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: InsightTheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: InsightTheme.line),
                    ),
                    child: _isLoadingTasks
                        ? const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Center(child: ImapsLoadingIndicator(size: 40)))
                        : _allTasks.isEmpty
                            ? Text('No tasks yet.', style: InsightTheme.inter(12, c: InsightTheme.ink2))
                            : Builder(builder: (context) {
                                final counts = _completionCounts;
                                final total = counts.values.fold<int>(0, (a, b) => a + b);
                                const labels = ['Scheduled', 'Pending', 'Ongoing', 'Completed'];
                                const colors = [InsightTheme.orange, InsightTheme.blue1, InsightTheme.blue1, InsightTheme.green];
                                final fractions = List.generate(labels.length, (i) {
                                  final count = counts[labels[i]] ?? 0;
                                  return total == 0 ? 0.0 : count / total;
                                });
                                final overdueCount = _allTasks.where((task) {
                                  if (task.category == 'Completed') return false;
                                  return task.scheduleUrgency == 'Overdue';
                                }).length;
                                return _CompletionRingChart(
                                      total: total,
                                      labels: labels,
                                      colors: colors,
                                      counts: List.generate(labels.length, (i) => counts[labels[i]] ?? 0),
                                      fractions: fractions,
                                      overdueCount: overdueCount,
                                );
                              }),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // ----------------------------------------------------
              // 4. RECENT ACTIVITY
              // ----------------------------------------------------
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: InsightTheme.surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SpringSlide(
                  animation: springFor(8),
                  beginOffset: const Offset(0, 20),
                  child: const _SectionLabel(title: "Recent activity"),
                ),
              ),
              const SizedBox(height: 12),

              // Text-only activity categories share one segmented surface.
              SpringSlide(
                animation: springFor(8),
                beginOffset: const Offset(0, 20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    key: const ValueKey('activity_filters'),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: InsightTheme.surface2,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                    children: [
                      Expanded(
                        child: _ActivityFilterChip(
                          label: 'All',
                          selected: _activityFilter == 'all',
                          onTap: () => setState(() => _activityFilter = 'all'),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _ActivityFilterChip(
                          label: 'Tasks',
                          selected: _activityFilter == 'tasks',
                          onTap: () => setState(() => _activityFilter = 'tasks'),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _ActivityFilterChip(
                          label: 'Sync',
                          selected: _activityFilter == 'sync',
                          onTap: () => setState(() => _activityFilter = 'sync'),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _ActivityFilterChip(
                          label: ActivityEventCategory.labelFor(
                            ActivityEventCategory.reports,
                          ),
                          selected:
                              _activityFilter == ActivityEventCategory.reports,
                          onTap: () => setState(
                            () => _activityFilter = ActivityEventCategory.reports,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _ActivityFilterChip(
                          label: 'Profile',
                          selected: _activityFilter == 'profile',
                          onTap: () => setState(() => _activityFilter = 'profile'),
                        ),
                      ),
                    ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _isLoadingActivity
                    ? const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: ImapsLoadingIndicator(size: 50)))
                    // Crossfade the timeline content when the filter changes —
                    // same easeOutCubic/220ms language _TimelineActivityTile
                    // already uses for its own expand/collapse, so the motion
                    // reads as one consistent feel rather than a second style.
                    : AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeOutCubic,
                        child: _filteredActivity.isEmpty
                            ? Padding(
                                key: ValueKey('empty_$_activityFilter'),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Text(
                                  _activityFilter == 'all'
                                      ? 'No recent activity yet.'
                                      : 'No $_activityFilter activity yet.',
                                  style: InsightTheme.inter(12, c: InsightTheme.ink2),
                                ),
                              )
                            : Stack(
                                key: ValueKey('list_$_activityFilter'),
                                children: [
                                  Positioned(
                                    left: 19, top: 12, bottom: 16,
                                    child: Container(width: 2, color: InsightTheme.ink3.withValues(alpha: 0.15)),
                                  ),
                                  Column(
                                    children: List.generate(_filteredActivity.length, (i) {
                                      final themeInfo = _eventTheme(_filteredActivity[i]['event_type'] as String? ?? '');
                                      final activityId = _filteredActivity[i]['id'] ?? i;
                                      return SpringSlide(
                                        // Cached by index — already settled after first load, so on
                                        // a later filter switch this simply renders at rest (opacity
                                        // 1, no offset) and the AnimatedSwitcher crossfade above does
                                        // the work. On first load it still plays the original stagger.
                                        animation: springFor(9 + i),
                                        beginOffset: const Offset(0, 28),
                                        child: UpdatingTile(
                                          itemKey: activityId,
                                          signature: Object.hash(
                                            _filteredActivity[i]['title'],
                                            _filteredActivity[i]['subtitle'],
                                            _filteredActivity[i]['occurred_at'],
                                          ),
                                          child: _TimelineActivityTile(
                                            icon: themeInfo['icon'],
                                            color: themeInfo['color'],
                                            categoryLabel: _eventCategoryLabel(_filteredActivity[i]['event_type'] as String? ?? ''),
                                            title: _filteredActivity[i]['title'] as String? ?? 'Update',
                                            subtitle: _filteredActivity[i]['subtitle'] as String? ?? '',
                                            time: _timeAgo(_filteredActivity[i]['occurred_at'] as String?),
                                            occurredAtIso: _filteredActivity[i]['occurred_at'] as String?,
                                          ),
                                        ),
                                      );
                                    }),
                                  ),
                                ],
                              ),
                      ),
              ),
                ],
                ),
              ),
            ],
            ),
          ),
        ),
      ),
      // Bottom navigation now lives solely in MainShellScreen (the app
      // shell). This screen no longer renders its own nav bar — see
      // NAVIGATION_REFACTOR.md for why the duplicate, per-page nav bar
      // was removed.
    );
  }
}

/// ==================================================================
/// COMPONENT WIDGETS
/// ==================================================================

/// Keeps clock ticks local and uses the full calendar's date mapping for Today.
class _TodayScheduleCard extends StatefulWidget {
  final List<TaskItem> Function(DateTime date) tasksForDate;
  final Color Function(TaskItem task) dotColorForTask;
  final bool isLoading;

  const _TodayScheduleCard({
    required this.tasksForDate,
    required this.dotColorForTask,
    required this.isLoading,
  });

  @override
  State<_TodayScheduleCard> createState() => _TodayScheduleCardState();
}

class _TodayScheduleCardState extends State<_TodayScheduleCard> {
  late DateTime _now = DateTime.now();
  Timer? _timer;
  bool _showTasks = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hour12 = _now.hour % 12 == 0 ? 12 : _now.hour % 12;
    final text = '${hour12.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')} ${_now.hour < 12 ? 'AM' : 'PM'}';
    final scaler = MediaQuery.textScalerOf(context);
    final tasks = widget.tasksForDate(_now);
    return Container(
      key: const ValueKey('clock_date_card'),
      height: scaler.scale(92),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: InsightTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: InsightTheme.line),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final tileWidth = constraints.maxWidth * 0.4;
        return Stack(children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOutCubic,
            top: 0,
            bottom: 0,
            left: _showTasks ? tileWidth : 0,
            width: constraints.maxWidth - tileWidth,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _showTasks
                    ? Column(
                        key: const ValueKey('today_note'),
                        children: [
                          Text('Note', style: InsightTheme.urbanist(14, w: FontWeight.w700, c: InsightTheme.ink)),
                          const SizedBox(height: 4),
                          Expanded(
                            child: SingleChildScrollView(
                              key: const ValueKey('today_tasks'),
                              child: widget.isLoading
                                  ? Text('Loading today’s tasks…', style: InsightTheme.inter(12, c: InsightTheme.ink2))
                                  : tasks.isEmpty
                                      ? Text('No tasks or PO due dates today.', textAlign: TextAlign.center, style: InsightTheme.inter(12, c: InsightTheme.ink2))
                                      : Column(
                                          children: tasks.map((task) => _CalendarTaskRow(task: task, color: widget.dotColorForTask(task))).toList(),
                                        ),
                            ),
                          ),
                        ],
                      )
                    : Center(
                        key: const ValueKey('live_clock'),
                        child: Text(text, textAlign: TextAlign.center, style: InsightTheme.urbanist(24, w: FontWeight.w800, c: InsightTheme.ink)),
                      ),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOutCubic,
            top: 0,
            bottom: 0,
            left: _showTasks ? 0 : constraints.maxWidth - tileWidth,
            width: tileWidth,
            child: Semantics(
              button: true,
              label: _showTasks ? 'Show clock and date' : "Show today's tasks",
              value: _showTasks ? 'Today' : '${_HomeDashboardScreenState._fullMonthNames[_now.month - 1]} ${_now.day}, ${_now.year}',
              onTap: () => setState(() => _showTasks = !_showTasks),
              excludeSemantics: true,
              child: Material(
                color: InsightTheme.blue1,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => setState(() => _showTasks = !_showTasks),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: _showTasks
                            ? Text('Today', key: const ValueKey('today_label'), style: InsightTheme.urbanist(24, w: FontWeight.w800, c: Colors.white))
                            : Column(
                                key: const ValueKey('date_label'),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('${_now.day}', style: InsightTheme.urbanist(30, w: FontWeight.w800, c: Colors.white)),
                                  Text(_HomeDashboardScreenState._fullMonthNames[_now.month - 1], textAlign: TextAlign.center, style: InsightTheme.inter(12, w: FontWeight.w600, c: Colors.white)),
                                  Text(const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][_now.weekday - 1], style: InsightTheme.inter(12, w: FontWeight.w600, c: Colors.white)),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]);
      }),
    );
  }
}

/// Shared by Today's notes and the selected date in the full calendar.
class _CalendarTaskRow extends StatelessWidget {
  final TaskItem task;
  final Color color;
  const _CalendarTaskRow({required this.task, required this.color});

  @override
  Widget build(BuildContext context) {
    final isVisit = task.lifecycleCategory == TaskLifecycleCategory.pending &&
        task.pendingSection == PendingTaskSection.scheduled;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6, height: 6,
            margin: const EdgeInsets.only(top: 6, right: 6),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.inspectionNo, style: InsightTheme.inter(12, w: FontWeight.w700, c: InsightTheme.ink)),
                Text(task.name, style: InsightTheme.inter(12, c: InsightTheme.ink2)),
                Text(isVisit ? 'Scheduled visit' : 'PO due date', style: InsightTheme.inter(12, w: FontWeight.w600, c: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationBtn extends StatelessWidget {
  final VoidCallback onTap;
  final bool hasUnread;
  const _NotificationBtn({required this.onTap, this.hasUnread = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48, height: 48,
        decoration: BoxDecoration(
          color: InsightTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: InsightTheme.line),
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
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: InsightTheme.surface2, borderRadius: BorderRadius.circular(999)),
              child: Text(title, style: InsightTheme.urbanist(16,
                w: FontWeight.w700, c: InsightTheme.ink)),
            ),
          ),
        ),
        if (trailing != null) const SizedBox(width: 12),
        ?trailing,
      ],
    );
  }
}

/// Section navigation keeps a full-height touch target.
class _SectionActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SectionActionButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: InsightTheme.inter(12, w: FontWeight.w700, c: InsightTheme.blueInk)),
            const SizedBox(width: 3),
            Icon(Icons.arrow_forward_rounded, size: 12, color: InsightTheme.blueInk),
          ],
        ),
      ),
    );
  }
}

/// Text-only category tab, with content-driven height for enlarged text.
class _ActivityFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ActivityFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? InsightTheme.ink : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.center,
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: InsightTheme.inter(12, w: FontWeight.w600,
                c: selected ? Colors.white : InsightTheme.ink2),
            ),
          ),
        ),
      ),
    );
  }
}

/// Concentric ring chart for Task Completion Flow (replaces the old
/// stacked progress-bar rows). One ring per category — Scheduled (outer)
/// through Completed (inner) — each ring's filled arc is that category's
/// share of the total task count. Categories stay in a compact two-by-two
/// layout, beside the rings when they fit and below on narrow layouts.
class _CompletionRingChart extends StatefulWidget {
  final int total;
  final List<String> labels;
  final List<Color> colors;
  final List<int> counts;
  final List<double> fractions; // 0..1 each, share of total
  final int overdueCount;

  const _CompletionRingChart({
    required this.total,
    required this.labels,
    required this.colors,
    required this.counts,
    required this.fractions,
    required this.overdueCount,
  });

  @override
  State<_CompletionRingChart> createState() => _CompletionRingChartState();
}

class _CompletionRingChartState extends State<_CompletionRingChart> {
  bool _filled = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) setState(() => _filled = true);
    });
  }

  static const double _outerSize = 100;
  static const double _ringStep = 16;
  static const double _strokeWidth = 8;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final ringSize = scaler.scale(_outerSize);
    final rings = SizedBox(
      width: ringSize,
      height: ringSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (int i = 0; i < widget.labels.length; i++)
            SizedBox(
              width: ringSize - (scaler.scale(_ringStep) * i),
              height: ringSize - (scaler.scale(_ringStep) * i),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: _filled ? widget.fractions[i].clamp(0.0, 1.0) : 0.0),
                duration: const Duration(milliseconds: 750),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => CircularProgressIndicator(
                  value: value <= 0 ? 0.001 : value,
                  strokeWidth: scaler.scale(_strokeWidth),
                  strokeCap: StrokeCap.round,
                  backgroundColor: widget.colors[i].withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation<Color>(widget.colors[i]),
                ),
              ),
            ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: scaler.scale(44)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${widget.total}', style: InsightTheme.urbanist(22, w: FontWeight.w800, c: InsightTheme.ink)),
                const SizedBox(height: 2),
                Text('Tasks', style: InsightTheme.openSans(12, w: FontWeight.w600, c: InsightTheme.ink3)),
              ],
            ),
          ),
        ],
      ),
    );
    final labelStyle = InsightTheme.inter(12, w: FontWeight.w500, c: InsightTheme.ink2);
    var labelWidth = 0.0;
    for (final label in widget.labels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: Directionality.of(context),
        textScaler: scaler,
      )..layout();
      if (painter.width > labelWidth) labelWidth = painter.width;
      painter.dispose();
    }
    final legend = Stack(
      alignment: Alignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int row = 0; row < widget.labels.length; row += 2) ...[
              if (row == 2) SizedBox(height: scaler.scale(widget.overdueCount > 0 ? 12 : 4)),
              Table(
                children: [TableRow(children: [
                  for (int i = row; i < row + 2; i++)
                    Padding(
                      padding: const EdgeInsets.all(2),
                      child: Container(
                        key: ValueKey('completion_${widget.labels[i]}'),
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: scaler.scale(6)),
                        decoration: BoxDecoration(
                          color: i == 0 ? InsightTheme.surface2 : widget.colors[i].withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: InsightTheme.line),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (i < 2) Text(widget.labels[i], softWrap: false, style: labelStyle),
                            Text('${widget.counts[i]}', style: InsightTheme.urbanist(22, w: FontWeight.w700, c: InsightTheme.ink)),
                            if (i >= 2) Text(widget.labels[i], softWrap: false, style: labelStyle),
                          ],
                        ),
                      ),
                    ),
                ])],
              ),
            ],
          ],
        ),
        if (widget.overdueCount > 0)
          Container(
            key: const ValueKey('completion_overdue'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: InsightTheme.redTint, borderRadius: BorderRadius.circular(999)),
            child: Text('${widget.overdueCount} Overdue', style: InsightTheme.inter(12, w: FontWeight.w700, c: InsightTheme.redInk)),
          ),
      ],
    );
    return LayoutBuilder(key: const ValueKey('completion_chart'), builder: (context, constraints) {
      // Keep category words intact with the actual font and accessibility size.
      if (constraints.maxWidth < ringSize + 8 + (labelWidth + 18) * 2) {
        return Column(children: [rings, const SizedBox(height: 12), legend]);
      }
      return Row(children: [
        rings,
        const SizedBox(width: 8),
        Expanded(child: legend),
      ]);
    });
  }
}

/// Inline full-month calendar (Master's Image 2 reference) — swapped in
/// for the day strip via the toggle button in build()'s AnimatedSwitcher.
/// No longer a modal/bottom sheet: it's stateless and driven entirely by
/// the parent screen's _calendarMonth/_selectedDay, so the strip and the
/// full grid can never disagree with each other.
class _InlineFullCalendarCard extends StatelessWidget {
  final DateTime month;
  final int selectedDay;
  final Set<int> Function(DateTime month) taskDaysForMonth;
  final Map<int, List<TaskItem>> tasksByDayInMonth;
  final Color Function(TaskItem task) dotColorForTask;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final void Function(DateTime month, int day) onPick;

  const _InlineFullCalendarCard({
    required this.month,
    required this.selectedDay,
    required this.taskDaysForMonth,
    required this.tasksByDayInMonth,
    required this.dotColorForTask,
    required this.onPrevMonth,
    required this.onNextMonth,
    required this.onPick,
  });

  // Sunday-start grid to match the reference; the day-strip stays
  // Monday-start elsewhere, they're independent visual conventions.
  static const _weekdayAbbrSunStart = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
  static const _fullWeekdayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _monthAbbr = _HomeDashboardScreenState._monthNames;

  @override
  Widget build(BuildContext context) {
    final taskDays = taskDaysForMonth(month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final firstWeekday = DateTime(month.year, month.month, 1).weekday; // 1=Mon..7=Sun
    final leadingBlanks = firstWeekday % 7; // Sunday-start offset

    final clampedDay = selectedDay.clamp(1, daysInMonth);
    final selectedDate = DateTime(month.year, month.month, clampedDay);
    final headerLabel =
        '$clampedDay ${_monthAbbr[month.month - 1]} ${(month.year % 100).toString().padLeft(2, '0')}, ${_fullWeekdayNames[selectedDate.weekday - 1]}';
    final selectedTasks = tasksByDayInMonth[clampedDay] ?? const <TaskItem>[];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: InsightTheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: InsightTheme.line, width: 1.2),
        boxShadow: kCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(headerLabel, style: InsightTheme.urbanist(15, w: FontWeight.w700, c: InsightTheme.ink)),
              ),
              IconButton(
                tooltip: 'Previous month',
                onPressed: onPrevMonth,
                icon: Icon(Icons.chevron_left_rounded, color: InsightTheme.ink2),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Next month',
                onPressed: onNextMonth,
                icon: Icon(Icons.chevron_right_rounded, color: InsightTheme.ink2),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: _weekdayAbbrSunStart.map((d) {
              return Expanded(
                child: Center(
                  child: Text(d.substring(0, 3), style: InsightTheme.inter(12, w: FontWeight.w700, c: InsightTheme.ink3)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 4),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              mainAxisExtent: MediaQuery.textScalerOf(context).scale(24) + 24,
            ),
            itemCount: daysInMonth + leadingBlanks,
            itemBuilder: (context, i) {
              if (i < leadingBlanks) return const SizedBox.shrink();
              final day = i - leadingBlanks + 1;
              final isSelected = day == selectedDay;
              final hasTask = taskDays.contains(day);
              final dayTasks = tasksByDayInMonth[day] ?? const <TaskItem>[];
              final dotColors = dayTasks
                  .map(dotColorForTask)
                  .toSet()
                  .toList();
              return GestureDetector(
                key: ValueKey('calendar_day_$day'),
                onTap: () => onPick(month, day),
                behavior: HitTestBehavior.opaque,
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected ? InsightTheme.blue1 : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('$day', style: InsightTheme.inter(12.5, w: FontWeight.w700, c: isSelected ? Colors.white : InsightTheme.ink)),
                        if (hasTask)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: dotColors.take(3).map((dotColor) {
                              return Container(
                                margin: const EdgeInsets.symmetric(horizontal: 1),
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected ? Colors.white : dotColor,
                                ),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          if (selectedTasks.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: InsightTheme.surface2,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tasks for $clampedDay ${_monthAbbr[month.month - 1]}',
                    style: InsightTheme.urbanist(12, w: FontWeight.w700, c: InsightTheme.ink),
                  ),
                  const SizedBox(height: 8),
                  ...selectedTasks.map((task) => _CalendarTaskRow(task: task, color: dotColorForTask(task))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Recent Activity tile — redesigned per Master's Image 4 reference as a
/// tinted, larger-radius card (category color at low opacity, no hard
/// border) instead of the previous plain-bordered rectangle. Left: a
/// category chip (icon + label). Right: timestamp. Below: the event
/// title with a short accent underline, matching the reference's shape.
/// Tap-to-expand for the exact timestamp is preserved from before.
class _TimelineActivityTile extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String categoryLabel;
  final String title;
  final String subtitle;
  final String time;
  final String? occurredAtIso;

  const _TimelineActivityTile({
    required this.icon, required this.color, required this.categoryLabel,
    required this.title, required this.subtitle, required this.time,
    this.occurredAtIso,
  });

  @override
  State<_TimelineActivityTile> createState() => _TimelineActivityTileState();
}

class _TimelineActivityTileState extends State<_TimelineActivityTile> {
  bool _expanded = false;

  String get _exactTimestamp {
    final iso = widget.occurredAtIso;
    if (iso == null) return '';
    try {
      final d = DateTime.parse(iso).toLocal();
      final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
      final period = d.hour < 12 ? 'AM' : 'PM';
      final minute = d.minute.toString().padLeft(2, '0');
      return '${_HomeDashboardScreenState._monthNames[d.month - 1]} ${d.day}, ${d.year} · $hour12:$minute $period';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline node — kept from before so this still reads as part
          // of the vertical timeline (the connector line sits behind it).
          Container(
            width: 34,
            alignment: Alignment.topCenter,
            padding: const EdgeInsets.only(top: 12),
            decoration: const BoxDecoration(color: InsightTheme.bg),
            child: Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
          const SizedBox(width: 6),

          // Activity card — tappable, animates open/closed for the exact
          // timestamp. Tinted fill instead of a white card + border.
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _expanded = !_expanded),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                // Compacted per feedback — previous padding/type scale
                // read too large next to the rest of the dashboard.
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Top row — category chip (icon + label) left,
                      // timestamp right.
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: InsightTheme.surface,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(widget.icon, size: 13, color: widget.color),
                                const SizedBox(width: 4),
                                Text(widget.categoryLabel, style: InsightTheme.inter(12, w: FontWeight.w700, c: widget.color)),
                              ],
                            ),
                          ),
                          Text(widget.time, style: InsightTheme.mono(12, w: FontWeight.w600, c: InsightTheme.ink2)),
                        ],
                      ),
                      const SizedBox(height: 9),
                      // Title + accent underline, per the reference shape.
                      Text(widget.title, style: InsightTheme.urbanist(13, w: FontWeight.w700, c: InsightTheme.ink), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 5),
                      Container(width: 32, height: 2, decoration: BoxDecoration(color: widget.color.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(2))),
                      if (widget.subtitle.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(widget.subtitle, style: InsightTheme.inter(12, w: FontWeight.w500, c: InsightTheme.ink2)),
                      ],
                      if (_expanded && _exactTimestamp.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.schedule_rounded, size: 13, color: InsightTheme.ink2),
                            const SizedBox(width: 6),
                            Text(_exactTimestamp, style: InsightTheme.mono(12, w: FontWeight.w500, c: InsightTheme.ink2)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
