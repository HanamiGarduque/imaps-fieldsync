import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../../../core/models/user_profile.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/db_helper.dart';
import '../../tasks/screens/tasks_screen.dart';
import '../../../core/navigation/parcel_detail_screen.dart';
import '../../profile_settings/screens/notifications_screen.dart';
import '../../profile_settings/screens/profile_edit_screen.dart'; 
import '../../../core/widgets/insight_bottom_nav.dart'; // kInsightBottomNavReserve (scroll padding) only
import '../../../core/widgets/motion/spring_entrance.dart';
import '../../../core/widgets/motion/updating_tile.dart';
import '../../../core/widgets/imaps_loading_indicator.dart';
import '../widgets/active_assignments_folder_card.dart';
import '../../../core/theme/insight_theme.dart';

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
  const HomeDashboardScreen({super.key, required this.profile, this.onNavigateToTab});

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen>
    with TickerProviderStateMixin, SpringEntrance {

  late PageController _pageController;
  int _currentCardIndex = 0;

  List<TaskItem> _upcomingTasks = [];
  // Full, unfiltered task list — separate from _upcomingTasks (which is
  // capped at 6 and excludes Completed for the assignments carousel).
  // Task Completion Flow and the calendar's task-dots both need the
  // complete picture, so this is loaded alongside it in the same fetch
  // rather than issuing a second network/service call.
  List<TaskItem> _allTasks = [];
  bool _isLoadingTasks = true;

  List<Map<String, dynamic>> _recentActivity = [];
  bool _isLoadingActivity = true;
  int _unreadCount = 0;

  // Recent Activity — category filter (All / Tasks / Sync / Profile).
  // Filtering happens client-side over the already-fetched batch (see
  // _kRecentActivityLimit below) rather than re-querying per tap.
  String _activityFilter = 'all';

  // Calendar strip / modal — visual day selector only (no filtering wired
  // to it beyond the subtitle + dots, matching the reference). `_now` is
  // captured once (not a ticking value) — only used to seed today's
  // month/day and the greeting; the actual live clock in the header is
  // its own small widget (_LiveClock) so its per-minute tick doesn't
  // rebuild this whole screen (see PERFORMANCE NOTE below).
  final DateTime _now = DateTime.now();
  late DateTime _calendarMonth = DateTime(_now.year, _now.month);
  late int _selectedDay = _now.day;
  final ScrollController _dayStripController = ScrollController();

  // Drawer toggle: false = slideable day strip showing, true = full month
  // grid showing in its place. See _toggleFullCalendar / build().
  bool _showFullCalendar = false;

  bool _isOnline = true;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.88);
    
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      if (mounted) {
        setState(() {
          _isOnline = !results.contains(ConnectivityResult.none);
        });
      }
    });

    // Auto-scroll the day strip to today the moment it first lays out —
    // it used to always start at day 1, forcing a manual swipe every time.
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollDayStripToSelected());

    _loadUpcomingTasks();
    _loadRecentActivity();
  }

  // Centers the selected day chip in the horizontal strip. Called after
  // first layout, whenever the picked day/month changes from the full
  // calendar, and (animated) on a direct tap in the strip itself.
  void _scrollDayStripToSelected({bool animate = false}) {
    if (!_dayStripController.hasClients) return;
    const chipWidth = 60.0; // 52 chip + 8 margin, see the day-strip builder
    final viewport = _dayStripController.position.viewportDimension;
    final target = ((_selectedDay - 1) * chipWidth - (viewport / 2) + (chipWidth / 2))
        .clamp(0.0, _dayStripController.position.maxScrollExtent);
    if (animate) {
      _dayStripController.animateTo(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
    } else {
      _dayStripController.jumpTo(target);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _connectivitySubscription.cancel();
    _dayStripController.dispose();
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
        tasks = jobs.map((j) => TaskItem.fromJob(j)).toList();
      } else {
        final localJobs = await DBHelper.getCachedJobs();
        tasks = localJobs.map((j) => TaskItem.fromJob({
              'id': j['id'],
              'supabase_parcel_id': j['supabase_parcel_id'],
              'status': j['status'],
              'local_inspection_id': j['local_inspection_id'],
              'scheduled_date': j['scheduled_date'],
              'deadline_date': j['deadline_date'],
              'is_self_scheduled': j['is_self_scheduled'] == 1,
              'supabase_zoning_applications': {
                'applicant_name': j['applicant_name'],
                'barangay': j['barangay'],
                'reference_number': j['reference_number'],
                'application_type': j['application_type'],
              }
            })).toList();
      }
    } catch (e) {
      debugPrint('Error loading tasks: $e');
    }

    final upcoming = tasks.where((t) => t.category == 'Scheduled' || t.category == 'Pending').toList()
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
        return {'icon': Icons.cloud_done_rounded, 'color': InsightTheme.blue1};
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
  String _eventCategory(String eventType) {
    switch (eventType) {
      case 'inspection_completed':
      case 'rework_started':
      case 'step_completed':
      case 'gps_confirmed':
        return 'tasks';
      case 'photos_synced':
        return 'sync';
      case 'push_received':
        return 'profile';
      default:
        // Unclassified/system events read as account-level notices.
        return 'profile';
    }
  }

  // Human-readable label for the category chip on the redesigned Recent
  // Activity tile (Master's Image 3 reference) — reuses _eventCategory's
  // same three buckets, just capitalized for display.
  String _eventCategoryLabel(String eventType) {
    switch (_eventCategory(eventType)) {
      case 'tasks':
        return 'Task';
      case 'sync':
        return 'Sync';
      default:
        return 'Profile';
    }
  }

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

  String _firstName(String name) {
    if (name.trim().isEmpty) return "there";
    return name.trim().split(' ').first;
  }

  String _greeting(DateTime now) {
    if (now.hour < 12) return 'Good morning';
    if (now.hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  // ----------------------------------------------------------------
  // TASK COMPLETION FLOW — Scheduled / Pending / Ongoing / Completed
  // ----------------------------------------------------------------
  // Real category values only (TaskItem.category) — the four buckets are
  // mutually exclusive and sum to the full task count.
  Map<String, int> get _completionCounts {
    int scheduled = 0, pending = 0, ongoing = 0, completed = 0;
    for (final t in _allTasks) {
      switch (t.category) {
        case 'Scheduled':
          scheduled++;
          break;
        case 'Pending':
          pending++;
          break;
        case 'Ongoing':
          ongoing++;
          break;
        case 'Completed':
          completed++;
          break;
      }
    }
    return {'Scheduled': scheduled, 'Pending': pending, 'Ongoing': ongoing, 'Completed': completed};
  }

  // Which day-of-month numbers (in `month`) have at least one active task
  // All active tasks back the dots under each day in both calendar views.
  // Scheduled tasks use their Visit date; Available Anytime and Ongoing tasks
  // use their admin Deadline date.
  String? _calendarDateForTask(TaskItem task) {
    if (task.category == 'Completed') return null;
    if (task.category == 'Scheduled') {
      return task.scheduledDate.isEmpty ? null : task.scheduledDate;
    }
    return task.deadlineDate?.isNotEmpty == true ? task.deadlineDate : null;
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
      if (task.category == 'Scheduled') {
        if (daysUntilTask <= 1) return 0;
        if (daysUntilTask <= 3) return 1;
      } else {
        if (daysUntilTask <= 1) return 0;
        if (daysUntilTask <= 3) return 1;
      }
    } catch (_) {}
    return 2;
  }

  List<Color> _calendarDotColorsForDay(DateTime month, int day) {
    final tasks = _tasksByDayInMonth(month)[day] ?? const <TaskItem>[];
    final colors = <Color>{};
    for (final task in tasks) {
      colors.add(_calendarDotColor(task));
    }
    return colors.toList();
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

  // Inline drawer toggle (UDAS §3.4 — secondary picker, not a full page
  // nav) — replaces the old showModalBottomSheet approach. Toggling swaps
  // the slideable day-strip out for the full month grid in place, via the
  // AnimatedSwitcher in build() (fade + slight vertical drawer motion).
  // No second route, no modal — same screen, same scroll position.
  void _toggleFullCalendar() {
    final closing = _showFullCalendar;
    setState(() => _showFullCalendar = !_showFullCalendar);
    if (closing) {
      // AnimatedSwitcher tears down the strip's Scrollable while the full
      // calendar is showing, so its ScrollController loses its offset —
      // the new Scrollable that attaches on the way back always starts
      // at 0 (day 1) unless explicitly re-centered here.
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollDayStripToSelected());
    }
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
    final firstName = _firstName(widget.profile.fullName);
    final greeting = _greeting(_now);
    final taskDays = _taskDaysInMonth(_calendarMonth);
    final tasksByDay = _tasksByDayInMonth(_calendarMonth);
    final selectedDayTasks = tasksByDay[_selectedDay] ?? const <TaskItem>[];
    final daysInMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1, 0).day;
    const weekdayAbbr = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

    return Scaffold(
      backgroundColor: InsightTheme.bg,
      extendBody: true, 
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: kInsightBottomNavReserve),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ----------------------------------------------------
              // HEADER + CALENDAR CARD — one continuous white surface
              // from the avatar/top-bar all the way down through the
              // "View full calendar" toggle, closed off with a rounded
              // bottom edge + shadow instead of a flat cut + divider.
              // Everything below (Active Assignments onward) sits back
              // on the plain scaffold background.
              // ----------------------------------------------------
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: InsightTheme.surface,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(28),
                    bottomRight: Radius.circular(28),
                  ),
                  boxShadow: kCardShadow,
                ),
                padding: const EdgeInsets.only(top: 12, bottom: 16),
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
                            onTap: () {
                              Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileEditScreen(profile: widget.profile)));
                            },
                            child: Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: InsightTheme.blue1,
                                border: Border.all(color: InsightTheme.surface, width: 2),
                                boxShadow: kCardShadow,
                              ),
                              alignment: Alignment.center,
                              child: Text(initials, style: InsightTheme.urbanist(13, w: FontWeight.w700, c: Colors.white)),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            margin: const EdgeInsets.only(right: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: _isOnline ? InsightTheme.green.withOpacity(0.12) : InsightTheme.red.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
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
                                Text(_isOnline ? 'ONLINE' : 'OFFLINE', 
                                     style: InsightTheme.mono(12, w: FontWeight.w700, c: _isOnline ? InsightTheme.greenInk : InsightTheme.redInk)),
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
                    const SizedBox(height: 16),

                    // ----------------------------------------------------
                    // GREETING
                    // ----------------------------------------------------
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SpringSlide(
                        animation: springFor(0),
                        beginOffset: const Offset(0, -20),
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(text: '$greeting, $firstName ', style: InsightTheme.urbanist(22, w: FontWeight.w800, c: InsightTheme.ink, ls: -0.4)),
                            const TextSpan(text: '👋', style: TextStyle(fontSize: 19)),
                          ]),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ----------------------------------------------------
                    // SCHEDULE / CALENDAR
                    // ----------------------------------------------------
                    // Month header is now display-only — the toggle to open the
                    // full calendar moved below the strip (see toggle button).
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SpringSlide(
                        animation: springFor(1),
                        beginOffset: const Offset(0, 18),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_fullMonthNames[_calendarMonth.month - 1],
                                style: InsightTheme.urbanist(19, w: FontWeight.w800, c: InsightTheme.ink)),
                            const _LiveClock(),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Drawer swap: slideable day strip <-> full month grid.
                    // Same screen, no modal, no second route — just a fade +
                    // slight vertical motion between the two, per Master's spec.
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
                            axisAlignment: -1,
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
                            : SizedBox(
                                key: const ValueKey('day_strip'),
                                height: 78,
                                child: ListView.builder(
                                  controller: _dayStripController,
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  itemCount: daysInMonth,
                                  itemBuilder: (context, i) {
                                    final day = i + 1;
                                    final weekday = DateTime(_calendarMonth.year, _calendarMonth.month, day).weekday; // 1=Mon..7=Sun
                                    final isSelected = day == _selectedDay;
                                    final hasTask = taskDays.contains(day);
                                    final dotColors = _calendarDotColorsForDay(_calendarMonth, day);
                                    return GestureDetector(
                                      onTap: () {
                                        setState(() => _selectedDay = day);
                                        _scrollDayStripToSelected(animate: true);
                                      },
                                      // Each day now sits in its own card — slight
                                      // curve, subtle lift — rather than a bare
                                      // transparent tap zone (Master's spec). Now
                                      // that the card behind it is also white,
                                      // the border + shadow (not color contrast)
                                      // is what keeps each chip readable as its
                                      // own card — a light "tint" background on
                                      // the unselected chip would fight the
                                      // theme-lock rule against inventing a new
                                      // token, so border+shadow do the work here.
                                      child: Container(
                                        width: 52,
                                        margin: const EdgeInsets.only(right: 8, top: 2, bottom: 2),
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                        decoration: BoxDecoration(
                                          color: isSelected ? InsightTheme.blue1 : InsightTheme.surface,
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(
                                            color: isSelected ? Colors.transparent : InsightTheme.line,
                                            width: 1.4,
                                          ),
                                          boxShadow: kCardShadow,
                                        ),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text('$day', style: InsightTheme.urbanist(14, w: FontWeight.w800, c: isSelected ? Colors.white : InsightTheme.ink)),
                                            Text(weekdayAbbr[weekday - 1], style: InsightTheme.openSans(12, w: FontWeight.w600, c: isSelected ? Colors.white.withOpacity(0.9) : InsightTheme.ink3)),
                                            const SizedBox(height: 4),
                                            if (hasTask)
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: dotColors.take(3).map((dotColor) {
                                                  return Container(
                                                    width: 5,
                                                    height: 5,
                                                    margin: const EdgeInsets.symmetric(horizontal: 1.2),
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      color: isSelected ? Colors.white : dotColor,
                                                    ),
                                                  );
                                                }).toList(),
                                              )
                                            else
                                              Container(
                                                width: 5,
                                                height: 5,
                                                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.transparent),
                                              ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Toggle button — always visible below the strip/grid so the
                    // same control opens AND closes the drawer. Lives outside the
                    // AnimatedSwitcher on purpose (per Master: click again to
                    // come back up).
                    Center(
                      child: GestureDetector(
                        onTap: _toggleFullCalendar,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                          decoration: BoxDecoration(
                            color: _showFullCalendar ? InsightTheme.blueTint : InsightTheme.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _showFullCalendar ? Colors.transparent : InsightTheme.line,
                              width: 1.4,
                            ),
                            boxShadow: kCardShadow,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _showFullCalendar ? 'Hide full calendar' : 'View full calendar',
                                style: InsightTheme.openSans(12, w: FontWeight.w700, c: _showFullCalendar ? InsightTheme.blueInk : InsightTheme.ink2),
                              ),
                              const SizedBox(width: 4),
                              AnimatedRotation(
                                turns: _showFullCalendar ? 0.5 : 0,
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                child: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: _showFullCalendar ? InsightTheme.blue2 : InsightTheme.blue1),
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

              // ----------------------------------------------------
              // 2. ACTIVE ASSIGNMENTS
              // ----------------------------------------------------
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SpringSlide(

                  animation: springFor(1),
                  beginOffset: const Offset(0, 20),
                  child: _SectionLabel(
                    title: "ACTIVE ASSIGNMENTS",
                    icon: Icons.assignment_rounded,
                    accentColor: InsightTheme.blue1,
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
                    style: InsightTheme.openSans(13.5, w: FontWeight.w600, c: InsightTheme.ink),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              
              SpringSlide(
                animation: springFor(2),
                beginOffset: const Offset(70, 0),
                child: SizedBox(
                height: 260,
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
                                      height: Curves.easeOut.transform(value) * 220,
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
                                      status: _upcomingTasks[index].category,
                                      onTap: () => Navigator.of(context).push(
                                          MaterialPageRoute(builder: (_) => ParcelDetailScreen(task: _upcomingTasks[index]))),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
              ),
              ),
              const SizedBox(height: 24),

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
                        color: _currentCardIndex == index ? InsightTheme.blue1 : InsightTheme.ink3.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    );
                  }),
                ),
              const SizedBox(height: 36),

              // ----------------------------------------------------
              // 3. TASK COMPLETION FLOW
              // ----------------------------------------------------
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SpringSlide(
                  animation: springFor(3),
                  beginOffset: const Offset(0, 20),
                  child: _SectionLabel(
                    title: "TASK COMPLETION FLOW",
                    icon: Icons.donut_large_rounded,
                    accentColor: InsightTheme.green,
                    trailing: _SectionActionButton(label: 'More details', onTap: _goToTasksTab),
                  ),
                ),
              ),
              const SizedBox(height: 16),
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
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: InsightTheme.surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: InsightTheme.line, width: 1.2),
                      boxShadow: kCardShadow,
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
                                const icons = [Icons.event_rounded, Icons.pending_actions_rounded, Icons.autorenew_rounded, Icons.check_circle_rounded];
                                final fractions = List.generate(labels.length, (i) {
                                  final count = counts[labels[i]] ?? 0;
                                  return total == 0 ? 0.0 : count / total;
                                });
                                final overdueCount = _allTasks.where((task) {
                                  if (task.category == 'Completed') return false;
                                  return task.scheduleUrgency == 'Overdue';
                                }).length;
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _CompletionRingChart(
                                      total: total,
                                      labels: labels,
                                      colors: colors,
                                      icons: icons,
                                      counts: List.generate(labels.length, (i) => counts[labels[i]] ?? 0),
                                      fractions: fractions,
                                    ),
                                    if (overdueCount > 0)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 14),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: InsightTheme.redTint,
                                            borderRadius: BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            '⚠️ $overdueCount overdue',
                                            style: InsightTheme.inter(11, w: FontWeight.w700, c: InsightTheme.redInk),
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              }),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // ----------------------------------------------------
              // 4. RECENT ACTIVITY
              // ----------------------------------------------------
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SpringSlide(
                  animation: springFor(8),
                  beginOffset: const Offset(0, 20),
                  child: const _SectionLabel(title: "RECENT ACTIVITY", icon: Icons.history_rounded, accentColor: InsightTheme.blue1),
                ),
              ),
              const SizedBox(height: 12),

              // Category filter — All / Tasks / Sync / Profile. Evenly
              // divided across the row (segmented-control style) so all
              // four fit without needing a horizontal scroll.
              SpringSlide(
                animation: springFor(8),
                beginOffset: const Offset(0, 20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
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
                          icon: Icons.checklist_rounded,
                          label: 'Tasks',
                          selected: _activityFilter == 'tasks',
                          onTap: () => setState(() => _activityFilter = 'tasks'),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _ActivityFilterChip(
                          icon: Icons.sync_rounded,
                          label: 'Sync',
                          selected: _activityFilter == 'sync',
                          onTap: () => setState(() => _activityFilter = 'sync'),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _ActivityFilterChip(
                          icon: Icons.person_rounded,
                          label: 'Profile',
                          selected: _activityFilter == 'profile',
                          onTap: () => setState(() => _activityFilter = 'profile'),
                        ),
                      ),
                    ],
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
                                    child: Container(width: 2, color: InsightTheme.ink3.withOpacity(0.15)),
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

/// PERFORMANCE NOTE: this used to be a plain Text fed by a `_now` field
/// on the main screen State, ticked every 30s via a Timer that called
/// setState on the WHOLE HomeDashboardScreen — meaning the entire
/// dashboard (assignments carousel, task list, activity feed) rebuilt
/// every 30 seconds just to update a clock, which is what was showing up
/// as scroll jank. Isolating the tick into this tiny widget means only
/// this Text rebuilds each minute; everything else is untouched.
class _LiveClock extends StatefulWidget {
  const _LiveClock();

  @override
  State<_LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<_LiveClock> {
  late DateTime _now = DateTime.now();
  Timer? _timer;

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
    return Text(text, style: InsightTheme.urbanist(19, w: FontWeight.w800, c: InsightTheme.ink, ls: -0.3));
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
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: InsightTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: InsightTheme.line, width: 1.5),
          boxShadow: kCardShadow,
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
  final IconData icon;
  final Color accentColor;
  final Widget? trailing;
  const _SectionLabel({required this.title, required this.icon, this.accentColor = InsightTheme.blue1, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon-in-tinted-square anchor — same treatment already used
            // for Recent Activity chips and the Completion legend, so the
            // header itself reads as a real component instead of a bare
            // line of muted caps text sitting on the page.
            Container(
              width: 26, height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 14, color: accentColor),
            ),
            const SizedBox(width: 8),
            // Bumped from ink3 (muted) to ink (full contrast) — the icon
            // now carries the "secondary/label" weight, so the text can
            // read as the actual heading it is.
            Text(title, style: InsightTheme.urbanist(12.5, w: FontWeight.w800, ls: 0.8, c: InsightTheme.ink)),
          ],
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Turns a "See All" / "More details" link into an actual small pill
/// button — a bare text link easily gets missed and reads as inert on a
/// page background; a tinted, tappable-looking pill signals affordance
/// the way the rest of the app's buttons already do.
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: InsightTheme.blueTint,
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

/// Recent Activity category filter pill (All / Tasks / Sync / Profile).
/// Selected state uses the app's real brand color (InsightTheme.blue1)
/// so it reads clearly against the dark theme; unselected pills sit on the
/// existing panel/line tokens rather than a second, invented surface color.
/// Height is fixed at 44px — UDAS §5.1 touch-target floor — even though the
/// visible pill reads slightly smaller, so the tap area itself never shrinks
/// below the minimum. Width now comes from its Expanded parent (segmented-
/// control layout), so content is centered rather than left-packed.
class _ActivityFilterChip extends StatelessWidget {
  final IconData? icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ActivityFilterChip({
    this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Material(
        color: selected ? InsightTheme.blue1 : InsightTheme.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? Colors.transparent : InsightTheme.line,
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 13, color: selected ? Colors.white : InsightTheme.ink3),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: InsightTheme.inter(
                    12,
                    w: FontWeight.w700,
                    c: selected ? Colors.white : InsightTheme.ink2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Concentric ring chart for Task Completion Flow (replaces the old
/// stacked progress-bar rows). One ring per category — Urgent (outer)
/// through Completed (inner) — each ring's filled arc is that category's
/// share of the total task count. Center shows the running total once,
/// so "tasks" never has to repeat per row. Legend below: label on top,
/// bold count under it, icon-in-circle at the bottom — per Master's spec.
class _CompletionRingChart extends StatefulWidget {
  final int total;
  final List<String> labels;
  final List<Color> colors;
  final List<IconData> icons;
  final List<int> counts;
  final List<double> fractions; // 0..1 each, share of total

  const _CompletionRingChart({
    required this.total,
    required this.labels,
    required this.colors,
    required this.icons,
    required this.counts,
    required this.fractions,
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

  static const double _outerSize = 176;
  static const double _ringStep = 38; // diameter decrement per ring, outer -> inner
  static const double _strokeWidth = 13;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Center(
          child: SizedBox(
            width: _outerSize,
            height: _outerSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                for (int i = 0; i < widget.labels.length; i++)
                  SizedBox(
                    width: _outerSize - (_ringStep * i),
                    height: _outerSize - (_ringStep * i),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: _filled ? widget.fractions[i].clamp(0.0, 1.0) : 0.0),
                      duration: const Duration(milliseconds: 750),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, _) => CircularProgressIndicator(
                        value: value <= 0 ? 0.001 : value,
                        strokeWidth: _strokeWidth,
                        strokeCap: StrokeCap.round,
                        backgroundColor: widget.colors[i].withOpacity(0.12),
                        valueColor: AlwaysStoppedAnimation<Color>(widget.colors[i]),
                      ),
                    ),
                  ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 54),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('${widget.total}', style: InsightTheme.urbanist(26, w: FontWeight.w800, c: InsightTheme.ink)),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Tasks', style: InsightTheme.openSans(12, w: FontWeight.w600, c: InsightTheme.ink3)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(widget.labels.length, (i) {
            return Expanded(
              child: Column(
                children: [
                  Text(
                    widget.labels[i],
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: InsightTheme.openSans(12, w: FontWeight.w700, c: InsightTheme.ink3),
                  ),
                  const SizedBox(height: 4),
                  Text('${widget.counts[i]}', style: InsightTheme.urbanist(17, w: FontWeight.w800, c: InsightTheme.ink)),
                  const SizedBox(height: 8),
                  // Same icon-in-circle treatment already used for Recent
                  // Activity tiles — reusing that pattern here too.
                  Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(
                      color: widget.colors[i].withOpacity(0.12),
                      shape: BoxShape.circle,
                      border: Border.all(color: widget.colors[i].withOpacity(0.3), width: 1.5),
                    ),
                    child: Icon(widget.icons[i], size: 15, color: widget.colors[i]),
                  ),
                ],
              ),
            );
          }),
        ),
      ],
    );
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
              GestureDetector(
                onTap: onPrevMonth,
                child: Container(
                  width: 30, height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: InsightTheme.surface2, borderRadius: BorderRadius.circular(9)),
                  child: Icon(Icons.chevron_left_rounded, size: 18, color: InsightTheme.ink2),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onNextMonth,
                child: Container(
                  width: 30, height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: InsightTheme.surface2, borderRadius: BorderRadius.circular(9)),
                  child: Icon(Icons.chevron_right_rounded, size: 18, color: InsightTheme.ink2),
                ),
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
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 1,
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
                onTap: () => onPick(month, day),
                behavior: HitTestBehavior.opaque,
                child: Center(
                  child: Container(
                    width: 34, height: 34,
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
                  ...selectedTasks.take(4).map((task) {
                    final color = dotColorForTask(task);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(top: 6, right: 8),
                            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  task.inspectionNo,
                                  style: InsightTheme.inter(12, w: FontWeight.w700, c: InsightTheme.ink),
                                ),
                                Text(
                                  task.name,
                                  style: InsightTheme.inter(11.5, w: FontWeight.w500, c: InsightTheme.ink2),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
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
                  color: widget.color.withOpacity(0.12),
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
                      Container(width: 32, height: 2, decoration: BoxDecoration(color: widget.color.withOpacity(0.5), borderRadius: BorderRadius.circular(2))),
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