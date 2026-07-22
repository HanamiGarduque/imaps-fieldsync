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

  List<Map<String, dynamic>> _pendingRows = [];
  List<Map<String, dynamic>> _syncedRows = [];
  Map<String, Map<String, dynamic>> _jobLookup = {};

  int _gpsWaiting = 0;
  int _checklistWaiting = 0;
  int _photosWaiting = 0;
  double _pendingBytes = 0;
  DateTime? _lastSync;

  Timer? _pollTimer;
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Light polling while this screen is open — catches progress from a
    // drain that SyncOutboxService kicked off elsewhere (e.g. connectivity
    // just came back while the inspector was on a different screen).
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

  Future<void> _refresh() async {
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
    resetSprings();
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

  Future<void> _handleSyncNow() async {
    if (_syncingNow) return;
    HapticFeedback.lightImpact();
    setState(() => _syncingNow = true);
    await SyncOutboxService.drain();
    await _refresh();
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
      case 'submit_inspection':
        final n = (payload['photosData'] as List?)?.length ?? 0;
        return 'Full Submission — $n photo(s) + Findings';
      default:
        return type;
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
                    onRefresh: _refresh,
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

                        const SizedBox(height: 32),

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
                                ..._pendingRows.asMap().entries.map((entry) {
                                  final i = entry.key;
                                  final row = entry.value;
                                  return LinkedListSlide(
                                    key: ValueKey(
                                      'linked_pending_${row['id']}',
                                    ),
                                    index: i,
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 10,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          UpdatingTile(
                                            itemKey: row['id'] ?? i,
                                            signature: Object.hash(
                                              row['status'],
                                              row['type'],
                                            ),
                                            child: _LogDataRow(
                                              icon: _iconFor(
                                                row['type'] as String,
                                              ),
                                              title: _jobLabel(
                                                row['job_id'] as String,
                                              ),
                                              dataType: _typeLabel(row),
                                              dataSize: _dataSizeFor(row),
                                              statusText: _statusTextFor(row),
                                              isPending: true,
                                              isFailed:
                                                  row['status'] == 'failed',
                                              isConflict:
                                                  row['status'] == 'conflict',
                                            ),
                                          ),
                                          if (row['status'] == 'conflict') ...[
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                TextButton(
                                                  onPressed: () =>
                                                      _handleReviewConflict(
                                                        row,
                                                      ),
                                                  child: const Text(
                                                    'Review changes',
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                TextButton(
                                                  onPressed: () =>
                                                      _handleForceSync(row),
                                                  child: const Text(
                                                    'Force sync anyway',
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                }),
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
