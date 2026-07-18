import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/db_helper.dart';
import 'login_screen.dart';
import 'parcel_detail_screen.dart';
import 'completed_inspection_detail_screen.dart';
import 'home_dashboard_screen.dart';
import 'updates_screen.dart';
import 'profile_screen.dart';

/// ==================================================================
/// THEME COLORS & TOKENS (InSight Blue Glass & Gradient Theme)
/// ==================================================================
class InsightTheme {
  static const Color bg = Color(0xFFF2F4FB);
  static const Color surface = Colors.white;
  static const Color surface2 = Color(0xFFEEF1FC);
  
  static const Color ink = Color(0xFF12141F);
  static const Color ink2 = Color(0xFF666C82);
  static const Color ink3 = Color(0xFFA2A7BC);
  
  static const Color blue1 = Color(0xFF3D6BFF);
  static const Color blue2 = Color(0xFF0B2FBF);
  static const Color blueTint = Color(0xFFE7EDFF);
  static const Color blueInk = Color(0xFF1A3FC4);
  
  static const Color green = Color(0xFF12A150);
  static const Color greenTint = Color(0xFFE3F8EC);
  static const Color greenInk = Color(0xFF0D7A3C);
  
  static const Color line = Color(0x12141628); 
  
  static TextStyle poppins(double size, {FontWeight w = FontWeight.w600, Color? c, double? h, double? ls}) => 
      GoogleFonts.poppins(fontSize: size, fontWeight: w, color: c ?? ink, height: h ?? 1.2, letterSpacing: ls);
      
