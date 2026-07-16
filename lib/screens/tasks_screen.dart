import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import 'login_screen.dart';
import 'parcel_detail_screen.dart';

class TaskItem {
  final String id;
  final String? parcelId;
  final String name;
  final String location;
  final String status;
  final String inspectionNo;
  final String scheduledDate;

  TaskItem({
    required this.id,
    required this.parcelId,
    required this.name,
    required this.location,
    required this.status,
    required this.inspectionNo,
    required this.scheduledDate,
  });

  factory TaskItem.fromJob(Map<String, dynamic> job) {
    final application = job['supabase_zoning_applications'] as Map<String, dynamic>?;
    return TaskItem(
      id: job['id'] as String,
      parcelId: job['supabase_parcel_id'] as String?,
      name: application?['applicant_name'] ?? 'Unknown Applicant',
      location: application?['barangay'] ?? 'No barangay listed',
      status: job['status'] as String,
      inspectionNo: application?['reference_number'] ?? job['local_inspection_id'].toString(),
      scheduledDate: job['scheduled_date'] ?? '',
    );
  }
}

class TasksScreen extends StatefulWidget {
  final UserProfile profile;

  const TasksScreen({super.key, required this.profile});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  static const _headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1B1140), Color(0xFF4A2FE0)],
  );

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
      final jobs = await SupabaseService.fetchMyJobs();
      setState(() {
        _allTasks = jobs.map((j) => TaskItem.fromJob(j)).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load tasks: $e';
        _isLoading = false;
      });
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

  @override
  Widget build(BuildContext context) {
    final assigned = _allTasks.where((t) => t.status == 'assigned').toList();
    final inProgress = _allTasks.where((t) => t.status == 'in_progress').toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              decoration: const BoxDecoration(
                gradient: _headerGradient,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.circle, color: Colors.greenAccent, size: 10),
                          SizedBox(width: 6),
                          Text('iMAPS-FieldSync', style: TextStyle(color: Colors.white70, fontSize: 13)),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout, color: Colors.white, size: 20),
                        onPressed: () => _handleLogout(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'My Tasks',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Welcome, ${widget.profile.fullName} · ${widget.profile.role}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? Center(child: Text(_errorMessage!))
                      : RefreshIndicator(
                          onRefresh: _loadTasks,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                            children: [
                              const Text('Assigned', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Color(0xFF1B1140))),
                              const SizedBox(height: 10),
                              if (assigned.isEmpty)
                                const Text('No assigned tasks yet.', style: TextStyle(color: Colors.grey)),
                              ...assigned.map((t) => _TaskCard(task: t)),
                              const SizedBox(height: 20),
                              const Text('In Progress', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Color(0xFF1B1140))),
                              const SizedBox(height: 10),
                              if (inProgress.isEmpty)
                                const Text('No tasks in progress.', style: TextStyle(color: Colors.grey)),
                              ...inProgress.map((t) => _TaskCard(task: t)),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final TaskItem task;
  const _TaskCard({required this.task});

  Color get _statusColor => task.status == 'assigned' ? const Color(0xFFFFF1C2) : const Color(0xFFD3F5DF);
  Color get _statusTextColor => task.status == 'assigned' ? const Color(0xFF9A7B14) : const Color(0xFF1E8A4C);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => ParcelDetailScreen(task: task)));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${task.name} - ${task.location}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                  const SizedBox(height: 4),
                  Text('Scheduled: ${task.scheduledDate}', style: const TextStyle(color: Colors.grey, fontSize: 12.5)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: _statusColor, borderRadius: BorderRadius.circular(20)),
              child: Text(task.status, style: TextStyle(color: _statusTextColor, fontSize: 11.5, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}