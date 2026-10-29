import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/services/db_helper.dart';
import '../../../core/widgets/motion/spring_entrance.dart';
import '../../../core/widgets/imaps_loading_indicator.dart';
import '../../../core/widgets/sensitive_screen.dart';
import '../../../core/widgets/field_form_widgets.dart';

import '../../../core/theme/insight_theme.dart';

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
  bool _activityUnreadOnly = false; // Unread filter — Activity mode
  bool _syncUnreadOnly = false; // Unread filter — Sync mode
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
  int get _syncUnreadCount => _syncLogs.where((entry) => entry['is_read'] != true).length;

  List<Map<String, dynamic>> get _visibleActivity =>
      _activityUnreadOnly ? _activity.where((a) => a['is_read'] != true).toList() : _activity;

  List<Map<String, dynamic>> get _visibleSyncLogs =>
      _syncUnreadOnly ? _syncLogs.where((entry) => entry['is_read'] != true).toList() : _syncLogs;

  Future<void> _markOneRead(Map<String, dynamic> item) async {
    if (item['is_read'] == true) return;
    final id = item['id']?.toString();
    if (id == null) return;
    setState(() {
      _activity = _activity.map((a) => a['id'] == item['id'] ? {...a, 'is_read': true} : a).toList();
    });
    await SupabaseService.markActivityRead(id);
  }

  Future<void> _markSyncEntryRead(Map<String, dynamic> entry) async {
    if (entry['is_read'] == true) return;
    setState(() {
      _syncLogs = _syncLogs.map((item) => item['id'] == entry['id'] ? {...item, 'is_read': true} : item).toList();
    });
  }

  Future<void> _openNotificationDetail(Map<String, dynamic> item) async {
    await _markOneRead(item);
    if (!mounted) return;

    final title = item['title']?.toString() ?? 'Activity update';
    final subtitle = item['subtitle']?.toString() ?? 'No additional details available.';
    final occurredAt = item['occurred_at']?.toString();
    final eventType = (item['event_type']?.toString() ?? 'activity').replaceAll('_', ' ');

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          margin: const EdgeInsets.only(top: 40),
          decoration: const BoxDecoration(
            color: InsightTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              // `subtitle` comes from activity_log at runtime and is unbounded,
              // so this sheet scrolls: mainAxisSize.min alone let a long body
              // push the Close button past the bottom edge with no way to reach
              // it. min still hugs the content whenever the body is short.
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: InsightTheme.line,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    style: InsightTheme.poppins(18, w: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    eventType,
                    style: InsightTheme.inter(12, w: FontWeight.w600, c: InsightTheme.blueInk),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    subtitle,
                    style: InsightTheme.inter(14, c: InsightTheme.ink, h: 1.5),
                  ),
                  if (occurredAt != null && occurredAt.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(
                      'Received: ${_timeAgo(occurredAt)}',
                      style: InsightTheme.inter(12, c: InsightTheme.ink2),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: InsightTheme.blue1,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Close'),
                    ),
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
    final targetCount = _mode == 0 ? _activity.length : _syncLogs.length;
    if (targetCount == 0) return;
    HapticFeedback.mediumImpact();
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: InsightTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          _mode == 0 ? 'Clear all notifications?' : 'Clear all sync history?',
          style: InsightTheme.poppins(16, w: FontWeight.w700),
        ),
        content: Text(
          'This will permanently remove all $targetCount item(s).',
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

    if (_mode == 0) {
      setState(() {
        _activity.clear();
      });
      try {
        await SupabaseService.clearAllActivity();
      } catch (e) {
        if (mounted) {
          _load();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to clear all: $e'),
              backgroundColor: InsightTheme.redInk,
            ),
          );
        }
      }
    } else {
      setState(() {
        _syncLogs = [];
        _syncLogHasMore = false;
      });
      try {
        await DBHelper.clearSyncLogEntries();
      } catch (e) {
        if (mounted) {
          _loadSyncLogs(reset: true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to clear sync history: $e'),
              backgroundColor: InsightTheme.redInk,
            ),
          );
        }
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

  /// Time bucket for a notification: Today / Yesterday / This week (2–7
  /// days) / Earlier. Only these four labels exist; a bucket with no items
  /// never renders a header.
  String _sectionLabel(String? isoTimestamp) {
    final when = isoTimestamp == null ? null : DateTime.tryParse(isoTimestamp)?.toLocal();
    if (when == null) return 'Earlier';
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(when.year, when.month, when.day))
        .inDays;
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days <= 7) return 'This week';
    return 'Earlier';
  }

  /// Groups newest-first items into fixed-order time buckets. A bucket with
  /// no items never renders.
  Map<String, List<Map<String, dynamic>>> _bucketItems(
    List<Map<String, dynamic>> items,
    String timeKey,
  ) {
    final buckets = <String, List<Map<String, dynamic>>>{
      for (final label in const ['Today', 'Yesterday', 'This week', 'Earlier'])
        label: <Map<String, dynamic>>[],
    };
    for (final item in items) {
      buckets[_sectionLabel(item[timeKey] as String?)]!.add(item);
    }
    buckets.removeWhere((_, bucket) => bucket.isEmpty);
    return buckets;
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    final visible = _visibleActivity;

    return SensitiveScreen(child: Scaffold(
      backgroundColor: InsightTheme.bg,
      body: Stack(
        children: [
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
                        FieldBackButton(onPressed: () => Navigator.pop(context)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _mode == 0 ? 'Notifications' : 'Synchronization History',
                            style: InsightTheme.urbanist(20, w: FontWeight.w700),
                          ),
                        ),
                        if ((_mode == 0 && _activity.isNotEmpty) || (_mode == 1 && _syncLogs.isNotEmpty))
                          TextButton(
                            onPressed: _clearAll,
                            style: TextButton.styleFrom(
                              minimumSize: const Size(48, 48),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              foregroundColor: InsightTheme.redInk,
                              shape: RoundedRectangleBorder(borderRadius: InsightTheme.roundedSm),
                            ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.delete_outline_rounded, size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Clear All',
                                    style: InsightTheme.inter(
                                      12, w: FontWeight.w700,
                                      c: InsightTheme.redInk,
                                    ),
                                  ),
                                ],
                              ),
                          ),
                      ],
                    ),
                  ),
                ),

                // ── Controls: Notifications / Sync history switch, then the
                // single Unread filter. No "All" chip: rows are already the
                // full list when Unread is off.
                SpringSlide(
                  animation: springFor(1),
                  beginOffset: const Offset(0, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _ModeSegment(
                          mode: _mode,
                          onChanged: (mode) => setState(() => _mode = mode),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _UnreadFilterChip(
                          count: _mode == 0 ? _unreadCount : _syncUnreadCount,
                          isActive: _mode == 0 ? _activityUnreadOnly : _syncUnreadOnly,
                          onTap: () => setState(() {
                            if (_mode == 0) {
                              _activityUnreadOnly = !_activityUnreadOnly;
                            } else {
                              _syncUnreadOnly = !_syncUnreadOnly;
                            }
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),

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
    if (_isLoading) {
      return const Center(child: ImapsLoadingIndicator(size: 60));
    }
    if (_error != null) {
      return Center(
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
      );
    }
    if (visible.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.notifications_none_rounded, size: 40, color: InsightTheme.ink3),
            const SizedBox(height: 12),
            Text(
              _activityUnreadOnly ? 'No unread notifications.' : 'No notifications yet.',
              style: InsightTheme.inter(13, c: InsightTheme.ink2),
            ),
          ],
        ),
      );
    }

    final buckets = _bucketItems(visible, 'occurred_at');
    final children = <Widget>[];
    var bucketIndex = 0;
    for (final bucket in buckets.entries) {
      final rows = bucket.value;
      children.add(_SectionHeader(
        label: bucket.key,
        count: rows.length,
        isFirst: bucketIndex == 0,
      ));
      children.add(_ListCard(
        children: [
          for (var i = 0; i < rows.length; i++)
            Builder(builder: (context) {
              final item = rows[i];
              final theme = _eventTheme(item['event_type'] as String? ?? '');
              return SpringSlide(
                animation: springForKey(item['id'] ?? i, 2 + (i % 6)),
                beginOffset: const Offset(40, 0),
                child: Dismissible(
                  key: ValueKey(item['id'] ?? i),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    color: InsightTheme.redInk.withValues(alpha: 0.1),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: InsightTheme.redInk,
                      size: 24,
                    ),
                  ),
                  confirmDismiss: (direction) async => true,
                  onDismissed: (_) => _deleteOne(item),
                  child: _NotificationRow(
                    icon: theme['icon'] as IconData,
                    iconBgColor: theme['bg'] as Color,
                    iconColor: theme['fg'] as Color,
                    title: item['title'] as String? ?? 'Update',
                    subtitle: item['subtitle'] as String? ?? '',
                    time: _timeAgo(item['occurred_at'] as String?),
                    isUnread: item['is_read'] != true,
                    isLast: i == rows.length - 1,
                    onTap: () => _openNotificationDetail(item),
                  ),
                ),
              );
            }),
        ],
      ));
      bucketIndex++;
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        children: children,
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
    final visibleSyncLogs = _visibleSyncLogs;
    if (visibleSyncLogs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sync_rounded, size: 40, color: InsightTheme.ink3),
            const SizedBox(height: 12),
            Text(
              _syncUnreadOnly ? 'No unread sync activity.' : 'No synchronization activity yet.',
              style: InsightTheme.inter(13, c: InsightTheme.ink2),
            ),
          ],
        ),
      );
    }

    final buckets = _bucketItems(visibleSyncLogs, 'created_at');
    final children = <Widget>[];
    var bucketIndex = 0;
    for (final bucket in buckets.entries) {
      final rows = bucket.value;
      children.add(_SectionHeader(
        label: bucket.key,
        count: rows.length,
        isFirst: bucketIndex == 0,
      ));
      final rowWidgets = <Widget>[];
      for (var i = 0; i < rows.length; i++) {
        final entry = rows[i];
        final theme = _syncResultTheme(entry['result'] as String? ?? 'info');
        final hasDetails = (entry['technical_details'] as String?)?.isNotEmpty == true;
        final isEntryUnread = entry['is_read'] != true;
        rowWidgets.add(Theme(
          data: Theme.of(context).copyWith(
            dividerColor: Colors.transparent,
            listTileTheme: Theme.of(context).listTileTheme.copyWith(
              titleAlignment: ListTileTitleAlignment.top,
              horizontalTitleGap: 16,
              minLeadingWidth: 40,
            ),
          ),
          child: ExpansionTile(
            enabled: hasDetails,
            tilePadding: const EdgeInsets.all(16),
            childrenPadding: const EdgeInsets.fromLTRB(72, 0, 16, 16),
            shape: const Border(),
            collapsedShape: const Border(),
            onExpansionChanged: (expanded) {
              if (expanded && isEntryUnread) {
                _markSyncEntryRead(entry);
              }
            },
            leading: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: theme['bg'] as Color, borderRadius: BorderRadius.circular(12)),
              child: Icon(theme['icon'] as IconData, size: 18, color: theme['fg'] as Color),
            ),
            title: Text(
              entry['message'] as String? ?? '',
              style: InsightTheme.inter(13.5, w: FontWeight.w600, c: InsightTheme.ink),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _timeAgo(entry['created_at'] as String?),
                style: InsightTheme.inter(12, c: InsightTheme.ink3),
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isEntryUnread)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: InsightTheme.blue1, shape: BoxShape.circle),
                  ),
                if (hasDetails)
                  const SizedBox(width: 8),
                hasDetails
                    ? const Icon(Icons.expand_more_rounded, size: 18, color: InsightTheme.ink3)
                    : const SizedBox.shrink(),
              ],
            ),
            children: hasDetails
                ? [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _formatTechnicalDetails(entry['technical_details'] as String?),
                        style: InsightTheme.inter(11, c: InsightTheme.ink3, h: 1.5),
                      ),
                    ),
                  ]
                : const [],
          ),
        ));
        if (i != rows.length - 1) {
          rowWidgets.add(const Divider(
            height: 1,
            color: InsightTheme.line,
            indent: 72,
            endIndent: 16,
          ));
        }
      }
      children.add(_ListCard(children: rowWidgets));
      bucketIndex++;
    }

    if (_syncLogHasMore) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 14),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => _loadSyncLogs(),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 48),
              side: const BorderSide(color: InsightTheme.lineStrong),
              shape: RoundedRectangleBorder(borderRadius: InsightTheme.roundedSm),
            ),
            child: Text(
              'Load more',
              style: InsightTheme.inter(12.5, w: FontWeight.w700, c: InsightTheme.ink2),
            ),
          ),
        ),
      ));
    }

    return RefreshIndicator(
      onRefresh: () => _loadSyncLogs(reset: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        children: children,
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: iconBgColor, borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, size: 18, color: iconColor),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: InsightTheme.inter(
                          13.5,
                          w: isUnread ? FontWeight.w800 : FontWeight.w600,
                          c: InsightTheme.ink,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(subtitle, style: InsightTheme.inter(11.5, c: InsightTheme.ink2)),
                      ],
                      if (time.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(time, style: InsightTheme.inter(12, c: InsightTheme.ink3)),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 12, top: 8),
                  child: isUnread
                      ? Container(
                          width: 8, height: 8,
                          decoration: const BoxDecoration(color: InsightTheme.blue1, shape: BoxShape.circle),
                        )
                      : const SizedBox.square(dimension: 8),
                ),
              ],
            ),
          ),
          if (!isLast)
            const Divider(height: 1, thickness: 1, indent: 72, endIndent: 16, color: InsightTheme.line),
        ],
      ),
    );
  }
}