  static TextStyle inter(double size, {FontWeight w = FontWeight.w400, Color? c, double? h}) => 
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: c ?? ink2, height: h ?? 1.5);
}

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
  final String landUseClass;
  final double? lotAreaSqm;
  final String? propertyIndexNumber;
  final String? applicationType;

  // Populated once a job has been submitted — used by the read-only
  // Completed-task view instead of hardcoded placeholder text.
  final String? findings;
  final String? observations;
  final String? discrepancies;
  final String? recommendations;
  final String? inspectorNotes;
  final String? inspectionResult;
  final bool? isCompliant;
  final List<String> photoPaths;
  final int photoCount;
  final int checklistCompletedCount;
  final int checklistTotalCount;
  final String? submittedAt;
  final List<Map<String, dynamic>> checklistData;
  final double? confirmedLatitude;
  final double? confirmedLongitude;
  final double? gpsAccuracyM;
  final String? gpsConfirmedAt;

  TaskItem({
    required this.id,
    this.parcelId,
    required this.name,
    required this.location,
    required this.parcels,
    required this.status,
    required this.inspectionNo,
    this.scheduledDate = '',
    this.landUseClass = 'Not yet on file',
    this.lotAreaSqm,
    this.propertyIndexNumber,
    this.applicationType,
    this.findings,
    this.observations,
    this.discrepancies,
    this.recommendations,
    this.inspectorNotes,
    this.inspectionResult,
    this.isCompliant,
    this.photoPaths = const [],
    this.photoCount = 0,
    this.checklistCompletedCount = 0,
    this.checklistTotalCount = 0,
    this.submittedAt,
    this.checklistData = const [],
    this.confirmedLatitude,
    this.confirmedLongitude,
    this.gpsAccuracyM,
    this.gpsConfirmedAt,
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
      parcels: scheduledDate.isNotEmpty
          ? scheduledDate
          : application?['reference_number'] as String? ?? 'No schedule',
      status: job['status'] as String? ?? 'Pending',
      inspectionNo: application?['reference_number'] as String? ?? job['local_inspection_id']?.toString() ?? 'N/A',
      scheduledDate: scheduledDate,
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
      photoCount: (job['photo_count'] as num?)?.toInt() ?? 0,
      checklistCompletedCount: (job['checklist_completed_count'] as num?)?.toInt() ?? 0,
      checklistTotalCount: (job['checklist_total_count'] as num?)?.toInt() ?? 0,
      submittedAt: job['submitted_at'] as String?,
      checklistData: (job['checklist_data'] as List?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList() ?? const [],
      confirmedLatitude: (job['confirmed_latitude'] as num?)?.toDouble(),
      confirmedLongitude: (job['confirmed_longitude'] as num?)?.toDouble(),
      gpsAccuracyM: (job['gps_accuracy_m'] as num?)?.toDouble(),
      gpsConfirmedAt: job['gps_confirmed_at'] as String?,
      applicationType: application?['application_type'] as String?,
    );
  }

  String get category {
    final s = status.toLowerCase();

    // Final state — once submitted, always Completed. Nothing below can
    // override this, even if the scheduled date has since passed.
    if (s.contains('complete') || s.contains('done')) return 'Completed';

    // The inspector has actually started this job (DB status flips to
    // 'in_progress' when GPS is confirmed on-site — see
    // SupabaseService.confirmGpsOnSite) but hasn't submitted yet.
    if (s.contains('progress') || s.contains('ongoing')) return 'Ongoing';

    // Not started yet. "Scheduled" == due today or overdue — computed from
    // scheduled_date, not a manually-assigned status, so it updates itself
    // as the date arrives instead of depending on an admin flag.
    if (_isDueOrOverdue) return 'Scheduled';

    // Not started, still has time before its scheduled date — can be done
    // whenever the inspector has a slot.
    return 'Pending';
  }

  IconData get typeIcon {
    final t = '${applicationType ?? ''} $landUseClass'.toLowerCase();
    if (t.contains('commercial')) return Icons.location_city_rounded;
    if (t.contains('industrial')) return Icons.factory_rounded;
    if (t.contains('agri')) return Icons.grass_rounded;
    if (t.contains('institutional')) return Icons.account_balance_rounded;
    return Icons.home_rounded;
  }

  bool get _isDueOrOverdue {
    if (scheduledDate.isEmpty) return false;
    try {
      final due = DateTime.parse(scheduledDate);
      final today = DateTime.now();
      final dueDay = DateTime(due.year, due.month, due.day);
      final todayDay = DateTime(today.year, today.month, today.day);
      return !dueDay.isAfter(todayDay); // due today or already overdue
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

  const TasksScreen({super.key, required this.profile});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  int _currentNavIndex = 1; // 1 = Tasks
  int _currentTabIndex = 1; // Default to 'Ongoing'

  static const _tabOrder = ['Pending', 'Ongoing', 'Scheduled', 'Completed'];

  List<TaskItem> _allTasks = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
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
        await DBHelper.cacheJobs(jobs);
        if (mounted) {
          setState(() {
            _allTasks = jobs.map((j) => TaskItem.fromJob(j)).toList();
            _isLoading = false;
          });
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
                'supabase_zoning_applications': {
                  'applicant_name': j['applicant_name'],
                  'barangay': j['barangay'],
                  'reference_number': j['reference_number'],
                }
              });
            }).toList();
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      try {
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
                'supabase_zoning_applications': {
                  'applicant_name': j['applicant_name'],
                  'barangay': j['barangay'],
                  'reference_number': j['reference_number'],
                }
              });
            }).toList();
            _isLoading = false;
          });
        }
      } catch (dbError) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Failed to load tasks: $e';
            _isLoading = false;
          });
        }
      }
    }
  }

  /// Completed jobs are done — open the read-only summary instead of the
  /// editable step flow (which used to show "Continue" on already-submitted
  /// work because it only tracked in-session progress, not real job status).
  void _openTask(BuildContext context, TaskItem task) {
    HapticFeedback.selectionClick();
    if (task.category == 'Completed') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => CompletedInspectionDetailScreen(task: task)));
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => ParcelDetailScreen(task: task)));
    }
  }

  Future<void> _handleLogout(BuildContext context) async {
    await AuthService.signOut();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  Map<String, List<TaskItem>> _categorize() {
    final map = <String, List<TaskItem>>{
      for (final t in _tabOrder) t: <TaskItem>[],
    };
    for (final task in _allTasks) {
      map[task.category]!.add(task);
    }
    return map;
  }

  @override
Widget build(BuildContext context) {
  final categorized = _categorize();
  final ongoing = categorized['Ongoing'] ?? [];
  final pending = categorized['Pending'] ?? [];
  final scheduled = categorized['Scheduled'] ?? [];
  final completed = categorized['Completed'] ?? [];

  final selectedCategory = _tabOrder[_currentTabIndex];
  final selectedTasks = categorized[selectedCategory] ?? [];

  final TaskItem? heroTask = selectedTasks.isNotEmpty ? selectedTasks.first : null;
  final gridTasks = selectedTasks.where((t) => t.id != heroTask?.id).toList();

  return Scaffold(
    backgroundColor: InsightTheme.bg,
    extendBody: true,
    body: SafeArea(
      bottom: false,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_errorMessage!, textAlign: TextAlign.center),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadTasks,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('My Tasks', style: InsightTheme.poppins(20, w: FontWeight.w700)),
                            _TopIconBtn(icon: Icons.filter_list_rounded, onTap: () {}),
                          ],
                        ),
                        const SizedBox(height: 24),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          clipBehavior: Clip.none,
                          child: Row(
                            children: [
                              _TabPill(text: "Pending ${pending.length}", isActive: _currentTabIndex == 0, onTap: () => setState(() => _currentTabIndex = 0)),
                              const SizedBox(width: 8),
                              _TabPill(text: "Ongoing ${ongoing.length}", isActive: _currentTabIndex == 1, onTap: () => setState(() => _currentTabIndex = 1)),
                              const SizedBox(width: 8),
                              _TabPill(text: "Scheduled ${scheduled.length}", isActive: _currentTabIndex == 2, onTap: () => setState(() => _currentTabIndex = 2)),
                              const SizedBox(width: 8),
                              _TabPill(text: "Completed ${completed.length}", isActive: _currentTabIndex == 3, onTap: () => setState(() => _currentTabIndex = 3)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (heroTask != null) ...[
                          _HeroTaskCard(
                            task: heroTask,
                            onTap: () => _openTask(context, heroTask),
                          ),
                          const SizedBox(height: 16),
                        ] else
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text('No assigned tasks yet.'),
                          ),
                        if (gridTasks.isNotEmpty)
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 1.15,
                            ),
                            itemCount: gridTasks.length,
                            itemBuilder: (context, index) {
                              return _GridTaskCard(
                                task: gridTasks[index],
                                onTap: () => _openTask(context, gridTasks[index]),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.65)),
                boxShadow: const [
                  BoxShadow(color: Color(0x0A000000), blurRadius: 2, offset: Offset(0, 1)),
                  BoxShadow(color: Color(0x1A000000), blurRadius: 24, offset: Offset(0, 12)),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _BottomNavItem(
                    icon: Icons.home_rounded, label: 'Home', isActive: _currentNavIndex == 0,
                    onTap: () {
                      setState(() => _currentNavIndex = 0);
                      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HomeDashboardScreen(profile: widget.profile)));
                    }
                  ),
                  _BottomNavItem(
                    icon: Icons.assignment_outlined, label: 'Tasks', isActive: _currentNavIndex == 1,
                    onTap: () => setState(() => _currentNavIndex = 1)
                  ),
                  _BottomNavItem(
                    icon: Icons.sync_rounded, label: 'Updates', isActive: _currentNavIndex == 3,
                    onTap: () {
                      setState(() => _currentNavIndex = 3);
                      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => UpdatesScreen(profile: widget.profile)));
                    }
                  ),
                  _BottomNavItem(
                    icon: Icons.person_outline_rounded, label: 'Profile', isActive: _currentNavIndex == 4,
                    onTap: () {
                      setState(() => _currentNavIndex = 4);
                      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ProfileScreen(profile: widget.profile)));
                    }
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}}

