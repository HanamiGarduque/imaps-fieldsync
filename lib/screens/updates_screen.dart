import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/user_profile.dart';
import '../services/db_helper.dart';
import '../services/supabase_service.dart';
import '../services/sync_outbox_service.dart';
import 'home_dashboard_screen.dart';
import 'tasks_screen.dart';
import 'profile_screen.dart';
import 'notifications_screen.dart';
import '../widgets/insight_bottom_nav.dart';
import '../widgets/insight_page_transition.dart';
import '../widgets/motion/spring_entrance.dart';
import '../widgets/motion/updating_tile.dart';
import '../widgets/motion/linked_list_motion.dart';
import '../widgets/imaps_loading_indicator.dart';

/// ==================================================================
/// THEME COLORS & TOKENS
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

  static const Color green = Color(0xFF10B981);
  static const Color greenTint = Color(0xFFE3F8EC);
  static const Color greenInk = Color(0xFF0D7A3C);

  static const Color amber = Color(0xFFFFB700);
  static const Color amberTint = Color(0xFFFEF3DE);
  static const Color amberInk = Color(0xFFA66C00);

  static const Color red = Color(0xFFE0473E);
  static const Color redTint = Color(0xFFFCE7E5);
  static const Color redInk = Color(0xFFB33128);

  static const Color line = Color(0x12141628);
  static const Color lineStrong = Color(0x21141628);

  static TextStyle poppins(
    double size, {
    FontWeight w = FontWeight.w600,
    Color? c,
    double? h,
    double? ls,
  }) => GoogleFonts.poppins(
    fontSize: size,
    fontWeight: w,
    color: c ?? ink,
    height: h ?? 1.2,
    letterSpacing: ls,
  );

  static TextStyle inter(
    double size, {
    FontWeight w = FontWeight.w400,
    Color? c,
    double? h,
  }) => GoogleFonts.inter(
    fontSize: size,
    fontWeight: w,
    color: c ?? ink2,
    height: h ?? 1.5,
  );

  static TextStyle jetBrains(
    double size, {
    FontWeight w = FontWeight.w500,
    Color? c,
    double? ls,
  }) => GoogleFonts.jetBrainsMono(
    fontSize: size,
    fontWeight: w,
    color: c ?? ink3,
    letterSpacing: ls,
  );
}

/// ==================================================================
/// SCREEN — SYNC CENTER (FieldSync)
/// ==================================================================
/// Rebuilt to read real data from the `pending_actions` outbox
/// (DBHelper / SyncOutboxService) instead of simulating a fake pipeline.
/// Every number here is either a live query result or a stat()'d file
/// size — nothing is fabricated.
class UpdatesScreen extends StatefulWidget {
  final UserProfile profile;
  final bool showBottomNav;
  const UpdatesScreen({
    super.key,
    required this.profile,
    this.showBottomNav = true,
  });

  @override
  State<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends State<UpdatesScreen>
    with TickerProviderStateMixin, SpringEntrance {
  final int _currentNavIndex = 2;

  bool _loading = true;
  bool _isOnline = true;
  bool _syncingNow = false;
  // Phase 8 (Selective Sync) — which job's "Sync This Inspection" button is
  // mid-flight, if any. Separate from `_syncingNow` (which tracks the
  // full-queue "Sync Now" button) so tapping one doesn't visually disable
  // the other's card, and so only the tapped card shows its own spinner.
  String? _syncingJobId;

  List<Map<String, dynamic>> _pendingRows = [];
  List<Map<String, dynamic>> _syncedRows = [];
  Map<String, Map<String, dynamic>> _jobLookup = {};

  int _gpsWaiting = 0;
  int _checklistWaiting = 0;
  int _photosWaiting = 0;
  double _pendingBytes = 0;
  DateTime? _lastSync;

  // --- Phase 7: Storage Management state ---
  int _cachedJobsCount = 0;
  int _syncedPhotoFileCount = 0;
  int _unsyncedPhotoFileCount = 0;
  int _clearableBytes = 0;
  int _syncLogCount = 0;
  bool _clearingCache = false;

  Timer? _pollTimer;
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  @override
  void initState() {
    super.initState();
    _refresh(replay: true);
    _loadCacheStats();
    // Light polling while this screen is open — catches progress from a
    // drain that SyncOutboxService kicked off elsewhere (e.g. connectivity
    // just came back while the inspector was on a different screen).
    // NOTE: intentionally does NOT replay entrance animations (replay:
    // false, the default) — this used to call the bare _refresh(), which
    // called resetSprings() unconditionally on every tick, so the whole
    // screen's entrance (header, status card, every completed-log row)
    // replayed from scratch every 4 seconds the screen was open. This is
    // a re-fix of the Phase 1 UI regression audit finding — a prior merge
    // reintroduced the unconditional resetSprings() call.
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) SyncOutboxService.drain();
      _refresh();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _connSub?.cancel();
    disposeSpringEntrance();
    super.dispose();
  }

