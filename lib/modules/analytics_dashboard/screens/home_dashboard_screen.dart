import 'dart:async';
import 'dart:math' show max, min, pi;
import 'package:flutter/material.dart';
import '../../../core/widgets/sensitive_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState;

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
import '../../../core/widgets/motion/linked_list_motion.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/imaps_loading_indicator.dart';
import '../../../core/widgets/offline_banner.dart';
import '../../../core/widgets/task_sync_indicator.dart';
import '../widgets/active_assignments_folder_card.dart';
import '../widgets/recent_activity_folder.dart';
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

  List<Map<String, dynamic>> _recentActivity = [];
  bool _isLoadingActivity = true;
  int _unreadCount = 0;

  // Home selects one latest event per category from the already-fetched batch.
  // Tapping that preview opens the category's full history in the modal.
  String _activityPreviewCategory = 'tasks';

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
    PaintingBinding.instance.systemFonts.addListener(_onFontsChanged);
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

    _authSubscription = SupabaseService.client.auth.onAuthStateChange
        .listen((_) => _retireIfOwnerChanged(),
            onError: (Object _) => _retireIfOwnerChanged());
    _loadUpcomingTasks();
    _loadRecentActivity();
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
  void _onFontsChanged() { if (mounted) setState(() {}); }

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
    _authSubscription?.cancel();
    _pageController.dispose();
    PaintingBinding.instance.systemFonts.removeListener(_onFontsChanged);
    _connectivitySubscription.cancel();
    disposeSpringEntrance();
    super.dispose();
  }

  /// The carousel population: exactly the filter and order the dashboard has
  /// always used.
  List<TaskItem> _upcomingFrom(List<TaskItem> tasks) {
    final upcoming = tasks.where(isHomeDashboardActiveAssignment).toList()
      ..sort((a, b) {
        final aDate = _calendarDateForTask(a) ?? '9999-12-31';
        final bDate = _calendarDateForTask(b) ?? '9999-12-31';
        return aDate.compareTo(bDate);
      });
    return upcoming.take(6).toList();
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
    var cacheFailed = false;
    if (owner != null && owner.isNotEmpty) {
      try {
        cached = await DBHelper.getCachedJobs();
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
        : await _savedCardSteps(_upcomingFrom(parsed));
    if (!mounted || requestId != _tasksRequestId) return;

    setState(() {
      _cardSteps = cardSteps;
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
            ? TaskRefreshPhase.cacheUnavailable : TaskRefreshPhase.offline;
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
      final tasks = jobs.map((j) => TaskItem.fromJob(j)).toList();
      final cardSteps = await _savedCardSteps(_upcomingFrom(tasks));
      if (!mounted || requestId != _tasksRequestId) return;
      setState(() {
        _allTasks = tasks;
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
            ? TaskRefreshPhase.cacheUnavailable : TaskRefreshPhase.failed;
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
      final dynamic result = await Connectivity()
          .checkConnectivity()
          .timeout(const Duration(milliseconds: 500));
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

  // Fetch a bounded recent batch; the dashboard previews only one event.
  static const int _kRecentActivityLimit = 50;

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
      case 'field_findings_updated':
        return {'icon': Icons.edit_note_rounded, 'color': InsightTheme.blueInk};
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

  /// "All" is available only inside the history sheet.
  String _activityLabel(String key) =>
      key == 'all' ? 'All' : ActivityEventCategory.labelFor(key);

  /// Home's category shortcuts, in sheet order. 'all' intentionally excluded.
  static const List<String> _activityShortcuts = [
    'tasks',
    'sync',
    ActivityEventCategory.reports,
    'profile',
  ];

  List<Map<String, dynamic>> _activityMatching(String filter) {
    if (filter == 'all') return _recentActivity;
    return _recentActivity
        .where((a) => _eventCategory(a['event_type'] as String? ?? '') == filter)
        .toList();
  }

  /// The sheet starts on the preview's category and can switch independently.
  void _showActivityHistory({String initialFilter = 'all'}) {
    if (_isLoadingActivity) return;
    var filter = initialFilter;
    String labelOf(String key) => _activityLabel(key);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: InsightTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final shown = _activityMatching(filter);
            return SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * 0.82,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 2, 12, 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Recent activity',
                                      style: InsightTheme.urbanist(20,
                                          w: FontWeight.w700,
                                          c: InsightTheme.ink)),
                                  const SizedBox(height: 3),
                                  Text(
                                      '${labelOf(filter)} · ${shown.length} ${shown.length == 1 ? 'event' : 'events'}',
                                      style: InsightTheme.inter(12, c: InsightTheme.ink2)),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Close recent activity',
                              onPressed: () => Navigator.of(sheetContext).pop(),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 20, top: 14),
                        child: ScrollConfiguration(
                          behavior: ScrollConfiguration.of(context)
                              .copyWith(scrollbars: false),
                          child: SingleChildScrollView(
                            key: const ValueKey('modal_activity_filters'),
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                for (final key in ActivityEventCategory.filters)
                                  Padding(
                                    padding: EdgeInsets.only(
                                        right: key == 'profile' ? 0 : 4),
                                    child: _ActivityFilterChip(
                                      label: labelOf(key),
                                      selected: filter == key,
                                      onTap: () =>
                                          setSheetState(() => filter = key),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: shown.isEmpty
                            ? Center(
                                child: Text(
                                  'No ${labelOf(filter).toLowerCase()} activity yet.',
                                  style: InsightTheme.inter(
                                      13, c: InsightTheme.ink2),
                                ),
                              )
                            : ListView.builder(
                                key: const ValueKey('recent_activity_modal_list'),
                                padding:
                                    const EdgeInsets.fromLTRB(18, 16, 18, 24),
                                itemCount: shown.length,
                                itemBuilder: (context, index) {
                                  final event = shown[index];
                                  final themeInfo = _eventTheme(
                                      event['event_type'] as String? ?? '');
                                  final tile = Stack(
                                    children: [
                                      if (index < shown.length - 1)
                                        Positioned(
                                          left: 16,
                                          top: 16,
                                          bottom: 0,
                                          child: Container(
                                            width: 2,
                                            color: InsightTheme.ink3
                                                .withValues(alpha: 0.15),
                                          ),
                                        ),
                                      _TimelineActivityTile(
                                        key: ValueKey(
                                            'modal_${event['id'] ?? index}'),
                                        icon: themeInfo['icon'],
                                        color: themeInfo['color'],
                                        categoryLabel: _eventCategoryLabel(event[
                                                'event_type'] as String? ??
                                            ''),
                                        title: event['title'] as String? ??
                                            'Update',
                                        subtitle: event['subtitle'] as String? ??
                                            '',
                                        time: _timeAgo(
                                            event['occurred_at'] as String?),
                                        occurredAtIso:
                                            event['occurred_at'] as String?,
                                      ),
                                    ],
                                  );
                                  return MediaQuery.disableAnimationsOf(context)
                                      ? tile
                                      : LinkedListSlide(
                                          key: ValueKey('activity-rise-$filter-${event['id'] ?? index}'),
                                          index: index,
                                          itemDelay: Spring.step,
                                          beginOffset: const Offset(0, 0.18),
                                          child: tile,
                                        );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
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
    final previewCategory = _activityPreviewCategory;
    final previewList = _activityMatching(previewCategory);
    final latestActivity = previewList.isEmpty ? null : previewList.first;
    final calendarMotion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero : const Duration(milliseconds: 320);

    return SensitiveScreen(
      child: Scaffold(
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
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
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: LayoutBuilder(builder: (context, constraints) {
                        final titleStyle = InsightTheme.urbanist(16, w: FontWeight.w700, c: InsightTheme.ink);
                        final titleSize = TextPainter(
                          text: TextSpan(text: 'FieldSync', style: titleStyle),
                          textScaler: MediaQuery.textScalerOf(context),
                          textDirection: Directionality.of(context),
                        )..layout();
                        final fitsOneRow = constraints.maxWidth >= 60 + titleSize.width + 24 + 48;
                        titleSize.dispose();
                        final identity = Row(mainAxisSize: MainAxisSize.min, children: [
                          Semantics(
                            button: true,
                            label: 'Edit profile',
                            child: GestureDetector(
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
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('FieldSync', style: titleStyle),
                              const SizedBox(height: 4),
                              Row(mainAxisSize: MainAxisSize.min, children: [
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
                              ]),
                            ],
                          ),
                        ]);
                        final notification = _NotificationBtn(
                            hasUnread: _unreadCount > 0,
                            onTap: () async {
                              await Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
                              // Notifications screen marks things read on its own
                              // timeline — resync the badge once the inspector
                              // backs out of it instead of leaving it stale.
                              _loadRecentActivity();
                            },
                          );
                        if (fitsOneRow) {
                          return Row(children: [identity, const Spacer(), notification]);
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            identity,
                            const SizedBox(height: 8),
                            Align(alignment: Alignment.centerRight, child: notification),
                          ],
                        );
                      }),
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
                            key: ValueKey('home_calendar_${widget.profile.id}'),
                            userId: widget.profile.id,
                            month: _calendarMonth,
                            selectedDay: _selectedDay,
                            tasksByDay: tasksByDay,
                            dotColorForTask: _calendarDotColor,
                            onPick: _onFullCalendarPick,
                            onPreviousMonth: () => setState(() => _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month - 1)),
                            onNextMonth: () => setState(() => _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1)),
                            timeDateView: _TodayScheduleCard(
                              tasksForDate: (date) => _tasksByDayInMonth(date)[date.day] ?? const <TaskItem>[],
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
                            message: _showFullCalendar ? 'Hide full calendar' : 'Show full calendar',
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Calendar', style: InsightTheme.inter(12, w: FontWeight.w600, c: InsightTheme.blueInk)),
                                AnimatedRotation(
                                  turns: _showFullCalendar ? 0.5 : 0,
                                   duration: calendarMotion,
                                  child: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: InsightTheme.blue1),
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
                         child: Padding(
                                key: const ValueKey('full_calendar'),
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
                                  onPrevMonth: () => setState(() => _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month - 1)),
                                  onNextMonth: () => setState(() => _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1)),
                                  onPick: _onFullCalendarPick,
                                      ),
                                     ),
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
                    trailing: _SectionActionButton(label: 'See All', onTap: _goToTasksTab),
                  ),
                ),
              ),

              SpringSlide(
                animation: springFor(2),
                beginOffset: const Offset(70, 0),
                child: SizedBox(
                height: 244 * max(1, MediaQuery.textScalerOf(context).scale(12) / 12),
                child: _isLoadingTasks
                    ? const Center(child: ImapsLoadingIndicator(size: 50))
                    : _upcomingTasks.isEmpty
                        ? (_savedDataNotice != null
                            // Never claim emptiness when the refresh failed:
                            // "nothing" is only ever stated once it is known.
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 36),
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
                                    Icon(Icons.assignment_outlined, size: 36, color: InsightTheme.ink3),
                                    const SizedBox(height: 10),
                                    Text(
                                      'No active assignments.',
                                      style: InsightTheme.openSans(13, c: InsightTheme.ink2),
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
                                      height: Curves.easeOut.transform(value) * 220 * max(1, MediaQuery.textScalerOf(context).scale(12) / 12),
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
                                      // IDs remain in Task Details and are no
                                      // longer printed on the carousel artwork.
                                      inspectionId: _formatShortId(_upcomingTasks[index].id),
                                      referenceNo: _upcomingTasks[index].inspectionNo,
                                      date: _calendarDateForTask(_upcomingTasks[index]) != null
                                          ? _formatScheduledDate(_calendarDateForTask(_upcomingTasks[index])!)
                                          : '—',
                                      dateLabel: _calendarDateForTask(_upcomingTasks[index]) == null
                                          ? null
                                          : _upcomingTasks[index].pendingSection == PendingTaskSection.scheduled
                                              ? 'Visit Date'
                                              : 'Deadline',
                                      // The durable draft step when it could be
                                      // read; the fetched counters otherwise.
                                      savedStep: _cardSteps[_upcomingTasks[index].id] ??
                                          (_upcomingTasks[index].currentStep > 0
                                                  ? _upcomingTasks[index].currentStep
                                                  : _upcomingTasks[index].derivedHighestStep)
                                              .clamp(0, 6),
                                      location: _upcomingTasks[index].location,
                                      applicantName: _upcomingTasks[index].name,
                                      applicationType: _upcomingTasks[index].applicationType?.isNotEmpty == true
                                          ? _upcomingTasks[index].applicationType!
                                          : _upcomingTasks[index].landUseClass,
                                      lifecycleCategory:
                                          _upcomingTasks[index].lifecycleCategory,
                                      pendingSection:
                                          _upcomingTasks[index].pendingSection,
                                      onTap: () {
                                        // A callback bound before an account
                                        // change must not open another
                                        // inspector's task from this page.
                                        final current = DBHelper.currentInspectorId;
                                        if (!mounted || current == null || current != _tasksOwner) {
                                          _retireIfOwnerChanged();
                                          return;
                                        }
                                        Navigator.of(context).push(
                                            MaterialPageRoute(builder: (_) => ParcelDetailScreen(
                                              task: _upcomingTasks[index],
                                              fetchedJob: _entryJobs[_upcomingTasks[index].id],
                                              relatedRounds: _allTasks.where(_upcomingTasks[index].sameApplicationAs).toList(),
                                            )));
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
                 const SizedBox(height: 8),
                   ],
                 ),
                ],
              ),
              const SizedBox(height: 16),

              // ----------------------------------------------------
              // 3. TASK COMPLETION FLOW
              // ----------------------------------------------------
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
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
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SpringSlide(
                  animation: springFor(4),
                  beginOffset: const Offset(0, 24),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: InsightTheme.surface,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    // 8px inset keeps the white card reading as a card around
                    // the tiles. With zero padding the four tiles ran edge to
                    // edge and buried the container they sit in.
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: _isLoadingTasks
                        ? const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Center(child: ImapsLoadingIndicator(size: 40)))
                        : _allTasks.isEmpty
                            ? Text('No tasks yet.', style: InsightTheme.inter(12, c: InsightTheme.ink2))
                            : Builder(builder: (context) {
                                final counts = _completionCounts;
                                final total = counts.values.fold<int>(0, (a, b) => a + b);
                                const labels = ['Scheduled', 'Pending', 'Ongoing', 'Completed'];
                                const colors = [InsightTheme.orange, Color(0xFF60A5FA), InsightTheme.blue1, InsightTheme.green];
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
              ),
              const SizedBox(height: 12),

              // ----------------------------------------------------
              // 4. RECENT ACTIVITY — one Home preview, full history in a modal.
              // ----------------------------------------------------
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SpringSlide(
                  animation: springFor(8),
                  beginOffset: const Offset(0, 20),
                  child: const _SectionLabel(title: 'Recent activity'),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: RecentActivityFolder(
                  key: const ValueKey('recent_activity_folder'),
                  categories: [for (final key in _activityShortcuts) (key: key, label: _activityLabel(key))],
                  selectedCategory: previewCategory,
                  onCategorySelected: (category) => setState(() => _activityPreviewCategory = category),
                  child: _isLoadingActivity
                    ? Semantics(
                        key: const ValueKey('activity_folder_loading'),
                        label: 'Loading recent activity',
                        liveRegion: true,
                        child: const SizedBox(
                          height: 112,
                          child: Center(child: ImapsLoadingIndicator(size: 32)),
                        ),
                      )
                    : AnimatedSwitcher(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                        child: latestActivity == null
                            ? ActivityFolderPreview(
                                key: ValueKey('empty_recent_$previewCategory'),
                                icon: Icons.inbox_outlined,
                                color: InsightTheme.inkMuted,
                                title: 'No ${_activityLabel(previewCategory).toLowerCase()} activity yet.',
                                subtitle: '', time: '', historyCount: 0,
                                onOpenHistory: () => _showActivityHistory(initialFilter: previewCategory),
                              )
                            : Builder(builder: (context) {
                                final activity = latestActivity;
                                final themeInfo = _eventTheme(
                                    activity['event_type'] as String? ?? '');
                                return ActivityFolderPreview(
                                  key: ValueKey(
                                      'preview_${previewCategory}_${activity['id'] ?? ''}'),
                                  icon: themeInfo['icon'],
                                  color: themeInfo['color'],
                                  title: activity['title'] as String? ?? 'Update',
                                  subtitle: activity['subtitle'] as String? ?? '',
                                  time: _timeAgo(activity['occurred_at'] as String?),
                                  onOpenHistory: () => _showActivityHistory(
                                      initialFilter: previewCategory),
                                  historyCount: previewList.length,
                                );
                              }),
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
      ? Duration.zero : const Duration(milliseconds: 280);

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
      _views!.animateToPage(next, duration: _motion, curve: Curves.easeOutCubic);
    }
  }

  @override
  void didUpdateWidget(_HomeCalendarPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.month != widget.month || oldWidget.selectedDay != widget.selectedDay) {
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
      ((widget.selectedDay.clamp(1, days) - 1) * _dayExtent - (_rowWidth - _dayExtent) / 2)
          .clamp(0.0, (days * _dayExtent - _rowWidth).clamp(0.0, double.infinity));

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final scaler = MediaQuery.textScalerOf(context);
      Size measure(String text, TextStyle style, {double width = double.infinity}) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: DefaultTextStyle.of(context).style.merge(style)),
          textDirection: Directionality.of(context),
          textScaler: scaler,
        )..layout(maxWidth: width);
        final size = painter.size;
        painter.dispose();
        return size;
      }

      final now = DateTime.now();
      final date = TextPainter(
        text: TextSpan(style: DefaultTextStyle.of(context).style, children: [
          TextSpan(text: '${now.day}\n', style: InsightTheme.urbanist(30, w: FontWeight.w800)),
          TextSpan(text: '${_HomeDashboardScreenState._fullMonthNames[now.month - 1]}\nThu',
              style: InsightTheme.inter(12, w: FontWeight.w600)),
        ]),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        textAlign: TextAlign.center,
      )..layout(maxWidth: ((constraints.maxWidth - 18) * 0.4 - 24).clamp(1, double.infinity));
      final clockHeight = (scaler.scale(92) + 16).clamp(date.height + 34, double.infinity);
      date.dispose();
      final weekdayStyle = InsightTheme.inter(12, w: FontWeight.w500, h: 1.2);
      final numberStyle = InsightTheme.urbanist(20, w: FontWeight.w700, h: 1.2);
      final monthLabel = '${_HomeDashboardScreenState._fullMonthNames[widget.month.month - 1]} ${widget.month.year}';
      final monthStyle = InsightTheme.urbanist(14, w: FontWeight.w700, h: 1.2);
      final headerHeight = (measure(monthLabel, monthStyle,
          width: (constraints.maxWidth - 114).clamp(1, double.infinity)).height + 20)
          .clamp(48.0, double.infinity);
      final dayHeight = (measure('Wed', weekdayStyle).height + measure('31', numberStyle).height + 10)
          .clamp(48.0, double.infinity);
      final height = clockHeight.clamp(headerHeight + dayHeight + 10, double.infinity);
      final tileWidth = [
        48.0, measure('Wed', weekdayStyle).width + 12, measure('31', numberStyle).width + 12,
      ].reduce((a, b) => a > b ? a : b);
      final days = DateTime(widget.month.year, widget.month.month + 1, 0).day;
      final rowWidth = constraints.maxWidth - 18;
      if (_rowWidth != 0 && (_rowWidth != rowWidth || _dayExtent != tileWidth + 6)) {
        _alignDates = true;
      }
      _rowWidth = rowWidth;
      _dayExtent = tileWidth + 6;
      _dates ??= ScrollController(initialScrollOffset: _selectedOffset(days));
      if (_alignDates) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_dates!.hasClients) return;
          _alignDates = false;
          final offset = _selectedOffset(days).clamp(0.0, _dates!.position.maxScrollExtent);
          if (_motion == Duration.zero) {
            _dates!.jumpTo(offset);
          } else {
            _dates!.animateTo(offset, duration: _motion, curve: Curves.easeOutCubic);
          }
        });
      }

      Widget withViewCue(Widget child, int page) => Stack(children: [
        Positioned.fill(child: child),
        // Keep the cue inside its page: header drags still reach PageView's
        // recognizer, while the date row retains its own horizontal drag.
        if (page == _view) Positioned(
          top: 0, left: (constraints.maxWidth - 48) / 2,
          child: IconButton(
            tooltip: _view == 0 ? 'Show Time and Date' : 'Show Calendar preview',
            onPressed: _switchView,
            alignment: Alignment.topCenter,
            padding: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: Row(mainAxisSize: MainAxisSize.min, children: [
              for (var index = 0; index < 2; index++)
                AnimatedContainer(
                  duration: _motion,
                  width: 6, height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(shape: BoxShape.circle,
                      color: _view == index ? InsightTheme.blue1 : InsightTheme.line),
                ),
            ]),
          ),
        ),
      ]);

      return SizedBox(
        key: const ValueKey('home_calendar_pager'),
        height: height,
        child: _views == null ? const SizedBox.shrink() : Material(
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
                withViewCue(Container(
                  key: const ValueKey('calendar_preview'),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: InsightTheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: InsightTheme.line),
                  ),
                  child: Column(children: [
                    SizedBox(
                      key: const ValueKey('calendar_preview_header'),
                      height: headerHeight,
                      child: Row(children: [
                        IconButton(tooltip: 'Previous preview month', onPressed: widget.onPreviousMonth,
                            icon: const Icon(Icons.chevron_left_rounded, color: InsightTheme.ink2)),
                        Expanded(child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(monthLabel, textAlign: TextAlign.center, style: monthStyle),
                        )),
                        IconButton(tooltip: 'Next preview month', onPressed: widget.onNextMonth,
                            icon: const Icon(Icons.chevron_right_rounded, color: InsightTheme.ink2)),
                      ]),
                    ),
                    Expanded(child: ListView.builder(
                      key: const ValueKey('calendar_preview_days'),
                      controller: _dates,
                      scrollDirection: Axis.horizontal,
                      itemExtent: _dayExtent,
                      itemCount: days,
                      itemBuilder: (context, index) {
                        final day = index + 1;
                        final selected = widget.selectedDay.clamp(1, days) == day;
                        final dayDate = DateTime(widget.month.year, widget.month.month, day);
                        final colors = (widget.tasksByDay[day] ?? const <TaskItem>[])
                            .map(widget.dotColorForTask).toSet().take(3).toList();
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Semantics(
                            container: true,
                            button: true,
                            selected: selected,
                            label: '$monthLabel, $day',
                            child: Material(
                              color: selected ? InsightTheme.blue1 : InsightTheme.surface2,
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => widget.onPick(widget.month, day),
                                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  Text(const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][dayDate.weekday - 1],
                                      style: weekdayStyle.copyWith(color: selected ? Colors.white : InsightTheme.ink2)),
                                  Text('$day', style: numberStyle.copyWith(color: selected ? Colors.white : InsightTheme.ink)),
                                  const SizedBox(height: 2),
                                  SizedBox(height: 4, child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    for (final color in colors)
                                      Container(width: 4, height: 4, margin: const EdgeInsets.symmetric(horizontal: 1),
                                          decoration: BoxDecoration(shape: BoxShape.circle,
                                              color: selected ? Colors.white : color)),
                                  ])),
                                ]),
                              ),
                            ),
                          ),
                        );
                      },
                    )),
                  ]),
                ), 0),
                withViewCue(widget.timeDateView, 1),
              ],
            ),
        ),
      );
    });
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
    final text = '${hour12.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')} ${_now.hour < 12 ? 'AM' : 'PM'}';
    final tasks = widget.tasksForDate(_now);
    final month = _HomeDashboardScreenState._fullMonthNames[_now.month - 1];
    final weekday = const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][_now.weekday - 1];
    return Container(
      key: const ValueKey('clock_date_card'),
      padding: const EdgeInsets.all(8),
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
              container: true,
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
                                  Text(month, textAlign: TextAlign.center, style: InsightTheme.inter(12, w: FontWeight.w600, c: Colors.white)),
                                  Text(weekday, style: InsightTheme.inter(12, w: FontWeight.w600, c: Colors.white)),
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
        width: 48, height: 48,
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
  final Widget? titleAction;
  const _SectionLabel({required this.title, this.trailing, this.titleAction});

  @override
  Widget build(BuildContext context) {
    if (titleAction != null) {
      return LayoutBuilder(builder: (context, constraints) => OverflowBar(
        alignment: MainAxisAlignment.spaceBetween,
        overflowAlignment: OverflowBarAlignment.end,
        spacing: 12,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: Semantics(header: true, child: Text(title,
                  style: InsightTheme.urbanist(16, w: FontWeight.w700, c: InsightTheme.ink)))),
              const SizedBox(width: 8),
              titleAction!,
            ]),
          ),
          ?trailing,
        ],
      ));
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
        color: selected ? InsightTheme.blue1 : InsightTheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.center,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? InsightTheme.blue1 : InsightTheme.line,
              ),
            ),
            child: Text(
              label,
              softWrap: false,
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

/// One flip surface: a concentric chart first, four status tiles on the back.
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
  bool _flipped = false;
  bool _autoFlipEnabled = false;
  Timer? _autoFlip;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _autoFlipEnabled = !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.accessibleNavigationOf(context) &&
        TickerMode.valuesOf(context).enabled && (ModalRoute.isCurrentOf(context) ?? true);
    _restartAutoFlip();
  }

  void _restartAutoFlip() {
    _autoFlip?.cancel();
    if (_autoFlipEnabled) {
      _autoFlip = Timer.periodic(const Duration(seconds: 18), (_) {
        if (mounted) setState(() => _flipped = !_flipped);
      });
    }
  }

  @override
  void dispose() {
    _autoFlip?.cancel();
    super.dispose();
  }

  void _toggleFlip() {
    setState(() => _flipped = !_flipped);
    _restartAutoFlip();
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    Size measure(String text, TextStyle style, {double maxWidth = double.infinity}) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: scaler,
      )..layout(maxWidth: maxWidth);
      final size = painter.size;
      painter.dispose();
      return size;
    }
    final labelMeasureStyle = DefaultTextStyle.of(context).style.merge(
      InsightTheme.inter(14, w: FontWeight.w600, h: 1.2),
    );
    final labelWidth = widget.labels.fold<double>(0,
        (width, label) => max(width, measure(label, labelMeasureStyle).width));
    final overdueLabel = '${widget.overdueCount} Overdue';
    final overdueStyle = InsightTheme.inter(11, w: FontWeight.w700, c: InsightTheme.redInk);
    final overdueSize = measure(overdueLabel, overdueStyle);
    // The centre gap is carved out whether or not a task is overdue: the
    // framework is what carries the shape, and the badge is only a guest in
    // it. With no badge the reserved slot stays empty instead of the block
    // silently closing back into a plain 2x2 grid.
    // Badge plus a small breathing margin; the gap between rows only has to
    // clear this much, so a shorter badge keeps the tiles full-size.
    // With no badge the reserved cross is only as wide as the tile gutter
    // (36 x 10 carves an 18 x 18 cross): wide enough to still read as four
    // tiles joined by a cross, narrow enough that the block stops looking
    // like it has a hole punched in it.
    var notchSize = widget.overdueCount > 0
        ? Size(overdueSize.width + 20, overdueSize.height + 12)
        : const Size(36, 10);

    return LayoutBuilder(
      key: const ValueKey('completion_chart'),
      builder: (context, constraints) {
        // The centre gap carries the badge, so it is wider than the tile gutter.
        // The right-column numbers need room to clear the badge without being
        // pushed off their own tile's left edge.
        const gutter = 8.0;
        final gap = max(gutter, notchSize.width / 2);
        // The badge lives in the centre gap, so the gap between rows must be
        // taller than the badge itself — otherwise the top-row number (bottom
        // of its tile) and the badge share the same pixels. 8 is the floor.
        final rowGap = max(gutter, notchSize.height + 8);
        // One scale with the assignment cards: that row is the Home's normal
        // section height, and a 2x2 block taller than it turns into a hero
        // card that overpowers everything around it. Fixed (not derived from
        // width) because height here is a rhythm decision, not a fit one; text
        // scales with the scaler and the ring takes whatever square it can.
        const height = 220.0;
        // The notch is clamped so the badge never eats more than a third of the
        // block it sits in — at 2x text an unbounded badge swallowed the tiles.
        if (notchSize.height > height / 3) {
          notchSize = Size(min(notchSize.width, constraints.maxWidth / 2),
              height / 3);
        }
        final ringSize = min(constraints.maxWidth, height) - 32;
        return SizedBox(
          width: constraints.maxWidth,
          height: height,
          child: _FlipCard(
            key: const ValueKey('completion_flip'),
            flipped: _flipped,
            onTap: _toggleFlip,
            back: Stack(
              alignment: Alignment.center,
              children: [
                ClipPath(
                  clipper: _CompletionNotchClipper(notchSize),
                  child: Column(
                    children: [
                      for (var row = 0; row < 2; row++) ...[
                        if (row > 0) SizedBox(height: rowGap),
                        Expanded(child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = row * 2; i < row * 2 + 2; i++) ...[
                              if (i.isOdd) SizedBox(width: gap),
                              Expanded(child: _CompletionStatusTile(
                                index: i,
                                label: widget.labels[i],
                                labelWidth: labelWidth,
                                count: widget.counts[i],
                                color: widget.colors[i],
                              )),
                            ],
                          ],
                        )),
                      ],
                    ],
                  ),
                ),
                if (widget.overdueCount > 0)
                  Container(
                    key: const ValueKey('completion_overdue'),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: InsightTheme.redTint,
                        borderRadius: BorderRadius.circular(999)),
                    child: FittedBox(fit: BoxFit.scaleDown, child: Text(overdueLabel, style: overdueStyle)),
                  ),
              ],
            ),
            front: Center(
              key: const ValueKey('completion_ring_chart'),
              child: SizedBox(
                key: const ValueKey('completion_rings'),
                width: ringSize,
                height: ringSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    for (var i = 0; i < widget.labels.length; i++)
                      SizedBox.square(
                        dimension: ringSize * (1 - 0.14 * i),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.0, end: widget.fractions[i].clamp(0.0, 1.0)),
                          duration: reducedMotion ? Duration.zero : const Duration(milliseconds: 750),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, _) => CircularProgressIndicator(
                            value: value,
                            strokeWidth: ringSize * 0.045,
                            strokeCap: StrokeCap.round,
                            backgroundColor: widget.colors[i].withValues(alpha: 0.12),
                            valueColor: AlwaysStoppedAnimation<Color>(widget.colors[i]),
                            semanticsLabel: '${widget.labels[i]}: ${widget.counts[i]} of ${widget.total} tasks',
                          ),
                        ),
                      ),
                    SizedBox.square(
                      key: const ValueKey('completion_readout'),
                      dimension: ringSize * 0.48,
                      child: Center(child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${widget.total}', style: InsightTheme.urbanist(36, w: FontWeight.w800)),
                            Text('Tasks', style: InsightTheme.inter(14, w: FontWeight.w600)),
                          ],
                        ),
                      )),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Back-face artwork only; the parent continues to own all tile geometry.
