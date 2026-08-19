import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart'; 

import '../../../core/models/user_profile.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/db_helper.dart';

import '../../../core/navigation/parcel_detail_screen.dart';
import '../../inspection/screens/completed_inspection_detail_screen.dart';
import '../../inspection/screens/inspection_progress.dart';
import '../../../core/widgets/motion/spring_entrance.dart';
import '../../../core/widgets/motion/updating_tile.dart';
import '../../../core/widgets/motion/linked_list_motion.dart';
import '../../../core/widgets/imaps_loading_indicator.dart';
import '../../../core/widgets/sensitive_screen.dart';


/// ==================================================================
/// THEME COLORS & TOKENS (Strict Enterprise Theme)
/// ==================================================================
class InsightTheme {
  static const Color bg = Color(0xFFF7F9FC); 
  static const Color surface = Colors.white;
  static const Color surface2 = Color(0xFFEDF1F5);
  
  static const Color ink = Color(0xFF0F172A);
  static const Color ink2 = Color(0xFF475569);
  static const Color ink3 = Color(0xFF94A3B8);
  
  static const Color blue1 = Color(0xFF2563EB); 
  static const Color blue2 = Color(0xFF1D4ED8);
  static const Color blueTint = Color(0xFFEFF6FF);
  static const Color blueInk = Color(0xFF1E3A8A); 
  
  static const Color green = Color(0xFF16A34A);
  static const Color greenTint = Color(0xFFF0FDF4);
  static const Color greenInk = Color(0xFF14532D); 
  
  static const Color orange = Color(0xFFD97706);
  static const Color orangeTint = Color(0xFFFFFBEB);
  static const Color orangeInk = Color(0xFF78350F); 
  
  static const Color line = Color(0xFFE2E8F0); 
  
  static TextStyle poppins(double size, {FontWeight w = FontWeight.w600, Color? c, double? h, double? ls}) => 
      GoogleFonts.poppins(fontSize: size, fontWeight: w, color: c ?? ink, height: h ?? 1.2, letterSpacing: ls);
      
  static TextStyle inter(double size, {FontWeight w = FontWeight.w400, Color? c, double? h, double? ls}) => 
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: c ?? ink2, height: h ?? 1.5, letterSpacing: ls);
}

/// ==================================================================
/// CONSTANTS
/// ==================================================================
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
class TaskItem {
  final String id;
  final String? parcelId;
  final String name;
  final String location;
  final String parcels; 
  final String status;
  final String inspectionNo;
  final String scheduledDate;
  final String? deadlineDate;
  final String landUseClass;
  final double? lotAreaSqm;
  final String? propertyIndexNumber;
  final String? applicationType;

  final String? findings;
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

  TaskItem({
    required this.id, this.parcelId, required this.name, required this.location,
    required this.parcels, required this.status, required this.inspectionNo, 
    this.scheduledDate = '', this.deadlineDate, this.landUseClass = 'Not yet on file', this.lotAreaSqm,
    this.propertyIndexNumber, this.applicationType, this.findings, this.observations,
    this.discrepancies, this.recommendations, this.inspectorNotes, this.inspectionResult,
    this.isCompliant, this.photoPaths = const [], this.photoDetails = const [], this.photoCount = 0,
    this.checklistCompletedCount = 0, this.checklistTotalCount = 0, this.submittedAt,
    this.checklistData = const [], this.confirmedLatitude, this.confirmedLongitude,
    this.gpsAccuracyM, this.gpsConfirmedAt, this.isSelfScheduled = false,
    this.applicantPhone, this.applicantEmail,
    this.currentStep = 0,
    this.createdAt = '',
    this.startedAt,
    this.reworkStartedAt,
    this.updatedAt,
  });

  factory TaskItem.fromJob(Map<String, dynamic> job) {
    final application = job['supabase_zoning_applications'] as Map<String, dynamic>?;
    final parcel = job['supabase_parcels'] as Map<String, dynamic>?;
    final scheduledDate = job['scheduled_date'] as String? ?? '';
    return TaskItem(
      id: job['id']?.toString() ?? '',
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
      status: job['status'] as String? ?? 'Pending',
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
      currentStep: (job['current_step'] as num?)?.toInt() ?? 0,
      createdAt: job['created_at'] as String? ?? '',
      startedAt: job['started_at'] as String?,
      reworkStartedAt: job['rework_started_at'] as String?,
      updatedAt: job['updated_at'] as String?,
    );
  }