/// ==================================================================
/// COMPONENT WIDGETS
/// ==================================================================

class _TopIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _TopIconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42, height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.65)),
          boxShadow: const [BoxShadow(color: InsightTheme.line, blurRadius: 14, offset: Offset(0, 4))],
        ),
        child: Icon(icon, color: InsightTheme.ink, size: 22),
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  final String text;
  final bool isActive;
  final VoidCallback onTap;

  const _TabPill({required this.text, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          gradient: isActive ? const LinearGradient(
            colors: [InsightTheme.blue1, InsightTheme.blue2],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ) : null,
          color: isActive ? null : InsightTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: isActive ? null : Border.all(color: InsightTheme.line),
          boxShadow: isActive ? [
            BoxShadow(color: InsightTheme.blue1.withOpacity(0.28), blurRadius: 18, offset: const Offset(0, 8))
          ] : [
            const BoxShadow(color: InsightTheme.line, blurRadius: 2, offset: Offset(0, 1))
          ],
        ),
        child: Text(
          text, 
          style: InsightTheme.inter(
            12, 
            w: FontWeight.w600, 
            c: isActive ? Colors.white : InsightTheme.ink2
          ),
        ),
      ),
    );
  }
}

class _HeroTaskCard extends StatelessWidget {
  final TaskItem task;
  final VoidCallback onTap;

