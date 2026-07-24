import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/supabase_service.dart';
import '../services/db_helper.dart';
import '../widgets/motion/spring_entrance.dart';
import '../widgets/imaps_loading_indicator.dart';
import '../widgets/sensitive_screen.dart';

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
/// SCREEN 4 — NOTIFICATIONS / ACTIVITY
/// Real data from activity_log (via fetchRecentActivity), with real
/// unread tracking (activity_log.is_read) instead of hardcoded rows.
/// Now with spring entrance animations, Clear All button, and
/// swipe-to-dismiss.
///
/// Phase 6 (Detailed Sync Logs): this screen is also the reused
/// architecture home for synchronization history — a top-level
/// "Activity | Sync" mode switch was added instead of building a
/// separate standalone Sync Logs page. "Activity" is the pre-existing
/// user-activity feed (unchanged). "Sync" is new: a paginated,
/// local-first (SQLite `sync_log_entries`) timeline of synchronization
/// engine events, with user-friendly messages by default and technical
/// details available behind an expandable section per entry.
/// ==================================================================
class NotificationsScreen extends StatefulWidget {
  /// 0 = Activity (default), 1 = Sync. Lets the Sync Center's
  /// "Synchronization History >" entry deep-link straight into the Sync
  /// tab instead of landing on Activity and requiring an extra tap.
  final int initialMode;

  const NotificationsScreen({super.key, this.initialMode = 0});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with TickerProviderStateMixin, SpringEntrance {
  late int _mode; // 0 = Activity, 1 = Sync — top-level switch (Phase 6)
  int _currentTabIndex = 0; // 0 = All, 1 = Unread — only used within Activity mode
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _activity = [];

  // --- Phase 6: Sync log state (separate from _activity by design —
  // different table, different meaning, never merged into one list) ---
  List<Map<String, dynamic>> _syncLogs = [];
  bool _isLoadingSyncLogs = true;
  bool _syncLogHasMore = true;
  static const int _syncLogPageSize = 20;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _load();
    _loadSyncLogs(reset: true);
  }

