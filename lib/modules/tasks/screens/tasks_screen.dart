import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState;
import 'package:url_launcher/url_launcher.dart'; 

import '../../../core/models/user_profile.dart';
import '../../../core/models/task_submission.dart';
import '../../../core/models/planning_review_metadata.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/db_helper.dart';
import '../../../core/services/sync_outbox_service.dart';

import '../../../core/navigation/parcel_detail_screen.dart';
import '../../inspection/screens/completed_inspection_detail_screen.dart';
import '../../inspection/screens/inspection_progress.dart';
import '../../../core/widgets/motion/spring_entrance.dart';
import '../../../core/widgets/motion/updating_tile.dart';
import '../../../core/widgets/motion/linked_list_motion.dart';
import '../../../core/widgets/imaps_loading_indicator.dart';
import '../../../core/widgets/offline_banner.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/task_sync_indicator.dart';
import '../../../core/widgets/sensitive_screen.dart';
import '../../../core/widgets/field_form_widgets.dart';


import '../../../core/theme/insight_theme.dart';
import '../models/task_lifecycle.dart';

/// ==================================================================
/// CONSTANTS
/// ==================================================================

/// Independent track gutters and tab padding; content never borrows either.
const double _segmentCountGap = 4;
const double _segmentInset = 4;
const double _segmentPadH = 8;
const double _segmentBadgePad = 8;
const double _segmentHeight = 72;

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
  return switch (MyTaskPresentation.lifecycleFor(
      MyTaskFacts(status: status, isSelfScheduled: false))) {
    MyTaskLifecycle.scheduled || MyTaskLifecycle.availableAnytime => TaskLifecycleCategory.pending,
    MyTaskLifecycle.ongoing => TaskLifecycleCategory.ongoing,
    MyTaskLifecycle.completed => TaskLifecycleCategory.completed,
    MyTaskLifecycle.unknown => TaskLifecycleCategory.unknown,
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
  /// Exact parcel address on file in iMAPS (`supabase_parcels.location_address`).
  /// Null/empty is meaningful: the UI must say "Address not on file", never
  /// substitute the barangay or invent a street address.
  final String? locationAddress;
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
    this.locationAddress,
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
      locationAddress:
          (parcel?['location_address'] as String?)?.trim().isNotEmpty == true
          ? (parcel?['location_address'] as String).trim()
          : null,
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
      'location_address': row['parcel_address'],
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
    if (currentStep > 0 || startedAt?.isNotEmpty == true ||
        mapTaskStatusToLifecycle(status) == TaskLifecycleCategory.ongoing) {
      return 1;
    }
    return 0;
  }

  MyTaskFacts get _presentationFacts => MyTaskFacts(
    status: status, isSelfScheduled: isSelfScheduled,
    visitDate: scheduledDate, deadlineDate: deadlineDate, currentStep: currentStep,
    hasStarted: startedAt?.isNotEmpty == true,
  );

  MyTaskPresentation presentationAt(DateTime today) => MyTaskPresentation.of(_presentationFacts, today);
  MyTaskPresentation get presentation => presentationAt(DateTime.now());

  TaskLifecycleCategory get lifecycleCategory => switch (MyTaskPresentation.lifecycleFor(_presentationFacts)) {
    MyTaskLifecycle.scheduled || MyTaskLifecycle.availableAnytime => TaskLifecycleCategory.pending,
    MyTaskLifecycle.ongoing => TaskLifecycleCategory.ongoing,
    MyTaskLifecycle.completed => TaskLifecycleCategory.completed,
    MyTaskLifecycle.unknown => TaskLifecycleCategory.unknown,
  };

  /// The displayed active date, never a PO placeholder disguised as a Visit.
  String? get activeDate => presentation.activeDay == null ? null :
      pendingSection == PendingTaskSection.scheduled ? scheduledDate : deadlineDate;

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
    return presentation.forReschedule ? 'For Reschedule' : null;
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
    final p = presentation;
    return p.isOverdue ? 'Overdue' : p.isDueToday ? 'Due today' : null;
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
    return presentation.border == MyTaskBorder.red;
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

  // Scheduled is a Pending subsection. Canonical presentation keeps active
  // committed Visits there even when the raw workflow status is in_progress.
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
  // Urgent uses the shared Visit/PO reminder window, excluding Overdue.
  String _urgencyFilter = 'All';

  static const _tabOrder = ['Pending', 'Ongoing', 'Completed'];
  static const _visibleTabOrder = _tabOrder;

  final GlobalKey _scheduledSectionKey = GlobalKey();
  bool _pendingScrollToScheduled = false;

  List<TaskItem> _allTasks = [];
  Map<String, TaskSubmission> _submissions = {};
  Map<String, Map<String, dynamic>> _remoteJobs = {};
  final Set<String> _diagnosedUnknownTaskIds = <String>{};
  bool _isLoading = true;
  String? _errorMessage;

  /// Only the newest load may write to this screen. A superseded request (or a
  /// late answer to one) is discarded instead of overwriting newer state.
  int _loadRequestId = 0;

  /// Set while locally saved tasks are on screen and the remote refresh did
  /// not complete, so the screen says what it is showing.
  String? _savedDataNotice;
  TaskRefreshPhase _taskRefreshPhase = TaskRefreshPhase.checking;
  DateTime? _lastTaskRefreshAt;

  /// The authenticated owner whose rows this page is currently showing.
  ///
  /// A genuine account change retires them instead of repurposing this
  /// still-mounted page for the next inspector; the previous owner's durable
  /// local evidence is never deleted by that.
  String? _tasksOwner;

  StreamSubscription<AuthState>? _authSubscription;

  /// Bounded remote refresh: long enough for a slow but real network, short
  /// enough that a dead one cannot hold the screen. Matches the service
  /// layer's own 10 s bound.
  static const Duration _refreshTimeout = Duration(seconds: 10);

  /// Honest terminal messages for the case where nothing is known locally and
  /// no refresh succeeded. A raw exception is never shown, and "nothing yet"
  /// is never presented as "no work". The shared notice constants own the
  /// wording so Home and My Tasks cannot drift apart.

  @override
  void initState() {
    super.initState();
    _currentTabIndex = widget.scrollToScheduled ? TasksScreen.tabPending : widget.initialTabIndex;
    PaintingBinding.instance.systemFonts.addListener(_onFontsChanged);
    _pendingScrollToScheduled = widget.scrollToScheduled;
    _authSubscription = SupabaseService.client.auth.onAuthStateChange
        .listen((_) => _retireIfOwnerChanged(),
            onError: (Object _) => _retireIfOwnerChanged());
    SyncOutboxService.drainCompleted.addListener(_refreshSubmissionState);
    SyncOutboxService.progress.addListener(_refreshSubmissionState);
    _loadTasks();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    SyncOutboxService.drainCompleted.removeListener(_refreshSubmissionState);
    SyncOutboxService.progress.removeListener(_refreshSubmissionState);
    _authSubscription?.cancel();
    _searchController.dispose();
    PaintingBinding.instance.systemFonts.removeListener(_onFontsChanged);
    disposeSpringEntrance();
    super.dispose();
  }

  /// A real account change invalidates what this mounted page is showing: the
  /// previous inspector's rows are retired from the display (their durable
  /// local rows are left exactly as they are) and any navigation bound before
  /// the change is refused instead of opening another inspector's task.
  void _retireIfOwnerChanged() {
    if (!mounted) return;
    final current = DBHelper.currentInspectorId;
    if (current != null && current == _tasksOwner) return;
    if (_tasksOwner == null && _allTasks.isEmpty && _savedDataNotice == null) {
      return;
    }
    setState(() {
      _loadRequestId++; // Retire every pending UI result with its owner.
      _tasksOwner = null;
      _allTasks = [];
      _submissions = {};
      _remoteJobs = {};
      _isLoading = false;
      _errorMessage = null;
      _savedDataNotice = SavedDataNotice.ownerChanged;
      _taskRefreshPhase = TaskRefreshPhase.ownerChanged;
      _lastTaskRefreshAt = null;
    });
    ScaffoldMessenger.maybeOf(context)?.removeCurrentSnackBar();
    AppFeedback.dismiss();
  }

  void _onFontsChanged() { if (mounted) setState(() {}); }

  String _displayCategory(TaskItem task) => _submissions.containsKey(task.id)
      ? 'Completed' : task.category;

  Map<String, TaskSubmission> _parseSubmissions(TaskPresentationSnapshot snapshot) {
    final result = <String, TaskSubmission>{};
    final jobs = {for (final row in snapshot.jobs) row['id']: row};
    for (final row in snapshot.submissions) {
      final job = jobs[row['job_id']];
      if (job == null || result.containsKey(row['job_id'])) continue;
      // A readable synced receipt is proof of acceptance even after the job is
      // completed; the ordering above already lets a newer outstanding action
      // win. Unreadable delivery history is never proof, so it is skipped
      // instead of failing the whole projection.
      final TaskSubmission submission;
      try {
        submission = TaskSubmission.fromRow(row);
      } on FormatException {
        // Unreadable delivery history is not proof of acceptance; an
        // unreadable *outstanding* final intent still surfaces the recoverable
        // local-read failure instead of disappearing silently.
        if (row['status'] == 'synced') continue;
        rethrow;
      } on TypeError {
        if (row['status'] == 'synced') continue;
        rethrow;
      }
      result[submission.jobId] = submission;
    }
    return result;
  }

  List<TaskItem> _snapshotTasks(TaskPresentationSnapshot snapshot) => [
    for (final row in snapshot.jobs)
      if (_remoteJobs[row['id']] case final remote?)
        TaskItem.fromJob({...remote, 'status': row['status'],
          'current_step': max((remote['current_step'] as num?)?.toInt() ?? 0,
              (row['current_step'] as num?)?.toInt() ?? 0)})
      else TaskItem.fromCachedJob(row),
  ];

  /// Sync notifications refresh SQLite presentation only, never start another
  /// HTTP refresh or infer success from an in-memory progress notification.
  Future<void> _refreshSubmissionState() async {
    final owner = _tasksOwner;
    final requestId = _loadRequestId;
    if (owner == null || owner != DBHelper.currentInspectorId) return;
    try {
      final snapshot = await DBHelper.getTaskPresentationSnapshot();
      final submissions = _parseSubmissions(snapshot);
      if (!mounted || requestId != _loadRequestId) return;
      if (owner != DBHelper.currentInspectorId) {
        _retireIfOwnerChanged();
        return;
      }
      setState(() {
        _allTasks = _snapshotTasks(snapshot);
        _submissions = submissions;
      });
    } catch (_) {
      if (mounted && requestId == _loadRequestId && owner == DBHelper.currentInspectorId) {
        setState(() {
          _savedDataNotice = SavedDataNotice.cacheReadFailed;
          _taskRefreshPhase = TaskRefreshPhase.cacheUnavailable;
        });
      }
    }
  }

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
          signature: Object.hash(task.status, task.scheduledDate, task.deadlineDate, _submissions[task.id]?.state),
          child: _CompactTaskCard(
            key: ValueKey(task.id),
            task: task,
            submission: _submissions[task.id],
            onTapDetail: () => _openTask(context, task),
            onScheduled: _loadTasks,
          ),
        ),
      ),
    );
  }

  /// Connectivity is advisory only: it chooses the wording of the notice and
  /// never decides what is rendered. The read is bounded, so a hanging
  /// platform call cannot hold the screen, and an unknown answer counts as
  /// not-online so a real backend failure is never relabelled as offline.
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

  /// Cache first, refresh second.
  ///
  /// 1. The owner-scoped cache is rendered immediately and is never gated on a
  ///    connectivity indication, so a weak, captive or dead network cannot turn
  ///    into an indefinite spinner while legitimate work sits unread. The moment
  ///    saved rows are shown they are identified as saved data.
  /// 2. The remote refresh is bounded, its commit is ordered per owner across
  ///    every screen, and no failed, timed-out or superseded answer can erase
  ///    valid cached work.
  /// 3. Reading the local store is as fallible as any other platform call: a
  ///    damaged or unavailable store reaches a recoverable screen state instead
  ///    of an unhandled future or a stuck spinner, and never deletes the row.
  Future<void> _loadTasks() async {
    final requestId = ++_loadRequestId;
    final owner = DBHelper.currentInspectorId;
    setState(() => _taskRefreshPhase = TaskRefreshPhase.checking);

    List<Map<String, dynamic>> cached = const [];
    Map<String, TaskSubmission> submissions = {};
    var cacheFailed = false;
    if (owner != null && owner.isNotEmpty) {
      try {
        final snapshot = await DBHelper.getTaskPresentationSnapshot();
        submissions = _parseSubmissions(snapshot);
        cached = snapshot.jobs;
      } catch (e) {
        debugPrint('[TASKS] saved task read failed (${e.runtimeType}).');
        cacheFailed = true;
      }
    }
    List<TaskItem>? parsed;
    if (cached.isNotEmpty) {
      try {
        parsed = cached.map(TaskItem.fromCachedJob).toList();
      } catch (e) {
        debugPrint('[TASKS] saved task rows unreadable: $e');
        cacheFailed = true;
      }
    }
    if (!mounted || requestId != _loadRequestId) return;

    setState(() {
      if (parsed != null) {
        _allTasks = parsed;
        _submissions = submissions;
        _isLoading = false;
        _errorMessage = null;
        // Identified as saved from the first frame it is shown, not only once
        // the refresh has finished or failed.
        _savedDataNotice = SavedDataNotice.refreshing;
      } else if (cacheFailed) {
        _isLoading = false;
        _errorMessage = SavedDataNotice.cacheReadFailed;
        _savedDataNotice = null;
        _taskRefreshPhase = TaskRefreshPhase.cacheUnavailable;
      } else if (_allTasks.isEmpty) {
        // Nothing is known yet, so "loading" is the only honest state.
        _isLoading = true;
        _errorMessage = null;
      }
    });
    if (parsed != null) _maybeScrollToScheduledSection();

    // The owner is recorded before any read: rows rendered from the cache
    // while offline still belong to this inspector and stay openable.
    if (owner != null && owner.isNotEmpty) {
      _tasksOwner = owner;
    }

    if (!await _hasConnectivity()) {
      if (!mounted || requestId != _loadRequestId) return;
      setState(() {
        _isLoading = false;
        _taskRefreshPhase = cacheFailed && parsed == null
            ? TaskRefreshPhase.cacheUnavailable : TaskRefreshPhase.offline;
        if (parsed != null) {
          _savedDataNotice = SavedDataNotice.offline;
        } else if (cacheFailed) {
          _savedDataNotice = null;
          _errorMessage = SavedDataNotice.cacheReadFailed;
        } else if (_allTasks.isEmpty) {
          _savedDataNotice = null;
          _errorMessage = SavedDataNotice.noCacheOffline;
        }
      });
      return;
    }

    if (owner == null || owner.isEmpty) {
      // No authenticated owner: nothing may be fetched, written, or shown.
      if (!mounted || requestId != _loadRequestId) return;
      setState(() {
        _isLoading = false;
        _allTasks = [];
        _errorMessage = null;
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
      final jobs =
          await SupabaseService.fetchMyJobs().timeout(_refreshTimeout);
      if (!mounted || requestId != _loadRequestId) return;
      // An answer that arrives after the device changed accounts belongs to
      // the previous account: it is never rendered and never cached.
      if (DBHelper.currentInspectorId != owner) {
        _retireIfOwnerChanged();
        return;
      }
      final applied = await DBHelper.cacheJobs(jobs, refresh: refresh);
      if (!mounted || requestId != _loadRequestId) return;
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
          _isLoading = false;
        });
        return;
      }
      final snapshot = await DBHelper.getTaskPresentationSnapshot();
      final refreshedSubmissions = _parseSubmissions(snapshot);
      if (!mounted || requestId != _loadRequestId) return;
      if (DBHelper.currentInspectorId != owner) {
        _retireIfOwnerChanged();
        return;
      }
      setState(() {
        _remoteJobs = {for (final job in jobs) job['id'] as String: job};
        _allTasks = _snapshotTasks(snapshot);
        _submissions = refreshedSubmissions;
        _isLoading = false;
        _errorMessage = null;
        _savedDataNotice = null;
        _taskRefreshPhase = TaskRefreshPhase.fresh;
        _lastTaskRefreshAt = DateTime.now();
      });
      _maybeScrollToScheduledSection();
    } catch (e) {
      // Diagnostics stay in the log; the inspector gets a plain state.
      debugPrint('[TASKS] assignment refresh failed: $e');
      if (!mounted || requestId != _loadRequestId) return;
      setState(() {
        _isLoading = false;
        _taskRefreshPhase = cacheFailed && parsed == null
            ? TaskRefreshPhase.cacheUnavailable : TaskRefreshPhase.failed;
        if (parsed != null || _allTasks.isNotEmpty) {
          _savedDataNotice = SavedDataNotice.refreshFailed;
        } else {
          _savedDataNotice = null;
          _errorMessage = cacheFailed
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
    _loadTasks();
  }

  void _openTask(BuildContext context, TaskItem task) async {
    // A callback bound before an account change must not open another
    // inspector's task from this page.
    final current = DBHelper.currentInspectorId;
    if (!mounted || current == null || current != _tasksOwner) {
      _retireIfOwnerChanged();
      return;
    }
    HapticFeedback.selectionClick();
    if (_displayCategory(task) == 'Completed') {
      final historical = task.planningReview?.decision == 'Requires Reinspection' ||
          _allTasks.any((round) => task.sameApplicationAs(round) &&
            round.previousSiteInspectionId == task.localInspectionId && task.localInspectionId != null);
      final submission = _submissions[task.id];
      await Navigator.push(context, MaterialPageRoute(builder: (_) => CompletedInspectionDetailScreen(
        task: task, historicalReadOnly: historical,
        submission: submission?.isSynced == true && task.category == 'Completed' ? null : submission)));
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

                        // Active Visit/PO reminders are Urgent; a passed PO
                        // deadline is exclusively Overdue. Completed is neither.
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
        final bool isCompleted = _displayCategory(task) == 'Completed';
        bool matches;
        switch (_urgencyFilter) {
          case 'Urgent':
            matches = !isCompleted && task.presentation.isUrgent;
            break;
          case 'Scheduled':
            matches = !isCompleted &&
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
      if (_datePreset != null) {
          final completionTime = _displayCategory(task) == 'Completed'
              ? DateTime.tryParse(task.submittedAt ?? _submissions[task.id]?.savedAt ?? '')?.toLocal()
              : null;
          final taskDate = completionTime == null
              ? (_displayCategory(task) == 'Completed' ? null : task.presentation.activeDay)
              : DateTime(completionTime.year, completionTime.month, completionTime.day);
          if (taskDate == null) continue;
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          if (_datePreset == 'last30') {
            if (taskDate.isBefore(DateTime(today.year, today.month, today.day - 30))) continue;
          } else if (_datePreset == 'last6months') {
            if (taskDate.isBefore(DateTime(today.year, today.month, today.day - 182))) continue;
          } else if (_datePreset == 'custom') {
            if (_customStartDate != null && taskDate.isBefore(_customStartDate!)) continue;
            if (_customEndDate != null && taskDate.isAfter(_customEndDate!)) continue;
          }
      }
      map[_displayCategory(task)]!.add(task);
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

  /// Header card — title, live sync state, summary, search/filter and the
  /// Pending / Ongoing / Completed switcher in one surface.
  Widget _buildHeaderCard({
    required int pendingCount,
    required int ongoingCount,
    required int completedCount,
    required int dueToday,
    required bool hasActiveFilters,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: InsightTheme.surface,
        borderRadius: InsightTheme.roundedLg,
        border: Border.all(color: InsightTheme.line),
        boxShadow: InsightTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        'My Tasks',
                        style: InsightTheme.urbanist(
                          24,
                          w: FontWeight.w800,
                          c: InsightTheme.ink,
                          ls: -0.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isLoading
                          ? 'Loading tasks…'
                          : _errorMessage != null
                              ? 'Saved tasks unavailable'
                              : '${_allTasks.length} assigned · $dueToday due today',
                      style: InsightTheme.inter(
                        12,
                        w: FontWeight.w500,
                        c: InsightTheme.ink3,
                      ),
                    ),
                  ],
                ),
              ),
              TaskSyncIndicator(
                key: const ValueKey('task-sync-indicator'),
                phase: _taskRefreshPhase,
                hasSavedTasks: _allTasks.isNotEmpty,
                lastChecked: _lastTaskRefreshAt,
                onRetry: _retryTaskRefresh,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Semantics(label: 'Search tasks', child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: TextField(
                    controller: _searchController,
                    style: InsightTheme.inter(14, c: InsightTheme.ink),
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: InsightTheme.surface2,
                      hintText: 'Search name, site or ID',
                      hintStyle: InsightTheme.inter(14, c: InsightTheme.ink3),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: InsightTheme.ink3,
                        size: 20,
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              tooltip: 'Clear task search',
                              onPressed: () {
                                _searchController.clear();
                                FocusScope.of(context).unfocus();
                              },
                              icon: const Icon(
                                Icons.close_rounded,
                                color: InsightTheme.ink3,
                                size: 20,
                              ),
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: InsightTheme.roundedSm,
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: InsightTheme.roundedSm,
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: InsightTheme.roundedSm,
                        borderSide: const BorderSide(
                          color: InsightTheme.blue1,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                )),
              ),
              const SizedBox(width: 8),
              Semantics(
                button: true,
                label: hasActiveFilters
                    ? 'Filter and sort tasks, active'
                    : 'Filter and sort tasks',
                child: Tooltip(
                  message: hasActiveFilters
                      ? 'Filter and sort tasks (active)'
                      : 'Filter and sort tasks',
                  child: SizedBox.square(
                    dimension: 48,
                    child: Material(
                      color: hasActiveFilters
                          ? InsightTheme.blueTint
                          : InsightTheme.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: InsightTheme.roundedSm,
                        side: BorderSide(
                          color: hasActiveFilters
                              ? InsightTheme.blue1
                              : InsightTheme.lineStrong,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: _showFilterBottomSheet,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              Icons.tune_rounded,
                              color: hasActiveFilters
                                  ? InsightTheme.blueInk
                                  : InsightTheme.ink,
                              size: 22,
                            ),
                            if (hasActiveFilters)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: InsightTheme.blue1,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: InsightTheme.surface,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildCategoryBar(pendingCount, ongoingCount, completedCount),
        ],
      ),
    );
  }

  /// The Pending / Ongoing / Completed segmented switcher.
  ///
  /// Equal stationary cells grow vertically for full labels and exact counts.
  Widget _buildCategoryBar(
      int pendingCount, int ongoingCount, int completedCount) {
    return Container(
      decoration: BoxDecoration(
        color: InsightTheme.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _segmentInset),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _SegmentTab(
                text: "Pending",
                count: pendingCount,
                isActive: _currentTabIndex == 0,
                onTap: () => setState(() => _currentTabIndex = 0),
              )),
              Expanded(child: _SegmentTab(
                text: "Ongoing",
                count: ongoingCount,
                isActive: _currentTabIndex == 1,
                onTap: () => setState(() => _currentTabIndex = 1),
              )),
              Expanded(child: _SegmentTab(
                text: "Completed",
                count: completedCount,
                isActive: _currentTabIndex == 2,
                onTap: () => setState(() => _currentTabIndex = 2),
              )),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categorized = _categorizeAndFilter();
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
    final dueToday = _allTasks
        .where((task) =>
            task.lifecycleCategory != TaskLifecycleCategory.unknown &&
            _displayCategory(task) != 'Completed' &&
            task.scheduleUrgency == 'Due today')
        .length;

    return SensitiveScreen(child: Scaffold(
      backgroundColor: InsightTheme.bg,
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: InsightTheme.blue1,
          onRefresh: _loadTasks,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Session recovery is not a saved-task banner.
                                if (_savedDataNotice == SavedDataNotice.ownerChanged)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: SavedDataNotice(message: _savedDataNotice!),
                                  ),
                                SpringSlide(
                                  animation: springFor(0),
                                  beginOffset: const Offset(0, -18),
                                  child: _buildHeaderCard(
                                    pendingCount: pending.length + scheduled.length,
                                    ongoingCount: ongoing.length,
                                    completedCount: completed.length,
                                    dueToday: dueToday,
                                    hasActiveFilters: hasActiveFilters,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // ACTIVE LIST VIEW
                        if (_isLoading)
                          const SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: ImapsLoadingIndicator(size: 60),
                            ),
                          )
                        else if (_errorMessage != null)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _errorMessage!,
                                      textAlign: TextAlign.center,
                                      style: InsightTheme.inter(14),
                                    ),
                                    const SizedBox(height: 12),
                                    TextButton(
                                      onPressed: _loadTasks,
                                      style: TextButton.styleFrom(
                                        minimumSize: const Size(88, 44),
                                      ),
                                      child: Text(
                                        'Retry',
                                        style: InsightTheme.inter(
                                          14,
                                          w: FontWeight.w600,
                                          c: InsightTheme.blue1,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        else if (selectedTasks.isEmpty)
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

class _SegmentTab extends StatelessWidget {
  final String text;
  final int count;
  final bool isActive;
  final VoidCallback onTap;

  const _SegmentTab({
    required this.text,
    required this.count,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    return Semantics(
      selected: isActive,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          // Keep the selected surface inset; enlarged labels grow the row.
          margin: const EdgeInsets.symmetric(vertical: _segmentInset),
          constraints: const BoxConstraints(
              minHeight: _segmentHeight - _segmentInset * 2),
          padding: const EdgeInsets.symmetric(horizontal: _segmentPadH, vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? InsightTheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: isActive
                ? const [
                    BoxShadow(
                        color: Color(0x0F000000),
                        blurRadius: 8,
                        offset: Offset(0, 2))
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                text,
                textScaler: textScaler,
                textAlign: TextAlign.center,
                style: InsightTheme.inter(
                  12,
                  w: isActive ? FontWeight.w700 : FontWeight.w600,
                  c: isActive ? InsightTheme.ink : InsightTheme.ink3,
                ),
              ),
              const SizedBox(height: _segmentCountGap),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                    horizontal: _segmentBadgePad, vertical: 2),
                decoration: BoxDecoration(
                  color: isActive ? InsightTheme.blueTint : InsightTheme.surface,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  count.toString(),
                  textScaler: textScaler,
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
      ),
    );
  }
}

class _CompactTaskCard extends StatefulWidget {
  final TaskItem task;
  final TaskSubmission? submission;
  final VoidCallback onTapDetail;
  final VoidCallback? onScheduled;

  const _CompactTaskCard({super.key, required this.task, required this.onTapDetail, this.onScheduled, this.submission});

  @override
  State<_CompactTaskCard> createState() => _CompactTaskCardState();
}

class _CompactTaskCardState extends State<_CompactTaskCard> {
  bool _isExpanded = false;
  String get _displayCategory => widget.submission != null ? 'Completed' : widget.task.category;
  bool get _awaitingAcceptance => widget.submission != null &&
      (!widget.submission!.isSynced || widget.task.category != 'Completed');

  String _getInitials(String name) {
    List<String> parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '??';
    if (parts.length == 1) return parts[0].length >= 2 ? parts[0].substring(0, 2).toUpperCase() : parts[0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  
  Color _getStatusColor(MyTaskPresentation p) {
    final cat = _displayCategory;
    if (_awaitingAcceptance) return InsightTheme.orangeInk;
    if (cat == 'Completed') return InsightTheme.green;
    return switch (p.border) {
      MyTaskBorder.red || MyTaskBorder.fullRed => InsightTheme.red,
      MyTaskBorder.orange => InsightTheme.orange,
      _ => InsightTheme.blue1,
    };
  }

  /// Explains the border using the same conditions as [_getStatusColor], so
  /// the dialog describes the color that is actually displayed.
  String _borderExplanation(MyTaskPresentation p) {
    if (_awaitingAcceptance) {
      return 'Orange — your final submission is saved on this device, but the '
          'server has not confirmed it yet. This color reflects sync status, '
          'not a date.';
    }
    if (_displayCategory == 'Completed') {
      return widget.submission == null
          ? 'Green — this inspection is completed. This device has no final-'
              'submission receipt, so server acceptance is unverified.'
          : 'Green — this inspection is completed and the server has '
              'confirmed it.';
    }
    if (p.border == MyTaskBorder.fullRed) {
      return 'Red — the PO Deadline has passed. This task is overdue.';
    }
    if (p.border == MyTaskBorder.red) {
      final days = p.visitDaysUntil;
      if (days != null && days < 0) {
        return 'Red — your scheduled Visit date has passed, but the PO Deadline '
            'has not. Reschedule the Visit or continue the inspection.';
      }
      if (days == 1) {
        return 'Red — your scheduled Visit is tomorrow. This is Visit timing, '
            'not a passed PO Deadline.';
      }
      if (days == 0) {
        return 'Red — your scheduled Visit is today. This is Visit timing, '
            'not a passed PO Deadline.';
      }
      return 'Red — this Visit needs attention now. This is Visit timing, '
          'not a passed PO Deadline.';
    }
    if (p.border == MyTaskBorder.orange) {
      final days = p.visitDaysUntil;
      return 'Orange — your scheduled Visit is in ${days ?? 'a few'} days, '
          'within the three-day reminder window. This is Visit timing, not a '
          'passed PO Deadline.';
    }
    return 'Blue — no Visit urgency and no passed PO Deadline are affecting '
        'this card. This is the normal state.';
  }

  Future<void> _showContextualInfo() async {
    final task = widget.task;
    final p = task.presentation;
    final statusColor = _getStatusColor(p);
    final borderExplanation = _borderExplanation(p);
    final indicators = <MapEntry<String, String>>[];
    final isCompleted = _displayCategory == 'Completed';
    final isScheduled =
        task.pendingSection == PendingTaskSection.scheduled;
    if (!isCompleted) {
      if (isScheduled) {
        indicators.add(MapEntry('Visit date', p.visitDay?.toIso8601String().split('T').first ?? 'Not verified'));
      }
      indicators.add(MapEntry('PO Deadline', p.deadlineDay?.toIso8601String().split('T').first ?? 'Not verified'));
      for (final notice in p.notices) {
        final title = switch (notice) {
          MyTaskNotice.visitInDays || MyTaskNotice.visitTomorrow ||
          MyTaskNotice.visitToday || MyTaskNotice.visitMissed => 'Visit notice',
          MyTaskNotice.scheduleConflict => 'Visit / PO Deadline conflict',
          _ => 'PO Deadline notice',
        };
        indicators.add(MapEntry(title, p.noticeText(notice)));
      }
      indicators.add(MapEntry('Next action', p.scheduleBlockReason ??
          'Continue your inspection before the PO Deadline. To ${isScheduled ? 'reschedule' : 'schedule'} a Visit, choose a date from tomorrow through the verified PO Deadline.'));
    }

    if (isCompleted) {
      // Completion and delivery are different facts. Only a readable synced
      // receipt proves server acceptance; a completed task with no receipt is
      // honestly unverified.
      final submission = widget.submission;
      if (submission == null) {
        indicators.add(const MapEntry(TaskSubmission.syncUnverifiedBadge,
            'This task is completed, but this device has no saved final-submission receipt. Server acceptance is not confirmed. Check Sync Center for delivery or review actions.'));
      } else if (_awaitingAcceptance) {
        indicators.add(const MapEntry('Completed on Device',
            'Your final submission is saved on this device. Server acceptance is not confirmed. Check Sync Center for delivery or review actions.'));
      } else {
        indicators.add(const MapEntry('Completed — Synced',
            'The server has confirmed this inspection.'));
      }
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

    if (!isCompleted && p.showInProgress) {
      indicators.add(const MapEntry('In Progress', 'You have already started this scheduled inspection. Continue working through the remaining steps until it is completed.'));
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Task details'),
        content: SingleChildScrollView(
          // At enlarged text the indicator list is taller than the dialog, so
          // it scrolls instead of overflowing and cutting the last lines off.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 3),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Border color', style: InsightTheme.inter(12, w: FontWeight.w700, c: InsightTheme.ink)),
                        const SizedBox(height: 2),
                        Text(borderExplanation, style: InsightTheme.inter(12, c: InsightTheme.ink2)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (final indicator in indicators) ...[
                Text(indicator.key, style: InsightTheme.inter(12, w: FontWeight.w700, c: InsightTheme.ink)),
                const SizedBox(height: 2),
                Text(indicator.value, style: InsightTheme.inter(12, c: InsightTheme.ink2)),
                const SizedBox(height: 10),
              ],
            ],
          ),
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
    AppFeedback.show(
      context,
      message: 'No $what on file for this applicant.',
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
      AppFeedback.show(
        context,
        message: 'No $label app found — $value copied to clipboard.',
        icon: Icons.content_copy_rounded,
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

  // Scheduling changes only the Visit; the raw inspection lifecycle survives.
  Future<void> _scheduleTask(BuildContext context) async {
    HapticFeedback.mediumImpact();

    final policy = widget.task.presentation;
    final owner = DBHelper.currentInspectorId;
    if (owner == null || owner != SupabaseService.client.auth.currentUser?.id ||
        _displayCategory == 'Completed' || !policy.canSchedule) {
      return;
    }
    final deadline = policy.latestVisit!;
    DateTime? pickedDate;
    final existing = policy.visitDay;
    if (widget.task.isSelfScheduled && existing != null &&
        !existing.isBefore(policy.earliestVisit!) && !existing.isAfter(deadline)) {
      pickedDate = existing;
    }
    var saving = false;
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
                      widget.task.isSelfScheduled ? 'Reschedule this task' : 'Schedule this task',
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
                        if (!mounted || owner != DBHelper.currentInspectorId ||
                            owner != SupabaseService.client.auth.currentUser?.id) {
                          return;
                        }
                        final window = widget.task.presentation;
                        if (_displayCategory == 'Completed' || !window.canSchedule || saving) return;
                        final selected = pickedDate;
                        final result = await showDatePicker(
                          context: sheetContext,
                          initialDate: selected != null && !selected.isBefore(window.earliestVisit!) &&
                              !selected.isAfter(window.latestVisit!) ? selected : window.earliestVisit!,
                          firstDate: window.earliestVisit!,
                          lastDate: window.latestVisit!,
                        );
                        if (result != null && sheetContext.mounted) setSheetState(() => pickedDate = result);
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
                    ...[
                      const SizedBox(height: 6),
                      Text(
                        'Must be on or before ${deadline.year}-${deadline.month.toString().padLeft(2, '0')}-${deadline.day.toString().padLeft(2, '0')} (assignment deadline)',
                        style: InsightTheme.inter(11, c: InsightTheme.ink3),
                      ),
                      const SizedBox(height: 4),
                      Text('Scheduling is online only. Your PO deadline is checked again at confirmation.',
                          style: InsightTheme.inter(11, c: InsightTheme.ink3)),
                    ],

                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: pickedDate == null || saving
                            ? null
                            : () async {
                                if (!mounted || owner != DBHelper.currentInspectorId ||
                                    owner != SupabaseService.client.auth.currentUser?.id) {
                                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                                      const SnackBar(content: Text(SavedDataNotice.ownerChanged)));
                                  Navigator.pop(sheetContext);
                                  return;
                                }
                                final window = widget.task.presentation;
                                final selected = pickedDate!;
                                if (_displayCategory == 'Completed' || !window.canSchedule ||
                                    selected.isBefore(window.earliestVisit!) || selected.isAfter(window.latestVisit!)) {
                                  ScaffoldMessenger.of(sheetContext).showSnackBar(SnackBar(content: Text(
                                    window.scheduleBlockReason ?? InspectionAuthorityResult.visitDateNotAllowed.message)));
                                  return;
                                }
                                setSheetState(() => saving = true);
                                try {
                                  // A zero-row write is never a successful
                                  // schedule; report the real outcome.
                                  final result = await SupabaseService.scheduleJob(
                                    jobId: widget.task.id,
                                    date: selected,
                                  );
                                  if (result != InspectionAuthorityResult.authorized) {
                                    if (sheetContext.mounted) {
                                      ScaffoldMessenger.of(sheetContext).showSnackBar(
                                        SnackBar(content: Text(result.message)),
                                      );
                                      Navigator.pop(sheetContext);
                                    }
                                    if (mounted) widget.onScheduled?.call();
                                    return;
                                  }
                                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                                  if (mounted) widget.onScheduled?.call();
                                } catch (_) {
                                  if (sheetContext.mounted) {
                                    ScaffoldMessenger.of(sheetContext).showSnackBar(
                                      SnackBar(content: Text(InspectionAuthorityResult.offlineOrUnverifiable.message)),
                                    );
                                  }
                                } finally {
                                  if (sheetContext.mounted) setSheetState(() => saving = false);
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: InsightTheme.blue1,
                          minimumSize: const Size(48, 48),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(
                          widget.task.isSelfScheduled ? 'Confirm reschedule' : 'Confirm schedule',
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
    final String taskCategory = _displayCategory;
    final p = widget.task.presentation;
    final notices = taskCategory == 'Completed' ? const <MyTaskNotice>[] : p.notices;
    final criticalNotice = notices.any((notice) => switch (notice) {
      MyTaskNotice.visitTomorrow || MyTaskNotice.visitToday ||
      MyTaskNotice.visitMissed || MyTaskNotice.deadlineToday ||
      MyTaskNotice.deadlinePassed || MyTaskNotice.scheduleConflict => true,
      MyTaskNotice.deadlineInDays => p.deadlineDaysUntil == 1,
      _ => false,
    });
    final bool isOverdue = taskCategory != 'Completed' && p.isOverdue;
    final statusColor = _getStatusColor(p);
    final bool showInProgress = taskCategory != 'Completed' && p.showInProgress;
    final int stepValue = (taskCategory == 'Completed' ? 6 : widget.task.currentStep > 0 ? widget.task.currentStep : widget.task.derivedHighestStep)
        .clamp(0, InspectionProgress.totalSteps);
    final bool canSchedule = taskCategory != 'Completed' && p.canSchedule;
    final borderColor = statusColor;

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
              // One deadline window controls every scheduling entry point.
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
                        if (taskCategory == 'Ongoing')
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
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.task.name,
                                      style: InsightTheme.poppins(14.5, w: FontWeight.w700, c: InsightTheme.ink),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 5),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(color: InsightTheme.surface2, borderRadius: BorderRadius.circular(6)),
                                      child: Text(
                                        widget.task.inspectionNo,
                                        style: InsightTheme.inter(10, w: FontWeight.w700, c: InsightTheme.blueInk, ls: 0.2),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                              FieldInfoButton(
                                label: 'About task details for ${widget.task.name}',
                                onPressed: _showContextualInfo,
                                color: criticalNotice ? InsightTheme.redInk : notices.isNotEmpty ? InsightTheme.orangeInk : InsightTheme.blueInk,
                                backgroundColor: criticalNotice ? InsightTheme.redTint : notices.isNotEmpty ? InsightTheme.orangeTint : InsightTheme.blueTint,
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
                          // A started inspector-committed Visit stays Scheduled.
                          if (taskCategory == 'Pending' && widget.task.pendingSection ==
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
                          if (taskCategory != 'Completed' && widget.task.deadlineDate != null && widget.task.deadlineDate!.isNotEmpty) ...[
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
                              if (taskCategory == 'Completed')
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                  decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                                  child: Text(TaskSubmission.badgeOrUnverified(widget.submission, canonicalCompleted: widget.task.category == 'Completed'),
                                    style: InsightTheme.inter(12, w: FontWeight.w700, c: statusColor)),
                                ),
                              // NOTE: no standalone "Scheduled" pill — it was
                              // redundant inside the Pending tab's Scheduled
                              // section (the section header + orange border +
                              // Visit row already say it) and added clutter
                              // on urgent cards. Scheduled state is carried
                              // by the orange border + avatar instead.
                              if (taskCategory != 'Completed' && p.forReschedule)
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
                              if (taskCategory != 'Completed' && p.deadlineState == MyTaskDeadlineState.today)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(color: InsightTheme.orangeTint,
                                      borderRadius: BorderRadius.circular(999)),
                                  child: Text('PO Deadline Today',
                                      style: InsightTheme.inter(10, w: FontWeight.w700, c: InsightTheme.orangeInk)),
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
                              if (taskCategory != 'Completed' &&
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
                              if (taskCategory != 'Completed' && widget.task.scheduleUrgency == 'Overdue')
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
                        if (canSchedule) ...[
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () => _scheduleTask(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              constraints: const BoxConstraints(minHeight: 48),
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
                                    Flexible(child: Text(
                                      widget.task.isSelfScheduled
                                        ? 'Reschedule Inspection Date'
                                        : 'Schedule Inspection Date',
                                    style: InsightTheme.inter(11, w: FontWeight.w600, c: InsightTheme.orangeInk),
                                    )),
                                ],
                              ),
                            ),
                          ),
                        ] else if (taskCategory != 'Completed') ...[
                          const SizedBox(height: 8),
                          Text(p.scheduleBlockReason!, style: InsightTheme.inter(12, c: InsightTheme.ink2)),
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