class _CompletionStatusTile extends StatelessWidget {
  final int index;
  final String label;
  final double labelWidth;
  final int count;
  final Color color;

  const _CompletionStatusTile({
    required this.index,
    required this.label,
    required this.labelWidth,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = switch (index) {
      0 => InsightTheme.orangeInk,
      1 => InsightTheme.blueInk,
      2 => Colors.white,
      _ => InsightTheme.greenInk,
    };
    final tint = switch (index) {
      0 => InsightTheme.orangeTint,
      1 => InsightTheme.blueTint,
      _ => InsightTheme.greenTint,
    };
    final fill = index == 2 ? color : Color.lerp(tint, color, 0.16)!;
    final labelStyle = DefaultTextStyle.of(context).style.merge(
      InsightTheme.inter(14, w: FontWeight.w600, c: foreground, h: 1.2),
    );
    final countStyle = DefaultTextStyle.of(context).style.merge(
      InsightTheme.urbanist(30, w: FontWeight.w800, c: foreground, h: 1.2),
    );
    final scaler = MediaQuery.textScalerOf(context);
    final icon = ExcludeSemantics(child: Container(
      key: ValueKey('completion_icon_$label'),
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: index == 2 ? 0.18 : 0.7),
      ),
      child: CustomPaint(
        size: const Size.square(14),
        painter: _CompletionStatusIconPainter(index, foreground),
      ),
    ));
    Widget fittedText(String value, TextStyle style) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(value, maxLines: 1, softWrap: false, style: style),
    );
    // Measure against the same longest label so narrow tiles keep a unified
    // type size and baseline instead of enlarging only the shorter words.
    final caption = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(constraints: BoxConstraints(minWidth: labelWidth),
        child: Text(label, maxLines: 1, softWrap: false, style: labelStyle)),
    );

    return Container(
      key: ValueKey('completion_$label'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(14)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            right: -24,
            bottom: -40,
            child: Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(shape: BoxShape.circle, color: foreground.withValues(alpha: 0.06)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: LayoutBuilder(builder: (context, constraints) {
              final stackedHeight = 18 + 2 + scaler.scale(14) * 1.2 + 2 + scaler.scale(30) * 1.2;
              if (stackedHeight <= constraints.maxHeight) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    icon,
                    const SizedBox(height: 2),
                    caption,
                    const SizedBox(height: 2),
                    fittedText('$count', countStyle),
                  ],
                );
              }
              if (constraints.maxWidth >= labelWidth + scaler.scale(30) + 8) {
                return Row(
                  children: [
                    Expanded(flex: 3, child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [icon, const SizedBox(height: 4), caption],
                    )),
                    const SizedBox(width: 8),
                    Expanded(flex: 2, child: fittedText('$count', countStyle)),
                  ],
                );
              }
              // Give enlarged labels the full width; the icon moves beside
              // the count so neither text scaling nor artwork grows the tile.
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.topLeft,
                        child: Text('$count', maxLines: 1, softWrap: false, style: countStyle),
                      )),
                      const SizedBox(width: 4),
                      icon,
                    ],
                  )),
                  const SizedBox(height: 2),
                  caption,
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// Original flat glyphs on a shared 24-unit grid, with one rounded stroke.
class _CompletionStatusIconPainter extends CustomPainter {
  final int index;
  final Color color;
  const _CompletionStatusIconPainter(this.index, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (index == 0) {
      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(4, 6, 20, 21), const Radius.circular(2)), stroke);
      canvas.drawPath(Path()
        ..moveTo(8, 3)..lineTo(8, 8)
        ..moveTo(16, 3)..lineTo(16, 8)
        ..moveTo(4, 11)..lineTo(20, 11)
        ..moveTo(8, 15)..lineTo(12, 15)
        ..moveTo(8, 18)..lineTo(15, 18), stroke);
      return;
    }
    canvas.drawCircle(const Offset(12, 12), 9, stroke);
    switch (index) {
      case 1:
        canvas.drawPath(Path()..moveTo(12, 7)..lineTo(12, 12)..lineTo(16, 14), stroke);
      case 2:
        canvas.drawPath(Path()..moveTo(10, 8)..lineTo(16, 12)..lineTo(10, 16)..close(), Paint()..color = color);
      default:
        canvas.drawPath(Path()..moveTo(8, 12)..lineTo(11, 15)..lineTo(16, 9), stroke);
    }
  }

  @override
  bool shouldRepaint(_CompletionStatusIconPainter oldDelegate) =>
      index != oldDelegate.index || color != oldDelegate.color;
}