  const _HeroTaskCard({required this.task, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: const LinearGradient(
            colors: [InsightTheme.blue1, InsightTheme.blue2],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(color: InsightTheme.blue1.withOpacity(0.30), blurRadius: 32, offset: const Offset(0, 16))
          ],
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            Positioned(
              right: -50, top: -50,
              child: Container(
                width: 160, height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.08),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        task.status, 
                        style: InsightTheme.inter(10, w: FontWeight.w600, c: Colors.white)
                      ),
                    ),
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.22),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.3)),
                      ),
                      child: const Icon(Icons.bookmark_outline_rounded, color: Colors.white, size: 18),
                    )
                  ],
                ),
                const SizedBox(height: 36),
                Text(task.location, style: InsightTheme.poppins(18, w: FontWeight.w700, c: Colors.white)),
                const SizedBox(height: 6),
                Text(task.parcels, style: InsightTheme.inter(12, c: Colors.white.withOpacity(0.85))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GridTaskCard extends StatelessWidget {
  final TaskItem task;
  final VoidCallback onTap;

  const _GridTaskCard({required this.task, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bool isDone = task.status == 'Done';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: InsightTheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: InsightTheme.line),
          boxShadow: const [BoxShadow(color: InsightTheme.line, blurRadius: 2, offset: Offset(0, 1))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: isDone ? InsightTheme.greenTint : InsightTheme.blueTint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.bookmark_outline_rounded, 
                    size: 16, 
                    color: isDone ? InsightTheme.greenInk : InsightTheme.blueInk
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isDone ? InsightTheme.greenTint : InsightTheme.surface2,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    task.status,
                    style: InsightTheme.inter(
                      10, 
                      w: FontWeight.w600, 
                      c: isDone ? InsightTheme.greenInk : InsightTheme.ink2
                    ),
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.location, 
                  style: InsightTheme.inter(13, w: FontWeight.w600, c: InsightTheme.ink),
                  maxLines: 1, 
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  task.parcels, 
                  style: InsightTheme.inter(11.5, c: InsightTheme.ink2),
                  maxLines: 1, 
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _BottomNavItem({required this.icon, required this.label, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: isActive ? 14 : 10, vertical: 10),
        decoration: BoxDecoration(
          gradient: isActive ? const LinearGradient(
            colors: [InsightTheme.blue1, InsightTheme.blue2],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ) : null,
          borderRadius: BorderRadius.circular(14),
          boxShadow: isActive ? [
            BoxShadow(color: InsightTheme.blue1.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))
          ] : [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isActive ? Colors.white : InsightTheme.ink3, size: 20),
            const SizedBox(height: 4),
            Text(
              label, 
              style: InsightTheme.inter(
                10, 
                w: FontWeight.w600, 
                c: isActive ? Colors.white : InsightTheme.ink3
              ),
            ),
          ],
        ),
      ),
    );
  }
}