  Future<void> _refresh({bool replay = false}) async {
    final connectivity = await Connectivity().checkConnectivity();
    final online = connectivity.any((r) => r != ConnectivityResult.none);
    final pending = await DBHelper.getSyncCenterQueueActions();
    final synced = await DBHelper.getRecentSyncedActions(limit: 20);
    final cachedJobs = await DBHelper.getCachedJobs();
    final lastSync = await SyncOutboxService.getLastSuccessfulSync();

    int gps = 0, checklist = 0, photos = 0;
    double bytes = 0;
    for (final row in pending) {
      final type = row['type'] as String;
      Map payload;
      try {
        payload = jsonDecode(row['payload'] as String) as Map;
      } catch (_) {
        payload = const {};
      }
      if (type == 'gps_confirm') gps++;
      if (type == 'checklist_update') checklist++;
      if (type == 'submit_inspection') {
        final photosData =
            (payload['photosData'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            const <Map<String, dynamic>>[];
        final paths = photosData
            .map((e) => e['photoPath']?.toString())
            .whereType<String>()
            .toList();
        photos += paths.length;
        for (final p in paths) {
          try {
            final f = File(p);
            if (await f.exists()) bytes += await f.length();
          } catch (_) {
            // File gone / inaccessible — just doesn't count toward size.
          }
        }
      }
    }

    if (!mounted) return;
    if (replay) resetSprings();
    setState(() {
      _isOnline = online;
      _pendingRows = pending;

      _syncedRows = synced;
      _jobLookup = {for (final j in cachedJobs) (j['id'] as String): j};
      _gpsWaiting = gps;
      _checklistWaiting = checklist;
      _photosWaiting = photos;
      _pendingBytes = bytes;
      _lastSync = lastSync;
      _loading = false;
      _syncingNow = SyncOutboxService.isDraining;
    });
  }

  /// Phase 7 — separate from the main `_refresh()` poll loop on purpose:
  /// this touches the filesystem (checking each synced photo's size),
  /// which is unnecessary work to repeat every 4 seconds. Loaded once at
  /// open and again right after a manual clear.
  Future<void> _loadCacheStats() async {
    final stats = await DBHelper.getCacheStats();
    if (!mounted) return;
    setState(() {
      _cachedJobsCount = stats['cachedJobsCount'] as int;
      _syncedPhotoFileCount = stats['syncedPhotoFileCount'] as int;
      _unsyncedPhotoFileCount = stats['unsyncedPhotoFileCount'] as int;
      _clearableBytes = stats['clearableBytes'] as int;
      _syncLogCount = stats['syncLogCount'] as int;
    });
  }

  Future<void> _handleClearCache() async {
    if (_clearingCache) return;
    if (_clearableBytes == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to clear right now.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: InsightTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Clear synced photo cache?', style: InsightTheme.poppins(16, w: FontWeight.w700)),
        content: Text(
          'This removes $_syncedPhotoFileCount photo file(s) already backed up to the server '
          '(${_formatBytes(_clearableBytes.toDouble())}) from this device. Photos still waiting '
          'to sync are never affected.',
          style: InsightTheme.inter(13, c: InsightTheme.ink2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: InsightTheme.inter(13, w: FontWeight.w600, c: InsightTheme.ink3)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Clear', style: InsightTheme.inter(13, w: FontWeight.w600, c: InsightTheme.redInk)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _clearingCache = true);
    final cleared = await DBHelper.clearSyncedPhotoCache();
    await _loadCacheStats();
    if (!mounted) return;
    setState(() => _clearingCache = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Freed $cleared photo file(s).'),
        backgroundColor: InsightTheme.greenInk,
      ),
    );
  }

  Future<void> _handleSyncNow() async {
    if (_syncingNow) return;
    HapticFeedback.lightImpact();
    setState(() => _syncingNow = true);
    await SyncOutboxService.drain(trigger: 'manual');
    await _refresh();
    unawaited(_loadCacheStats());
    if (!mounted) return;
    final stillPending = _pendingRows.length;
    final conflictCount = _pendingRows
        .where((r) => r['status'] == 'conflict')
        .length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          stillPending == 0
              ? 'All caught up — nothing left to sync.'
              : conflictCount > 0
              ? '$conflictCount item(s) need conflict review.'
              : '$stillPending item(s) still waiting (check connection).',
          style: InsightTheme.inter(13, c: Colors.white),
        ),
        backgroundColor: stillPending == 0
            ? InsightTheme.greenInk
            : InsightTheme.amberInk,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// Phase 8 (Selective Sync). Syncs only the pending actions belonging to
  /// one inspection, via `drain(onlyJobId: ...)` — the full-queue "Sync Now"
  /// path above is completely untouched. Guarded against double-taps the
  /// same way `_handleSyncNow` is, plus it also backs off while a full sync
  /// is already running (both ultimately go through the same `_draining`
  /// flag in SyncOutboxService, so a second concurrent call would just be
  /// silently ignored there — checking here too keeps the button itself
  /// visibly disabled instead of tapping into a no-op).
  Future<void> _handleSyncThisInspection(String jobId) async {
    if (_syncingNow || _syncingJobId != null) return;
    if (!_isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No internet connection. This will sync automatically once you\'re back online.',
            style: InsightTheme.inter(13, c: Colors.white),
          ),
          backgroundColor: InsightTheme.amberInk,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _syncingJobId = jobId);
    await SyncOutboxService.drain(trigger: 'manual', onlyJobId: jobId);
    await _refresh();
    if (!mounted) return;
    setState(() => _syncingJobId = null);

    final stillPendingForJob = _pendingRows
        .where((r) => r['job_id'] == jobId)
        .toList();
    final hasConflict = stillPendingForJob.any((r) => r['status'] == 'conflict');
    final hasFailed = stillPendingForJob.any((r) => r['status'] == 'failed');
    final label = _jobLabel(jobId);

    String message;
    Color color;
    if (stillPendingForJob.isEmpty) {
      message = '$label synced successfully.';
      color = InsightTheme.greenInk;
    } else if (hasConflict) {
      message = '$label needs conflict review before it can sync.';
      color = InsightTheme.amberInk;
    } else if (hasFailed) {
      message = '$label couldn\'t sync. It will retry automatically.';
      color = InsightTheme.redInk;
    } else {
      message = '$label is still syncing.';
      color = InsightTheme.amberInk;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: InsightTheme.inter(13, c: Colors.white)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// Phase 8 (Selective Sync) + visual grouping fix (2026-07-23).
  ///
  /// A job can have several independent pending action rows (GPS confirm,
  /// checklist update, current_step update, submit_inspection) — each is
  /// its own row in `pending_actions` by design (see roadmap Phase 0), but
  /// previously they rendered as N separate, unrelated-looking cards with
  /// the "Sync This Inspection" button floating as a plain text link above
  /// the first one — nothing visually tied the button, or the rows
  /// themselves, together as belonging to one inspection. Inspectors
  /// reasonably read this as 4 unrelated things instead of 1 inspection
  /// with 4 pending pieces.
  ///
  /// This groups all of a job's rows inside one shared, clearly-bordered
  /// container, with a small group header naming the inspection once, and
  /// the "Sync This Inspection" (or conflict) action(s) anchored inside
  /// that same container — so it's unambiguous which rows an action
  /// applies to.
  List<Widget> _buildPendingCards() {
    // Group rows by job_id, preserving the order each job first appears in.
    final order = <String>[];
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in _pendingRows) {
      final jobId = row['job_id'] as String;
      if (!grouped.containsKey(jobId)) order.add(jobId);
      grouped.putIfAbsent(jobId, () => []).add(row);
    }
  
    var flatIndex = 0;
    return order.map((jobId) {
      final rows = grouped[jobId]!;
      final groupIndex = flatIndex;
      flatIndex++;
      final hasConflict = rows.any((r) => r['status'] == 'conflict');
      final isSyncingThisJob = _syncingJobId == jobId;

      return LinkedListSlide(
        key: ValueKey('linked_group_$jobId'),
        index: groupIndex,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: InsightTheme.surface2,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: InsightTheme.line, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
                  child: Row(
                    children: [
                      Icon(Icons.folder_copy_outlined, size: 15, color: InsightTheme.ink2),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _jobLabel(jobId),
                          style: InsightTheme.inter(12, w: FontWeight.w700, c: InsightTheme.ink2),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        rows.length == 1 ? '1 item' : '${rows.length} items',
                        style: InsightTheme.jetBrains(10, c: InsightTheme.ink3),
                      ),
                    ],
                  ),
                ),
                for (final row in rows) ...[
                  UpdatingTile(
                    itemKey: row['id'] ?? row.hashCode,
                    signature: Object.hash(row['status'], row['type']),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _LogDataRow(
                        icon: _iconFor(row['type'] as String),
                        title: _typeLabel(row),
                        dataType: _shortTypeTag(row),
                        dataSize: _dataSizeFor(row),
                        statusText: (isSyncingThisJob && row['status'] != 'conflict')
                            ? 'Syncing…'
                            : _statusTextFor(row),
                        isPending: true,
                        isFailed: row['status'] == 'failed',
                        isConflict: row['status'] == 'conflict',
                      ),
                    ),
                  ),
                ],
                if (hasConflict) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => _handleReviewConflict(
                          rows.firstWhere((r) => r['status'] == 'conflict'),
                        ),
                        child: const Text('Review changes'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => _handleForceSync(
                          rows.firstWhere((r) => r['status'] == 'conflict'),
                        ),
                        child: const Text('Force sync anyway'),
                      ),
                    ],
                  ),
                ] else ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: (_syncingNow || _syncingJobId != null)
                            ? null
                            : () => _handleSyncThisInspection(jobId),
                        icon: isSyncingThisJob
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.sync_rounded, size: 16),
                        label: Text(
                          isSyncingThisJob ? 'Syncing…' : 'Sync This Inspection',
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }).toList();
  }
  }

  String _jobLabel(String jobId) {
    final job = _jobLookup[jobId];
    if (job == null) {
      return 'Job ${jobId.length > 8 ? jobId.substring(0, 8) : jobId}';
    }
    final applicant = (job['applicant_name'] as String?) ?? '';
    final barangay = (job['barangay'] as String?) ?? '';
    if (applicant.isNotEmpty && barangay.isNotEmpty) {
      return '$applicant — $barangay';
    }
    if (applicant.isNotEmpty) return applicant;
    if (barangay.isNotEmpty) return barangay;
    return 'Job ${jobId.length > 8 ? jobId.substring(0, 8) : jobId}';
  }

  Map _payloadOf(Map<String, dynamic> row) {
    try {
      return jsonDecode(row['payload'] as String) as Map;
    } catch (_) {
      return const {};
    }
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'gps_confirm':
        return Icons.map_rounded;
      case 'checklist_update':
        return Icons.text_snippet_rounded;
      case 'current_step_update':
        return Icons.timeline_rounded;
      case 'submit_inspection':
        return Icons.image_rounded;
      default:
        return Icons.sync_rounded;
    }
  }

  String _typeLabel(Map<String, dynamic> row) {
    final type = row['type'] as String;
    final payload = _payloadOf(row);
    switch (type) {
      case 'gps_confirm':
        return 'GPS Verification Coordinates';
      case 'checklist_update':
        return 'Checklist Data (${payload['checklistCompletedCount'] ?? 0}/${payload['checklistTotalCount'] ?? 0} items)';
      case 'current_step_update':
        return 'Progress Update (Step ${payload['currentStep'] ?? '—'})';
      case 'submit_inspection':
        final n = (payload['photosData'] as List?)?.length ?? 0;
        return 'Full Submission — $n photo(s) + Findings';
      default:
        return type;
    }
  }

  String _shortTypeTag(Map<String, dynamic> row) {
    switch (row['type'] as String) {
      case 'gps_confirm':
        return 'GPS check-in';
      case 'checklist_update':
        return 'Checklist';
      case 'current_step_update':
        return 'Step progress';
      case 'submit_inspection':
        return 'Final submission';
      default:
        return 'Update';
    }
  }

  String _dataSizeFor(Map<String, dynamic> row) {
    final type = row['type'] as String;
    if (type != 'submit_inspection') return '—';
    final payload = _payloadOf(row);
    final n = (payload['photosData'] as List?)?.length ?? 0;
    return n > 0 ? '$n file(s)' : '0 B';
  }

  String _statusTextFor(Map<String, dynamic> row) {
    final status = row['status'] as String;
    final retries = row['retry_count'] as int? ?? 0;
    switch (status) {
      case 'syncing':
        return 'Uploading...';
      case 'failed':
        return retries > 0 ? 'Failed — retry #$retries' : 'Failed — will retry';
      case 'conflict':
        return 'Conflict detected — review required';
      default:
        return 'Waiting for signal';
    }
  }

  Future<void> _handleReviewConflict(Map<String, dynamic> row) async {
    final payload = _payloadOf(row);
    final cachedUpdatedAt = payload['cachedUpdatedAtSnapshot'] as String?;
    String serverUpdatedAt = 'Unavailable';
    try {
      final fetched = await SupabaseService.fetchJobUpdatedAt(
        row['job_id'] as String,
      );
      if (fetched != null && fetched.isNotEmpty) {
        serverUpdatedAt = fetched;
      }
    } catch (e) {
      serverUpdatedAt = 'Unavailable ($e)';
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sync conflict detected'),
        content: Text(
          'This job changed on server after the offline action was queued.\n\n'
          'Cached snapshot: ${cachedUpdatedAt ?? 'Unknown'}\n'
          'Server now: $serverUpdatedAt',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleForceSync(Map<String, dynamic> row) async {
    final id = row['id'] as String?;
    if (id == null || id.isEmpty) return;
    await DBHelper.markActionForceSync(id);
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Conflict marked for force sync on next drain.',
          style: InsightTheme.inter(13, c: Colors.white),
        ),
        backgroundColor: InsightTheme.amberInk,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  String _relativeTime(DateTime? dt) {
    if (dt == null) return 'Never';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _formatBytes(double bytes) {
    if (bytes <= 0) return '0.00 B';
    if (bytes < 1024) return '${bytes.toStringAsFixed(0)} B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    final hasPending = _pendingRows.isNotEmpty;

    return Scaffold(
      backgroundColor: InsightTheme.bg,
      extendBody: true,
      body: Stack(
        children: [
          Positioned(
            top: -120,
            right: -60,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: InsightTheme.blue1.withValues(alpha: 0.1),
                ),
              ),
            ),
          ),

          SafeArea(
            bottom: false,
            child: _loading
                ? const Center(
                    child: ImapsLoadingIndicator(
                      size: 60,
                      label: "Syncing data...",
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () => _refresh(replay: true),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1. TOP UTILITY HEADER
                        SpringSlide(
                          animation: springFor(0),
                          beginOffset: const Offset(0, -28),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Sync Center',
                                      style: InsightTheme.poppins(
                                        24,
                                        w: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            color: _isOnline
                                                ? InsightTheme.green
                                                : InsightTheme.red,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _isOnline ? 'Online' : 'Offline',
                                          style: InsightTheme.inter(
                                            12,
                                            w: FontWeight.w500,
                                            c: InsightTheme.ink2,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '· Last sync: ${_relativeTime(_lastSync)}',
                                          style: InsightTheme.inter(
                                            12,
                                            w: FontWeight.w500,
                                            c: InsightTheme.ink3,
                                          ),
                                        ),
                                      ],
                                    ),
                                    // Phase 5: live drain progress, e.g.
                                    // "Submitting inspection (2 of 5) —
                                    // Uploading photo 3 of 12". Only visible
                                    // while SyncOutboxService is actually
                                    // draining; collapses to nothing (not
                                    // even a SizedBox) the rest of the time
                                    // so it doesn't reserve dead space.
                                    ValueListenableBuilder<SyncProgress?>(
                                      valueListenable: SyncOutboxService.progress,
                                      builder: (context, syncProgress, _) {
                                        if (syncProgress == null) {
                                          return const SizedBox.shrink();
                                        }
                                        return Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const SizedBox(
                                                width: 9,
                                                height: 9,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 1.3,
                                                  color: InsightTheme.blue1,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Flexible(
                                                child: Text(
                                                  syncProgress.displayText,
                                                  style: InsightTheme.inter(
                                                    11.5,
                                                    w: FontWeight.w500,
                                                    c: InsightTheme.blueInk,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                                GestureDetector(
                                  onTap: _handleSyncNow,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: InsightTheme.lineStrong,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_syncingNow) ...[
                                          const SizedBox(
                                            width: 10,
                                            height: 10,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 1.5,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                        Text(
                                          _syncingNow
                                              ? 'Syncing...'
                                              : 'Sync Now',
                                          style: InsightTheme.inter(
                                            11,
                                            w: FontWeight.w600,
                                            c: InsightTheme.ink2,
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

                        const SizedBox(height: 24),

                        // 2. STATUS CARD — real pending state
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: SpringScale(
                            animation: springFor(1),
                            beginScale: 0.92,
                            child: Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                gradient: const LinearGradient(
                                  colors: [
                                    InsightTheme.blue1,
                                    InsightTheme.blue2,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: InsightTheme.blue1.withValues(
                                      alpha: 0.3,
                                    ),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        hasPending
                                            ? Icons
                                                  .swap_vertical_circle_outlined
                                            : Icons.verified_user_rounded,
                                        color: hasPending
                                            ? InsightTheme.amber
                                            : InsightTheme.green,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        hasPending
                                            ? '${_pendingRows.length} ITEM(S) WAITING TO SYNC'
                                            : 'ALL FIELD DATA SYNCED',
                                        style: InsightTheme.jetBrains(
                                          11,
                                          w: FontWeight.w600,
                                          c: Colors.white,
                                          ls: 0.8,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 18),
                                    child: Divider(
                                      height: 1,
                                      color: Colors.white12,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _MetricItem(
                                          label: 'GPS WAITING',
                                          value: '$_gpsWaiting',
                                          numericValue: _gpsWaiting,
                                          labelColor: Colors.white.withValues(
                                            alpha: 0.5,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        width: 1,
                                        height: 28,
                                        color: Colors.white12,
                                      ),
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            left: 16,
                                          ),
                                          child: _MetricItem(
                                            label: 'PHOTOS WAITING',
                                            value: '$_photosWaiting',
                                            numericValue: _photosWaiting,
                                            labelColor: Colors.white.withValues(
                                              alpha: 0.5,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Container(
                                        width: 1,
                                        height: 28,
                                        color: Colors.white12,
                                      ),
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            left: 16,
                                          ),
                                          child: _MetricItem(
                                            label: 'PENDING SIZE',
                                            value: _formatBytes(_pendingBytes),
                                            labelColor: Colors.white.withValues(
                                              alpha: 0.5,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _MetricItem(
                                          label: 'CHECKLIST UPDATES',
                                          value: '$_checklistWaiting',
                                          numericValue: _checklistWaiting,
                                          labelColor: Colors.white.withValues(
                                            alpha: 0.5,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        width: 1,
                                        height: 28,
                                        color: Colors.white12,
                                      ),
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            left: 16,
                                          ),
                                          child: _MetricItem(
                                            label: 'CONNECTION',
                                            value: _isOnline
                                                ? 'ONLINE'
                                                : 'OFFLINE',
                                            labelColor: Colors.white.withValues(
                                              alpha: 0.5,
                                            ),
                                            valueColor: _isOnline
                                                ? InsightTheme.green
                                                : InsightTheme.amber,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Phase 6: lightweight entry point to the full
                        // Synchronization Activity history — deliberately
                        // NOT a long log inline here (per the Phase 6
                        // architecture decision, the Sync Center stays
                        // focused on live/current status only). Deep-links
                        // straight into the Notifications screen's "Sync"
                        // tab.
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const NotificationsScreen(initialMode: 1),
                              ),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              decoration: BoxDecoration(
                                color: InsightTheme.surface,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: InsightTheme.line),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.history_rounded, size: 18, color: InsightTheme.ink2),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Synchronization History',
                                      style: InsightTheme.inter(13, w: FontWeight.w600, c: InsightTheme.ink),
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right_rounded, size: 18, color: InsightTheme.ink3),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Phase 7: Storage Management. Shows what's
                        // actually reclaimable (synced photo files only —
                        // see DBHelper.getCacheStats doc comment for why
                        // job cache and the Completed Audit Log's
                        // underlying rows are deliberately excluded).
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: InsightTheme.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: InsightTheme.line),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.sd_storage_rounded, size: 16, color: InsightTheme.ink2),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Offline Storage',
                                      style: InsightTheme.jetBrains(10.5, w: FontWeight.w700, ls: 0.6, c: InsightTheme.ink2),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _StorageStatItem(
                                        label: 'Cached Jobs',
                                        value: '$_cachedJobsCount',
                                      ),
                                    ),
                                    Expanded(
                                      child: _StorageStatItem(
                                        label: 'Photos Waiting',
                                        value: '$_unsyncedPhotoFileCount',
                                      ),
                                    ),
                                    Expanded(
                                      child: _StorageStatItem(
                                        label: 'Reclaimable',
                                        value: _formatBytes(_clearableBytes.toDouble()),
                                        valueColor: _clearableBytes > 0 ? InsightTheme.amberInk : null,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton(
                                    onPressed: _clearingCache ? null : _handleClearCache,
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: InsightTheme.lineStrong),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                    ),
                                    child: _clearingCache
                                        ? const SizedBox(
                                            width: 16, height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : Text(
                                            'Clear Synced Photo Cache',
                                            style: InsightTheme.inter(12.5, w: FontWeight.w600, c: InsightTheme.ink2),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // 3. REAL DATA LOG
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(
                              20,
                              0,
                              20,
                              kInsightBottomNavReserve,
                            ),
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              if (hasPending) ...[
                                Row(
                                  children: [
                                    Container(
                                      width: 3,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: InsightTheme.amberInk,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'WAITING TO SYNC',
                                      style: InsightTheme.jetBrains(
                                        10,
                                        w: FontWeight.w700,
                                        ls: 1.2,
                                        c: InsightTheme.ink2,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                ..._buildPendingCards(),
                                const SizedBox(height: 18),
                              ],

                              Row(
                                children: [
                                  Container(
                                    width: 3,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: InsightTheme.ink3,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'COMPLETED AUDIT LOG',
                                    style: InsightTheme.jetBrains(
                                      10,
                                      w: FontWeight.w700,
                                      ls: 1.2,
                                      c: InsightTheme.ink3,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              if (_syncedRows.isEmpty)
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: InsightTheme.surface,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: InsightTheme.line,
                                    ),
                                  ),
                                  child: Text(
                                    'No synced items yet. Once a queued item finishes syncing, it will show up here.',
                                    style: InsightTheme.inter(
                                      12.5,
                                      c: InsightTheme.ink3,
                                    ),
                                  ),
                                )
                              else
                                Container(
                                  decoration: BoxDecoration(
                                    color: InsightTheme.surface,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: InsightTheme.line,
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x04141628),
                                        blurRadius: 10,
                                        offset: Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    children: [
                                      for (
                                        int i = 0;
                                        i < _syncedRows.length;
                                        i++
                                      ) ...[
                                        SpringSlide(
                                          animation: springForKey(
                                            'synced-${_syncedRows[i]['id']}',
                                            10 + (i % 8),
                                          ),
                                          beginOffset: const Offset(0, 22),
                                          child: UpdatingTile(
                                            itemKey: _syncedRows[i]['id'] ?? i,
                                            signature: Object.hash(
                                              _syncedRows[i]['updated_at'],
                                              _syncedRows[i]['status'],
                                            ),
                                            child: _LogDataRow(
                                              icon: _iconFor(
                                                _syncedRows[i]['type']
                                                    as String,
                                              ),
                                              title: _jobLabel(
                                                _syncedRows[i]['job_id']
                                                    as String,
                                              ),
                                              dataType: _typeLabel(
                                                _syncedRows[i],
                                              ),
                                              dataSize: _dataSizeFor(
                                                _syncedRows[i],
                                              ),
                                              statusText: _relativeTime(
                                                DateTime.tryParse(
                                                  _syncedRows[i]['updated_at']
                                                          as String? ??
                                                      '',
                                                ),
                                              ),
                                              isPending: false,
                                            ),
                                          ),
                                        ),
                                        if (i != _syncedRows.length - 1)
                                          const Divider(
                                            height: 1,
                                            color: InsightTheme.line,
                                            indent: 56,
                                          ),
                                      ],
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),

      // 4. FLOATING BOTTOM NAVIGATION
      bottomNavigationBar: !widget.showBottomNav
          ? null
          : InsightBottomNav(
              currentIndex: _currentNavIndex,
              items: const [
                InsightNavItem(icon: Icons.home_rounded, label: 'Home'),
                InsightNavItem(icon: Icons.assignment_outlined, label: 'Tasks'),
                InsightNavItem(icon: Icons.sync_rounded, label: 'Updates'),
                InsightNavItem(
                  icon: Icons.person_outline_rounded,
                  label: 'Profile',
                ),
              ],
              onTap: (i) {
                if (i == _currentNavIndex) return;
                switch (i) {
                  case 0:
                    Navigator.of(context).pushReplacement(
                      insightTabRoute(
                        HomeDashboardScreen(profile: widget.profile),
                      ),
                    );
                    break;
                  case 1:
                    Navigator.of(context).pushReplacement(
                      insightTabRoute(TasksScreen(profile: widget.profile)),
                    );
                    break;
                  case 3:
                    Navigator.of(context).pushReplacement(
                      insightTabRoute(ProfileScreen(profile: widget.profile)),
                    );
                    break;
                }
              },
            ),
    );
  }
}

/// ==================================================================
/// COMPONENT WIDGETS
/// ==================================================================

class _StorageStatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _StorageStatItem({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: InsightTheme.jetBrains(8.5, c: InsightTheme.ink3, ls: 0.3),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: InsightTheme.poppins(14, w: FontWeight.w700, c: valueColor ?? InsightTheme.ink),
        ),
      ],
    );
  }
}

class _MetricItem extends StatelessWidget {
  final String label;
  final String value;
  final num? numericValue;
  final Color? valueColor;
  final Color labelColor;

  const _MetricItem({
    required this.label,
    required this.value,
    this.numericValue,
    this.valueColor,
    required this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    final valueStyle = InsightTheme.poppins(
      14,
      w: FontWeight.w700,
      c: valueColor ?? Colors.white,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: InsightTheme.jetBrains(8.5, c: labelColor, ls: 0.3)),
        const SizedBox(height: 4),
        numericValue != null
            ? CountUpText(value: numericValue!, style: valueStyle)
            : Text(value, style: valueStyle),
      ],
    );
  }
}

class _LogDataRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String dataType;
  final String dataSize;
  final String statusText;
  final bool isPending;
  final bool isFailed;
  final bool isConflict;

  const _LogDataRow({
    required this.icon,
    required this.title,
    required this.dataType,
    required this.dataSize,
    required this.statusText,
    required this.isPending,
    this.isFailed = false,
    this.isConflict = false,
  });

  @override
  Widget build(BuildContext context) {
    final accentTint = isFailed ? InsightTheme.redTint : InsightTheme.amberTint;
    final accentInk = isFailed ? InsightTheme.redInk : InsightTheme.amberInk;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: isPending
          ? BoxDecoration(
              color: InsightTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accentTint, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x04141628),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isPending ? accentTint : InsightTheme.surface2,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 16,
              color: isPending ? accentInk : InsightTheme.ink2,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: InsightTheme.inter(
                          13.5,
                          w: FontWeight.w600,
                          c: InsightTheme.ink,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      dataSize,
                      style: InsightTheme.jetBrains(
                        10.5,
                        w: FontWeight.w600,
                        c: InsightTheme.ink2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        dataType,
                        style: InsightTheme.inter(11.5, c: InsightTheme.ink2),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Row(
                      children: [
                        if (isPending) ...[
                          if (isConflict) ...[
                            Icon(
                              Icons.warning_rounded,
                              size: 10,
                              color: InsightTheme.amberInk,
                            ),
                          ] else if (!isFailed) ...[
                            const SizedBox(
                              width: 8,
                              height: 8,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: InsightTheme.amberInk,
                              ),
                            ),
                          ] else ...[
                            Icon(
                              Icons.error_rounded,
                              size: 10,
                              color: InsightTheme.redInk,
                            ),
                          ],
                          const SizedBox(width: 6),
                        ] else ...[
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 10,
                            color: InsightTheme.greenInk,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          statusText,
                          style: InsightTheme.inter(
                            10.5,
                            w: FontWeight.w500,
                            c: isPending ? accentInk : InsightTheme.ink3,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: isActive ? 14 : 10,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          gradient: isActive
              ? const LinearGradient(
                  colors: [InsightTheme.blue1, InsightTheme.blue2],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          borderRadius: BorderRadius.circular(14),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: InsightTheme.blue1.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive ? Colors.white : InsightTheme.ink3,
              size: 20,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: InsightTheme.inter(
                10,
                w: FontWeight.w600,
                c: isActive ? Colors.white : InsightTheme.ink3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}