  /// Highest step (0-6) verifiably done, based on what's ACTUALLY saved in
  /// the DB — not client-side session memory. This is what makes progress
  /// survive app restarts and stay correct when switching between tasks
  /// (each task derives its own number from its own real data).
  int get derivedHighestStep {
    if (status.toLowerCase().contains('complete')) return 6;
    final hasFindings = (observations?.isNotEmpty ?? false) ||
        (discrepancies?.isNotEmpty ?? false) ||
        (recommendations?.isNotEmpty ?? false) ||
        (inspectorNotes?.isNotEmpty ?? false);
    if (hasFindings) return 5;
    if (checklistCompletedCount > 0) return 4;
    if (photoCount > 0 || photoPaths.isNotEmpty) return 3;
    if (confirmedLatitude != null && confirmedLongitude != null) return 2;
    final s = status.toLowerCase();
    if (s.contains('progress') || s.contains('ongoing')) return 1;
    return 0;
  }

  String get category {
    final s = status.toLowerCase();
    if (s.contains('complete') || s.contains('done')) return 'Completed';
    if (s.contains('progress') || s.contains('ongoing')) return 'Ongoing';
    // "Scheduled" == the inspector has actively booked a date for this job
    // (via the Schedule action / long-press on a Pending card) — this is
    // sticky (isSelfScheduled) so the task stays here even once that date
    // arrives or passes, instead of disappearing back into Pending and
    // losing the "this was planned" signal. A merely-future scheduled_date
    // that was only ever the admin's default assignment date also counts,
    // since that's still "not due yet."
    // "Pending" is the default: no plan locked in, so it can be done
    // whenever there's a slot — due-today/overdue included.
    if (isScheduledPlan) return 'Scheduled';
    return 'Pending';
  }

  /// Whether this task is "on the schedule plan" at all — independent of
  /// its current workflow status. Used both by `category` above (Pending
  /// vs Scheduled, only reached once not Ongoing/Completed) and by the
  /// cross-cutting "ScheduledActive" bucket in _categorizeAndFilter(),
  /// which needs this same test WITHOUT the Ongoing/Completed short-circuit
  /// — so a task can be "on the schedule plan" and "in progress" at the
  /// same time (see Scheduled-vs-Ongoing UX fix).
  bool get isScheduledPlan => isSelfScheduled || _isScheduledAhead;

  /// Null when a Scheduled task's date hasn't arrived yet. Otherwise flags
  /// how urgent it now is, so it doesn't just quietly sit there once due —
  /// used for the "Due today" / "Overdue" badge in the Scheduled tab.
  String? get scheduleUrgency {
    if (category != 'Scheduled' || scheduledDate.isEmpty) return null;
    try {
      final due = DateTime.parse(scheduledDate);
      final today = DateTime.now();
      final dueDay = DateTime(due.year, due.month, due.day);
      final todayDay = DateTime(today.year, today.month, today.day);
      if (dueDay.isAtSameMomentAs(todayDay)) return 'Due today';
      if (dueDay.isBefore(todayDay)) return 'Overdue';
      return null; // still in the future — no urgency badge needed yet
    } catch (_) {
      return null;
    }
  }

  IconData get typeIcon {
    final t = '${applicationType ?? ''} $landUseClass'.toLowerCase();
    if (t.contains('commercial')) return Icons.location_city_rounded;
    if (t.contains('industrial')) return Icons.factory_rounded;
    if (t.contains('agri')) return Icons.grass_rounded;
    if (t.contains('institutional')) return Icons.account_balance_rounded;
    return Icons.home_rounded;
  }

  bool get _isScheduledAhead {
    if (scheduledDate.isEmpty) return false;
    try {
      final due = DateTime.parse(scheduledDate);
      final today = DateTime.now();
      final dueDay = DateTime(due.year, due.month, due.day);
      final todayDay = DateTime(today.year, today.month, today.day);
      return dueDay.isAfter(todayDay); // booked for a future date
    } catch (_) {
      return false;
    }
  }

