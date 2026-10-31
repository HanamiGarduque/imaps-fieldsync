import 'dart:async';
import 'dart:math' show max;
import 'package:flutter/material.dart';
import '../../../core/widgets/sensitive_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState;

import '../../../core/models/user_profile.dart';
import '../../../core/models/task_submission.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/db_helper.dart';
import '../../../core/services/sync_outbox_service.dart';
import '../../../core/utils/calendar_date.dart';
import '../../tasks/screens/tasks_screen.dart';
import '../../tasks/widgets/task_notices.dart';
import '../../../core/navigation/parcel_detail_screen.dart';
import '../../profile_settings/screens/notifications_screen.dart';
import '../../profile_settings/screens/profile_edit_screen.dart';
import '../../../core/widgets/insight_bottom_nav.dart'; // kInsightBottomNavReserve (scroll padding) only
import '../../../core/layout/responsive_layout.dart';
import '../../../core/widgets/motion/spring_entrance.dart';
import '../../../core/widgets/motion/updating_tile.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/imaps_loading_indicator.dart';
import '../../../core/widgets/offline_banner.dart';
import '../../../core/widgets/task_sync_indicator.dart';
import '../widgets/active_assignments_folder_card.dart';
import '../../../core/theme/insight_theme.dart';

/// Whether a task belongs in the dashboard's Active Assignments carousel.
/// Uses the same canonical lifecycle categories as My Tasks.
bool isHomeDashboardActiveAssignment(TaskItem task) =>
    task.lifecycleCategory == TaskLifecycleCategory.pending ||
    task.lifecycleCategory == TaskLifecycleCategory.ongoing;