  @override
  void dispose() {
    disposeSpringEntrance();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final activity = await SupabaseService.fetchRecentActivity(limit: 50);
      if (!mounted) return;
      setState(() { _activity = activity; _isLoading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = 'Could not load notifications.'; _isLoading = false; });
    }
  }

  /// Phase 6 — loads sync log entries a page at a time (default 20).
  /// [reset] starts over from the newest entry (pull-to-refresh, initial
  /// load); otherwise appends the next page ("Load more" tap) so opening
  /// a long-lived install's history never pulls the whole table at once.
  Future<void> _loadSyncLogs({bool reset = false}) async {
    if (reset) {
      setState(() { _isLoadingSyncLogs = true; _syncLogs = []; _syncLogHasMore = true; });
    }
    try {
      final page = await DBHelper.getSyncLogEntries(
        limit: _syncLogPageSize,
        offset: reset ? 0 : _syncLogs.length,
      );
      if (!mounted) return;
      setState(() {
        _syncLogs = reset ? page : [..._syncLogs, ...page];
        _syncLogHasMore = page.length == _syncLogPageSize;
        _isLoadingSyncLogs = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _isLoadingSyncLogs = false; });
    }
  }

  /// Icon + color per sync log `result` — kept visually distinct from
  /// the Activity feed's per-event-type theme, since this answers "did
  /// this sync step succeed?" rather than "what kind of action was it?".
  Map<String, dynamic> _syncResultTheme(String result) {
    switch (result) {
      case 'success':
        return {'icon': Icons.check_circle_rounded, 'bg': InsightTheme.greenTint, 'fg': InsightTheme.greenInk};
      case 'error':
        return {'icon': Icons.error_rounded, 'bg': InsightTheme.redTint, 'fg': InsightTheme.redInk};
      case 'warning':
        return {'icon': Icons.warning_rounded, 'bg': InsightTheme.amberTint, 'fg': InsightTheme.amberInk};
      default:
        return {'icon': Icons.sync_rounded, 'bg': InsightTheme.blueTint, 'fg': InsightTheme.blueInk};
    }
  }

  /// Pretty-prints the technical_details JSON for the expandable section.
  /// Deliberately simple key: value lines — this is a debugging aid, not
  /// user-facing copy, so raw field names are fine here.
  String _formatTechnicalDetails(String? raw) {
    if (raw == null || raw.isEmpty) return 'No additional details.';
    try {
      final map = jsonDecode(raw) as Map;
      return map.entries.map((e) => '${e.key}: ${e.value}').join('\n');
    } catch (_) {
      return raw;
    }
  }

  int get _unreadCount => _activity.where((a) => a['is_read'] != true).length;

  List<Map<String, dynamic>> get _visibleActivity =>
      _currentTabIndex == 1 ? _activity.where((a) => a['is_read'] != true).toList() : _activity;

  Future<void> _markAllRead() async {
    if (_unreadCount == 0) return;
    HapticFeedback.lightImpact();
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

  Future<void> _deleteOne(Map<String, dynamic> item) async {
    final id = item['id']?.toString();
    if (id == null) return;

    // Optimistically remove from UI first
    setState(() {
      _activity.removeWhere((a) => a['id'] == item['id']);
    });
    HapticFeedback.mediumImpact();

    try {
      await SupabaseService.deleteActivity(id);
    } catch (e) {
      // Revert on failure and show error
      if (mounted) {
        setState(() {
          _activity.insert(0, item);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete notification: $e'),
            backgroundColor: InsightTheme.redInk,
          ),
        );
      }
    }
  }

  Future<void> _clearAll() async {
    if (_activity.isEmpty) return;
    HapticFeedback.mediumImpact();
    final count = _activity.length;
    if (!mounted) return;
    
    // Show confirmation
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: InsightTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Clear all notifications?', style: InsightTheme.poppins(16, w: FontWeight.w700)),
        content: Text(
          'This will permanently remove all $count notification(s).',
          style: InsightTheme.inter(13, c: InsightTheme.ink2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: InsightTheme.inter(13, w: FontWeight.w600, c: InsightTheme.ink3)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Clear All', style: InsightTheme.inter(13, w: FontWeight.w600, c: InsightTheme.redInk)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _activity.clear();
    });
    try {
      await SupabaseService.clearAllActivity();
    } catch (e) {
      if (mounted) {
        // Reload from server to undo optimistic clear
        _load();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to clear all: $e'),
            backgroundColor: InsightTheme.redInk,
          ),
        );
      }
    }
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

    return SensitiveScreen(child: Scaffold(
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
                // ── Header ──
                SpringSlide(
                  animation: springFor(0),
                  beginOffset: const Offset(0, -30),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      children: [
                        _GlassBackButton(onTap: () => Navigator.pop(context)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _mode == 0 ? 'Notifications' : 'Synchronization History',
                            style: InsightTheme.poppins(17, w: FontWeight.w700),
                          ),
                        ),
                        if (_mode == 0 && _activity.isNotEmpty)
                          GestureDetector(
                            onTap: _clearAll,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: InsightTheme.redTint,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.delete_outline_rounded, size: 16, color: InsightTheme.redInk),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Clear All',
                                    style: InsightTheme.inter(
                                      12, w: FontWeight.w600,
                                      c: InsightTheme.redInk,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                // ── Phase 6: Activity / Sync mode switch ──
                // Kept logically separate from the All/Unread pills below
                // — this is a different axis (WHICH log you're viewing),
                // not a filter within one log.
                SpringSlide(
                  animation: springFor(1),
                  beginOffset: const Offset(0, 16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        _TabPill(text: "Activity", isActive: _mode == 0, onTap: () => setState(() => _mode = 0)),
                        const SizedBox(width: 8),
                        _TabPill(text: "Sync", isActive: _mode == 1, onTap: () => setState(() => _mode = 1)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // ── All/Unread pills — only meaningful within Activity ──
                if (_mode == 0)
                SpringSlide(
                  animation: springFor(2),
                  beginOffset: const Offset(0, 20),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        _TabPill(text: "All · ${_activity.length}", isActive: _currentTabIndex == 0, onTap: () => setState(() => _currentTabIndex = 0)),
                        const SizedBox(width: 8),
                        _TabPill(text: "Unread · $_unreadCount", isActive: _currentTabIndex == 1, onTap: () => setState(() => _currentTabIndex = 1)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // ── List — Activity feed or Sync log, per _mode ──
                Expanded(
                  child: _mode == 1 ? _buildSyncLogList() : _buildActivityList(visible),
                ),
              ],
            ),
          ),
        ],
      ),
    ));
  }

  Widget _buildActivityList(List<Map<String, dynamic>> visible) {
    return _isLoading
                      ? const Center(child: ImapsLoadingIndicator(size: 60))
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
                                      return SpringSlide(
                                        animation: springForKey(
                                          item['id'] ?? i,
                                          2 + (i % 6),
                                        ),
                                        beginOffset: const Offset(40, 0),
                                        child: Dismissible(
                                          key: ValueKey(item['id'] ?? i),
                                          direction: DismissDirection.endToStart,
                                          background: Container(
                                            alignment: Alignment.centerRight,
                                            padding: const EdgeInsets.only(right: 24),
                                            margin: const EdgeInsets.only(bottom: 1),
                                            decoration: BoxDecoration(
                                              color: InsightTheme.redInk.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(16),
                                            ),
                                            child: const Icon(
                                              Icons.delete_outline_rounded,
                                              color: InsightTheme.redInk,
                                              size: 24,
                                            ),
                                          ),
                                          confirmDismiss: (direction) async {
                                            return true;
                                          },
                                          onDismissed: (_) => _deleteOne(item),
                                          child: _NotificationRow(
                                            icon: theme['icon'] as IconData,
                                            iconBgColor: theme['bg'] as Color,
                                            iconColor: theme['fg'] as Color,
                                            title: item['title'] as String? ?? 'Update',
                                            subtitle: item['subtitle'] as String? ?? '',
                                            time: _timeAgo(item['occurred_at'] as String?),
                                            isUnread: item['is_read'] != true,
                                            isLast: i == visible.length - 1,
                                            onTap: () => _markOneRead(item),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                );
  }

  /// Phase 6 — Sync log list. Same paginated data-integrity guarantees as
  /// the outbox itself: every entry shows a friendly message by default,
  /// with technical details behind a per-entry expandable section.
  Widget _buildSyncLogList() {
    if (_isLoadingSyncLogs) {
      return const Center(child: ImapsLoadingIndicator(size: 60));
    }
    if (_syncLogs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sync_rounded, size: 40, color: InsightTheme.ink3),
            const SizedBox(height: 12),
            Text('No synchronization activity yet.', style: InsightTheme.inter(13, c: InsightTheme.ink2)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _loadSyncLogs(reset: true),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        itemCount: _syncLogs.length + (_syncLogHasMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == _syncLogs.length) {
            // "Load more" footer — keeps this screen fast to open even
            // with thousands of historical entries (Performance
            // requirement from the Phase 6 spec).
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: OutlinedButton(
                  onPressed: () => _loadSyncLogs(),
                  child: const Text('Load more'),
                ),
              ),
            );
          }
          final entry = _syncLogs[i];
          final theme = _syncResultTheme(entry['result'] as String? ?? 'info');
          final hasDetails = (entry['technical_details'] as String?)?.isNotEmpty == true;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              decoration: BoxDecoration(
                color: InsightTheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: InsightTheme.line),
              ),
              child: Theme(
                // Removes the default ExpansionTile divider lines so it
                // matches the rest of this screen's card styling.
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  enabled: hasDetails,
                  tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  leading: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(color: theme['bg'] as Color, borderRadius: BorderRadius.circular(11)),
                    child: Icon(theme['icon'] as IconData, size: 16, color: theme['fg'] as Color),
                  ),
                  title: Text(
                    entry['message'] as String? ?? '',
                    style: InsightTheme.inter(13, w: FontWeight.w600, c: InsightTheme.ink),
                  ),
                  subtitle: Text(
                    _timeAgo(entry['created_at'] as String?),
                    style: InsightTheme.inter(11, c: InsightTheme.ink3),
                  ),
                  trailing: hasDetails
                      ? const Icon(Icons.expand_more_rounded, size: 18, color: InsightTheme.ink3)
                      : const SizedBox.shrink(),
                  children: hasDetails
                      ? [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _formatTechnicalDetails(entry['technical_details'] as String?),
                                style: InsightTheme.inter(11, c: InsightTheme.ink3, h: 1.5),
                              ),
                            ),
                          ),
                        ]
                      : const [],
                ),
              ),
            ),
          );
        },
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
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
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