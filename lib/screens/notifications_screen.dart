import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/supabase_service.dart';

/// ==================================================================
/// THEME COLORS & TOKENS
/// ==================================================================
class InsightTheme {
  static const Color bg = Color(0xFFF2F4FB);
  static const Color surface = Colors.white;

  static const Color ink = Color(0xFF12141F);
  static const Color ink2 = Color(0xFF666C82);
  static const Color ink3 = Color(0xFFA2A7BC);

  static const Color blue1 = Color(0xFF3D6BFF);
  static const Color blue2 = Color(0xFF0B2FBF);
  static const Color blueTint = Color(0xFFE7EDFF);
  static const Color blueInk = Color(0xFF1A3FC4);

  static const Color redTint = Color(0xFFFDECEE);
  static const Color redInk = Color(0xFFB72A3B);

  static const Color greenTint = Color(0xFFE3F8EC);
  static const Color greenInk = Color(0xFF0D7A3C);

  static const Color amberTint = Color(0xFFFEF3DE);
  static const Color amberInk = Color(0xFFA66C00);

  static const Color line = Color(0x12141628);

  static TextStyle poppins(double size, {FontWeight w = FontWeight.w600, Color? c, double? h, double? ls}) =>
      GoogleFonts.poppins(fontSize: size, fontWeight: w, color: c ?? ink, height: h ?? 1.2, letterSpacing: ls);

  static TextStyle inter(double size, {FontWeight w = FontWeight.w400, Color? c, double? h}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: c ?? ink2, height: h ?? 1.5);
}