/// A shared capsule cutout creates the four inward-curved central corners.
class _CompletionNotchClipper extends CustomClipper<Path> {
  final Size notch;
  const _CompletionNotchClipper(this.notch);

  @override
  Path getClip(Size size) => Path()
    ..fillType = PathFillType.evenOdd
    ..addRect(Offset.zero & size)
    ..addRRect(RRect.fromRectAndRadius(
      Rect.fromCenter(center: size.center(Offset.zero), width: notch.width, height: notch.height),
      Radius.circular(notch.height / 2),
    ));

  @override
  bool shouldReclip(_CompletionNotchClipper oldClipper) => oldClipper.notch != notch;
}

/// The whole block turns together; the reverse is counter-rotated for legibility.
class _FlipCard extends StatelessWidget {
  final Widget front;
  final Widget back;
  final bool flipped;

  final VoidCallback onTap;

  const _FlipCard({
    super.key,
    required this.front,
    required this.back,
    required this.flipped,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: flipped,
      label: 'Flip task completion card',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: flipped ? 1.0 : 0.0),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero : const Duration(milliseconds: 620),
          curve: Curves.easeInOutCubic,
          builder: (context, t, _) {
            final onBack = t >= 0.5;
            final face = onBack ? back : front;
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0015)
                ..rotateY(t * pi),
              // Counter-rotate the back face so its text reads normally.
              child: onBack
                  ? Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()..rotateY(pi),
                      child: face,
                    )
                  : face,
            );
          },
        ),
      ),
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
    _swing.animateTo(
      widget.visible ? 1 : 0,
      curve: Curves.easeOutCubic,
    );
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
        Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(
            key: ValueKey('calendar_lanyard'),
            height: 30,
            width: double.infinity,
            child: ExcludeSemantics(child: CustomPaint(painter: _CalendarLanyardPainter())),
          ),
          child,
        ]),
        // Paint the hardware after the card: geometric overlap otherwise gets
        // hidden by the card's opaque background.
        Positioned(
          top: 19,
          child: ExcludeSemantics(child: Container(
            key: const ValueKey('calendar_lanyard_clip'),
            width: 12,
            height: 16,
            decoration: BoxDecoration(
              color: InsightTheme.ink3,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Center(child: Container(width: 12, height: 2, color: InsightTheme.surface)),
          )),
        ),
      ],
    );
}