  /// True when the deadline is tomorrow, today, or already past — used to
  /// visually flag a Scheduled card as urgent so the inspector can spot it
  /// at a glance, like a filling-up warning.
  bool get isUrgentDeadline {
    if (deadlineDate == null || deadlineDate!.isEmpty) return false;
    try {
      final due = DateTime.parse(deadlineDate!);
      final today = DateTime.now();
      final dueDay = DateTime(due.year, due.month, due.day);
      final todayDay = DateTime(today.year, today.month, today.day);
      return dueDay.difference(todayDay).inDays <= 1;
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

  // Phase 3 (My Tasks status architecture): "Scheduled" is no longer its
  // own segment tab — it's now a section header inside Pending (see
  // `_categorizeAndFilter` / `_visibleTabOrder`). TaskItem.category still
  // returns 'Scheduled' as its own value (unchanged) so callers outside
  // this screen — e.g. ActiveAssignmentsFolderCard's status coloring on
  // the Home dashboard — keep working exactly as before; only this
  // screen's tab layout changed.
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
  // 'All' | 'Overdue' | 'Due today' — new quick-filter inside the filter sheet.
  String _urgencyFilter = 'All';

  // Internal categorization/sorting still uses all 4 real categories —
  // TaskItem.category is unchanged. Only the visible segment tabs (below)
  // collapse Scheduled into Pending.
  static const _tabOrder = ['Pending', 'Ongoing', 'Scheduled', 'Completed'];
  // What's actually shown as segment tabs, post-Phase-3.
  static const _visibleTabOrder = ['Pending', 'Ongoing', 'Completed'];

  final GlobalKey _scheduledSectionKey = GlobalKey();
  bool _pendingScrollToScheduled = false;

  List<TaskItem> _allTasks = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _currentTabIndex = widget.scrollToScheduled ? TasksScreen.tabPending : widget.initialTabIndex;
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
    disposeSpringEntrance();
    super.dispose();
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
          signature: Object.hash(task.status, task.scheduledDate, task.deadlineDate),
          child: _CompactTaskCard(
            key: ValueKey(task.id),
            task: task,
            onTapDetail: () => _openTask(context, task),
            onScheduled: _loadTasks,
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
            _allTasks = localJobs.map((j) {
              return TaskItem.fromJob({
                'id': j['id'],
                'supabase_parcel_id': j['supabase_parcel_id'],
                'status': j['status'],
                'local_inspection_id': j['local_inspection_id'],
                'scheduled_date': j['scheduled_date'],
                'deadline_date': j['deadline_date'],
                'is_self_scheduled': j['is_self_scheduled'] == 1,
                'rework_started_at': j['rework_started_at'],
                'supabase_zoning_applications': {
                  'applicant_name': j['applicant_name'],
                  'barangay': j['barangay'],
                  'reference_number': j['reference_number'],
                  'application_type': j['application_type'],
                },
                // Phase 1 audit fix (item #1 — Pre-Cache display gap):
                // `local_jobs` already caches these parcel fields
                // (see DBHelper.cacheJobs) but this offline branch never
                // passed them through, so the Tasks List always showed
                // "Not yet on file" for land use/lot area while offline
                // even though GPS Verification (which reads local_jobs
                // directly) already had the real cached values.
                // NOTE: property_index_number and the applicant's
                // contact_number/email are not cached in local_jobs at
                // all today — those stay null/"Not yet on file" offline
                // regardless of this fix. Caching them would need a
                // schema change to local_jobs + cacheJobs(), which is a
                // separate, larger change than this display-wiring fix.
                'supabase_parcels': {
                  'land_use_class': j['declared_land_use'],
                  'lot_area_sqm': j['lot_area_sqm'],
                },
              });
            }).toList();
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
      await Navigator.push(context, MaterialPageRoute(builder: (_) => CompletedInspectionDetailScreen(task: task)));
    } else {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ParcelDetailScreen(task: task)));
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

                        // PRIORITY / URGENCY SECTION — new, per request:
                        // quick filter for Overdue and Due Today, using the
                        // same task.scheduleUrgency values already computed
                        // and already shown on the card badges — no new
                        // data source.
                        Row(
                          children: [
                            const Icon(Icons.priority_high_rounded, color: InsightTheme.ink3, size: 18),
                            const SizedBox(width: 8),
                            Text('FILTER BY PRIORITY', style: InsightTheme.inter(11, w: FontWeight.w700, c: InsightTheme.ink3, ls: 1.0)),
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
                                label: 'Overdue',
                                isSelected: tempUrgency == 'Overdue',
                                onTap: () => setModalState(() => tempUrgency = 'Overdue'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _NativeFilterChip(
                                label: 'Due Today',
                                isSelected: tempUrgency == 'Due today',
                                onTap: () => setModalState(() => tempUrgency = 'Due today'),
                              ),
                            ),
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
                          height: 42,
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
                                  decoration: BoxDecoration(
                                    color: isSelected ? InsightTheme.blueTint : Colors.transparent,
                                    border: Border(bottom: BorderSide(color: InsightTheme.line.withValues(alpha: 0.5))),
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
                      backgroundColor: InsightTheme.ink,
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

  Map<String, List<TaskItem>> _categorizeAndFilter() {
    final map = <String, List<TaskItem>>{
      for (final t in _tabOrder) t: <TaskItem>[],
      // Design decision (Scheduled vs Ongoing UX, validated before
      // implementing): a task that's on today's/self-scheduled plan
      // AND already in progress should still surface in the Pending
      // tab's "Scheduled" section — not just the Ongoing tab (both,
      // per instruction) — even though its `category` is 'Ongoing' and
      // it's therefore NOT in the `map['Scheduled']` bucket above.
      // This bucket is that cross-cutting view: same "is this on the
      // schedule plan" test as `category`, but without excluding
      // Ongoing tasks — only Completed is excluded, since a finished
      // inspection has nothing left to plan around.
      'ScheduledActive': <TaskItem>[],
    };
    
    for (final task in _allTasks) {
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
        if (task.scheduleUrgency != _urgencyFilter) continue;
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
      if (task.isScheduledPlan && task.category != 'Completed') {
        map['ScheduledActive']!.add(task);
      }
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
          case 'Scheduled':
          case 'ScheduledActive':
            final da = a.deadlineDate?.isNotEmpty == true ? a.deadlineDate! : '9999-12-31';
            final db = b.deadlineDate?.isNotEmpty == true ? b.deadlineDate! : '9999-12-31';
            return da.compareTo(db);
          case 'Completed':
            final sa = a.submittedAt ?? '';
            final sb = b.submittedAt ?? '';
            return sa.compareTo(sb);
          default:
            return 0;
        }
      });
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final categorized = _categorizeAndFilter();
    final ongoing = categorized['Ongoing'] ?? [];
    final pending = categorized['Pending'] ?? [];
    // Scheduled vs Ongoing UX fix: use the cross-cutting bucket (includes
    // today's/self-scheduled tasks that are already In Progress), not the
    // plain category bucket — see _categorizeAndFilter(). The Ongoing tab
    // below still uses the plain `ongoing` bucket unchanged, so an active
    // scheduled task appears in both, by design (validated: "show in both").
    final scheduled = categorized['ScheduledActive'] ?? [];
    final completed = categorized['Completed'] ?? [];

    final selectedCategory = _visibleTabOrder[_currentTabIndex];
    final bool isPendingTab = selectedCategory == 'Pending';
    // Phase 3: Pending tab now shows both real-Pending and Scheduled tasks
    // together, split into two headed sections below — but as one combined
    // list for the empty-state check and non-Pending tabs.
    final selectedTasks = isPendingTab
        ? [...scheduled, ...pending]
        : (categorized[selectedCategory] ?? []);

    final bool hasActiveFilters = _selectedBarangay != 'All Barangays' || _datePreset != null || _urgencyFilter != 'All';

    return SensitiveScreen(child: Scaffold(
      backgroundColor: InsightTheme.bg,
      extendBody: true,
      appBar: AppBar(
        backgroundColor: InsightTheme.surface,
        elevation: 0,
        automaticallyImplyLeading: false, 
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 85,
        title: SpringSlide(
          animation: springFor(0),
          beginOffset: const Offset(0, -24),
          child: Padding(
          padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Restyled to a pill badge w/ status dot — visual only,
                  // same "Active Monitoring" copy, matches reference header.
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: InsightTheme.blueTint,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6, height: 6,
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: InsightTheme.blue1),
                        ),
                        const SizedBox(width: 6),
                        Text('ACTIVE MONITORING', style: InsightTheme.inter(10, w: FontWeight.w700, c: InsightTheme.blueInk, ls: 0.8)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('My Tasks', style: InsightTheme.poppins(26, w: FontWeight.w800, c: InsightTheme.ink, ls: -0.4)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: InsightTheme.blue1,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [BoxShadow(color: Color(0x1A2563EB), blurRadius: 16, offset: Offset(0, 6))],
                ),
                child: Column(
                  children: [
                    CountUpText(
                      value: _allTasks.length,
                      style: InsightTheme.poppins(18, w: FontWeight.w800, c: Colors.white, h: 1.0),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ASSIGNED',
                      style: InsightTheme.inter(9, w: FontWeight.w700, c: Colors.white.withValues(alpha: 0.85), ls: 0.6),
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
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // SEARCH & FILTER COMPONENT
                                SpringSlide(
                                  animation: springFor(1),
                                  beginOffset: const Offset(0, 22),
                                  child: Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: InsightTheme.bg,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: InsightTheme.line),
                                        ),
                                        child: TextField(
                                          controller: _searchController,
                                          style: InsightTheme.inter(14, w: FontWeight.w400, c: InsightTheme.ink),
                                          decoration: InputDecoration(
                                            hintText: 'Search fields or inspection IDs...',
                                            hintStyle: InsightTheme.inter(14, c: InsightTheme.ink3),
                                            prefixIcon: const Icon(Icons.search_rounded, color: InsightTheme.ink2, size: 18),
                                            suffixIcon: _searchQuery.isNotEmpty 
                                                ? GestureDetector(
                                                    onTap: () {
                                                      _searchController.clear();
                                                      FocusScope.of(context).unfocus();
                                                    },
                                                    child: const Icon(Icons.cancel, color: InsightTheme.ink3, size: 18),
                                                  )
                                                : null,
                                            border: InputBorder.none,
                                            contentPadding: const EdgeInsets.symmetric(vertical: 11),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    GestureDetector(
                                      onTap: _showFilterBottomSheet,
                                      child: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Container(
                                            height: 42, width: 42,
                                            decoration: BoxDecoration(
                                              color: InsightTheme.surface,
                                              border: Border.all(color: InsightTheme.line),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: const Icon(Icons.tune_rounded, color: InsightTheme.ink, size: 20),
                                          ),
                                          if (hasActiveFilters)
                                            Positioned(
                                              top: -3, right: -3,
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
                                  ),
                                ),
                                const SizedBox(height: 14),
                                
                                // CATEGORY SEGMENTED TABS — evenly divided,
                                // no horizontal scroll needed for 3 items
                                // (was a left-packed scrolling chip row).
                                // Same _currentTabIndex state/logic, visual only.
                                SpringSlide(
                                  animation: springFor(2),
                                  beginOffset: const Offset(0, 22),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    margin: const EdgeInsets.only(bottom: 12),
                                    decoration: BoxDecoration(
                                      color: InsightTheme.surface2,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        // Wrapped in Expanded — without it, a
                                        // 2-digit count (e.g. "Completed 21")
                                        // pushes this tab's intrinsic width
                                        // past the row's available space and
                                        // the row overflows on the right,
                                        // since a plain spaceBetween Row
                                        // doesn't constrain child widths.
                                        Expanded(
                                          child: _SegmentTab(text: "Pending", count: pending.length + scheduled.length, isActive: _currentTabIndex == 0, onTap: () => setState(() => _currentTabIndex = 0)),
                                        ),
                                        Expanded(
                                          child: _SegmentTab(text: "Ongoing", count: ongoing.length, isActive: _currentTabIndex == 1, onTap: () => setState(() => _currentTabIndex = 1)),
                                        ),
                                        Expanded(
                                          child: _SegmentTab(text: "Completed", count: completed.length, isActive: _currentTabIndex == 2, onTap: () => setState(() => _currentTabIndex = 2)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
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
                            padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 140),
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
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: InsightTheme.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: InsightTheme.line),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: InsightTheme.inter(13, c: InsightTheme.ink2)),
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

  const _SegmentTab({required this.text, required this.count, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Restyled from a left-packed filled chip to a full-width segmented
    // tab (white pill + shadow when active) — same tap target/state,
    // matches the reference's segmented-tab look while staying on
    // this screen's own InsightTheme tokens.
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        // Horizontal padding tightened (14 -> 8) — combined with the
        // smaller font/gap/badge below, this is what actually keeps
        // "Completed 21" fitting at 100% scale so the FittedBox safety
        // net never has to engage for it. Before this, "Completed" was
        // the one tab that needed scaling down while "Pending"/"Ongoing"
        // didn't, so despite sharing the same font-size value in code,
        // they rendered at visibly different sizes — inconsistent look.
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
        // FittedBox stays only as a defensive fallback for extremely
        // narrow devices — under normal widths every tab now fits at its
        // true 100% size, so all three render at the exact same text
        // size instead of "Completed" alone shrinking to fit.
        child: FittedBox(
          fit: BoxFit.scaleDown,
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
      ),
    );
  }
}

class _CompactTaskCard extends StatefulWidget {
  final TaskItem task;
  final VoidCallback onTapDetail;
  final VoidCallback? onScheduled;

  const _CompactTaskCard({super.key, required this.task, required this.onTapDetail, this.onScheduled});

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
    if (cat == 'Scheduled') return InsightTheme.orange;
    return InsightTheme.blue1;
  }

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

  // Long-press a Pending card -> pick a date (never past the admin's
  // deadline_date) + optional note -> updates scheduled_date, which moves
  // this task into the Scheduled tab automatically (see TaskItem.category).
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
    final notesController = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
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
                            Text(
                              pickedDate == null
                                  ? 'Select a date'
                                  : '${pickedDate!.year}-${pickedDate!.month.toString().padLeft(2, '0')}-${pickedDate!.day.toString().padLeft(2, '0')}',
                              style: InsightTheme.inter(13.5, w: FontWeight.w600, c: InsightTheme.ink),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (deadline != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Must be on or before ${deadline.year}-${deadline.month.toString().padLeft(2, '0')}-${deadline.day.toString().padLeft(2, '0')} (deadline set by admin)',
                        style: InsightTheme.inter(11, c: InsightTheme.ink3),
                      ),
                    ],

                    const SizedBox(height: 16),
                    Text('Notes (optional)', style: InsightTheme.inter(12, w: FontWeight.w600, c: InsightTheme.ink2)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: InsightTheme.bg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: InsightTheme.line),
                      ),
                      child: TextField(
                        controller: notesController,
                        maxLines: 3,
                        style: InsightTheme.inter(13, c: InsightTheme.ink2),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'e.g. "Applicant requested morning slot"',
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: pickedDate == null
                            ? null
                            : () async {
                                try {
                                  await SupabaseService.scheduleJob(
                                    jobId: widget.task.id,
                                    date: pickedDate!,
                                    note: notesController.text,
                                  );
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
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor();
    final isUrgent = widget.task.category == 'Scheduled' && widget.task.isUrgentDeadline;
    // Visual-only addition (approved Task 2 scope): a slim step-progress
    // bar under the badge row, matching the reference mockup. Reuses the
    // exact step math already used by the "In Progress" badge below —
    // no new data source, no logic change.
    final int stepValue = (widget.task.currentStep > 0 ? widget.task.currentStep : widget.task.derivedHighestStep)
        .clamp(0, InspectionProgress.totalSteps);
    // Reschedule availability: a task can be (re)scheduled whenever it's
    // still "on the schedule plan" and hasn't been submitted yet — that
    // covers plain Pending/Scheduled AND an Ongoing-but-scheduled task
    // (the ones that show up under the Pending tab's "Scheduled" section
    // while already In Progress). Completed tasks are excluded since
    // there's nothing left to plan around.
    final bool canSchedule = widget.task.category != 'Completed' &&
        (widget.task.category == 'Pending' ||
            widget.task.category == 'Scheduled' ||
            widget.task.isScheduledPlan);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isUrgent ? const Color(0xFFFEF2F2) : InsightTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isUrgent ? const Color(0xFFEF4444) : InsightTheme.line,
          width: isUrgent ? 1.4 : 1,
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
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                ),
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
                              if (widget.task.category == 'Ongoing')
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
                                      const Icon(Icons.schedule_rounded, size: 11, color: Color(0xFFB45309)),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Modified',
                                        style: InsightTheme.inter(10, w: FontWeight.w700, c: const Color(0xFFB45309)),
                                      ),
                                    ],
                                  ),
                                ),
                              if (widget.task.scheduleUrgency != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: widget.task.scheduleUrgency == 'Overdue'
                                        ? const Color(0xFFFEE2E2)
                                        : InsightTheme.orangeTint,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        widget.task.scheduleUrgency == 'Overdue' ? Icons.warning_rounded : Icons.access_time_rounded,
                                        size: 11,
                                        color: widget.task.scheduleUrgency == 'Overdue' ? const Color(0xFFB91C1C) : InsightTheme.orangeInk,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        widget.task.scheduleUrgency!,
                                        style: InsightTheme.inter(
                                          10, w: FontWeight.w700,
                                          c: widget.task.scheduleUrgency == 'Overdue'
                                              ? const Color(0xFFB91C1C)
                                              : InsightTheme.orangeInk,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
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