/// The existing dashboard display bucket for a task.
///
/// Started inspector-committed Visits remain Scheduled; the raw workflow status
/// is preserved by TaskItem's canonical presentation.
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
  const HomeDashboardScreen({
    super.key,
    required this.profile,
    this.onNavigateToTab,
    this.onProfileUpdated,
  });

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
  // Task Status Overview and the calendar's task-dots both need the
  // complete picture, so this is loaded alongside it in the same fetch
  // rather than issuing a second network/service call.
  List<TaskItem> _allTasks = [];
  Set<String> _deviceCompletedIds = {};
  // Keep real fetched metadata for selected normal entry; display is read-only.
  Map<String, Map<String, dynamic>> _entryJobs = {};
  // Durable saved progress per upcoming card, read from the exact-owner draft.
  Map<String, int> _cardSteps = {};
  bool _isLoadingTasks = true;

  /// Only the newest assignments load may write to this screen's state. A
  /// superseded request, or a late answer to one, is discarded instead of
  /// overwriting newer state.
  int _tasksRequestId = 0;

  /// Set while saved assignments are on screen and the remote refresh did not
  /// complete, so the carousel says what it is showing instead of claiming
  /// there is nothing.
  String? _savedDataNotice;
  TaskRefreshPhase _taskRefreshPhase = TaskRefreshPhase.checking;
  DateTime? _lastTaskRefreshAt;

  /// The authenticated owner whose assignments this page is currently showing.
  ///
  /// A genuine account change retires them instead of repurposing this
  /// still-mounted page for the next inspector; the previous owner's durable
  /// local rows are never deleted by that.
  String? _tasksOwner;

  StreamSubscription<AuthState>? _authSubscription;

  /// Bounded remote refresh — same 10 s service bound My Tasks uses.
  static const Duration _refreshTimeout = Duration(seconds: 10);

  int _unreadCount = 0;

  // The calendar selection is independent of the live Today/Note card.
  final DateTime _now = DateTime.now();
  late DateTime _calendarMonth = DateTime(_now.year, _now.month);
  late int _selectedDay = _now.day;
  bool _showFullCalendar = false;
  final ScrollController _homeScrollController = ScrollController();
  final GlobalKey _fullCalendarKey = GlobalKey();
  double? _calendarScrollOffsetBeforeExpand;

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
    final maxPage = (_upcomingTasks.length - 1)
        .clamp(0, double.infinity)
        .toDouble();
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
    PaintingBinding.instance.systemFonts.addListener(_onFontsChanged);
    _checkInitialConnectivity();

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      if (mounted) {
        final online = results.any((r) => r != ConnectivityResult.none);
        if (_isOnline != online) {
          setState(() {
            _isOnline = online;
          });
        }
      }
    });

    _authSubscription = SupabaseService.client.auth.onAuthStateChange.listen(
      (_) => _retireIfOwnerChanged(),
      onError: (Object _) => _retireIfOwnerChanged(),
    );
    SyncOutboxService.drainCompleted.addListener(_refreshSubmissionState);
    SyncOutboxService.progress.addListener(_refreshSubmissionState);
    _loadUpcomingTasks();
    _loadUnreadActivityCount();
  }

  /// A real account change invalidates what this mounted page is showing: the
  /// previous inspector's assignments are retired from the display (their
  /// durable local rows are left exactly as they are) and any navigation bound
  /// before the change is refused instead of opening another inspector's task.
  void _retireIfOwnerChanged() {
    if (!mounted) return;
    final current = DBHelper.currentInspectorId;
    if (current != null && current == _tasksOwner) return;
    if (_tasksOwner == null && _allTasks.isEmpty && _savedDataNotice == null) {
      return;
    }
    setState(() {
      _tasksRequestId++; // Retire every pending UI result with its owner.
      _tasksOwner = null;
      _allTasks = [];
      _deviceCompletedIds = {};
      _upcomingTasks = [];
      _entryJobs = {};
      _isLoadingTasks = false;
      _savedDataNotice = SavedDataNotice.ownerChanged;
      _taskRefreshPhase = TaskRefreshPhase.ownerChanged;
      _lastTaskRefreshAt = null;
    });
    ScaffoldMessenger.maybeOf(context)?.removeCurrentSnackBar();
    AppFeedback.dismiss();
  }

  // TextPainter-based layout must be measured again when runtime fonts load.
  void _onFontsChanged() {
    if (mounted) setState(() {});
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
    // refresh the unread notification badge.
    if (oldWidget.profile.fullName != widget.profile.fullName ||
        oldWidget.profile.avatarUrl != widget.profile.avatarUrl) {
      _loadUnreadActivityCount();
    }
  }

  @override
  void dispose() {
    SyncOutboxService.drainCompleted.removeListener(_refreshSubmissionState);
    SyncOutboxService.progress.removeListener(_refreshSubmissionState);
    _authSubscription?.cancel();
    _pageController.dispose();
    _homeScrollController.dispose();
    PaintingBinding.instance.systemFonts.removeListener(_onFontsChanged);
    _connectivitySubscription.cancel();
    disposeSpringEntrance();
    super.dispose();
  }

  /// The carousel population: exactly the filter and order the dashboard has
  /// always used.
  List<TaskItem> _upcomingFrom(
    List<TaskItem> tasks, [
    Set<String>? deviceCompleted,
  ]) {
    final completed = deviceCompleted ?? _deviceCompletedIds;
    final upcoming =
        tasks
            .where(
              (task) =>
                  isHomeDashboardActiveAssignment(task) &&
                  !completed.contains(task.id),
            )
            .toList()
          ..sort((a, b) {
            final aDate = _calendarDateForTask(a) ?? '9999-12-31';
            final bDate = _calendarDateForTask(b) ?? '9999-12-31';
            return aDate.compareTo(bDate);
          });
    return upcoming.take(6).toList();
  }

  Set<String> _deviceCompletions(TaskPresentationSnapshot snapshot) {
    final activeIds = {
      for (final job in snapshot.jobs)
        if (mapTaskStatusToLifecycle(job['status'] as String?) !=
                TaskLifecycleCategory.completed &&
            mapTaskStatusToLifecycle(job['status'] as String?) !=
                TaskLifecycleCategory.unknown)
          job['id'],
    };
    return {
      for (final row in snapshot.submissions)
        if (activeIds.contains(row['job_id']))
          TaskSubmission.fromRow(row).jobId,
    };
  }

  List<TaskItem> _snapshotTasks(TaskPresentationSnapshot snapshot) => [
    for (final row in snapshot.jobs)
      if (_entryJobs[row['id']] case final remote?)
        TaskItem.fromJob({
          ...remote,
          'status': row['status'],
          'current_step': max(
            (remote['current_step'] as num?)?.toInt() ?? 0,
            (row['current_step'] as num?)?.toInt() ?? 0,
          ),
        })
      else
        TaskItem.fromCachedJob(row),
  ];

  /// Final intent and receipts refresh from the same owner-scoped SQLite
  /// snapshot as My Tasks; no network request or invented remote completion.
  Future<void> _refreshSubmissionState() async {
    final owner = _tasksOwner;
    final request = _tasksRequestId;
    if (owner == null || owner != DBHelper.currentInspectorId) return;
    try {
      final snapshot = await DBHelper.getTaskPresentationSnapshot();
      if (!mounted || request != _tasksRequestId) return;
      if (owner != DBHelper.currentInspectorId) {
        _retireIfOwnerChanged();
        return;
      }
      final completed = _deviceCompletions(snapshot);
      final tasks = _snapshotTasks(snapshot);
      setState(() {
        _deviceCompletedIds = completed;
        _allTasks = tasks;
        _upcomingTasks = _upcomingFrom(tasks, completed);
      });
    } catch (_) {
      // Keep the last known snapshot; never turn a cache failure into success.
      if (mounted &&
          request == _tasksRequestId &&
          owner == DBHelper.currentInspectorId) {
        setState(() => _savedDataNotice = SavedDataNotice.cacheReadFailed);
      }
    }
  }

  /// Saved progress for the upcoming cards: the task's own counters joined
  /// with the exact-owner SQLite draft, so a reopened assignment resumes at
  /// the step it reached instead of resetting to the fetched value.
  Future<Map<String, int>> _savedCardSteps(List<TaskItem> upcoming) async {
    final steps = <String, int>{};
    for (final task in upcoming.take(6)) {
      try {
        final draft = await DBHelper.getLocalInspection(task.id);
        DBHelper.requireSameInspector(widget.profile.id);
        steps[task.id] = max(
          max(task.currentStep, task.derivedHighestStep),
          (draft?['current_step'] as num?)?.toInt() ?? 0,
        ).clamp(0, 6);
      } catch (e) {
        debugPrint('Saved assignment progress unavailable: ${e.runtimeType}');
      }
    }
    return steps;
  }

  /// Cache first, refresh second — the same contract My Tasks uses.
  ///
  /// 1. The owner-scoped cache renders immediately and is never gated on a
  ///    connectivity indication, so a weak, captive or dead network cannot turn
  ///    into an indefinite spinner while saved assignments sit unread. The
  ///    moment saved rows are shown they are identified as saved data.
  /// 2. The refresh is bounded, its commit is ordered per owner across every
  ///    screen, and no failed, timed-out or superseded answer can erase what is
  ///    on screen or leave the carousel claiming there is nothing.
  /// 3. Reading the local store is as fallible as any other platform call: a
  ///    damaged or unavailable store reaches a recoverable state instead of an
  ///    unhandled future or a stuck spinner, and never deletes the row.
  Future<void> _loadUpcomingTasks() async {
    final requestId = ++_tasksRequestId;
    final owner = DBHelper.currentInspectorId;
    setState(() => _taskRefreshPhase = TaskRefreshPhase.checking);

    List<Map<String, dynamic>> cached = const [];
    var deviceCompleted = <String>{};
    var cacheFailed = false;
    if (owner != null && owner.isNotEmpty) {
      try {
        final snapshot = await DBHelper.getTaskPresentationSnapshot();
        cached = snapshot.jobs;
        deviceCompleted = _deviceCompletions(snapshot);
      } catch (e) {
        debugPrint('[HOME] saved task read failed: $e');
        cacheFailed = true;
      }
    }
    List<TaskItem>? parsed;
    if (cached.isNotEmpty) {
      try {
        parsed = cached.map(TaskItem.fromCachedJob).toList();
      } catch (e) {
        debugPrint('[HOME] saved task rows unreadable: $e');
        cacheFailed = true;
      }
    }
    if (!mounted || requestId != _tasksRequestId) return;

    // Saved-step reads happen before the cache paint, so a reopened draft is
    // on screen from the first frame instead of only after a refresh answers.
    final cardSteps = parsed == null
        ? <String, int>{}
        : await _savedCardSteps(_upcomingFrom(parsed, deviceCompleted));
    if (!mounted || requestId != _tasksRequestId) return;

    setState(() {
      _cardSteps = cardSteps;
      _deviceCompletedIds = deviceCompleted;
      if (parsed != null) {
        _allTasks = parsed;
        _upcomingTasks = _upcomingFrom(parsed);
        _isLoadingTasks = false;
        // Identified as saved from the first frame it is shown, not only once
        // the refresh has finished or failed.
        _savedDataNotice = SavedDataNotice.refreshing;
      } else if (cacheFailed) {
        _isLoadingTasks = false;
        _upcomingTasks = [];
        _savedDataNotice = SavedDataNotice.cacheReadFailed;
        _taskRefreshPhase = TaskRefreshPhase.cacheUnavailable;
      } else if (_allTasks.isEmpty) {
        // Nothing is known yet, so "loading" is the only honest state.
        _isLoadingTasks = true;
      }
    });

    // The owner is recorded before any read: rows rendered from the cache
    // while offline still belong to this inspector and stay openable.
    if (owner != null && owner.isNotEmpty) {
      _tasksOwner = owner;
    }

    if (!await _hasConnectivity()) {
      if (!mounted || requestId != _tasksRequestId) return;
      setState(() {
        // Unchanged from the original offline path: entry detail is refetched
        // by the detail screen rather than served from a remembered online row.
        _entryJobs = {};
        _isLoadingTasks = false;
        _taskRefreshPhase = cacheFailed && parsed == null
            ? TaskRefreshPhase.cacheUnavailable
            : TaskRefreshPhase.offline;
        if (parsed != null || _upcomingTasks.isNotEmpty) {
          _savedDataNotice = SavedDataNotice.offline;
        } else if (cacheFailed) {
          _savedDataNotice = SavedDataNotice.cacheReadFailed;
        } else {
          // An empty device is not proof that there is no work.
          _savedDataNotice = SavedDataNotice.noCacheOffline;
        }
      });
      return;
    }

    if (owner == null || owner.isEmpty) {
      // No authenticated owner: nothing may be fetched, written, or shown.
      if (!mounted || requestId != _tasksRequestId) return;
      setState(() {
        _allTasks = [];
        _upcomingTasks = [];
        _entryJobs = {};
        _isLoadingTasks = false;
        _savedDataNotice = SavedDataNotice.ownerChanged;
        _taskRefreshPhase = TaskRefreshPhase.ownerChanged;
        _lastTaskRefreshAt = null;
      });
      return;
    }
    // Captured before the remote read, so the shared commit boundary can reject
    // a snapshot that another screen or a later load has already superseded.
    final refresh = DBHelper.beginJobsRefresh();
    try {
      final jobs = await SupabaseService.fetchMyJobs().timeout(_refreshTimeout);
      if (!mounted || requestId != _tasksRequestId) return;
      // An answer that arrives after the device changed accounts belongs to
      // the previous account: it is never rendered and never cached.
      if (DBHelper.currentInspectorId != owner) {
        _retireIfOwnerChanged();
        return;
      }
      final applied = await DBHelper.cacheJobs(jobs, refresh: refresh);
      if (!mounted || requestId != _tasksRequestId) return;
      if (DBHelper.currentInspectorId != owner) {
        _retireIfOwnerChanged();
        return;
      }
      if (!applied) {
        // A newer snapshot already reached this device, so this answer is
        // never presented as the current picture.
        setState(() {
          _savedDataNotice = SavedDataNotice.saved;
          _taskRefreshPhase = TaskRefreshPhase.saved;
          _isLoadingTasks = false;
        });
        return;
      }
      _entryJobs = {for (final job in jobs) job['id'] as String: job};
      final snapshot = await DBHelper.getTaskPresentationSnapshot();
      if (!mounted || requestId != _tasksRequestId) return;
      if (DBHelper.currentInspectorId != owner) {
        _retireIfOwnerChanged();
        return;
      }
      final completed = _deviceCompletions(snapshot);
      final tasks = _snapshotTasks(snapshot);
      final cardSteps = await _savedCardSteps(_upcomingFrom(tasks, completed));
      if (!mounted || requestId != _tasksRequestId) return;
      setState(() {
        _allTasks = tasks;
        _deviceCompletedIds = completed;
        _upcomingTasks = _upcomingFrom(tasks);
        _cardSteps = cardSteps;
        _isLoadingTasks = false;
        _savedDataNotice = null;
        _taskRefreshPhase = TaskRefreshPhase.fresh;
        _lastTaskRefreshAt = DateTime.now();
      });
    } catch (e) {
      debugPrint('Assignment refresh failed (saved data kept): $e');
      if (!mounted || requestId != _tasksRequestId) return;
      setState(() {
        _isLoadingTasks = false;
        _taskRefreshPhase = cacheFailed && parsed == null
            ? TaskRefreshPhase.cacheUnavailable
            : TaskRefreshPhase.failed;
        if (parsed != null || _upcomingTasks.isNotEmpty) {
          _savedDataNotice = SavedDataNotice.refreshFailed;
        } else {
          _savedDataNotice = cacheFailed
              ? SavedDataNotice.cacheReadFailed
              : SavedDataNotice.noCacheFailure;
        }
      });
    }
  }

  void _retryTaskRefresh() {
    if (!mounted) return;
    if (_tasksOwner == null || _tasksOwner != DBHelper.currentInspectorId) {
      _retireIfOwnerChanged();
      return;
    }
    _loadUpcomingTasks();
  }

  /// Retry is offered only where it can change the outcome: a terminal state
  /// with nothing usable on screen. While a refresh is outstanding, or while
  /// saved rows are being shown, there is nothing to retry yet.
  VoidCallback? get _noticeRetry {
    final notice = _savedDataNotice;
    if (notice == SavedDataNotice.cacheReadFailed ||
        notice == SavedDataNotice.noCacheFailure ||
        notice == SavedDataNotice.noCacheOffline) {
      return _retryTaskRefresh;
    }
    return null;
  }

  /// Connectivity is advisory only: it chooses the wording of the notice and
  /// never decides what is rendered. The read is bounded, so a hanging
  /// platform call cannot hold the screen.
  Future<bool> _hasConnectivity() async {
    try {
      final dynamic result = await Connectivity().checkConnectivity().timeout(
        const Duration(milliseconds: 500),
      );
      if (result is ConnectivityResult) {
        return result != ConnectivityResult.none;
      }
      if (result is List) {
        return result.any((status) => status != ConnectivityResult.none);
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadUnreadActivityCount() async {
    try {
      final unread = await SupabaseService.fetchUnreadActivityCount();
      if (mounted) setState(() => _unreadCount = unread);
    } catch (e) {
      debugPrint('Error loading unread notification count: $e');
    }
  }

  static const _monthNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  static const _fullMonthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  String _formatScheduledDate(String isoDate) {
    final d = parseLocalCalendarDate(isoDate);
    return d == null
        ? isoDate
        : '${_monthNames[d.month - 1]} ${d.day}, ${d.year}';
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
    final counts = {'Scheduled': 0, 'Pending': 0, 'Ongoing': 0, 'Completed': 0};
    for (final task in _allTasks) {
      final presentationCategory = _deviceCompletedIds.contains(task.id)
          ? 'Completed'
          : homeDashboardTaskPresentationCategory(task);
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
    return _deviceCompletedIds.contains(task.id) ? null : task.activeDate;
  }

  Set<int> _taskDaysInMonth(DateTime month) {
    final days = <int>{};
    for (final t in _allTasks) {
      final calendarDate = _calendarDateForTask(t);
      if (calendarDate == null) continue;
      try {
        final d = parseLocalCalendarDate(calendarDate);
        if (d == null) continue;
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
        final d = parseLocalCalendarDate(calendarDate);
        if (d == null) continue;
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
    final p = task.presentation;
    if (p.isOverdue) return 0;
    final date = p.activeDay;
    if (date == null) return 2;
    final days = calendarDaysBetween(DateTime.now(), date);
    if (days <= 1) return 0;
    if (days <= 3) return 1;
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
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TasksScreen(profile: widget.profile)),
      );
    }
  }

  String _formatShortId(String fullId) {
    if (fullId.length > 8) return fullId.substring(0, 8).toUpperCase();
    return fullId.toUpperCase();
  }

  int _calendarScrollRequest = 0;

  void _toggleFullCalendar() {
    final opening = !_showFullCalendar;
    final request = ++_calendarScrollRequest;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);

    if (opening) {
      _calendarScrollOffsetBeforeExpand = _homeScrollController.hasClients
          ? _homeScrollController.offset
          : null;
      setState(() => _showFullCalendar = true);
      unawaited(
        Future<void>.delayed(
          reducedMotion ? Duration.zero : const Duration(milliseconds: 420),
          () {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted ||
                  request != _calendarScrollRequest ||
                  !_showFullCalendar ||
                  !_homeScrollController.hasClients) {
                return;
              }
              final calendarContext = _fullCalendarKey.currentContext;
              if (calendarContext == null || !calendarContext.mounted) return;
              unawaited(
                Scrollable.ensureVisible(
                  calendarContext,
                  alignment: 0,
                  duration: reducedMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 280),
                  curve: Curves.easeInOutCubic,
                ),
              );
            });
          },
        ),
      );
      return;
    }

    setState(() => _showFullCalendar = false);
    final previousOffset = _calendarScrollOffsetBeforeExpand;
    _calendarScrollOffsetBeforeExpand = null;
    if (previousOffset == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          request != _calendarScrollRequest ||
          _showFullCalendar ||
          !_homeScrollController.hasClients) {
        return;
      }
      final position = _homeScrollController.position;
      final target = previousOffset.clamp(0.0, position.maxScrollExtent);
      if (reducedMotion) {
        _homeScrollController.jumpTo(target);
      } else {
        _homeScrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeInOutCubic,
        );
      }
    });
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
    final calendarMotion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 320);

    return SensitiveScreen(
      child: Scaffold(
        backgroundColor: InsightTheme.bg,
        extendBody: true,
        body: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            controller: _homeScrollController,
            padding: EdgeInsets.only(
              bottom:
                  kInsightBottomNavReserve +
                  MediaQuery.viewPaddingOf(context).bottom,
            ),
            child: ConstrainedContent.wide(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ----------------------------------------------------
                  // Separate white surfaces follow the v3 section grouping.
                  // ----------------------------------------------------
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Container(
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final titleStyle = InsightTheme.urbanist(
                                    16,
                                    w: FontWeight.w700,
                                    c: InsightTheme.ink,
                                  );
                                  final titleSize = TextPainter(
                                    text: TextSpan(
                                      text: 'FieldSync',
                                      style: titleStyle,
                                    ),
                                    textScaler: MediaQuery.textScalerOf(
                                      context,
                                    ),
                                    textDirection: Directionality.of(context),
                                  )..layout();
                                  final fitsOneRow =
                                      constraints.maxWidth >=
                                      60 + titleSize.width + 24 + 48;
                                  titleSize.dispose();
                                  final identity = Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Semantics(
                                        button: true,
                                        label: 'Edit profile',
                                        child: GestureDetector(
                                          onTap: () async {
                                            final result =
                                                await Navigator.push<
                                                  UserProfile?
                                                >(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        ProfileEditScreen(
                                                          profile:
                                                              widget.profile,
                                                        ),
                                                  ),
                                                );
                                            if (result != null && mounted) {
                                              widget.onProfileUpdated?.call(
                                                result,
                                              );
                                            }
                                          },
                                          child: Container(
                                            width: 48,
                                            height: 48,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: InsightTheme.blue1,
                                              border: Border.all(
                                                color: InsightTheme.blue1,
                                                width: 2,
                                              ),
                                            ),
                                            child: ClipOval(
                                              child:
                                                  widget.profile.avatarUrl !=
                                                          null &&
                                                      widget
                                                          .profile
                                                          .avatarUrl!
                                                          .isNotEmpty
                                                  ? Image.network(
                                                      widget.profile.avatarUrl!,
                                                      width: 44,
                                                      height: 44,
                                                      fit: BoxFit.cover,
                                                      errorBuilder:
                                                          (
                                                            context,
                                                            error,
                                                            stackTrace,
                                                          ) => Center(
                                                            child: Text(
                                                              initials,
                                                              style:
                                                                  InsightTheme.urbanist(
                                                                    13,
                                                                    w: FontWeight
                                                                        .w700,
                                                                    c: Colors
                                                                        .white,
                                                                  ),
                                                            ),
                                                          ),
                                                    )
                                                  : Center(
                                                      child: Text(
                                                        initials,
                                                        style:
                                                            InsightTheme.urbanist(
                                                              13,
                                                              w: FontWeight
                                                                  .w700,
                                                              c: Colors.white,
                                                            ),
                                                      ),
                                                    ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('FieldSync', style: titleStyle),
                                          const SizedBox(height: 4),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                width: 6,
                                                height: 6,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: _isOnline
                                                      ? InsightTheme.green
                                                      : InsightTheme.red,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                _isOnline
                                                    ? 'Online'
                                                    : 'Offline',
                                                style: InsightTheme.inter(
                                                  12,
                                                  w: FontWeight.w600,
                                                  c: _isOnline
                                                      ? InsightTheme.greenInk
                                                      : InsightTheme.redInk,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  );
                                  final notification = _NotificationBtn(
                                    hasUnread: _unreadCount > 0,
                                    onTap: () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const NotificationsScreen(),
                                        ),
                                      );
                                      // Notifications screen marks things read on its own
                                      // timeline — resync the badge once the inspector
                                      // backs out of it instead of leaving it stale.
                                      _loadUnreadActivityCount();
                                    },
                                  );
                                  if (fitsOneRow) {
                                    return Row(
                                      children: [
                                        identity,
                                        const Spacer(),
                                        notification,
                                      ],
                                    );
                                  }
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      identity,
                                      const SizedBox(height: 8),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: notification,
                                      ),
                                    ],
                                  );
                                },
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
                                  Text(
                                    greeting,
                                    style: InsightTheme.inter(
                                      13,
                                      w: FontWeight.w500,
                                      c: InsightTheme.ink3,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    firstName,
                                    style: InsightTheme.urbanist(
                                      24,
                                      w: FontWeight.w700,
                                      c: InsightTheme.ink,
                                      ls: -0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // ----------------------------------------------------
                  // 2. ACTIVE ASSIGNMENTS
                  // ----------------------------------------------------
                  // The section surface follows the gutters; the interactive
                  // carousel uses the full width, including its next-card peek.
                  Stack(
                    children: [
                      Positioned.fill(
                        left: 20,
                        right: 20,
                        child: Container(
                          key: const ValueKey('assignments_section'),
                          decoration: BoxDecoration(
                            color: InsightTheme.surface,
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 36),
                            child: SpringSlide(
                              animation: springFor(1),
                              beginOffset: const Offset(0, 20),
                              child: _SectionLabel(
                                title: "Active Assignments",
                                titleAction: TaskSyncIndicator(
                                  key: const ValueKey('task-sync-indicator'),
                                  phase: _taskRefreshPhase,
                                  hasSavedTasks: _allTasks.isNotEmpty,
                                  lastChecked: _lastTaskRefreshAt,
                                  onRetry: _retryTaskRefresh,
                                ),
                                trailing: _SectionActionButton(
                                  label: 'See All',
                                  onTap: _goToTasksTab,
                                ),
                              ),
                            ),
                          ),

                          SpringSlide(
                            animation: springFor(2),
                            beginOffset: const Offset(70, 0),
                            child: SizedBox(
                              height:
                                  244 *
                                  max(
                                    1,
                                    MediaQuery.textScalerOf(context).scale(12) /
                                        12,
                                  ),
                              child: _isLoadingTasks
                                  ? const Center(
                                      child: ImapsLoadingIndicator(size: 50),
                                    )
                                  : _upcomingTasks.isEmpty
                                  ? (_savedDataNotice != null
                                        // Never claim emptiness when the refresh failed:
                                        // "nothing" is only ever stated once it is known.
                                        ? Center(
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 36,
                                                  ),
                                              child: SavedDataNotice(
                                                message: _savedDataNotice!,
                                                onRetry: _noticeRetry,
                                              ),
                                            ),
                                          )
                                        : Center(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.assignment_outlined,
                                                  size: 36,
                                                  color: InsightTheme.ink3,
                                                ),
                                                const SizedBox(height: 10),
                                                Text(
                                                  'No active assignments.',
                                                  style: InsightTheme.openSans(
                                                    13,
                                                    c: InsightTheme.ink2,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ))
                                  : PageView.builder(
                                      controller: _pageController,
                                      // Reuses the same controller; only the visible
                                      // fraction adapts, so the page index and the
                                      // spring-scale effect keep working unchanged.
                                      itemCount: _upcomingTasks.length,
                                      clipBehavior: Clip.none,
                                      onPageChanged: (index) => setState(
                                        () => _currentCardIndex = index,
                                      ),
                                      itemBuilder: (context, index) {
                                        return AnimatedBuilder(
                                          animation: _pageController,
                                          builder: (context, child) {
                                            double value = 1.0;
                                            if (_pageController
                                                .position
                                                .haveDimensions) {
                                              value =
                                                  _pageController.page! - index;
                                              value = (1 - (value.abs() * 0.08))
                                                  .clamp(0.92, 1.0);
                                            } else {
                                              value = (index == 0) ? 1.0 : 0.92;
                                            }
                                            return Center(
                                              child: SizedBox(
                                                height:
                                                    Curves.easeOut.transform(
                                                      value,
                                                    ) *
                                                    220 *
                                                    max(
                                                      1,
                                                      MediaQuery.textScalerOf(
                                                            context,
                                                          ).scale(12) /
                                                          12,
                                                    ),
                                                width: double.infinity,
                                                child: child,
                                              ),
                                            );
                                          },
                                          child: Container(
                                            margin: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                            ),
                                            child: UpdatingTile(
                                              itemKey: _upcomingTasks[index].id,
                                              signature: Object.hash(
                                                _upcomingTasks[index]
                                                    .scheduledDate,
                                                _upcomingTasks[index].location,
                                                _upcomingTasks[index]
                                                    .applicationType,
                                                _upcomingTasks[index]
                                                    .landUseClass,
                                                _upcomingTasks[index].status,
                                              ),
                                              child: ActiveAssignmentsFolderCard(
                                                // IDs remain in Task Details and are no
                                                // longer printed on the carousel artwork.
                                                inspectionId: _formatShortId(
                                                  _upcomingTasks[index].id,
                                                ),
                                                referenceNo:
                                                    _upcomingTasks[index]
                                                        .inspectionNo,
                                                date:
                                                    _calendarDateForTask(
                                                          _upcomingTasks[index],
                                                        ) !=
                                                        null
                                                    ? _formatScheduledDate(
                                                        _calendarDateForTask(
                                                          _upcomingTasks[index],
                                                        )!,
                                                      )
                                                    : '—',
                                                dateLabel:
                                                    _calendarDateForTask(
                                                          _upcomingTasks[index],
                                                        ) ==
                                                        null
                                                    ? null
                                                    : _upcomingTasks[index]
                                                              .pendingSection ==
                                                          PendingTaskSection
                                                              .scheduled
                                                    ? 'Visit Date'
                                                    : 'Deadline',
                                                // The durable draft step when it could be
                                                // read; the fetched counters otherwise.
                                                savedStep:
                                                    _cardSteps[_upcomingTasks[index]
                                                        .id] ??
                                                    (_upcomingTasks[index]
                                                                    .currentStep >
                                                                0
                                                            ? _upcomingTasks[index]
                                                                  .currentStep
                                                            : _upcomingTasks[index]
                                                                  .derivedHighestStep)
                                                        .clamp(0, 6),
                                                location: _upcomingTasks[index]
                                                    .location,
                                                applicantName:
                                                    _upcomingTasks[index].name,
                                                applicationType:
                                                    _upcomingTasks[index]
                                                            .applicationType
                                                            ?.isNotEmpty ==
                                                        true
                                                    ? _upcomingTasks[index]
                                                          .applicationType!
                                                    : _upcomingTasks[index]
                                                          .landUseClass,
                                                lifecycleCategory:
                                                    _upcomingTasks[index]
                                                        .lifecycleCategory,
                                                pendingSection:
                                                    _upcomingTasks[index]
                                                        .pendingSection,
                                                onTap: () {
                                                  // A callback bound before an account
                                                  // change must not open another
                                                  // inspector's task from this page.
                                                  final current = DBHelper
                                                      .currentInspectorId;
                                                  if (!mounted ||
                                                      current == null ||
                                                      current != _tasksOwner) {
                                                    _retireIfOwnerChanged();
                                                    return;
                                                  }
                                                  Navigator.of(context).push(
                                                    MaterialPageRoute(
                                                      builder: (_) => ParcelDetailScreen(
                                                        task:
                                                            _upcomingTasks[index],
                                                        fetchedJob:
                                                            _entryJobs[_upcomingTasks[index]
                                                                .id],
                                                        relatedRounds: _allTasks
                                                            .where(
                                                              _upcomingTasks[index]
                                                                  .sameApplicationAs,
                                                            )
                                                            .toList(),
                                                      ),
                                                    ),
                                                  );
                                                },
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
                              children: List.generate(_upcomingTasks.length, (
                                index,
                              ) {
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  height: 6,
                                  width: _currentCardIndex == index ? 24 : 8,
                                  decoration: BoxDecoration(
                                    color: _currentCardIndex == index
                                        ? InsightTheme.blue1
                                        : InsightTheme.ink3.withValues(
                                            alpha: 0.3,
                                          ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                );
                              }),
                            ),
                          if (!_isLoadingTasks && _upcomingTasks.isNotEmpty)
                            Builder(
                              builder: (context) {
                                final task =
                                    _upcomingTasks[_currentCardIndex.clamp(
                                      0,
                                      _upcomingTasks.length - 1,
                                    )];
                                return TaskNoticeSummary(
                                  key: ValueKey('home_task_notices_${task.id}'),
                                  presentation: task.presentation,
                                  applicantName: task.name,
                                  inset: true,
                                  onDetails: () {
                                    final current = DBHelper.currentInspectorId;
                                    if (!mounted ||
                                        current == null ||
                                        current != _tasksOwner) {
                                      _retireIfOwnerChanged();
                                      return;
                                    }
                                    showTaskNoticeDetails(
                                      context,
                                      presentation: task.presentation,
                                      applicantName: task.name,
                                      referenceNumber: task.inspectionNo,
                                      roundLabel: task.roundLabel,
                                    );
                                  },
                                );
                              },
                            ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      key: const ValueKey('calendar_section'),
                      padding: const EdgeInsets.only(top: 12, bottom: 4),
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
                              child: _HomeCalendarPager(
                                key: ValueKey(
                                  'home_calendar_${widget.profile.id}',
                                ),
                                userId: widget.profile.id,
                                month: _calendarMonth,
                                selectedDay: _selectedDay,
                                tasksByDay: tasksByDay,
                                dotColorForTask: _calendarDotColor,
                                onPick: _onFullCalendarPick,
                                onPreviousMonth: () => setState(
                                  () => _calendarMonth = DateTime(
                                    _calendarMonth.year,
                                    _calendarMonth.month - 1,
                                  ),
                                ),
                                onNextMonth: () => setState(
                                  () => _calendarMonth = DateTime(
                                    _calendarMonth.year,
                                    _calendarMonth.month + 1,
                                  ),
                                ),
                                timeDateView: _TodayScheduleCard(
                                  tasksForDate: (date) =>
                                      _tasksByDayInMonth(date)[date.day] ??
                                      const <TaskItem>[],
                                  dotColorForTask: _calendarDotColor,
                                  isLoading: _isLoadingTasks,
                                ),
                              ),
                            ),
                          ),
                          Center(
                            child: TextButton(
                              onPressed: _toggleFullCalendar,
                              child: Tooltip(
                                message: _showFullCalendar
                                    ? 'Hide full calendar'
                                    : 'Show full calendar',
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Calendar',
                                      style: InsightTheme.inter(
                                        12,
                                        w: FontWeight.w600,
                                        c: InsightTheme.blueInk,
                                      ),
                                    ),
                                    AnimatedRotation(
                                      turns: _showFullCalendar ? 0.5 : 0,
                                      duration: calendarMotion,
                                      child: const Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        size: 18,
                                        color: InsightTheme.blue1,
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
                  ),
                  _SuspendedMonthCalendar(
                    visible: _showFullCalendar,
                    child: KeyedSubtree(
                      key: const ValueKey('full_calendar'),
                      child: Padding(
                        key: _fullCalendarKey,
                        // The monthly grid fits the card's available
                        // width, keeping the surrounding Home gutter.
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: ConstrainedContent(
                          maxWidth: 560,
                          child: _CalendarLanyard(
                            child: _InlineFullCalendarCard(
                              month: _calendarMonth,
                              selectedDay: _selectedDay,
                              taskDaysForMonth: _taskDaysInMonth,
                              tasksByDayInMonth: tasksByDay,
                              dotColorForTask: _calendarDotColor,
                              onPrevMonth: () => setState(
                                () => _calendarMonth = DateTime(
                                  _calendarMonth.year,
                                  _calendarMonth.month - 1,
                                ),
                              ),
                              onNextMonth: () => setState(
                                () => _calendarMonth = DateTime(
                                  _calendarMonth.year,
                                  _calendarMonth.month + 1,
                                ),
                              ),
                              onPick: _onFullCalendarPick,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ----------------------------------------------------
                  // 3. TASK STATUS OVERVIEW
                  // ----------------------------------------------------
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SpringSlide(
                      animation: springFor(3),
                      beginOffset: const Offset(0, 24),
                      child: Builder(
                        builder: (context) {
                          final counts = _completionCounts;
                          final total = counts.values.fold<int>(
                            0,
                            (a, b) => a + b,
                          );
                          const labels = [
                            'Scheduled',
                            'Pending',
                            'Ongoing',
                            'Completed',
                          ];
                          const colors = [
                            InsightTheme.orange,
                            InsightTheme.blue1,
                            InsightTheme.lightBlue,
                            InsightTheme.green,
                          ];
                          final overdueCount = _allTasks.where((task) {
                            if (task.category == 'Completed' ||
                                _deviceCompletedIds.contains(task.id)) {
                              return false;
                            }
                            return task.scheduleUrgency == 'Overdue';
                          }).length;
                          return _TaskCompletionBubbleChart(
                            total: total,
                            labels: labels,
                            colors: colors,
                            counts: List.generate(
                              labels.length,
                              (i) => counts[labels[i]] ?? 0,
                            ),
                            overdueCount: overdueCount,
                            isLoading: _isLoadingTasks,
                            hasTasks: _allTasks.isNotEmpty,
                            onMoreDetails: _goToTasksTab,
                          );
                        },
                      ),
                    ),
                  ),
                  if (_deviceCompletedIds.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: Text(
                        '${_deviceCompletedIds.length} completed on device — awaiting server acceptance.',
                        style: InsightTheme.inter(
                          12,
                          c: InsightTheme.orangeInk,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
        // Bottom navigation now lives solely in MainShellScreen (the app
        // shell). This screen no longer renders its own nav bar — see
        // NAVIGATION_REFACTOR.md for why the duplicate, per-page nav bar
        // was removed.
      ),
    );
  }
}

/// ==================================================================
/// COMPONENT WIDGETS
/// ==================================================================

/// Keeps clock ticks local and uses the full calendar's date mapping for Today.
/// The day row owns its drag; the surrounding PageView handles header/card
/// swipes. Its controller is restored once, never reset by data refreshes.
class _HomeCalendarPager extends StatefulWidget {
  final String userId;
  final DateTime month;
  final int selectedDay;
  final Map<int, List<TaskItem>> tasksByDay;
  final Color Function(TaskItem) dotColorForTask;
  final void Function(DateTime, int) onPick;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final Widget timeDateView;

  const _HomeCalendarPager({
    super.key,
    required this.userId,
    required this.month,
    required this.selectedDay,
    required this.tasksByDay,
    required this.dotColorForTask,
    required this.onPick,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.timeDateView,
  });

  @override
  State<_HomeCalendarPager> createState() => _HomeCalendarPagerState();
}

class _HomeCalendarPagerState extends State<_HomeCalendarPager> {
  PageController? _views;
  ScrollController? _dates;
  SharedPreferences? _preferences;
  int _view = 0;
  double _dayExtent = 0;
  double _rowWidth = 0;
  bool _alignDates = false;
  String get _preferenceKey => 'home_calendar_view_${widget.userId}';
  Duration get _motion => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 280);

  @override
  void initState() {
    super.initState();
    _restoreView();
  }

  Future<void> _restoreView() async {
    SharedPreferences? preferences;
    var view = 0;
    try {
      preferences = await SharedPreferences.getInstance();
      view = preferences.getInt(_preferenceKey) == 1 ? 1 : 0;
    } catch (error) {
      debugPrint('Unable to restore Home calendar view: $error');
    }
    if (!mounted) return;
    setState(() {
      _preferences = preferences;
      _view = view;
      _views = PageController(initialPage: view);
    });
  }

  Future<void> _rememberView(int view) async {
    try {
      await _preferences?.setInt(_preferenceKey, view);
    } catch (error) {
      debugPrint('Unable to save Home calendar view: $error');
    }
  }

  void _switchView() {
    if (_views?.hasClients != true) return;
    final next = 1 - _view;
    if (_motion == Duration.zero) {
      _views!.jumpToPage(next);
    } else {
      _views!.animateToPage(
        next,
        duration: _motion,
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void didUpdateWidget(_HomeCalendarPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.month != widget.month ||
        oldWidget.selectedDay != widget.selectedDay) {
      _alignDates = true;
    }
  }

  @override
  void dispose() {
    _views?.dispose();
    _dates?.dispose();
    super.dispose();
  }

  double _selectedOffset(int days) =>
      ((widget.selectedDay.clamp(1, days) - 1) * _dayExtent -
              (_rowWidth - _dayExtent) / 2)
          .clamp(
            0.0,
            (days * _dayExtent - _rowWidth).clamp(0.0, double.infinity),
          );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        Size measure(
          String text,
          TextStyle style, {
          double width = double.infinity,
        }) {
          final painter = TextPainter(
            text: TextSpan(
              text: text,
              style: DefaultTextStyle.of(context).style.merge(style),
            ),
            textDirection: Directionality.of(context),
            textScaler: scaler,
          )..layout(maxWidth: width);
          final size = painter.size;
          painter.dispose();
          return size;
        }

        final now = DateTime.now();
        final date =
            TextPainter(
              text: TextSpan(
                style: DefaultTextStyle.of(context).style,
                children: [
                  TextSpan(
                    text: '${now.day}\n',
                    style: InsightTheme.urbanist(30, w: FontWeight.w800),
                  ),
                  TextSpan(
                    text:
                        '${_HomeDashboardScreenState._fullMonthNames[now.month - 1]}\nThu',
                    style: InsightTheme.inter(12, w: FontWeight.w600),
                  ),
                ],
              ),
              textDirection: Directionality.of(context),
              textScaler: scaler,
              textAlign: TextAlign.center,
            )..layout(
              maxWidth: ((constraints.maxWidth - 18) * 0.4 - 24).clamp(
                1,
                double.infinity,
              ),
            );
        final clockHeight = (scaler.scale(92) + 16).clamp(
          date.height + 34,
          double.infinity,
        );
        date.dispose();
        final weekdayStyle = InsightTheme.inter(12, w: FontWeight.w500, h: 1.2);
        final numberStyle = InsightTheme.urbanist(
          20,
          w: FontWeight.w700,
          h: 1.2,
        );
        final monthLabel =
            '${_HomeDashboardScreenState._fullMonthNames[widget.month.month - 1]} ${widget.month.year}';
        final monthStyle = InsightTheme.urbanist(
          14,
          w: FontWeight.w700,
          h: 1.2,
        );
        final headerHeight =
            (measure(
                      monthLabel,
                      monthStyle,
                      width: (constraints.maxWidth - 114).clamp(
                        1,
                        double.infinity,
                      ),
                    ).height +
                    20)
                .clamp(48.0, double.infinity);
        final dayHeight =
            (measure('Wed', weekdayStyle).height +
                    measure('31', numberStyle).height +
                    10)
                .clamp(48.0, double.infinity);
        final height = clockHeight.clamp(
          headerHeight + dayHeight + 10,
          double.infinity,
        );
        final tileWidth = [
          48.0,
          measure('Wed', weekdayStyle).width + 12,
          measure('31', numberStyle).width + 12,
        ].reduce((a, b) => a > b ? a : b);
        final days = DateTime(widget.month.year, widget.month.month + 1, 0).day;
        final rowWidth = constraints.maxWidth - 18;
        if (_rowWidth != 0 &&
            (_rowWidth != rowWidth || _dayExtent != tileWidth + 6)) {
          _alignDates = true;
        }
        _rowWidth = rowWidth;
        _dayExtent = tileWidth + 6;
        _dates ??= ScrollController(initialScrollOffset: _selectedOffset(days));
        if (_alignDates) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_dates!.hasClients) return;
            _alignDates = false;
            final offset = _selectedOffset(
              days,
            ).clamp(0.0, _dates!.position.maxScrollExtent);
            if (_motion == Duration.zero) {
              _dates!.jumpTo(offset);
            } else {
              _dates!.animateTo(
                offset,
                duration: _motion,
                curve: Curves.easeOutCubic,
              );
            }
          });
        }

        Widget withViewCue(Widget child, int page) => Stack(
          children: [
            Positioned.fill(child: child),
            // Keep the cue inside its page: header drags still reach PageView's
            // recognizer, while the date row retains its own horizontal drag.
            if (page == _view)
              Positioned(
                top: 0,
                left: (constraints.maxWidth - 48) / 2,
                child: IconButton(
                  tooltip: _view == 0
                      ? 'Show Time and Date'
                      : 'Show Calendar preview',
                  onPressed: _switchView,
                  alignment: Alignment.topCenter,
                  padding: const EdgeInsets.only(top: 4),
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  icon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var index = 0; index < 2; index++)
                        AnimatedContainer(
                          duration: _motion,
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _view == index
                                ? InsightTheme.blue1
                                : InsightTheme.line,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );

        return SizedBox(
          key: const ValueKey('home_calendar_pager'),
          height: height,
          child: _views == null
              ? const SizedBox.shrink()
              : Material(
                  color: Colors.transparent,
                  child: PageView(
                    controller: _views,
                    allowImplicitScrolling: true,
                    onPageChanged: (view) {
                      if (_view == view) return;
                      setState(() => _view = view);
                      unawaited(_rememberView(view));
                    },
                    children: [
                      withViewCue(
                        Container(
                          key: const ValueKey('calendar_preview'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: InsightTheme.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: InsightTheme.line),
                          ),
                          child: Column(
                            children: [
                              SizedBox(
                                key: const ValueKey('calendar_preview_header'),
                                height: headerHeight,
                                child: Row(
                                  children: [
                                    IconButton(
                                      tooltip: 'Previous preview month',
                                      onPressed: widget.onPreviousMonth,
                                      icon: const Icon(
                                        Icons.chevron_left_rounded,
                                        color: InsightTheme.ink2,
                                      ),
                                    ),
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: Text(
                                          monthLabel,
                                          textAlign: TextAlign.center,
                                          style: monthStyle,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Next preview month',
                                      onPressed: widget.onNextMonth,
                                      icon: const Icon(
                                        Icons.chevron_right_rounded,
                                        color: InsightTheme.ink2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: ListView.builder(
                                  key: const ValueKey('calendar_preview_days'),
                                  controller: _dates,
                                  scrollDirection: Axis.horizontal,
                                  itemExtent: _dayExtent,
                                  itemCount: days,
                                  itemBuilder: (context, index) {
                                    final day = index + 1;
                                    final selected =
                                        widget.selectedDay.clamp(1, days) ==
                                        day;
                                    final dayDate = DateTime(
                                      widget.month.year,
                                      widget.month.month,
                                      day,
                                    );
                                    final colors =
                                        (widget.tasksByDay[day] ??
                                                const <TaskItem>[])
                                            .map(widget.dotColorForTask)
                                            .toSet()
                                            .take(3)
                                            .toList();
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: Semantics(
                                        container: true,
                                        button: true,
                                        selected: selected,
                                        label: '$monthLabel, $day',
                                        child: Material(
                                          color: selected
                                              ? InsightTheme.blue1
                                              : InsightTheme.surface2,
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            onTap: () => widget.onPick(
                                              widget.month,
                                              day,
                                            ),
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  const [
                                                    'Mon',
                                                    'Tue',
                                                    'Wed',
                                                    'Thu',
                                                    'Fri',
                                                    'Sat',
                                                    'Sun',
                                                  ][dayDate.weekday - 1],
                                                  style: weekdayStyle.copyWith(
                                                    color: selected
                                                        ? Colors.white
                                                        : InsightTheme.ink2,
                                                  ),
                                                ),
                                                Text(
                                                  '$day',
                                                  style: numberStyle.copyWith(
                                                    color: selected
                                                        ? Colors.white
                                                        : InsightTheme.ink,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                SizedBox(
                                                  height: 4,
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      for (final color
                                                          in colors)
                                                        Container(
                                                          width: 4,
                                                          height: 4,
                                                          margin:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 1,
                                                              ),
                                                          decoration:
                                                              BoxDecoration(
                                                                shape: BoxShape
                                                                    .circle,
                                                                color: selected
                                                                    ? Colors
                                                                          .white
                                                                    : color,
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
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        0,
                      ),
                      withViewCue(widget.timeDateView, 1),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

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
    final text =
        '${hour12.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')} ${_now.hour < 12 ? 'AM' : 'PM'}';
    final tasks = widget.tasksForDate(_now);
    final month = _HomeDashboardScreenState._fullMonthNames[_now.month - 1];
    final weekday = const [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ][_now.weekday - 1];
    return Container(
      key: const ValueKey('clock_date_card'),
      padding: const EdgeInsets.all(8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: InsightTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: InsightTheme.line),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tileWidth = constraints.maxWidth * 0.4;
          return Stack(
            children: [
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
                              Text(
                                'Note',
                                style: InsightTheme.urbanist(
                                  14,
                                  w: FontWeight.w700,
                                  c: InsightTheme.ink,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Expanded(
                                child: SingleChildScrollView(
                                  key: const ValueKey('today_tasks'),
                                  child: widget.isLoading
                                      ? Text(
                                          'Loading today’s tasks…',
                                          style: InsightTheme.inter(
                                            12,
                                            c: InsightTheme.ink2,
                                          ),
                                        )
                                      : tasks.isEmpty
                                      ? Text(
                                          'No tasks or PO due dates today.',
                                          textAlign: TextAlign.center,
                                          style: InsightTheme.inter(
                                            12,
                                            c: InsightTheme.ink2,
                                          ),
                                        )
                                      : Column(
                                          children: tasks
                                              .map(
                                                (task) => _CalendarTaskRow(
                                                  task: task,
                                                  color: widget.dotColorForTask(
                                                    task,
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                        ),
                                ),
                              ),
                            ],
                          )
                        : Center(
                            key: const ValueKey('live_clock'),
                            child: Text(
                              text,
                              textAlign: TextAlign.center,
                              style: InsightTheme.urbanist(
                                24,
                                w: FontWeight.w800,
                                c: InsightTheme.ink,
                              ),
                            ),
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
                  container: true,
                  button: true,
                  label: _showTasks
                      ? 'Show clock and date'
                      : "Show today's tasks",
                  value: _showTasks
                      ? 'Today'
                      : '${_HomeDashboardScreenState._fullMonthNames[_now.month - 1]} ${_now.day}, ${_now.year}',
                  onTap: () => setState(() => _showTasks = !_showTasks),
                  excludeSemantics: true,
                  child: Material(
                    color: InsightTheme.blue1,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => setState(() => _showTasks = !_showTasks),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Center(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: _showTasks
                                ? Text(
                                    'Today',
                                    key: const ValueKey('today_label'),
                                    style: InsightTheme.urbanist(
                                      24,
                                      w: FontWeight.w800,
                                      c: Colors.white,
                                    ),
                                  )
                                : Column(
                                    key: const ValueKey('date_label'),
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${_now.day}',
                                        style: InsightTheme.urbanist(
                                          30,
                                          w: FontWeight.w800,
                                          c: Colors.white,
                                        ),
                                      ),
                                      Text(
                                        month,
                                        textAlign: TextAlign.center,
                                        style: InsightTheme.inter(
                                          12,
                                          w: FontWeight.w600,
                                          c: Colors.white,
                                        ),
                                      ),
                                      Text(
                                        weekday,
                                        style: InsightTheme.inter(
                                          12,
                                          w: FontWeight.w600,
                                          c: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
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
    final isVisit =
        task.lifecycleCategory == TaskLifecycleCategory.pending &&
        task.pendingSection == PendingTaskSection.scheduled;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 6, right: 6),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.inspectionNo,
                  style: InsightTheme.inter(
                    12,
                    w: FontWeight.w700,
                    c: InsightTheme.ink,
                  ),
                ),
                Text(
                  task.name,
                  style: InsightTheme.inter(12, c: InsightTheme.ink2),
                ),
                Text(
                  isVisit ? 'Scheduled visit' : 'PO due date',
                  style: InsightTheme.inter(12, w: FontWeight.w600, c: color),
                ),
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
    return IconButton(
      tooltip: 'Notifications',
      onPressed: onTap,
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        backgroundColor: InsightTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: const BorderSide(color: InsightTheme.line),
      ),
      icon: SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(
              Icons.notifications_outlined,
              color: InsightTheme.ink,
              size: 22,
            ),
            if (hasUnread)
              Positioned(
                right: 10,
                top: 10,
                child: Container(
                  key: const ValueKey('notification_unread_badge'),
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: InsightTheme.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final Widget? titleAction;
  const _SectionLabel({required this.title, this.trailing, this.titleAction});

  @override
  Widget build(BuildContext context) {
    if (titleAction != null) {
      return LayoutBuilder(
        builder: (context, constraints) => OverflowBar(
          alignment: MainAxisAlignment.spaceBetween,
          overflowAlignment: OverflowBarAlignment.end,
          spacing: 12,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: InsightTheme.urbanist(
                          16,
                          w: FontWeight.w700,
                          c: InsightTheme.ink,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  titleAction!,
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: InsightTheme.urbanist(
                  16,
                  w: FontWeight.w700,
                  c: InsightTheme.ink,
                ),
              ),
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
            Text(
              label,
              style: InsightTheme.inter(
                12,
                w: FontWeight.w700,
                c: InsightTheme.blueInk,
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              Icons.arrow_forward_rounded,
              size: 12,
              color: InsightTheme.blueInk,
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact bubble chart and legend for the current task-status counts.
class _TaskCompletionBubbleChart extends StatelessWidget {
  final int total;
  final List<String> labels;
  final List<Color> colors;
  final List<int> counts;
  final int overdueCount;
  final bool isLoading;
  final bool hasTasks;
  final VoidCallback onMoreDetails;

  const _TaskCompletionBubbleChart({
    required this.total,
    required this.labels,
    required this.colors,
    required this.counts,
    required this.overdueCount,
    required this.isLoading,
    required this.hasTasks,
    required this.onMoreDetails,
  });

  Color _countColor(Color background) {
    final luminance = background.computeLuminance();
    final darkContrast =
        (luminance + 0.05) / (InsightTheme.ink.computeLuminance() + 0.05);
    final lightContrast = 1.05 / (luminance + 0.05);
    return lightContrast > darkContrast ? Colors.white : InsightTheme.ink;
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final statuses = <({String label, int count, Color color})>[
      for (var i = 0; i < labels.length; i++)
        (label: labels[i], count: counts[i], color: colors[i]),
      (label: 'Overdue', count: overdueCount, color: InsightTheme.red),
    ];
    final bubbles = SizedBox(
      key: const ValueKey('completion_bubble_chart'),
      width: 138,
      height: 102,
      child: Stack(
        key: const ValueKey('completion_bubbles'),
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < statuses.length; i++)
            Builder(
              builder: (context) {
                const centers = [
                  Offset(31.5, 31.5),
                  Offset(67.5, 31.5),
                  Offset(103.5, 31.5),
                  Offset(49.5, 70.5),
                  Offset(85.5, 70.5),
                ];
                final status = statuses[i];
                final cappedCount = status.count.clamp(0, 7);
                final diameter = 42.0 + 3.0 * cappedCount;
                final color = status.color;
                return Positioned(
                  left: centers[i].dx - diameter / 2,
                  top: centers[i].dy - diameter / 2,
                  width: diameter,
                  height: diameter,
                  child: Semantics(
                    label: status.label == 'Overdue'
                        ? '${status.count} overdue tasks'
                        : '${status.label}: ${status.count} tasks',
                    child: Container(
                      key: ValueKey('completion_bubble_${status.label}'),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: InsightTheme.surface,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.12),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            '${status.count}',
                            style: InsightTheme.urbanist(
                              13,
                              w: FontWeight.w800,
                              c: _countColor(color),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );

    Widget legend() => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final status in statuses)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Container(
              key: ValueKey('completion_${status.label}'),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    key: ValueKey('completion_icon_${status.label}'),
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: status.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      status.label,
                      style: InsightTheme.inter(
                        11,
                        w: FontWeight.w500,
                        c: status.label == 'Overdue'
                            ? InsightTheme.redInk
                            : InsightTheme.ink2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${status.count}',
                    style: InsightTheme.inter(
                      12,
                      w: FontWeight.w700,
                      c: status.label == 'Overdue'
                          ? InsightTheme.redInk
                          : InsightTheme.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );

    return LayoutBuilder(
      key: const ValueKey('completion_chart'),
      builder: (context, constraints) {
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: InsightTheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: InsightTheme.line),
            boxShadow: [
              BoxShadow(
                color: InsightTheme.ink.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, headerConstraints) {
                  final stackHeader =
                      headerConstraints.maxWidth < 320 || scaler.scale(16) > 24;
                  final title = Semantics(
                    header: true,
                    child: Text(
                      'Task Status Overview',
                      maxLines: stackHeader ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: InsightTheme.urbanist(
                        16,
                        w: FontWeight.w700,
                        c: InsightTheme.ink,
                      ),
                    ),
                  );
                  return title;
                },
              ),
              const SizedBox(height: 3),
              Text(
                'Tasks grouped by status',
                style: InsightTheme.inter(
                  11,
                  w: FontWeight.w400,
                  c: InsightTheme.inkMuted,
                ),
              ),
              const SizedBox(height: 12),
              if (isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: ImapsLoadingIndicator(size: 40)),
                )
              else if (!hasTasks)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: Text(
                      'No tasks yet.',
                      style: InsightTheme.inter(12, c: InsightTheme.ink2),
                    ),
                  ),
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    bubbles,
                    const SizedBox(width: 8),
                    Expanded(child: legend()),
                  ],
                ),
              if (!isLoading && hasTasks) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: _SectionActionButton(
                    label: 'More details',
                    onTap: onMoreDetails,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// One shared hanging pivot for the strap and the month card it carries.
const double _kCalendarSwingRadians = 0.0349; // 2 degrees

/// Reveals the month card hanging from its lanyard, and replays the same
/// motion in reverse when it closes.
///
/// One controller owns the whole reveal, so the strap, the card and the pivot
/// always move as a single suspended piece instead of three decorations that
/// happen to animate together.
class _SuspendedMonthCalendar extends StatefulWidget {
  const _SuspendedMonthCalendar({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  State<_SuspendedMonthCalendar> createState() =>
      _SuspendedMonthCalendarState();
}

class _SuspendedMonthCalendarState extends State<_SuspendedMonthCalendar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _swing = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: widget.visible ? 1 : 0,
  );

  @override
  void didUpdateWidget(_SuspendedMonthCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible == widget.visible) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _swing.value = widget.visible ? 1 : 0;
      return;
    }
    _swing.animateTo(widget.visible ? 1 : 0, curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _swing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _swing,
    child: widget.child,
    builder: (context, child) {
      if (_swing.value <= 0) return const SizedBox.shrink();
      return Transform.rotate(
        angle: (1 - _swing.value) * _kCalendarSwingRadians,
        alignment: Alignment.topCenter,
        child: SizeTransition(
          sizeFactor: _swing,
          alignment: Alignment.topCenter,
          child: child,
        ),
      );
    },
  );
}

/// The visible strap the month card actually hangs from.
///
/// The ribbon converges onto a real clip at the card's top-centre slot, so the
/// lanyard reads as attached hardware rather than decoration floating between
/// the toggle and the card.
class _CalendarLanyard extends StatelessWidget {
  const _CalendarLanyard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    alignment: Alignment.topCenter,
    children: [
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            key: ValueKey('calendar_lanyard'),
            height: 30,
            width: double.infinity,
            child: ExcludeSemantics(
              child: CustomPaint(painter: _CalendarLanyardPainter()),
            ),
          ),
          child,
        ],
      ),
      // Paint the hardware after the card: geometric overlap otherwise gets
      // hidden by the card's opaque background.
      Positioned(
        top: 19,
        child: ExcludeSemantics(
          child: Container(
            key: const ValueKey('calendar_lanyard_clip'),
            width: 12,
            height: 16,
            decoration: BoxDecoration(
              color: InsightTheme.ink3,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Center(
              child: Container(
                width: 12,
                height: 2,
                color: InsightTheme.surface,
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class _CalendarLanyardPainter extends CustomPainter {
  const _CalendarLanyardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final ribbon = Paint()..color = InsightTheme.blue1.withValues(alpha: 0.62);
    final seam = Paint()
      ..color = InsightTheme.blueInk.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final centre = size.width / 2;
    final clipTop = size.height - 6;
    // Two ribbons hang from the toggle and converge onto the clip, so the card
    // reads as carried hardware rather than sitting under loose lines.
    for (final direction in [-1.0, 1.0]) {
      final outer = centre + direction * 26;
      final inner = centre + direction * 8;
      canvas.drawPath(
        Path()
          ..moveTo(outer - direction * 5, 0)
          ..lineTo(outer + direction * 5, 0)
          ..lineTo(inner + direction * 3, clipTop)
          ..lineTo(inner - direction * 3, clipTop)
          ..close(),
        ribbon,
      );
      canvas.drawPath(
        Path()
          ..moveTo(outer, 1)
          ..lineTo(inner, clipTop - 1),
        seam,
      );
    }
  }

  @override
  bool shouldRepaint(_CalendarLanyardPainter oldDelegate) => false;
}

/// A separate full-month card sharing the strip's real selection/task sources.
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
  static const _weekdayAbbrSunStart = [
    'SUN',
    'MON',
    'TUE',
    'WED',
    'THU',
    'FRI',
    'SAT',
  ];
  static const _fullWeekdayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _monthAbbr = _HomeDashboardScreenState._monthNames;

  @override
  Widget build(BuildContext context) {
    final taskDays = taskDaysForMonth(month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final firstWeekday = DateTime(
      month.year,
      month.month,
      1,
    ).weekday; // 1=Mon..7=Sun
    final leadingBlanks = firstWeekday % 7; // Sunday-start offset

    final clampedDay = selectedDay.clamp(1, daysInMonth);
    final selectedDate = DateTime(month.year, month.month, clampedDay);
    final selectedTasks = tasksByDayInMonth[clampedDay] ?? const <TaskItem>[];

    return Container(
      key: const ValueKey('calendar_month_card'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: InsightTheme.surface,
        borderRadius: InsightTheme.roundedMd,
        border: Border.all(color: InsightTheme.line, width: 1.2),
        boxShadow: kCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_monthAbbr[month.month - 1]} ${month.year}',
                        style: InsightTheme.urbanist(
                          15,
                          w: FontWeight.w700,
                          c: InsightTheme.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // The selected date rides in the header instead of a
                      // separate caption row, so the month stays compact.
                      Text(
                        key: const ValueKey('calendar_selected_date'),
                        '${_fullWeekdayNames[selectedDate.weekday - 1].substring(0, 3)} $clampedDay ${_monthAbbr[month.month - 1]}',
                        style: InsightTheme.inter(12, c: InsightTheme.ink3),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Previous month',
                  onPressed: onPrevMonth,
                  icon: Icon(
                    Icons.chevron_left_rounded,
                    color: InsightTheme.ink2,
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Next month',
                  onPressed: onNextMonth,
                  icon: Icon(
                    Icons.chevron_right_rounded,
                    color: InsightTheme.ink2,
                  ),
                ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final dayStyle = InsightTheme.inter(12.5, w: FontWeight.w700);
              final weekdayStyle = InsightTheme.inter(
                12,
                w: FontWeight.w700,
                c: InsightTheme.ink3,
              );
              final columnWidth = constraints.maxWidth / 7;
              Size measure(String label, TextStyle style) {
                final painter = TextPainter(
                  text: TextSpan(
                    text: label,
                    style: DefaultTextStyle.of(context).style.merge(style),
                  ),
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                )..layout();
                final size = painter.size;
                painter.dispose();
                return size;
              }

              // Adapt the heading, not the user's text size or the grid width.
              var weekdayLength = 3;
              while (weekdayLength > 1 &&
                  _weekdayAbbrSunStart.any(
                    (label) =>
                        measure(
                              label.substring(0, weekdayLength),
                              weekdayStyle,
                            ).width +
                            4 >
                        columnWidth,
                  )) {
                weekdayLength--;
              }
              var plateWidth = 32.0;
              var plateHeight = 32.0;
              for (var day = 1; day <= daysInMonth; day++) {
                final size = measure('$day', dayStyle);
                if (size.width + 8 > plateWidth) plateWidth = size.width + 8;
                if (size.height + 8 > plateHeight) {
                  plateHeight = size.height + 8;
                }
              }
              plateWidth = plateWidth.clamp(0.0, columnWidth).toDouble();
              // Number plate, 2dp separation, 4dp task track, 4dp breathing room.
              // The approved compact Calendar uses the full cell as its target.
              final rowHeight = (plateHeight + 2 + 4 + 4)
                  .clamp(44.0, double.infinity)
                  .toDouble();
              return Column(
                children: [
                  Row(
                    children: [
                      for (
                        var index = 0;
                        index < _weekdayAbbrSunStart.length;
                        index++
                      )
                        Expanded(
                          child: Semantics(
                            key: ValueKey('calendar_weekday_$index'),
                            label: _fullWeekdayNames[(index + 6) % 7],
                            excludeSemantics: true,
                            child: Center(
                              child: Text(
                                _weekdayAbbrSunStart[index].substring(
                                  0,
                                  weekdayLength,
                                ),
                                style: weekdayStyle,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisSpacing: 0,
                      crossAxisSpacing: 0,
                      mainAxisExtent: rowHeight,
                    ),
                    itemCount: daysInMonth + leadingBlanks,
                    itemBuilder: (context, i) {
                      if (i < leadingBlanks) return const SizedBox.shrink();
                      final day = i - leadingBlanks + 1;
                      final isSelected = day == clampedDay;
                      final hasTask = taskDays.contains(day);
                      final dayTasks =
                          tasksByDayInMonth[day] ?? const <TaskItem>[];
                      final dotColors = dayTasks
                          .map(dotColorForTask)
                          .toSet()
                          .toList();
                      return Semantics(
                        key: ValueKey('calendar_day_$day'),
                        container: true,
                        button: true,
                        selected: isSelected,
                        label:
                            '${_fullWeekdayNames[DateTime(month.year, month.month, day).weekday - 1]}, '
                            '${_HomeDashboardScreenState._fullMonthNames[month.month - 1]} $day, ${month.year}, '
                            '${dayTasks.length} ${dayTasks.length == 1 ? 'task' : 'tasks'}',
                        onTap: () => onPick(month, day),
                        excludeSemantics: true,
                        child: InkWell(
                          onTap: () => onPick(month, day),
                          borderRadius: BorderRadius.circular(24),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  key: ValueKey('calendar_day_plate_$day'),
                                  width: plateWidth,
                                  height: plateHeight,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? InsightTheme.blue1
                                        : Colors.transparent,
                                    // A circle at normal text; a content-sized capsule when
                                    // large digits need more height than a narrow column.
                                    borderRadius: BorderRadius.circular(
                                      plateHeight / 2,
                                    ),
                                  ),
                                  child: Text(
                                    '$day',
                                    style: dayStyle.copyWith(
                                      color: isSelected
                                          ? Colors.white
                                          : InsightTheme.ink,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                SizedBox(
                                  height: 4,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children:
                                        (hasTask ? dotColors : const <Color>[])
                                            .take(3)
                                            .map(
                                              (dotColor) => Container(
                                                margin:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 1,
                                                    ),
                                                width: 4,
                                                height: 4,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: dotColor,
                                                ),
                                              ),
                                            )
                                            .toList(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
          if (selectedTasks.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: InsightTheme.surface2,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tasks for $clampedDay ${_monthAbbr[month.month - 1]}',
                      style: InsightTheme.urbanist(
                        12,
                        w: FontWeight.w700,
                        c: InsightTheme.ink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...selectedTasks.map(
                      (task) => _CalendarTaskRow(
                        task: task,
                        color: dotColorForTask(task),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