class _CalendarLanyardPainter extends CustomPainter {
  const _CalendarLanyardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final ribbon = Paint()
      ..color = InsightTheme.blue1.withValues(alpha: 0.62);
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
                    Text('${_monthAbbr[month.month - 1]} ${month.year}',
                        style: InsightTheme.urbanist(15, w: FontWeight.w700, c: InsightTheme.ink)),
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
          ),
          LayoutBuilder(builder: (context, constraints) {
            final dayStyle = InsightTheme.inter(12.5, w: FontWeight.w700);
            final weekdayStyle = InsightTheme.inter(12, w: FontWeight.w700, c: InsightTheme.ink3);
            final columnWidth = constraints.maxWidth / 7;
            Size measure(String label, TextStyle style) {
              final painter = TextPainter(
                text: TextSpan(text: label, style: DefaultTextStyle.of(context).style.merge(style)),
                textDirection: Directionality.of(context), textScaler: MediaQuery.textScalerOf(context),
              )..layout();
              final size = painter.size;
              painter.dispose();
              return size;
            }

            // Adapt the heading, not the user's text size or the grid width.
            var weekdayLength = 3;
            while (weekdayLength > 1 && _weekdayAbbrSunStart.any((label) =>
                measure(label.substring(0, weekdayLength), weekdayStyle).width + 4 > columnWidth)) {
              weekdayLength--;
            }
            var plateWidth = 32.0;
            var plateHeight = 32.0;
            for (var day = 1; day <= daysInMonth; day++) {
              final size = measure('$day', dayStyle);
              if (size.width + 8 > plateWidth) plateWidth = size.width + 8;
              if (size.height + 8 > plateHeight) plateHeight = size.height + 8;
            }
            plateWidth = plateWidth.clamp(0.0, columnWidth).toDouble();
            // Number plate, 2dp separation, 4dp task track, 4dp breathing room.
            // The approved compact Calendar uses the full cell as its target.
            final rowHeight = (plateHeight + 2 + 4 + 4).clamp(44.0, double.infinity).toDouble();
            return Column(children: [
              Row(children: [
                for (var index = 0; index < _weekdayAbbrSunStart.length; index++)
                  Expanded(child: Semantics(
                    key: ValueKey('calendar_weekday_$index'),
                    label: _fullWeekdayNames[(index + 6) % 7],
                    excludeSemantics: true,
                    child: Center(child: Text(_weekdayAbbrSunStart[index].substring(0, weekdayLength),
                        style: weekdayStyle)),
                  )),
              ]),
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
                  final dayTasks = tasksByDayInMonth[day] ?? const <TaskItem>[];
                  final dotColors = dayTasks.map(dotColorForTask).toSet().toList();
                  return Semantics(
                    key: ValueKey('calendar_day_$day'),
                    container: true,
                    button: true,
                    selected: isSelected,
                    label: '${_fullWeekdayNames[DateTime(month.year, month.month, day).weekday - 1]}, '
                        '${_HomeDashboardScreenState._fullMonthNames[month.month - 1]} $day, ${month.year}, '
                        '${dayTasks.length} ${dayTasks.length == 1 ? 'task' : 'tasks'}',
                    onTap: () => onPick(month, day),
                    excludeSemantics: true,
                    child: InkWell(
                      onTap: () => onPick(month, day),
                      borderRadius: BorderRadius.circular(24),
                      child: Center(child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            key: ValueKey('calendar_day_plate_$day'),
                            width: plateWidth,
                            height: plateHeight,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSelected ? InsightTheme.blue1 : Colors.transparent,
                              // A circle at normal text; a content-sized capsule when
                              // large digits need more height than a narrow column.
                              borderRadius: BorderRadius.circular(plateHeight / 2),
                            ),
                            child: Text('$day', style: dayStyle.copyWith(
                                color: isSelected ? Colors.white : InsightTheme.ink)),
                          ),
                          const SizedBox(height: 2),
                          SizedBox(height: 4, child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: (hasTask ? dotColors : const <Color>[]).take(3).map((dotColor) =>
                              Container(
                                margin: const EdgeInsets.symmetric(horizontal: 1),
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
                              ),
                            ).toList(),
                          )),
                        ],
                      )),
                    ),
                  );
                },
              ),
            ]);
          }),
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
                    style: InsightTheme.urbanist(12, w: FontWeight.w700, c: InsightTheme.ink),
                  ),
                  const SizedBox(height: 8),
                  ...selectedTasks.map((task) => _CalendarTaskRow(task: task, color: dotColorForTask(task))),
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
    super.key,
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
          // Timeline node remains within the scrollable modal.
          Container(
            width: 34,
            alignment: Alignment.topCenter,
            padding: const EdgeInsets.only(top: 12),
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
            child: Semantics(
              button: true,
              expanded: _expanded,
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
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 6,
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
                      Text(widget.title, style: InsightTheme.urbanist(14, w: FontWeight.w700, c: InsightTheme.ink)),
                      const SizedBox(height: 5),
                      Container(width: 32, height: 2, decoration: BoxDecoration(color: widget.color.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(2))),
                      if (widget.subtitle.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(widget.subtitle, style: InsightTheme.inter(12, w: FontWeight.w500, c: InsightTheme.ink2)),
                      ],
                      if (_expanded && _exactTimestamp.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.schedule_rounded, size: 13, color: InsightTheme.ink2),
                            const SizedBox(width: 6),
                            Expanded(child: Text(_exactTimestamp, style: InsightTheme.mono(12, w: FontWeight.w500, c: InsightTheme.ink2))),
                          ],
                        ),
                      ],
                    ],
                  ),
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