/// ==================================================================
/// SCREEN 4 — NOTIFICATIONS
/// Real data from activity_log (via fetchRecentActivity), with real
/// unread tracking (activity_log.is_read) instead of hardcoded rows.
/// ==================================================================
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  int _currentTabIndex = 0; // 0 = All, 1 = Unread
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _activity = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      // Pull more than the dashboard's preview needs — this is the full feed.
      final activity = await SupabaseService.fetchRecentActivity(limit: 50);
      if (!mounted) return;
      setState(() { _activity = activity; _isLoading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = 'Could not load notifications.'; _isLoading = false; });
    }
  }

  int get _unreadCount => _activity.where((a) => a['is_read'] != true).length;

  List<Map<String, dynamic>> get _visibleActivity =>
      _currentTabIndex == 1 ? _activity.where((a) => a['is_read'] != true).toList() : _activity;

  Future<void> _markAllRead() async {
    if (_unreadCount == 0) return;
    HapticFeedback.lightImpact();
    // Update UI immediately, then sync — a failed sync isn't worth
    // blocking on since this is a best-effort read receipt, not data loss.
    setState(() {
      _activity = _activity.map((a) => {...a, 'is_read': true}).toList();
    });
    await SupabaseService.markAllActivityRead();
  }

  Future<void> _markOneRead(Map<String, dynamic> item) async {
    if (item['is_read'] == true) return;
    final id = item['id']?.toString();
    if (id == null) return;
    setState(() {
      _activity = _activity.map((a) => a['id'] == item['id'] ? {...a, 'is_read': true} : a).toList();
    });
    await SupabaseService.markActivityRead(id);
  }

  Map<String, dynamic> _eventTheme(String eventType) {
    switch (eventType) {
      case 'inspection_completed':
        return {'icon': Icons.check_rounded, 'bg': InsightTheme.greenTint, 'fg': InsightTheme.greenInk};
      case 'rework_started':
        return {'icon': Icons.refresh_rounded, 'bg': InsightTheme.amberTint, 'fg': InsightTheme.amberInk};
      case 'gps_confirmed':
        return {'icon': Icons.gps_fixed_rounded, 'bg': InsightTheme.blueTint, 'fg': InsightTheme.blueInk};
      case 'push_received':
        return {'icon': Icons.campaign_rounded, 'bg': InsightTheme.redTint, 'fg': InsightTheme.redInk};
      default:
        return {'icon': Icons.notifications_rounded, 'bg': InsightTheme.blueTint, 'fg': InsightTheme.blueInk};
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
      return '${then.year}-${then.month.toString().padLeft(2, '0')}-${then.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    final visible = _visibleActivity;

    return Scaffold(
      backgroundColor: InsightTheme.bg,
      body: Stack(
        children: [
          Positioned(
            top: -60, right: -60,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                width: 260, height: 260,
                decoration: BoxDecoration(shape: BoxShape.circle, color: InsightTheme.blue1.withOpacity(0.20)),
              ),
            ),
          ),
          Positioned(
            bottom: -80, left: -80,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                width: 220, height: 220,
                decoration: BoxDecoration(shape: BoxShape.circle, color: InsightTheme.blue1.withOpacity(0.10)),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      _GlassBackButton(onTap: () => Navigator.pop(context)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('Notifications', style: InsightTheme.poppins(17, w: FontWeight.w700)),
                      ),
                      GestureDetector(
                        onTap: _markAllRead,
                        child: Text(
                          'Mark all read',
                          style: InsightTheme.inter(
                            13.5, w: FontWeight.w600,
                            c: _unreadCount == 0 ? InsightTheme.ink3 : InsightTheme.blueInk,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      _TabPill(text: "All", isActive: _currentTabIndex == 0, onTap: () => setState(() => _currentTabIndex = 0)),
                      const SizedBox(width: 8),
                      _TabPill(text: "Unread · $_unreadCount", isActive: _currentTabIndex == 1, onTap: () => setState(() => _currentTabIndex = 1)),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(color: InsightTheme.blue1))
                      : _error != null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 32),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(_error!, textAlign: TextAlign.center, style: InsightTheme.inter(13, c: InsightTheme.ink2)),
                                    const SizedBox(height: 12),
                                    OutlinedButton(onPressed: _load, child: const Text('Try again')),
                                  ],
                                ),
                              ),
                            )
                          : visible.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.notifications_none_rounded, size: 40, color: InsightTheme.ink3),
                                      const SizedBox(height: 12),
                                      Text(
                                        _currentTabIndex == 1 ? 'No unread notifications.' : 'No notifications yet.',
                                        style: InsightTheme.inter(13, c: InsightTheme.ink2),
                                      ),
                                    ],
                                  ),
                                )
                              : RefreshIndicator(
                                  onRefresh: _load,
                                  child: ListView.builder(
                                    padding: const EdgeInsets.symmetric(horizontal: 20),
                                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                                    itemCount: visible.length,
                                    itemBuilder: (context, i) {
                                      final item = visible[i];
                                      final theme = _eventTheme(item['event_type'] as String? ?? '');
                                      return _NotificationRow(
                                        icon: theme['icon'] as IconData,
                                        iconBgColor: theme['bg'] as Color,
                                        iconColor: theme['fg'] as Color,
                                        title: item['title'] as String? ?? 'Update',
                                        subtitle: item['subtitle'] as String? ?? '',
                                        time: _timeAgo(item['occurred_at'] as String?),
                                        isUnread: item['is_read'] != true,
                                        isLast: i == visible.length - 1,
                                        onTap: () => _markOneRead(item),
                                      );
                                    },
                                  ),
                                ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ==================================================================
/// COMPONENT WIDGETS
/// ==================================================================

class _NotificationRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String time;
  final Color iconBgColor;
  final Color iconColor;
  final bool isUnread;
  final bool isLast;
  final VoidCallback onTap;

  const _NotificationRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.time,
    required this.iconBgColor,
    required this.iconColor,
    required this.onTap,
    this.isUnread = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: isLast ? null : const Border(bottom: BorderSide(color: InsightTheme.line)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: iconBgColor, borderRadius: BorderRadius.circular(13)),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: InsightTheme.inter(13.5, w: FontWeight.w600, c: InsightTheme.ink)),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: InsightTheme.inter(11.5, c: InsightTheme.ink2)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(time, style: InsightTheme.inter(11.5, c: InsightTheme.ink2)),
                if (isUnread) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(color: InsightTheme.blue1, shape: BoxShape.circle),
                  ),
                ]
              ],
            ),
          ],
        ),
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
          style: InsightTheme.inter(12, w: FontWeight.w600, c: isActive ? Colors.white : InsightTheme.ink2),
        ),
      ),
    );
  }
}

class _GlassBackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _GlassBackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.5),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Colors.white.withOpacity(0.65)),
          boxShadow: const [BoxShadow(color: Color(0x0F141628), blurRadius: 14, offset: Offset(0, 4))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: const Center(
              child: Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: InsightTheme.ink),
            ),
          ),
        ),
      ),
    );
  }
}