class _ModeSegment extends StatelessWidget {
  final int mode;
  final ValueChanged<int> onChanged;

  const _ModeSegment({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: InsightTheme.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeTab(
              label: 'Notifications',
              isActive: mode == 0,
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(0);
              },
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: _ModeTab(
              label: 'Sync history',
              isActive: mode == 1,
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(1);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ModeTab({required this.label, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isActive,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? InsightTheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: isActive
                ? const [BoxShadow(color: Color(0x0F0F172A), blurRadius: 3, offset: Offset(0, 1))]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: InsightTheme.inter(
              12,
              w: isActive ? FontWeight.w700 : FontWeight.w600,
              c: isActive ? InsightTheme.ink : InsightTheme.ink3,
            ),
          ),
        ),
      ),
    );
  }
}

class _UnreadFilterChip extends StatelessWidget {
  final int count;
  final bool isActive;
  final VoidCallback onTap;

  const _UnreadFilterChip({
    required this.count,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isActive,
      child: Material(
        key: const ValueKey('unread-filter'),
        color: isActive ? InsightTheme.blueTint : InsightTheme.surface,
        shape: StadiumBorder(
          side: BorderSide(
            color: isActive
                ? InsightTheme.blue1.withValues(alpha: 0.34)
                : InsightTheme.lineStrong,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Unread',
                    style: InsightTheme.inter(
                      11.5,
                      w: isActive ? FontWeight.w700 : FontWeight.w600,
                      c: isActive ? InsightTheme.blueInk : InsightTheme.ink2,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: isActive
                          ? InsightTheme.blue1.withValues(alpha: 0.12)
                          : InsightTheme.surface2,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$count',
                      key: const ValueKey('unread-count'),
                      style: InsightTheme.inter(
                        10,
                        w: FontWeight.w700,
                        c: isActive ? InsightTheme.blueInk : InsightTheme.ink2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ListCard extends StatelessWidget {
  final List<Widget> children;

  const _ListCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: InsightTheme.surface,
        borderRadius: InsightTheme.roundedMd,
        border: Border.all(color: InsightTheme.line),
        boxShadow: InsightTheme.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

/// Uppercase time-bucket label ("TODAY", "YESTERDAY", ...) that opens each
/// non-empty section in both the Activity and Sync lists.
class _SectionHeader extends StatelessWidget {
  final String label;
  final int count;
  final bool isFirst;

  const _SectionHeader({
    required this.label,
    required this.count,
    this.isFirst = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(4, isFirst ? 4 : 16, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: InsightTheme.inter(11, w: FontWeight.w700, c: InsightTheme.ink3, ls: 0.8),
            ),
          ),
          Text(
            '$count',
            style: InsightTheme.inter(11, w: FontWeight.w700, c: InsightTheme.ink3),
          ),
        ],
      ),
    );
  }
}
