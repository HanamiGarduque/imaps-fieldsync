import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart'; 

import '../../../core/models/user_profile.dart';
import '../../../core/models/planning_review_metadata.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/db_helper.dart';

import '../../../core/navigation/parcel_detail_screen.dart';
import '../../inspection/screens/completed_inspection_detail_screen.dart';
import '../../inspection/screens/inspection_progress.dart';
import '../../inspection/widgets/inspection_round_widgets.dart';
import '../../../core/widgets/motion/spring_entrance.dart';
import '../../../core/widgets/motion/updating_tile.dart';
import '../../../core/widgets/motion/linked_list_motion.dart';
import '../../../core/widgets/imaps_loading_indicator.dart';
import '../../../core/widgets/sensitive_screen.dart';
import '../../../core/widgets/field_form_widgets.dart';


import '../../../core/theme/insight_theme.dart';

/// ==================================================================
/// CONSTANTS
/// ==================================================================

/// Height reserved for the pinned Pending/Ongoing/Completed bar in
/// AppBar.bottom, including its 12px bottom gap and the 1px divider.
///
/// Derived from the bar's own metrics rather than guessed: segmented container
/// padding 4+4, tab vertical padding 10+10 around a ~15px row, then the 12px
/// bottom gap and the 1px divider. A regression test asserts the bar still fits
/// (no overflow) at several widths and text scales, so if the tab metrics ever
/// change this constant fails loudly instead of silently clipping.
const double kCategoryBarHeight = 68;

const List<String> rosarioBarangays = [
  'All Barangays', 'Alupay', 'Antipolo', 'Bagong Tubig', 'Bayawang', 'Bulihan', 
  'Cahigam', 'Calantas', 'Colongan', 'Itlugan', 'Lumbangan', 'Macalamcam A', 
  'Macalamcam B', 'Maligaya', 'Marilag', 'Matamis', 'Mawal', 'Mayuro', 'Nasi', 
  'Natu', 'Palakpak', 'Pinagsibaan', 'Poblacion A', 'Poblacion B', 'Poblacion C', 
  'Poblacion D', 'Poblacion E', 'Putingkahoy', 'Quilib', 'Salao', 'San Carlos', 
  'San Ignacio', 'San Isidro', 'San Jose', 'San Roque', 'Santa Cruz', 'Timbugan', 'Tulos'
];

/// ==================================================================
/// MODEL
/// ==================================================================
enum TaskLifecycleCategory { pending, ongoing, completed, unknown }

enum PendingTaskSection { availableAnytime, scheduled }

/// Transitional read compatibility for field_jobs.status.
///
/// Matching is deliberately exact and case-sensitive. Do not trim, lowercase,
/// coerce, or use substring matching here: anything outside this approved map
/// must remain visible to diagnostics rather than entering a normal task list.
TaskLifecycleCategory mapTaskStatusToLifecycle(String? status) {
  return switch (status) {
    'assigned' || 'Pending' || 'pending' => TaskLifecycleCategory.pending,
    'in_progress' || 'in-progress' || 'ongoing' =>
      TaskLifecycleCategory.ongoing,
    'completed' || 'Completed' || 'submitted' =>
      TaskLifecycleCategory.completed,
    _ => TaskLifecycleCategory.unknown,
  };
}

class TaskItem {
  final String id;
  final int? localInspectionId;
  final int? inspectionRoundNumber;
  final int? previousSiteInspectionId;
  final String? reinspectionReason;
  final String? reinspectionReviewedAt;
  final String? parcelId;
  final String name;
  final String location;
  final String parcels; 
  final String? status;
  final String inspectionNo;
  final String scheduledDate;
  final String? deadlineDate;
  final String landUseClass;
  final double? lotAreaSqm;
  final String? propertyIndexNumber;
  final String? applicationType;

  final String? findings;
  final String? assignmentInstructions;
  // Loop 3 — Assigning Planning Officer (read-only; iMAPS-owned).
  // Never written by FieldSync. Null when columns are absent from Supabase
  // (schema not yet applied) — display remains neutral/unavailable.
  final String? assignedByImapsUserId;
  final String? assignedByName;
  // Exact remote identity used only to author Application Support reports.
  // NULL for upgraded v14 cache rows until the task is refreshed online; such
  // rows become ineligible for Application Support and show an honest state.
  final String? supabaseApplicationId;
  final String? bridgeSourceId;
  final String? observations;
  final String? discrepancies;
  final String? recommendations;
  final String? inspectorNotes;
  final String? inspectionResult;
  final bool? isCompliant;
  final List<String> photoPaths;
  // Fix (Step 3 / photo-notes audit, 2026-07): photoPaths (from
  // field_jobs.photo_paths) is only a flat list of URLs — it never carried
  // the per-photo note the inspector typed at capture time. That note
  // actually lives in the field_job_photos join (fetched by
  // fetchJobDetail's `field_job_photos(...)` select) and was simply never
  // read into TaskItem before. This carries the richer per-photo record
  // (url/notes/lat/lng/captured_at) through so the Summary can show it.
  final List<Map<String, dynamic>> photoDetails;
  final int photoCount;
  final int checklistCompletedCount;
  final int checklistTotalCount;
  final String? submittedAt;
  final List<Map<String, dynamic>> checklistData;
  final double? confirmedLatitude;
  final double? confirmedLongitude;
  final double? gpsAccuracyM;
  final String? gpsConfirmedAt;
  final String? applicantPhone;
  final String? applicantEmail;
  final int currentStep;
  final bool isSelfScheduled;
  // F1 fix: real per-step saved times, parsed from field_jobs.step_timestamps
  // ({"1": "2026-08-25T04:00:00.000Z", ...}). Keyed by step number so the
  // Task Overview can show when each step was actually saved per task.
  final Map<int, String> stepTimestamps;
  final String createdAt;
  final String? startedAt;
  // Rework redesign: non-null while a completed task has an unfinished
  // rework session — status itself stays 'completed' throughout, so this
  // is the actual signal for the "Modified" badge. Cleared back to null
  // on finalize (Review & Submit).
  final String? reworkStartedAt;
  // Enhancement (Completed/Summary, 2026-07): DB-driven "last saved" signal.
  // field_jobs.updated_at is auto-maintained by the trg_field_jobs_set_updated_at
  // trigger on every UPDATE, so it reflects the true last-write time for both
  // a normal submit and any in-progress rework edit — no new column needed.
  final String? updatedAt;
  // Loop 8 — optional, read-only Planning Review metadata for THIS exact
  // inspection round. Presentational only: it must never alter status, category,
  // current_step, progress or completed state, and its absence is meaningful
  // (no review row = no Planning Review section, nothing inferred).
  final PlanningReviewMetadata? planningReview;

  TaskItem({
    this.localInspectionId, this.inspectionRoundNumber,
    this.previousSiteInspectionId, this.reinspectionReason, this.reinspectionReviewedAt,
    required this.id, this.parcelId, required this.name, required this.location,
    required this.parcels, required this.status, required this.inspectionNo, 
    this.scheduledDate = '', this.deadlineDate, this.landUseClass = 'Not yet on file', this.lotAreaSqm,
    this.propertyIndexNumber, this.applicationType, this.findings, this.observations,
    this.discrepancies, this.recommendations, this.inspectorNotes, this.assignmentInstructions,
    this.assignedByImapsUserId, this.assignedByName,
    this.supabaseApplicationId, this.bridgeSourceId,
    this.inspectionResult,
    this.isCompliant, this.photoPaths = const [], this.photoDetails = const [], this.photoCount = 0,
    this.checklistCompletedCount = 0, this.checklistTotalCount = 0, this.submittedAt,
    this.checklistData = const [], this.confirmedLatitude, this.confirmedLongitude,
    this.gpsAccuracyM, this.gpsConfirmedAt, this.isSelfScheduled = false,
    this.stepTimestamps = const <int, String>{},
    this.applicantPhone, this.applicantEmail,
    this.currentStep = 0,
    this.createdAt = '',
    this.startedAt,
    this.reworkStartedAt,
    this.updatedAt,
    this.planningReview,
  });

