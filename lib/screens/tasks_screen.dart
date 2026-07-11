import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'parcel_detail_screen.dart';

class TaskItem {
  final String name;
  final String location;
  final String parcels;
  final String status;
  final String inspectionNo;

  TaskItem({
    required this.name,
    required this.location,
    required this.parcels,
    required this.status,
    required this.inspectionNo,
  });
}

class TasksScreen extends StatelessWidget {
  final UserProfile profile;

  const TasksScreen({super.key, required this.profile});

  static const _headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1B1140), Color(0xFF4A2FE0)],
  );

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
    final assigned = [
      TaskItem(
        name: 'Maria Santos',
        location: 'San Roque',
        parcels: '2 parcels',
        status: 'Assigned',
        inspectionNo: 'FI-20260608001',
      ),
      TaskItem(
        name: 'Ralph Ramos',
        location: 'Malaya',
        parcels: '2 parcels',
        status: 'Assigned',
        inspectionNo: 'FI-20260608002',
      ),
    ];

    final inProgress = [
      TaskItem(
        name: 'Juan Rodriguez',
        location: 'Alupay',
        parcels: '3 parcels',
        status: 'In Progress',
        inspectionNo: 'FI-20260608003',
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: SafeArea(
        child: Column(
          children: [
            // Header
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
                          Text(
                            'iMAPS-FieldSync',
                            style: TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha:0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Offline Mode',
                              style: TextStyle(color: Colors.white, fontSize: 11),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.logout, color: Colors.white, size: 20),
                            onPressed: () => _handleLogout(context),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'My Tasks',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Welcome, ${profile.fullName} · ${profile.role}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.search, color: Colors.grey, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Enter Inspection No., Applicant Name, or Barangay',
                            style: TextStyle(color: Colors.grey, fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Task list
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                children: [
                  const Text(
                    'Assigned',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: Color(0xFF1B1140),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...assigned.map((t) => _TaskCard(task: t)),
                  const SizedBox(height: 20),
                  const Text(
                    'In Progress',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: Color(0xFF1B1140),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...inProgress.map((t) => _TaskCard(task: t)),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        selectedItemColor: const Color(0xFF3D2FE0),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Tasks'),
          BottomNavigationBarItem(icon: Icon(Icons.grid_view), label: 'Services'),
          BottomNavigationBarItem(icon: Icon(Icons.notifications_none), label: 'Alerts'),
          BottomNavigationBarItem(icon: Icon(Icons.call_outlined), label: 'Contact'),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final TaskItem task;
  const _TaskCard({required this.task});

  Color get _statusColor =>
      task.status == 'Assigned' ? const Color(0xFFFFF1C2) : const Color(0xFFD3F5DF);

  Color get _statusTextColor =>
      task.status == 'Assigned' ? const Color(0xFF9A7B14) : const Color(0xFF1E8A4C);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ParcelDetailScreen(task: task),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha:0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${task.name} - ${task.location}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
                ),
                const SizedBox(height: 4),
                Text(
                  task.parcels,
                  style: const TextStyle(color: Colors.grey, fontSize: 12.5),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _statusColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                task.status,
                style: TextStyle(
                  color: _statusTextColor,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}