  factory TaskItem.fromJob(Map<String, dynamic> job) {
    final application = job['supabase_zoning_applications'] as Map<String, dynamic>?;
    final parcel = job['supabase_parcels'] as Map<String, dynamic>?;
    final scheduledDate = job['scheduled_date'] as String? ?? '';
    return TaskItem(
      id: job['id']?.toString() ?? '',
      localInspectionId: (job['local_inspection_id'] as num?)?.toInt(),
      inspectionRoundNumber: (job['inspection_round_number'] as num?)?.toInt(),
      previousSiteInspectionId: (job['previous_site_inspection_id'] as num?)?.toInt(),
      reinspectionReason: job['reinspection_reason'] as String?,
      reinspectionReviewedAt: job['reinspection_reviewed_at'] as String?,
      parcelId: job['supabase_parcel_id'] as String?,
      name: application?['applicant_name'] as String? ?? 'Unknown Applicant',
      location: application?['barangay'] as String? ?? 'No barangay listed',
      applicantPhone: (application?['contact_number'] as String?)?.trim().isNotEmpty == true
          ? (application?['contact_number'] as String).trim()
          : null,
      applicantEmail: (application?['email'] as String?)?.trim().isNotEmpty == true
          ? (application?['email'] as String).trim()
          : null,
      parcels: scheduledDate.isNotEmpty ? scheduledDate : application?['reference_number'] as String? ?? 'No schedule',
      status: job['status'] as String?,
      inspectionNo: application?['reference_number'] as String? ?? job['local_inspection_id']?.toString() ?? 'N/A',
      scheduledDate: scheduledDate,
      deadlineDate: job['deadline_date'] as String?,
      landUseClass: parcel?['land_use_class'] as String? ?? 'Not yet on file',
      lotAreaSqm: (parcel?['lot_area_sqm'] as num?)?.toDouble(),
      propertyIndexNumber: parcel?['property_index_number'] as String?,
      findings: job['findings'] as String?,
      observations: job['observations'] as String?,
      discrepancies: job['discrepancies'] as String?,
      recommendations: job['recommendations'] as String?,
      inspectorNotes: job['inspector_notes'] as String?,
      assignmentInstructions: job['assignment_instructions'] as String?,
      // Loop 3 — read-only; null gracefully when Supabase columns are not yet live.
      assignedByImapsUserId: job['assigned_by_imaps_user_id']?.toString(),
      assignedByName: job['assigned_by_name'] as String?,
      inspectionResult: job['inspection_result'] as String?,
      isCompliant: job['is_compliant'] as bool?,
      photoPaths: (job['photo_paths'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      photoDetails: (job['field_job_photos'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
      photoCount: (job['photo_count'] as num?)?.toInt() ?? 0,
      checklistCompletedCount: (job['checklist_completed_count'] as num?)?.toInt() ?? 0,
      checklistTotalCount: (job['checklist_total_count'] as num?)?.toInt() ?? 0,
      submittedAt: job['submitted_at'] as String?,
      checklistData: (job['checklist_data'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? const [],
      confirmedLatitude: (job['confirmed_latitude'] as num?)?.toDouble(),
      confirmedLongitude: (job['confirmed_longitude'] as num?)?.toDouble(),
      gpsAccuracyM: (job['gps_accuracy_m'] as num?)?.toDouble(),
      gpsConfirmedAt: job['gps_confirmed_at'] as String?,
      applicationType: application?['application_type'] as String?,
      isSelfScheduled: job['is_self_scheduled'] as bool? ?? false,
      stepTimestamps: job['step_timestamps'] is Map
          ? (job['step_timestamps'] as Map).map(
              (k, v) => MapEntry(int.tryParse(k.toString()) ?? 0, v.toString()),
            )
          : const <int, String>{},
      currentStep: (job['current_step'] as num?)?.toInt() ?? 0,
      createdAt: job['created_at'] as String? ?? '',
      startedAt: job['started_at'] as String?,
      reworkStartedAt: job['rework_started_at'] as String?,
      updatedAt: job['updated_at'] as String?,
      supabaseApplicationId: job['supabase_application_id'] as String?,
      bridgeSourceId: job['bridge_source_id'] as String?,
      // Loop 8 — read-only review metadata, resolved by exact field_job_id.
      planningReview: PlanningReviewMetadata.fromJobRow(job),
    );
  }

  factory TaskItem.fromCachedJob(Map<String, dynamic> row) => TaskItem.fromJob({
    ...row,
    'is_self_scheduled': row['is_self_scheduled'] == 1,
    'updated_at': row['cached_updated_at'],
    'supabase_zoning_applications': {
      'applicant_name': row['applicant_name'], 'barangay': row['barangay'],
      'reference_number': row['reference_number'], 'application_type': row['application_type'],
    },
    'supabase_parcels': {
      'land_use_class': row['declared_land_use'], 'lot_area_sqm': row['lot_area_sqm'],
    },
  });

  bool get isReinspection => previousSiteInspectionId != null ||
      (inspectionRoundNumber != null && inspectionRoundNumber! > 1);
  String? get roundLabel => inspectionRoundNumber != null && inspectionRoundNumber! > 0
      ? '${isReinspection ? 'Reinspection — ' : ''}Round $inspectionRoundNumber'
      : (isReinspection ? 'Reinspection' : null);

  bool sameApplicationAs(TaskItem other) => supabaseApplicationId != null &&
      bridgeSourceId != null && supabaseApplicationId == other.supabaseApplicationId &&
      bridgeSourceId == other.bridgeSourceId;

  String previousRoundLabel(Iterable<TaskItem> rounds) {
    for (final round in rounds) {
      if (sameApplicationAs(round) && previousSiteInspectionId != null &&
          round.localInspectionId == previousSiteInspectionId &&
          round.inspectionRoundNumber != null && round.inspectionRoundNumber! > 0) {
        return 'Round ${round.inspectionRoundNumber}';
      }
    }
    return 'Previous inspection round';
  }

  /// Highest step (0-6) verifiably done, based on what's ACTUALLY saved in
  /// the DB — not client-side session memory. This is what makes progress
  /// survive app restarts and stay correct when switching between tasks
  /// (each task derives its own number from its own real data).
  int get derivedHighestStep {
    if (lifecycleCategory == TaskLifecycleCategory.completed) return 6;
    final hasFindings = (observations?.isNotEmpty ?? false) ||
        (discrepancies?.isNotEmpty ?? false) ||
        (recommendations?.isNotEmpty ?? false) ||
        (inspectorNotes?.isNotEmpty ?? false);
    if (hasFindings) return 5;
    if (checklistCompletedCount > 0) return 4;
    if (photoCount > 0 || photoPaths.isNotEmpty) return 3;
    if (confirmedLatitude != null && confirmedLongitude != null) return 2;
    if (lifecycleCategory == TaskLifecycleCategory.ongoing) return 1;
    return 0;
  }

  TaskLifecycleCategory get lifecycleCategory => mapTaskStatusToLifecycle(status);

  String get category => switch (lifecycleCategory) {
    TaskLifecycleCategory.pending => 'Pending',
    TaskLifecycleCategory.ongoing => 'Ongoing',
    TaskLifecycleCategory.completed => 'Completed',
    TaskLifecycleCategory.unknown => 'Unknown',
  };

  PendingTaskSection? get pendingSection {
    if (lifecycleCategory != TaskLifecycleCategory.pending) return null;
    return isSelfScheduled
        ? PendingTaskSection.scheduled
        : PendingTaskSection.availableAnytime;
  }

  String? get forReschedule {
    // Gate on isSelfScheduled directly — scheduledDate is non-nullable and
    // always populated in the DB even for tasks the inspector never chose
    // a visit date for, so checking scheduledDate alone (as before) let
    // this fire for every category, not just Scheduled.
    if (!isSelfScheduled || scheduledDate.isEmpty) return null;
    try {
      final visitDate = DateTime.parse(scheduledDate);
      final today = DateTime.now();
      final visitDay = DateTime(visitDate.year, visitDate.month, visitDate.day);
      final todayDay = DateTime(today.year, today.month, today.day);
      if (!visitDay.isBefore(todayDay)) return null;
      if (deadlineDate == null || deadlineDate!.isEmpty) return 'For Reschedule';
      final deadline = DateTime.parse(deadlineDate!);
      final deadlineDay = DateTime(deadline.year, deadline.month, deadline.day);
      if (deadlineDay.isAfter(todayDay)) return 'For Reschedule';
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Due Today / Overdue, correctly split by category (Fix 3):
  /// - Overdue is ALWAYS Deadline-driven, checked first (more severe,
  ///   admin-set cutoff, applies to every category alike).
  /// - For Scheduled tasks (isSelfScheduled true), Due Today is
  ///   Visit-date-driven — this is the deliberate date the inspector chose.
  /// - For Pending (Available Anytime) / Ongoing tasks, Due Today is
  ///   Deadline-driven — scheduledDate is just a non-nullable DB default
  ///   for these, never a real commitment, so it must NOT be consulted here
  ///   (this was the root cause of "Due Today" appearing on brand-new
  ///   Available Anytime tasks whose default scheduled_date happened to
  ///   equal today's date).
  String? get scheduleUrgency {
    final today = DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);

    if (deadlineDate != null && deadlineDate!.isNotEmpty) {
      try {
        final due = DateTime.parse(deadlineDate!);
        final dueDay = DateTime(due.year, due.month, due.day);
        if (dueDay.isBefore(todayDay)) return 'Overdue';
      } catch (_) {}
    }

    if (isSelfScheduled && scheduledDate.isNotEmpty) {
      try {
        final due = DateTime.parse(scheduledDate);
        final dueDay = DateTime(due.year, due.month, due.day);
        if (dueDay.isAtSameMomentAs(todayDay)) return 'Due today';
      } catch (_) {}
      return null; // Scheduled, visit not today, not overdue — nothing yet
    }

    if (deadlineDate != null && deadlineDate!.isNotEmpty) {
      try {
        final due = DateTime.parse(deadlineDate!);
        final dueDay = DateTime(due.year, due.month, due.day);
        if (dueDay.isAtSameMomentAs(todayDay)) return 'Due today';
      } catch (_) {}
    }
    return null;
  }

  IconData get typeIcon {
    final t = '${applicationType ?? ''} $landUseClass'.toLowerCase();
    if (t.contains('commercial')) return Icons.location_city_rounded;
    if (t.contains('industrial')) return Icons.factory_rounded;
    if (t.contains('agri')) return Icons.grass_rounded;
    if (t.contains('institutional')) return Icons.account_balance_rounded;
    return Icons.home_rounded;
  }

  /// Visit-date urgency for Scheduled tasks. Red is kept for the visit day and
  /// any passed visit date until the task reaches deadline overdue. Orange is
  /// used for 2-3 days away; blue is the normal/default state.
  bool get isUrgentDeadline {
    // Gate on isSelfScheduled directly, not the old isScheduledPlan (which
    // incorrectly treated every task as "on the schedule plan" since
    // scheduledDate is never actually empty in the DB).
    if (!isSelfScheduled || scheduledDate.isEmpty) return false;
    try {
      final due = DateTime.parse(scheduledDate);
      final today = DateTime.now();
      final dueDay = DateTime(due.year, due.month, due.day);
      final todayDay = DateTime(today.year, today.month, today.day);
      final diff = dueDay.difference(todayDay).inDays;
      return diff <= 1 || dueDay.isBefore(todayDay);
    } catch (_) {
      return false;
    }
  }
}

/// ==================================================================
/// TASKS SCREEN
/// ==================================================================
class TasksScreen extends StatefulWidget {
  final UserProfile profile;

  /// Which segment tab to land on when this screen mounts.
  /// Use the `TasksScreen.tab*` constants instead of raw ints so
  /// callers stay readable and in sync with `_visibleTabOrder`.
  final int initialTabIndex;

  // Phase 3 (My Tasks status architecture): "Scheduled" is not a lifecycle
  // category or segment tab. It is a subsection inside Pending, selected only
  // after the explicit lifecycle mapper classifies a task as Pending.
  static const int tabPending = 0;
  static const int tabOngoing = 1;
  static const int tabCompleted = 2;

  /// When true, mounts on the Pending tab and auto-scrolls to the
  /// "Scheduled" section header once tasks finish loading — used by the
  /// Home dashboard's "Schedule" quick action, which used to jump straight
  /// to the now-removed standalone Scheduled tab.
  final bool scrollToScheduled;

  const TasksScreen({
    super.key,
    required this.profile,
    this.initialTabIndex = tabOngoing,
    this.scrollToScheduled = false,
  });

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> with TickerProviderStateMixin, SpringEntrance {
  late int _currentTabIndex;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _datePreset; // 'last30' | 'last6months' | 'custom' | null
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  String _selectedBarangay = 'All Barangays';
  // 'All' | 'Urgent' | 'Scheduled' | 'Overdue' — finalized urgency
  // quick-filter inside the filter sheet (deadline-driven; see the
  // switch in _categorizeAndFilter for each option's exact condition).
  String _urgencyFilter = 'All';

  static const _tabOrder = ['Pending', 'Ongoing', 'Completed'];
  static const _visibleTabOrder = _tabOrder;

  final GlobalKey _scheduledSectionKey = GlobalKey();
  bool _pendingScrollToScheduled = false;

  List<TaskItem> _allTasks = [];
  final Set<String> _diagnosedUnknownTaskIds = <String>{};
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _currentTabIndex = widget.scrollToScheduled ? TasksScreen.tabPending : widget.initialTabIndex;
    PaintingBinding.instance.systemFonts.addListener(_onFontsChanged);
    _pendingScrollToScheduled = widget.scrollToScheduled;
    _loadTasks();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    PaintingBinding.instance.systemFonts.removeListener(_onFontsChanged);
    disposeSpringEntrance();
    super.dispose();
  }

  void _onFontsChanged() { if (mounted) setState(() {}); }

  /// Runs once after the first frame where the Scheduled section actually
  /// has content to scroll to — skips silently (and un-arms itself) if the
  /// inspector has no scheduled tasks, since there's nothing to show.
  void _maybeScrollToScheduledSection() {
    if (!_pendingScrollToScheduled) return;
    _pendingScrollToScheduled = false; // one-shot, regardless of outcome
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _scheduledSectionKey.currentContext;
      if (ctx == null || !mounted) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignment: 0.0,
      );
    });
  }

  /// Renders one task row exactly as before — factored out so both the
  /// flat tabs (Ongoing/Completed) and the headed Pending tab build the
  /// identical card/animation wrapper, byte-for-byte with the pre-Phase-3
  /// version.
  Widget _buildTaskRow(BuildContext context, TaskItem task, int index) {
    return LinkedListSlide(
      key: ValueKey('linked_tab_${_currentTabIndex}_${task.id}'),
      index: index,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: UpdatingTile(
          itemKey: task.id,
          signature: Object.hash(task.status, task.scheduledDate, task.deadlineDate),
          child: _CompactTaskCard(
            key: ValueKey(task.id),
            task: task,
            onTapDetail: () => _openTask(context, task),
            onScheduled: _loadTasks,
            relatedRounds: _allTasks.where(task.sameApplicationAs).toList(),
            onOpenRound: (round) => _openTask(context, round),
          ),
        ),
      ),
    );
  }

  Future<void> _loadTasks() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final dynamic connectivityResult = await Connectivity().checkConnectivity();
      final bool hasConnection = (connectivityResult is ConnectivityResult) 
          ? connectivityResult != ConnectivityResult.none
          : (connectivityResult as List).any((status) => status != ConnectivityResult.none);

      if (hasConnection) {
        final jobs = await SupabaseService.fetchMyJobs();
        await DBHelper.cacheJobs(jobs);
        if (mounted) {
          setState(() {
            _allTasks = jobs.map((j) => TaskItem.fromJob(j)).toList();
            _isLoading = false;
          });
          _maybeScrollToScheduledSection();
        }
      } else {
        final localJobs = await DBHelper.getCachedJobs();
        if (mounted) {
          setState(() {
            _allTasks = localJobs.map(TaskItem.fromCachedJob).toList();
            _isLoading = false;
          });
          _maybeScrollToScheduledSection();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load tasks: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _openTask(BuildContext context, TaskItem task) async {
    HapticFeedback.selectionClick();
    if (task.category == 'Completed') {
      final historical = task.planningReview?.decision == 'Requires Reinspection' ||
          _allTasks.any((round) => task.sameApplicationAs(round) &&
            round.previousSiteInspectionId == task.localInspectionId && task.localInspectionId != null);
      await Navigator.push(context, MaterialPageRoute(builder: (_) => CompletedInspectionDetailScreen(task: task, historicalReadOnly: historical)));
    } else {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ParcelDetailScreen(task: task,
        relatedRounds: _allTasks.where(task.sameApplicationAs).toList())));
    }
    if (mounted) _loadTasks();
  }
  
  void _showFilterBottomSheet() {
    HapticFeedback.lightImpact();
    String? tempDatePreset = _datePreset;
    DateTime? tempStartDate = _customStartDate;
    DateTime? tempEndDate = _customEndDate;
    String tempBarangay = _selectedBarangay;
    String tempUrgency = _urgencyFilter;
    String barangaySearchQuery = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          final filteredBarangays = rosarioBarangays
              .where((b) => b.toLowerCase().contains(barangaySearchQuery.toLowerCase()))
              .toList();

          return Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              top: 12, left: 24, right: 24,
            ),
            decoration: const BoxDecoration(
              color: InsightTheme.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [BoxShadow(color: Color(0x1A000000), blurRadius: 40, offset: Offset(0, -10))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(color: InsightTheme.line, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Filter & Sort', style: InsightTheme.poppins(18, w: FontWeight.w600)),
                    TextButton(
                      onPressed: () {
                        setModalState(() {
                          tempDatePreset = null;
                          tempStartDate = null;
                          tempEndDate = null;
                          tempBarangay = 'All Barangays';
                          tempUrgency = 'All';
                          barangaySearchQuery = '';
                        });
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text('Reset', style: InsightTheme.inter(13, w: FontWeight.w600, c: InsightTheme.blue1)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(color: InsightTheme.line, height: 1),
                
                Flexible(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),

                        // URGENCY SECTION — disjoint filter model (revised
                        // after testing showed Urgent ⊇ Overdue made the two
                        // chips return identical counts): All / Urgent /
                        // Scheduled / Overdue — Urgent = admin deadline_date
                        // is today or tomorrow (approaching, NOT yet past),
                        // Scheduled = on the schedule plan (orange), Overdue
                        // = admin deadline already passed. No overlap between
                        // Urgent and Overdue; each matches its card badge.
                        // Visit date drives no filter option; Completed
                        // never matches.
                        Row(
                          children: [
                            const Icon(Icons.priority_high_rounded, color: InsightTheme.ink3, size: 18),
                            const SizedBox(width: 8),
                            Text('FILTER BY URGENCY', style: InsightTheme.inter(11, w: FontWeight.w700, c: InsightTheme.ink3, ls: 1.0)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _NativeFilterChip(
                                label: 'All',
                                isSelected: tempUrgency == 'All',
                                onTap: () => setModalState(() => tempUrgency = 'All'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _NativeFilterChip(
                                label: 'Urgent',
                                isSelected: tempUrgency == 'Urgent',
                                onTap: () => setModalState(() => tempUrgency = 'Urgent'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _NativeFilterChip(
                                label: 'Scheduled',
                                isSelected: tempUrgency == 'Scheduled',
                                onTap: () => setModalState(() => tempUrgency = 'Scheduled'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _NativeFilterChip(
                                label: 'Overdue',
                                isSelected: tempUrgency == 'Overdue',
                                onTap: () => setModalState(() => tempUrgency = 'Overdue'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Expanded(child: SizedBox()),
                            const SizedBox(width: 8),
                            const Expanded(child: SizedBox()),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // DATE RANGE SECTION
                        Row(
                          children: [
                            const Icon(Icons.date_range_rounded, color: InsightTheme.ink3, size: 18),
                            const SizedBox(width: 8),
                            Text('FILTER BY DATE RANGE', style: InsightTheme.inter(11, w: FontWeight.w700, c: InsightTheme.ink3, ls: 1.0)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _NativeFilterChip(
                                label: 'Last 30 Days',
                                isSelected: tempDatePreset == 'last30',
                                onTap: () => setModalState(() {
                                  tempDatePreset = 'last30';
                                  tempStartDate = null;
                                  tempEndDate = null;
                                }),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _NativeFilterChip(
                                label: 'Last 6 Months',
                                isSelected: tempDatePreset == 'last6months',
                                onTap: () => setModalState(() {
                                  tempDatePreset = 'last6months';
                                  tempStartDate = null;
                                  tempEndDate = null;
                                }),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text('CUSTOM DATE RANGE', style: InsightTheme.inter(11, w: FontWeight.w700, c: InsightTheme.ink3, ls: 1.0)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _DatePickerChip(
                                label: tempStartDate == null
                                    ? 'Start date'
                                    : '${tempStartDate!.year}-${tempStartDate!.month.toString().padLeft(2, '0')}-${tempStartDate!.day.toString().padLeft(2, '0')}',
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: tempStartDate ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now(),
                                  );
                                  if (picked != null) {
                                    setModalState(() {
                                      tempStartDate = picked;
                                      tempDatePreset = 'custom';
                                    });
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _DatePickerChip(
                                label: tempEndDate == null
                                    ? 'End date'
                                    : '${tempEndDate!.year}-${tempEndDate!.month.toString().padLeft(2, '0')}-${tempEndDate!.day.toString().padLeft(2, '0')}',
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: tempEndDate ?? DateTime.now(),
                                    firstDate: tempStartDate ?? DateTime(2020),
                                    lastDate: DateTime.now(),
                                  );
                                  if (picked != null) {
                                    setModalState(() {
                                      tempEndDate = picked;
                                      tempDatePreset = 'custom';
                                    });
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        
                        // SEARCHABLE BARANGAY SECTION
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined, color: InsightTheme.ink3, size: 18),
                            const SizedBox(width: 8),
                            Text('BARANGAY', style: InsightTheme.inter(11, w: FontWeight.w700, c: InsightTheme.ink3, ls: 1.0)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        
                         // Local Search Bar inside Sheet
                         Container(
                           constraints: const BoxConstraints(minHeight: 48),
                          decoration: BoxDecoration(
                            color: InsightTheme.bg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: InsightTheme.line),
                          ),
                          child: TextField(
                            style: InsightTheme.inter(14, w: FontWeight.w400, c: InsightTheme.ink),
                            decoration: const InputDecoration(
                              hintText: 'Search fields or barangays...',
                              hintStyle: TextStyle(color: InsightTheme.ink3, fontSize: 14),
                              prefixIcon: Icon(Icons.search_rounded, color: InsightTheme.ink2, size: 18),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(vertical: 11),
                            ),
                            onChanged: (value) {
                              setModalState(() {
                                barangaySearchQuery = value;
                              });
                            },
                          ),
                        ),
                        const SizedBox(height: 10),
                        
                        // Filtered Scrollable List Frame
                        Container(
                          height: 180,
                          decoration: BoxDecoration(
                            color: InsightTheme.bg.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: InsightTheme.line),
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: filteredBarangays.length,
                            physics: const BouncingScrollPhysics(),
                            itemBuilder: (context, idx) {
                              final b = filteredBarangays[idx];
                              final isSelected = tempBarangay == b;
                              return InkWell(
                                onTap: () {
                                  setModalState(() {
                                    tempBarangay = b;
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  // No divider between items (visual fix per
                                  // user feedback): the per-row bottom border
                                  // made the list look like a striped table.
                                  // Selection is communicated by the tint +
                                  // check icon alone.
                                  decoration: BoxDecoration(
                                    color: isSelected ? InsightTheme.blueTint : Colors.transparent,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        b, 
                                        style: InsightTheme.inter(14, w: isSelected ? FontWeight.w600 : FontWeight.w400, c: isSelected ? InsightTheme.blue2 : InsightTheme.ink)
                                      ),
                                      if (isSelected)
                                        const Icon(Icons.check_circle_rounded, color: InsightTheme.blue1, size: 18),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
                
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _datePreset = tempDatePreset;
                        _customStartDate = tempStartDate;
                        _customEndDate = tempEndDate;
                        _selectedBarangay = tempBarangay;
                        _urgencyFilter = tempUrgency;
                      });
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: InsightTheme.blue1,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    child: Text('Apply Filters', style: InsightTheme.inter(14, w: FontWeight.w600, c: Colors.white)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _diagnoseUnknownStatus(TaskItem task) {
    final diagnosticKey = '${task.id}:${task.status ?? '<null>'}';
    if (_diagnosedUnknownTaskIds.add(diagnosticKey)) {
      debugPrint(
        '[MyTasks] Excluded task ${task.id} from lifecycle lists: '
        'unrecognized status ${task.status == null ? '<null>' : '"${task.status}"'}.',
      );
    }
  }

  Map<String, List<TaskItem>> _categorizeAndFilter() {
    final map = <String, List<TaskItem>>{
      for (final t in _tabOrder) t: <TaskItem>[],
    };

    for (final task in _allTasks) {
      if (task.lifecycleCategory == TaskLifecycleCategory.unknown) {
        _diagnoseUnknownStatus(task);
        continue;
      }

      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        if (!task.name.toLowerCase().contains(query) &&
            !task.location.toLowerCase().contains(query) &&
            !task.inspectionNo.toLowerCase().contains(query)) {
          continue;
        }
      }
      if (_selectedBarangay != 'All Barangays') {
        if (!task.location.toLowerCase().contains(_selectedBarangay.toLowerCase())) continue;
      }
      if (_urgencyFilter != 'All') {
        final bool isCompleted = task.category == 'Completed';
        bool matches;
        switch (_urgencyFilter) {
          case 'Urgent':
            matches = !isCompleted && (task.scheduleUrgency == 'Due today' || task.isUrgentDeadline);
            break;
          case 'Scheduled':
            matches =
                task.pendingSection == PendingTaskSection.scheduled;
            break;
          case 'Overdue':
            matches = !isCompleted && task.scheduleUrgency == 'Overdue';
            break;
          default:
            matches = true;
        }
        if (!matches) continue;
      }
      if (_datePreset != null && task.scheduledDate.isNotEmpty) {
        try {
          final taskDate = DateTime.parse(task.scheduledDate);
          if (_datePreset == 'last30') {
            if (taskDate.isBefore(DateTime.now().subtract(const Duration(days: 30)))) continue;
          } else if (_datePreset == 'last6months') {
            if (taskDate.isBefore(DateTime.now().subtract(const Duration(days: 182)))) continue;
          } else if (_datePreset == 'custom') {
            if (_customStartDate != null && taskDate.isBefore(_customStartDate!)) continue;
            if (_customEndDate != null && taskDate.isAfter(_customEndDate!)) continue;
          }
        } catch (_) {}
      }
      map[task.category]!.add(task);
    }

    for (final category in map.keys) {
      map[category]!.sort((a, b) {
        switch (category) {
          case 'Pending':
            return a.createdAt.compareTo(b.createdAt);
          case 'Ongoing':
            final sa = a.startedAt ?? a.createdAt;
            final sb = b.startedAt ?? b.createdAt;
            return sa.compareTo(sb);
          case 'Completed':
            final sa = a.submittedAt ?? '';
            final sb = b.submittedAt ?? '';
            return sb.compareTo(sa);
          default:
            return 0;
        }
      });
    }
    return map;
  }

  /// The Pending / Ongoing / Completed segmented switcher.
  ///
  /// Extracted so the exact same widget can be mounted in AppBar.bottom (where
  /// it stays pinned) without duplicating it or leaving a second copy behind in
  /// the scroll view. Same `_currentTabIndex` state and same tap handlers —
  /// presentation only, category logic untouched.
  Widget _buildCategoryBar(
      int pendingCount, int ongoingCount, int completedCount) {
    // The opaque outer surface is what makes this safe to pin: the Search /
    // Filter row scrolling up disappears behind it rather than bleeding through.
    return Container(
      color: InsightTheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: SpringSlide(
          animation: springFor(2),
          beginOffset: const Offset(0, 22),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: InsightTheme.surface2,
              borderRadius: BorderRadius.circular(14),
            ),
            child: LayoutBuilder(builder: (context, constraints) {
              return SingleChildScrollView(scrollDirection: Axis.horizontal, child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: IntrinsicWidth(child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: _SegmentTab(
                    text: "Pending",
                    count: pendingCount,
                    isActive: _currentTabIndex == 0,
                    onTap: () => setState(() => _currentTabIndex = 0),
                  ),
                ),
                Expanded(
                  child: _SegmentTab(
                    text: "Ongoing",
                    count: ongoingCount,
                    isActive: _currentTabIndex == 1,
                    onTap: () => setState(() => _currentTabIndex = 1),
                  ),
                ),
                Expanded(
                  child: _SegmentTab(
                    text: "Completed",
                    count: completedCount,
                    isActive: _currentTabIndex == 2,
                    onTap: () => setState(() => _currentTabIndex = 2),
                  ),
                ),
              ],
            ))));
            }),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categorized = _categorizeAndFilter();
    final scaler = MediaQuery.textScalerOf(context);
    Size measureHeader(String text, TextStyle style, {double width = double.infinity}) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: DefaultTextStyle.of(context).style.merge(style)),
        textDirection: Directionality.of(context), textScaler: scaler,
      )..layout(maxWidth: width);
      final size = painter.size;
      painter.dispose();
      return size;
    }
    final titleStyle = InsightTheme.urbanist(26, w: FontWeight.w800, c: InsightTheme.ink, ls: -0.4);
    final assignedStyle = InsightTheme.inter(12, w: FontWeight.w600, c: InsightTheme.ink3);
    final countSize = measureHeader('${_allTasks.length}', InsightTheme.urbanist(22, w: FontWeight.w800, h: 1));
    final assignedSize = measureHeader('ASSIGNED', assignedStyle);
    final counterWidth = countSize.width.clamp(assignedSize.width, double.infinity) + 32;
    final availableWidth = MediaQuery.sizeOf(context).width - MediaQuery.paddingOf(context).horizontal - 40;
    final naturalTitleWidth = measureHeader('My Tasks', titleStyle).width;
    final stackedHeader = naturalTitleWidth + counterWidth + 12 > availableWidth;
    final titleWidth = stackedHeader ? availableWidth : availableWidth - counterWidth - 12;
    final titleHeight = measureHeader('My Tasks', titleStyle, width: titleWidth).height;
    final counterHeight = countSize.height + assignedSize.height + 22;
    final headerHeight = (12 + (stackedHeader ? titleHeight + counterHeight + 8
        : titleHeight.clamp(counterHeight, double.infinity))).ceilToDouble().clamp(kToolbarHeight, double.infinity);
    final categoryHeight = (scaler.scale(12) * 1.4 + 44).ceilToDouble().clamp(kCategoryBarHeight, double.infinity);
    final ongoing = categorized['Ongoing'] ?? [];
    final pendingTasks = categorized['Pending'] ?? [];
    final scheduled = pendingTasks
        .where((task) => task.pendingSection == PendingTaskSection.scheduled)
        .toList();
    final pending = pendingTasks
        .where(
          (task) =>
              task.pendingSection == PendingTaskSection.availableAnytime,
        )
        .toList();
    final completed = categorized['Completed'] ?? [];

    final selectedCategory = _visibleTabOrder[_currentTabIndex];
    final bool isPendingTab = selectedCategory == 'Pending';
    final selectedTasks = isPendingTab
        ? [...scheduled, ...pending]
        : (categorized[selectedCategory] ?? []);

    final bool hasActiveFilters = _selectedBarangay != 'All Barangays' || _datePreset != null || _urgencyFilter != 'All';

    return SensitiveScreen(child: Scaffold(
      backgroundColor: InsightTheme.bg,
      extendBody: true,
      appBar: AppBar(
        titleSpacing: 20,
        backgroundColor: InsightTheme.surface,
        elevation: 0,
        automaticallyImplyLeading: false,
        surfaceTintColor: Colors.transparent,
        // The My Tasks title and ASSIGNED counter stay together,
        // and the whole group is pinned because it is Scaffold app-bar chrome.
        // Only Search / Filter scroll away; the category switcher below is a
        // pinned sliver that parks directly under this complete header.
        toolbarHeight: headerHeight,
        title: SpringSlide(
          animation: springFor(0),
          beginOffset: const Offset(0, -24),
          child: Padding(
          padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
          child: Flex(
            direction: stackedHeader ? Axis.vertical : Axis.horizontal,
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: stackedHeader ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              SizedBox(width: titleWidth, child: Text('My Tasks', style: titleStyle)),
              SizedBox(width: stackedHeader ? 0 : 12, height: stackedHeader ? 8 : 0),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: InsightTheme.blueTint,
                  borderRadius: InsightTheme.roundedSm,
                ),
                child: Column(
                  children: [
                    CountUpText(
                      value: _allTasks.length,
                      style: InsightTheme.urbanist(22, w: FontWeight.w800, c: InsightTheme.blueInk, h: 1.0),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ASSIGNED',
                      style: assignedStyle,
                    ),
                  ],
                ),
              ),
            ],
          ),
          ),
        ),
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: InsightTheme.line, height: 1.0),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: _isLoading
            ? const Center(child: ImapsLoadingIndicator(size: 60))
            : _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_errorMessage!, textAlign: TextAlign.center, style: InsightTheme.inter(14)),
                    ),
                  )
                : RefreshIndicator(
                    color: InsightTheme.blue1,
                    onRefresh: _loadTasks,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(
                          child: Container(
                            color: InsightTheme.surface,
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // SEARCH & FILTER COMPONENT
                                SpringSlide(
                                  animation: springFor(1),
                                  beginOffset: const Offset(0, 22),
                                  child: LayoutBuilder(builder: (context, constraints) {
                                    final searchWidth = measureHeader('Search tasks', InsightTheme.inter(16)).width + 96;
                                    final stacked = searchWidth + 68 > constraints.maxWidth;
                                    return Wrap(alignment: WrapAlignment.end, spacing: 12, runSpacing: 12,
                                  children: [
                                    SizedBox(width: stacked ? constraints.maxWidth : constraints.maxWidth - 68,
                                        child: Container(
                                          constraints: const BoxConstraints(minHeight: 56),
                                        child: TextField(
                                          controller: _searchController,
                                          style: InsightTheme.inter(16, c: InsightTheme.ink),
                                          decoration: InsightTheme.formInput.copyWith(
                                            fillColor: InsightTheme.bg,
                                            labelText: 'Search tasks',
                                            hintText: 'Name, site or inspection ID',
                                            prefixIcon: const Icon(Icons.search_rounded, color: InsightTheme.ink2, size: 20),
                                            suffixIcon: _searchQuery.isNotEmpty 
                                                ? IconButton(
                                                    tooltip: 'Clear task search',
                                                    onPressed: () {
                                                      _searchController.clear();
                                                      FocusScope.of(context).unfocus();
                                                    },
                                                    icon: const Icon(Icons.close_rounded, color: InsightTheme.ink3, size: 20),
                                                  )
                                                : null,
                                          ),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: hasActiveFilters ? 'Filter and sort tasks (active)' : 'Filter and sort tasks',
                                      onPressed: _showFilterBottomSheet,
                                      padding: EdgeInsets.zero,
                                      icon: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Container(
                                            height: 56, width: 56,
                                            decoration: BoxDecoration(
                                              color: hasActiveFilters ? InsightTheme.blueTint : InsightTheme.surface,
                                              border: Border.all(color: hasActiveFilters ? InsightTheme.blue1 : InsightTheme.lineStrong),
                                              borderRadius: InsightTheme.roundedSm,
                                            ),
                                            child: Icon(Icons.tune_rounded, color: hasActiveFilters ? InsightTheme.blueInk : InsightTheme.ink, size: 22),
                                          ),
                                          if (hasActiveFilters)
                                            Positioned(
                                              top: 7, right: 7,
                                              child: Container(
                                                width: 10, height: 10,
                                                decoration: BoxDecoration(
                                                  color: InsightTheme.blue1,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(color: InsightTheme.surface, width: 2),
                                                ),
                                              ),
                                            )
                                        ],
                                      ),
                                    ),
                                  ],
                                  );
                                  }),
                                ),
                                const SizedBox(height: 14),
                              ],
                            ),
                          ),
                        ),
                        // Pinned Pending / Ongoing / Completed switcher.
                        //
                        // Placed AFTER Search/Filter so the original visual
                        // order is preserved, and pinned so it stays directly
                        // under the (already pinned) "My Tasks" title once the
                        // user scrolls. Its opaque surface means the Search /
                        // Filter row travelling up passes behind it instead of
                        // showing through.
                        SliverPersistentHeader(
                          pinned: true,
                           delegate: _CategoryBarHeaderDelegate(
                             extent: categoryHeight,
                            child: _buildCategoryBar(
                              pending.length + scheduled.length,
                              ongoing.length,
                              completed.length,
                            ),
                          ),
                        ),

                        // ACTIVE LIST VIEW
                        if (selectedTasks.isEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 20),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 60, height: 60,
                                    decoration: BoxDecoration(
                                      color: InsightTheme.surface2,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.assignment_late_outlined, size: 28, color: InsightTheme.ink3),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No ${_visibleTabOrder[_currentTabIndex].toLowerCase()} tasks found',
                                    style: InsightTheme.poppins(15, w: FontWeight.w600, c: InsightTheme.ink),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _searchQuery.isNotEmpty || hasActiveFilters
                                        ? 'Try adjusting your search query or filter presets.'
                                        : 'You are all caught up for this category.',
                                    style: InsightTheme.inter(13, c: InsightTheme.ink3),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.only(left: 20, right: 20, top: 12, bottom: 140),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  // Phase 3: within the Pending tab only, insert
                                  // "Scheduled" / "Available Anytime" section
                                  // headers ahead of their respective task
                                  // groups. Other tabs render exactly as before —
                                  // a flat list with no header rows.
                                  if (isPendingTab) {
                                    final hasScheduledHeader = scheduled.isNotEmpty;
                                    final hasAvailableHeader = pending.isNotEmpty;
                                    var cursor = index;
                                    if (hasScheduledHeader) {
                                      if (cursor == 0) {
                                        return _PendingSectionHeader(
                                          key: _scheduledSectionKey,
                                          title: 'Scheduled',
                                          count: scheduled.length,
                                        );
                                      }
                                      cursor -= 1;
                                      if (cursor < scheduled.length) {
                                        return _buildTaskRow(context, scheduled[cursor], index);
                                      }
                                      cursor -= scheduled.length;
                                    }
                                    if (hasAvailableHeader) {
                                      if (cursor == 0) {
                                        return _PendingSectionHeader(
                                          title: 'Available Anytime',
                                          count: pending.length,
                                        );
                                      }
                                      cursor -= 1;
                                      return _buildTaskRow(context, pending[cursor], index);
                                    }
                                    // Shouldn't reach here given selectedTasks
                                    // isn't empty, but fail safe rather than crash.
                                    return const SizedBox.shrink();
                                  }
                                  final task = selectedTasks[index];
                                  return _buildTaskRow(context, task, index);
                                },
                                childCount: isPendingTab
                                    ? selectedTasks.length +
                                        (scheduled.isNotEmpty ? 1 : 0) +
                                        (pending.isNotEmpty ? 1 : 0)
                                    : selectedTasks.length,
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
    ));
  }
}

/// ==================================================================
/// COMPONENT WIDGETS
/// ==================================================================

class _NativeFilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NativeFilterChip({required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? InsightTheme.blueTint : InsightTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? InsightTheme.blue1 : InsightTheme.line),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: InsightTheme.inter(12, w: isSelected ? FontWeight.w600 : FontWeight.w500, c: isSelected ? InsightTheme.blue2 : InsightTheme.ink2),
          maxLines: 1, overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _DatePickerChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _DatePickerChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        // minHeight, not height: the date label wraps at a larger text scale or
        // with a long value, and a fixed 42px silently cut the second line.
        constraints: const BoxConstraints(minHeight: 42),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: InsightTheme.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: InsightTheme.line),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(label, style: InsightTheme.inter(13, c: InsightTheme.ink2)),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.calendar_today_outlined, size: 15, color: InsightTheme.ink3),
          ],
        ),
      ),
    );
  }
}

/// Phase 3 — simple, plain section header used inside the Pending tab to
/// separate Scheduled tasks from Available Anytime tasks. Deliberately
/// minimal (just a label + count) per the "no folder UI, no collapsible
/// sections, no redesign" instruction — this replaces a whole segment tab,
/// not a stylistic upgrade.
class _PendingSectionHeader extends StatelessWidget {
  final String title;
  final int count;

  const _PendingSectionHeader({super.key, required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Row(
        children: [
          Text(
            title,
            style: InsightTheme.poppins(13, w: FontWeight.w700, c: InsightTheme.ink2),
          ),
          const SizedBox(width: 6),
          Text(
            '($count)',
            style: InsightTheme.inter(12, w: FontWeight.w500, c: InsightTheme.ink3),
          ),
        ],
      ),
    );
  }
}

/// Pins the Pending/Ongoing/Completed switcher to the top of the scroll view.
///
/// One extent (min == max) for the chosen text size, so the whole band parks
/// under the pinned "My Tasks" app bar without scaling the labels.
class _CategoryBarHeaderDelegate extends SliverPersistentHeaderDelegate {
  _CategoryBarHeaderDelegate({required this.child, required this.extent});

  final Widget child;
  final double extent;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox(height: extent, child: child);
  }

  @override
  bool shouldRebuild(covariant _CategoryBarHeaderDelegate oldDelegate) =>
      oldDelegate.child != child || oldDelegate.extent != extent;
}

class _SegmentTab extends StatelessWidget {
  final String text;
  final int count;
  final bool isActive;
  final VoidCallback onTap;

  const _SegmentTab({required this.text, required this.count, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Restyled from a left-packed filled chip to a full-width segmented
    // tab (white pill + shadow when active) — same tap target/state,
    // matches the reference's segmented-tab look while staying on
    // this screen's own InsightTheme tokens.
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        // Centers the Row now that this tab is wrapped in Expanded (see the
        // call site) — without this, the tab's fixed-size content would
        // sit left-packed with dead space to the right of it.
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive ? InsightTheme.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          boxShadow: isActive ? const [BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2))] : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              style: InsightTheme.inter(
                11.5,
                w: isActive ? FontWeight.w700 : FontWeight.w600,
                c: isActive ? InsightTheme.blueInk : InsightTheme.ink3,
              ),
            ),
            const SizedBox(width: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: isActive ? InsightTheme.blueTint : InsightTheme.surface,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                count.toString(),
                style: InsightTheme.inter(
                  10.5,
                  w: FontWeight.w700,
                  c: isActive ? InsightTheme.blueInk : InsightTheme.ink2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactTaskCard extends StatefulWidget {
  final List<TaskItem> relatedRounds;
  final ValueChanged<TaskItem>? onOpenRound;
  final TaskItem task;
  final VoidCallback onTapDetail;
  final VoidCallback? onScheduled;

  const _CompactTaskCard({super.key, required this.task, required this.onTapDetail, this.onScheduled,
    this.relatedRounds = const [], this.onOpenRound});

  @override
  State<_CompactTaskCard> createState() => _CompactTaskCardState();
}

class _CompactTaskCardState extends State<_CompactTaskCard> {
  bool _isExpanded = false;

  String _getInitials(String name) {
    List<String> parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '??';
    if (parts.length == 1) return parts[0].length >= 2 ? parts[0].substring(0, 2).toUpperCase() : parts[0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  
  Color _getStatusColor() {
    final cat = widget.task.category;
    if (cat == 'Completed') return InsightTheme.green;
    if (widget.task.pendingSection == PendingTaskSection.scheduled) {
      final scheduledDate = widget.task.scheduledDate;
      if (scheduledDate.isEmpty) return InsightTheme.blue1;
      try {
        final due = DateTime.parse(scheduledDate);
        final today = DateTime.now();
        final dueDay = DateTime(due.year, due.month, due.day);
        final todayDay = DateTime(today.year, today.month, today.day);
        final diff = dueDay.difference(todayDay).inDays;
        if (diff <= 1 || dueDay.isBefore(todayDay)) return InsightTheme.red;
        if (diff >= 2 && diff <= 3) return InsightTheme.orange;
      } catch (_) {}
      return InsightTheme.blue1;
    }
    return InsightTheme.blue1;
  }

  Future<void> _showContextualInfo() async {
    final task = widget.task;
    final indicators = <MapEntry<String, String>>[];
    final isCompleted = task.category == 'Completed';
    final isScheduled =
        task.pendingSection == PendingTaskSection.scheduled;
    final visitRowVisible = isScheduled && task.scheduledDate.isNotEmpty;
    final deadlineRowVisible = !isCompleted && task.deadlineDate?.isNotEmpty == true;

    DateTime? parseDay(String? value) {
      if (value == null || value.isEmpty) return null;
      try {
        final date = DateTime.parse(value);
        return DateTime(date.year, date.month, date.day);
      } catch (_) {
        return null;
      }
    }

    final now = DateTime.now();
    final todayDay = DateTime(now.year, now.month, now.day);
    final visitDay = parseDay(task.scheduledDate);
    final visitDiff = visitDay?.difference(todayDay).inDays;
    final isOverdue = !isCompleted && task.scheduleUrgency == 'Overdue';
    final scheduledVisitRed = isScheduled && task.isUrgentDeadline && !isOverdue;
    final scheduledVisitOrange = isScheduled &&
        !task.isUrgentDeadline &&
        visitDiff != null &&
        visitDiff >= 2 &&
        visitDiff <= 3;

    if (isCompleted) {
      indicators.add(const MapEntry('Completed', 'This inspection has been finished and submitted. No further action is normally required.'));
      if (task.reworkStartedAt != null) {
        indicators.add(const MapEntry('Modified', 'This completed inspection was changed after it was submitted. The Modified label lets you know that the original submitted information was edited.'));
      }
    } else if (isScheduled) {
      indicators.add(const MapEntry('Scheduled', 'You have chosen a visit date for this task. The task stays Scheduled until the inspection is completed and submitted. You can reschedule the visit when needed, as long as the new date is still allowed by the deadline.'));
    } else if (task.category == 'Ongoing') {
      indicators.add(const MapEntry('Ongoing', 'This task is already being worked on, but no fixed visit date was set. You can continue the inspection without scheduling a visit.'));
    } else {
      indicators.add(const MapEntry('Available Anytime', 'This task does not have a fixed visit date yet. You can inspect it anytime before the admin-set deadline. If you want a specific visit date, you can schedule one.'));
    }

    if (!isCompleted) {
      if (visitRowVisible) {
        indicators.add(const MapEntry('Visit', 'This task has a deliberate visit date selected for the inspection.'));
      }
      if (deadlineRowVisible) {
        indicators.add(const MapEntry('Deadline', 'This is the admin-set deadline for completing the inspection.'));
      }
      if (isOverdue) {
        indicators.add(const MapEntry('Full red container', 'The admin-set deadline has passed, so the active task is fully highlighted red to show that it needs immediate attention.'));
      } else if (scheduledVisitRed) {
        indicators.add(const MapEntry('Red border', 'The scheduled visit date is today, tomorrow, or has already passed. Check the task and take action before the admin-set deadline.'));
      } else if (scheduledVisitOrange) {
        indicators.add(const MapEntry('Orange border', 'Your visit date is coming up in 2–3 days. Make sure you are prepared to complete the inspection on time.'));
      } else {
        indicators.add(const MapEntry('Blue border', 'The visit date is not close yet, or this task has no deliberate visit date, so no urgent action is needed.'));
      }
      if (task.scheduleUrgency == 'Due today') {
        final dueTodayFromVisit = visitRowVisible && visitDay?.isAtSameMomentAs(todayDay) == true;
        indicators.add(MapEntry(
          'Due Today',
          dueTodayFromVisit
              ? 'The scheduled visit date is today. This inspection should be handled today.'
              : 'The admin-set deadline is today. This inspection should be completed today.',
        ));
      }
      if (isScheduled && task.forReschedule != null) {
        indicators.add(const MapEntry('For Reschedule', 'The scheduled visit date has already passed, but the admin-set deadline has not. Choose a new valid visit date as soon as possible.'));
      }
      if (isOverdue) {
        indicators.add(const MapEntry('Overdue', 'The admin-set deadline has already passed. This task needs immediate attention.'));
      }
    }
    if (isScheduled && task.currentStep >= 1 && task.currentStep <= 5) {
      indicators.add(const MapEntry('In Progress', 'You have already started this scheduled inspection. Continue working through the remaining steps until it is completed.'));
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Task details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final indicator in indicators) ...[
              Text(indicator.key, style: InsightTheme.inter(12, w: FontWeight.w700, c: InsightTheme.ink)),
              const SizedBox(height: 2),
              Text(indicator.value, style: InsightTheme.inter(12, c: InsightTheme.ink2)),
              const SizedBox(height: 10),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
        ],
      ),
    );
  }

  /// Formats the real original submission timestamp (`field_jobs.submitted_at`,
  /// mapped to TaskItem.submittedAt) as e.g. "Aug 26, 2026" for the Completed
  /// card row. Deliberately NOT updated_at/Last-saved — those change during
  /// rework and are owned by the Modified state, not the completion date.
  String _formatCompletionDate(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) {
      return iso;
    }
  }

  // Removed: _deadlineUrgencyLabel getter. It duplicated (and mis-computed)
  // what the fixed `scheduleUrgency` getter already correctly returns
  // ('Due today' / 'Overdue' / null) — its own logic returned 'Deadline
  // tomorrow' for ANY future date (not just 1-day-out) and 'Deadline near'
  // whenever deadlineDate was missing, which is what caused those labels to
  // appear on brand-new tasks with a deadline a week away. Call sites now
  // use `scheduleUrgency` directly (see below).

  // BUG FIX #1 (v2) — canLaunchUrl() itself was returning a null component
  // on real devices even with a real number/email, because it depends on
  // queryIntentActivities(), which Android 11+ package-visibility rules can
  // block regardless of whether Phone/Messages/Gmail is actually installed.
  // Fix: skip canLaunchUrl and just launchUrl() directly (externalApplication
  // mode), same pattern already used in login_screen.dart's email flow —
  // with a clipboard fallback if no app is available to handle it at all.
  Future<void> _missingContact(String what) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('No $what on file for this applicant.')),
    );
  }

  Future<void> _launchOrFallback(Uri uri, String value, String label) async {
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) throw Exception('No app handled $label');
    } catch (e) {
      debugPrint('Could not launch $label ($uri): $e');
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: value));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No $label app found — $value copied to clipboard.')),
      );

    }
  }

  Future<void> _handleCall() async {
    HapticFeedback.lightImpact();
    final phone = widget.task.applicantPhone;
    if (phone == null || phone.isEmpty) return _missingContact('phone number');
    await _launchOrFallback(Uri.parse('tel:$phone'), phone, 'dialer');
  }

  Future<void> _handleSMS() async {
    HapticFeedback.lightImpact();
    final phone = widget.task.applicantPhone;
    if (phone == null || phone.isEmpty) return _missingContact('phone number');
    await _launchOrFallback(Uri.parse('sms:$phone'), phone, 'messaging');
  }

  Future<void> _handleEmail() async {
    HapticFeedback.lightImpact();
    final email = widget.task.applicantEmail;
    if (email == null || email.isEmpty) return _missingContact('email address');
    String? encodeQueryParameters(Map<String, String> params) {
      return params.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&');
    }
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: email,
      query: encodeQueryParameters({'subject': 'Inspection Notification: ${widget.task.inspectionNo}'}),
    );
    await _launchOrFallback(emailUri, email, 'email');
  }

  // Long-press a Pending card -> pick a date (never past the assignment
  // deadline) -> moves the task into the Scheduled subsection while its
  // lifecycle remains Pending.
  Future<void> _scheduleTask(BuildContext context) async {
    HapticFeedback.mediumImpact();

    final tomorrow = DateTime.now().add(const Duration(days: 1));
    DateTime? deadline;
    if (widget.task.deadlineDate != null && widget.task.deadlineDate!.isNotEmpty) {
      try {
        deadline = DateTime.parse(widget.task.deadlineDate!);
      } catch (_) {}
    }
    final lastPickableDate = (deadline != null && deadline.isAfter(tomorrow)) ? deadline : tomorrow;

    // Reschedule UX: if this task already has a scheduledDate, start the
    // picker there instead of always defaulting to tomorrow — same
    // scheduleJob() call either way, just a friendlier starting point.
    DateTime? pickedDate;
    if (widget.task.scheduledDate.isNotEmpty) {
      try {
        final existing = DateTime.parse(widget.task.scheduledDate);
        if (!existing.isBefore(tomorrow)) pickedDate = existing;
      } catch (_) {}
    }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
              child: SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                decoration: const BoxDecoration(
                  color: InsightTheme.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40, height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(color: InsightTheme.line, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    Text(
                      widget.task.scheduledDate.isNotEmpty ? 'Reschedule this task' : 'Schedule this task',
                      style: InsightTheme.poppins(16, w: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(widget.task.location, style: InsightTheme.inter(12.5, c: InsightTheme.ink2)),
                    const SizedBox(height: 18),

                    Text('Date', style: InsightTheme.inter(12, w: FontWeight.w600, c: InsightTheme.ink2)),
                    const SizedBox(height: 6),
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () async {
                        final result = await showDatePicker(
                          context: sheetContext,
                          initialDate: pickedDate ?? tomorrow,
                          firstDate: tomorrow,
                          lastDate: lastPickableDate,
                        );
                        if (result != null) setSheetState(() => pickedDate = result);
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: InsightTheme.bg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: InsightTheme.line),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today_rounded, size: 16, color: InsightTheme.blueInk),
                            const SizedBox(width: 10),
                            Expanded(child: Text(
                              pickedDate == null
                                  ? 'Select a date'
                                  : '${pickedDate!.year}-${pickedDate!.month.toString().padLeft(2, '0')}-${pickedDate!.day.toString().padLeft(2, '0')}',
                              style: InsightTheme.inter(13.5, w: FontWeight.w600, c: InsightTheme.ink),
                            )),
                          ],
                        ),
                      ),
                    ),
                    if (deadline != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Must be on or before ${deadline.year}-${deadline.month.toString().padLeft(2, '0')}-${deadline.day.toString().padLeft(2, '0')} (assignment deadline)',
                        style: InsightTheme.inter(11, c: InsightTheme.ink3),
                      ),
                    ],

                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: pickedDate == null
                            ? null
                            : () async {
                                try {
                                  // A zero-row write is never a successful
                                  // schedule; report the real outcome.
                                  final result = await SupabaseService.scheduleJob(
                                    jobId: widget.task.id,
                                    date: pickedDate!,
                                  );
                                  if (result != InspectionAuthorityResult.authorized) {
                                    if (sheetContext.mounted) {
                                      ScaffoldMessenger.of(sheetContext).showSnackBar(
                                        SnackBar(content: Text(result.message)),
                                      );
                                    }
                                    return;
                                  }
                                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                                  widget.onScheduled?.call();
                                } catch (e) {
                                  if (sheetContext.mounted) {
                                    ScaffoldMessenger.of(sheetContext).showSnackBar(
                                      SnackBar(content: Text('Could not schedule: $e')),
                                    );
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: InsightTheme.blue1,
                          minimumSize: const Size(48, 48),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(
                          widget.task.scheduledDate.isNotEmpty ? 'Confirm reschedule' : 'Confirm schedule',
                          style: InsightTheme.poppins(14, w: FontWeight.w600, c: Colors.white),
                        ),
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

  @override
  Widget build(BuildContext context) {
    final String taskCategory = widget.task.category;
    final bool isOverdue = taskCategory != 'Completed' && widget.task.scheduleUrgency == 'Overdue';
    final statusColor = isOverdue ? InsightTheme.red : _getStatusColor();
    final bool showInProgress =
        widget.task.pendingSection == PendingTaskSection.scheduled &&
        widget.task.currentStep >= 1 &&
        widget.task.currentStep <= 5;
    final int stepValue = (widget.task.currentStep > 0 ? widget.task.currentStep : widget.task.derivedHighestStep)
        .clamp(0, InspectionProgress.totalSteps);
    final bool canSchedule = widget.task.category != 'Completed';

    Color borderColor;
    if (isOverdue) {
      borderColor = InsightTheme.red;
    } else if (taskCategory == 'Completed') {
      borderColor = InsightTheme.green;
    } else if (widget.task.pendingSection == PendingTaskSection.scheduled) {
      if (widget.task.isUrgentDeadline) {
        borderColor = InsightTheme.red;
      } else if (widget.task.scheduledDate.isNotEmpty) {
        try {
          final due = DateTime.parse(widget.task.scheduledDate);
          final today = DateTime.now();
          final dueDay = DateTime(due.year, due.month, due.day);
          final todayDay = DateTime(today.year, today.month, today.day);
          final diff = dueDay.difference(todayDay).inDays;
          borderColor = diff >= 2 && diff <= 3 ? InsightTheme.orange : InsightTheme.blue1;
        } catch (_) {
          borderColor = InsightTheme.blue1;
        }
      } else {
        borderColor = InsightTheme.blue1;
      }
    } else {
      borderColor = InsightTheme.blue1;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isOverdue ? InsightTheme.redTint : InsightTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: borderColor,
          width: taskCategory == 'Completed' || taskCategory == 'Ongoing' ? 1 : 1.4,
        ),
        boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              onTap: () {
                setState(() => _isExpanded = !_isExpanded);
                HapticFeedback.selectionClick();
              },
              // Reschedule allowed for Pending, Scheduled, AND an
              // Ongoing-but-scheduled task — same canSchedule test used
              // for the button below, so long-press and the visible
              // button never disagree about whether this card can be
              // (re)scheduled.
              onLongPress: canSchedule ? () => _scheduleTask(context) : null,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar — enlarged (32->44) per reference; status dot
                    // moved onto the avatar corner instead of a separate
                    // free-floating dot, same statusColor source.
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 44, height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                          ),
                          child: Text(_getInitials(widget.task.name), style: InsightTheme.poppins(13, w: FontWeight.w800, c: statusColor)),
                        ),
                        if (widget.task.category == 'Ongoing')
                          Positioned(
                            top: -2, right: -2,
                            child: Container(
                              width: 12, height: 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: statusColor,
                                border: Border.all(color: InsightTheme.surface, width: 2),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  widget.task.name,
                                  style: InsightTheme.poppins(14.5, w: FontWeight.w700, c: InsightTheme.ink),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              FieldInfoButton(
                                label: 'About task details for ${widget.task.name}',
                                onPressed: _showContextualInfo,
                              ),
                              const SizedBox(width: 6),
                              AnimatedRotation(
                                turns: _isExpanded ? 0.5 : 0.0,
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOutCubic,
                                child: const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: InsightTheme.ink3, size: 20,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          // Permit/inspection no. — moved below the name into
                          // its own mono chip (was inline beside the name).
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(color: InsightTheme.surface2, borderRadius: BorderRadius.circular(6)),
                            child: Text(
                              widget.task.inspectionNo,
                              style: InsightTheme.inter(10, w: FontWeight.w700, c: InsightTheme.blueInk, ls: 0.2),
                            ),
                          ),
                          if (widget.task.roundLabel != null) ...[
                            const SizedBox(height: 6),
                            Text(widget.task.roundLabel!, style: InsightTheme.inter(12, w: FontWeight.w700, c: InsightTheme.blueInk)),
                          ],
                          const SizedBox(height: 7),
                          Row(
                            children: [
                              const Icon(Icons.location_on_rounded, size: 13, color: InsightTheme.blue1),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  widget.task.location,
                                  style: InsightTheme.inter(11.5, w: FontWeight.w600, c: InsightTheme.ink2),
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          // The Visit row belongs only to the Scheduled
                          // subsection of Pending. Ongoing and Completed tasks
                          // may retain schedule metadata, but scheduling never
                          // overrides their lifecycle category.
                          if (widget.task.pendingSection ==
                                  PendingTaskSection.scheduled &&
                              widget.task.scheduledDate.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                const Icon(Icons.event_available_rounded, size: 13, color: InsightTheme.blue1),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Visit: ${widget.task.scheduledDate}',
                                    style: InsightTheme.inter(11.5, w: FontWeight.w600, c: InsightTheme.ink2),
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (widget.task.category != 'Completed' && widget.task.deadlineDate != null && widget.task.deadlineDate!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.flag_rounded, size: 13, color: InsightTheme.orangeInk),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Deadline: ${widget.task.deadlineDate}',
                                    style: InsightTheme.inter(11.5, w: FontWeight.w600, c: InsightTheme.ink2),
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          // Final lifecycle semantics: Completed cards show
                          // the real original completion date from
                          // field_jobs.submitted_at (never updated_at /
                          // Last-saved — those belong to Modified/Rework).
                          if (widget.task.category == 'Completed' &&
                              widget.task.submittedAt != null &&
                              widget.task.submittedAt!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.check_circle_rounded, size: 13, color: InsightTheme.green),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Completed: ${_formatCompletionDate(widget.task.submittedAt!)}',
                                    style: InsightTheme.inter(11.5, w: FontWeight.w600, c: InsightTheme.ink2),
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 8),
                          // Status badges — same three conditions as before
                          // (Ongoing / Modified / scheduleUrgency), now
                          // wrapped instead of a single spaceBetween Row so
                          // they can co-occur without overflow, each as a
                          // rounded pill w/ icon.
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              // NOTE: no standalone "Scheduled" pill — it was
                              // redundant inside the Pending tab's Scheduled
                              // section (the section header + orange border +
                              // Visit row already say it) and added clutter
                              // on urgent cards. Scheduled state is carried
                              // by the orange border + avatar instead.
                              if (widget.task.pendingSection == PendingTaskSection.scheduled &&
                                  widget.task.forReschedule != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: InsightTheme.orangeTint,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.pending_actions_rounded, size: 11, color: InsightTheme.orangeInk),
                                      const SizedBox(width: 4),
                                      Text(
                                        'For Reschedule',
                                        style: InsightTheme.inter(10, w: FontWeight.w700, c: InsightTheme.orangeInk),
                                      ),
                                    ],
                                  ),
                                ),
                              if (showInProgress)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: InsightTheme.blue1.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.autorenew_rounded, size: 11, color: InsightTheme.blue1),
                                      const SizedBox(width: 4),
                                      Text(
                                        'In Progress',
                                        style: InsightTheme.inter(10, w: FontWeight.w700, c: InsightTheme.blue1),
                                      ),
                                    ],
                                  ),
                                ),
                              // Rework redesign: status stays 'completed' for
                              // the whole rework session now (see
                              // SupabaseService.reopenForRework), so this
                              // badge — keyed off reworkStartedAt, not status
                              // — is the only signal that a completed task
                              // has an unfinished rework in progress.
                              if (widget.task.category == 'Completed' && widget.task.reworkStartedAt != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: InsightTheme.orangeTint,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.schedule_rounded, size: 11, color: InsightTheme.orangeInk),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Modified',
                                        style: InsightTheme.inter(10, w: FontWeight.w700, c: InsightTheme.orangeInk),
                                      ),
                                    ],
                                  ),
                                ),
                              // Double-Overdue fix: this pill (visit-date
                              // driven) is suppressed when the deadline pill
                              // below is already showing the exact same
                              // label (e.g. both say "Overdue") — two
                              // identical pills for different data sources
                              // read as a rendering bug. Non-identical
                              // labels ("Due today" vs "Deadline tomorrow")
                              // still both render.
                              if (widget.task.category != 'Completed' &&
                                  widget.task.scheduleUrgency != null &&
                                  widget.task.scheduleUrgency != 'Overdue' &&
                                  widget.task.forReschedule == null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: InsightTheme.orangeTint,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.access_time_rounded, size: 11, color: InsightTheme.orangeInk),
                                      const SizedBox(width: 4),
                                      Text(
                                        widget.task.scheduleUrgency!,
                                        style: InsightTheme.inter(10, w: FontWeight.w700, c: InsightTheme.orangeInk),
                                      ),
                                    ],
                                  ),
                                ),
                              if (widget.task.category != 'Completed' && widget.task.scheduleUrgency == 'Overdue')
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: InsightTheme.redTint,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.warning_rounded, size: 11, color: InsightTheme.redInk),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Overdue',
                                        style: InsightTheme.inter(10, w: FontWeight.w700, c: InsightTheme.redInk),
                                      ),
                                    ],
                                  ),
                                ),
                              // Removed the old separate "Deadline urgency
                              // pill" here — it duplicated the Overdue/Due
                              // Today pills above using the buggy
                              // _deadlineUrgencyLabel getter (now deleted).
                              // The two pills above (from the corrected
                              // scheduleUrgency getter) already cover every
                              // category correctly.
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    value: InspectionProgress.totalSteps == 0 ? 0 : stepValue / InspectionProgress.totalSteps,
                                    minHeight: 5,
                                    backgroundColor: InsightTheme.surface2,
                                    valueColor: AlwaysStoppedAnimation(statusColor),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'STEP $stepValue/${InspectionProgress.totalSteps}',
                                style: InsightTheme.inter(9.5, w: FontWeight.w700, c: InsightTheme.ink3),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity, height: 0),
              secondChild: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(color: InsightTheme.line, height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: _ActionBtn(icon: Icons.phone_rounded, label: 'Call', onTap: _handleCall)),
                            const SizedBox(width: 6),
                            Expanded(child: _ActionBtn(icon: Icons.chat_bubble_outline_rounded, label: 'SMS', onTap: _handleSMS)),
                            const SizedBox(width: 6),
                            Expanded(child: _ActionBtn(icon: Icons.mail_outline_rounded, label: 'Email', onTap: _handleEmail)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: widget.onTapDetail,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: InsightTheme.bg,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: InsightTheme.line),
                            ),
                            child: Row(
                              children: [
                                Icon(widget.task.typeIcon, color: InsightTheme.blue1, size: 16),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Application Details', style: InsightTheme.inter(11, w: FontWeight.w600, c: InsightTheme.ink)), 
                                      const SizedBox(height: 1),
                                      Text(
                                        '${widget.task.applicationType ?? 'General'} • ${widget.task.landUseClass}',
                                        style: InsightTheme.inter(10, c: InsightTheme.ink2),
                                        maxLines: 1, overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.arrow_forward_ios_rounded, color: InsightTheme.ink3, size: 10),
                              ],
                            ),
                          ),
                        ),
                        if (widget.relatedRounds.length > 1 && widget.onOpenRound != null) ...[
                          const SizedBox(height: 12),
                          InspectionRoundList(rounds: widget.relatedRounds, onOpen: widget.onOpenRound!),
                        ],
                        if (canSchedule) ...[
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () => _scheduleTask(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: InsightTheme.orangeTint,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: InsightTheme.orange.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.calendar_today_rounded, color: InsightTheme.orange, size: 14),
                                  const SizedBox(width: 6),
                                  Text(
                                    // Label now reflects whether a date is
                                    // actually already set (scheduledDate),
                                    // not just the category string — an
                                    // Ongoing-but-scheduled task also has a
                                    // date on file, so it should read
                                    // "Reschedule" too, not "Schedule".
                                    widget.task.scheduledDate.isNotEmpty
                                        ? 'Reschedule Inspection Date'
                                        : 'Schedule Inspection Date',
                                    style: InsightTheme.inter(11, w: FontWeight.w600, c: InsightTheme.orangeInk),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              crossFadeState: _isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 260),
              firstCurve: Curves.easeOutCubic,
              secondCurve: Curves.easeOutCubic,
              sizeCurve: Curves.easeOutCubic,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionBtn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: InsightTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: InsightTheme.line),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: InsightTheme.ink2, size: 14), 
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label, 
                style: InsightTheme.inter(12, w: FontWeight.w500, c: InsightTheme.ink), 
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
