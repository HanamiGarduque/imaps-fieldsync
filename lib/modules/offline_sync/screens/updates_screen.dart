import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/models/user_profile.dart';
import '../../../core/services/db_helper.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/sync_outbox_service.dart';
import '../../../core/widgets/insight_bottom_nav.dart'; // kInsightBottomNavReserve (scroll padding) only
import '../../../core/widgets/motion/spring_entrance.dart';
import '../../../core/widgets/motion/updating_tile.dart';
import '../../../core/widgets/motion/linked_list_motion.dart';
import '../../../core/widgets/imaps_loading_indicator.dart';
import '../../profile_settings/screens/notifications_screen.dart';

import '../../../core/theme/insight_theme.dart';

/// ==================================================================
/// SCREEN — SYNC CENTER (FieldSync)
/// ==================================================================
/// Rebuilt to read real data from the `pending_actions` outbox
/// (DBHelper / SyncOutboxService) instead of simulating a fake pipeline.
/// Every number here is either a live query result or a stat()'d file
/// size — nothing is fabricated.
class UpdatesScreen extends StatefulWidget {
  final UserProfile profile;
  const UpdatesScreen({
    super.key,
    required this.profile,
  });

  @override
  State<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends State<UpdatesScreen>
    with TickerProviderStateMixin, SpringEntrance {
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
  bool _clearingCache = false;

  Timer? _pollTimer;
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  // --- Floating toast (matches the provided design reference) ---
  String? _toastMessage;
  Color _toastColor = InsightTheme.greenInk;
  Timer? _toastTimer;

  void _showToast(String message, {Color color = InsightTheme.greenInk}) {
    _toastTimer?.cancel();
    setState(() {
      _toastMessage = message;
      _toastColor = color;
    });
    _toastTimer = Timer(const Duration(milliseconds: 3500), () {
      if (mounted) setState(() => _toastMessage = null);
    });
  }



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
    _toastTimer?.cancel();
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
    });
  }

  Future<void> _handleClearCache() async {
    if (_clearingCache) return;
    if (_clearableBytes == 0) {
      _showToast('Nothing to clear right now.', color: InsightTheme.ink2);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: InsightTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: InsightTheme.redTint,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.delete_outline_rounded, color: InsightTheme.redInk, size: 20),
              ),
              const SizedBox(height: 12),
              Text('Clear cached photo files?', style: InsightTheme.urbanist(16, w: FontWeight.w700, c: InsightTheme.ink)),
              const SizedBox(height: 6),
              Text(
                'This will remove $_syncedPhotoFileCount photo file(s) already backed up to the '
                'server (${_formatBytes(_clearableBytes.toDouble())}) from this device. '
                'Unsynced photos are never touched.',
                style: InsightTheme.openSans(13, c: InsightTheme.ink2, h: 1.4),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text('Keep Photo Cache', style: InsightTheme.openSans(13, w: FontWeight.w600, c: InsightTheme.ink2)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: InsightTheme.red,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text('Delete $_syncedPhotoFileCount Files', style: InsightTheme.openSans(13, w: FontWeight.w700, c: Colors.white)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _clearingCache = true);
    final cleared = await DBHelper.clearSyncedPhotoCache();
    await _loadCacheStats();
    if (!mounted) return;
    setState(() => _clearingCache = false);
    _showToast('Freed $cleared photo file(s).', color: InsightTheme.greenInk);
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
    _showToast(
      stillPending == 0
          ? 'All caught up — nothing left to sync.'
          : conflictCount > 0
              ? '$conflictCount item(s) need conflict review.'
              : '$stillPending item(s) still waiting (check connection).',
      color: stillPending == 0 ? InsightTheme.greenInk : InsightTheme.amberInk,
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
      _showToast(
        'No internet connection. This will sync automatically once you\'re back online.',
        color: InsightTheme.amberInk,
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
    _showToast(message, color: color);
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

      final job = _jobLookup[jobId];
      final applicant = (job?['applicant_name'] as String?) ?? '';
      final barangay = (job?['barangay'] as String?) ?? '';
      final initial = applicant.isNotEmpty ? applicant.substring(0, 1).toUpperCase() : 'J';

      return LinkedListSlide(
        key: ValueKey('linked_group_$jobId'),
        index: groupIndex,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: InsightTheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: InsightTheme.line, width: 1),
              boxShadow: const [
                BoxShadow(color: Color(0x06141628), blurRadius: 8, offset: Offset(0, 3)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.only(bottom: 10),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: InsightTheme.line)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: InsightTheme.blueTint,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            initial,
                            style: InsightTheme.urbanist(13, w: FontWeight.w700, c: InsightTheme.blue1),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                applicant.isNotEmpty ? applicant : 'Job $jobId',
                                style: InsightTheme.urbanist(13.5, w: FontWeight.w700, c: InsightTheme.ink),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (barangay.isNotEmpty)
                                Text(
                                  barangay,
                                  style: InsightTheme.openSans(12, c: InsightTheme.ink2),
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: InsightTheme.surface2,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            rows.length == 1 ? '1 update' : '${rows.length} updates',
                            style: InsightTheme.jetBrains(12, c: InsightTheme.ink2),
                          ),
                        ),
                      ],
                    ),
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
                  Container(
                    padding: const EdgeInsets.only(top: 10),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: InsightTheme.line)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          style: TextButton.styleFrom(
                            backgroundColor: InsightTheme.blueTint,
                            foregroundColor: InsightTheme.blueInk,
                            minimumSize: const Size(0, 44),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () => _handleReviewConflict(
                            rows.firstWhere((r) => r['status'] == 'conflict'),
                          ),
                          child: Text('Review conflict', style: InsightTheme.openSans(13, w: FontWeight.w700, c: InsightTheme.blueInk)),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          style: TextButton.styleFrom(
                            backgroundColor: InsightTheme.amberTint,
                            foregroundColor: InsightTheme.amberInk,
                            minimumSize: const Size(0, 44),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () => _handleForceSync(
                            rows.firstWhere((r) => r['status'] == 'conflict'),
                          ),
                          child: Text('Force overwrite', style: InsightTheme.openSans(13, w: FontWeight.w700, c: InsightTheme.amberInk)),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.only(top: 10),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: InsightTheme.line)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: InsightTheme.blue1,
                            minimumSize: const Size(0, 44),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(color: InsightTheme.blue1.withValues(alpha: 0.2)),
                            ),
                          ),
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
                            isSyncingThisJob ? 'Syncing…' : 'Sync Inspection (${rows.length})',
                            style: InsightTheme.openSans(13, w: FontWeight.w700, c: InsightTheme.blue1),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }).toList();
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
      builder: (ctx) => Dialog(
        backgroundColor: InsightTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: InsightTheme.amberTint,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.warning_amber_rounded, color: InsightTheme.amberInk, size: 20),
              ),
              const SizedBox(height: 12),
              Text('Sync Conflict Review', style: InsightTheme.urbanist(16, w: FontWeight.w700, c: InsightTheme.ink)),
              const SizedBox(height: 6),
              Text(
                'This job record was modified on the remote server after local offline changes were saved.',
                style: InsightTheme.openSans(13, c: InsightTheme.ink2, h: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: InsightTheme.bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: InsightTheme.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Local Offline Snapshot: ${cachedUpdatedAt ?? 'Unknown'}',
                      style: InsightTheme.jetBrains(12, c: InsightTheme.ink2),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Server Timestamp: $serverUpdatedAt',
                      style: InsightTheme.jetBrains(12, c: InsightTheme.ink2),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: InsightTheme.ink,
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('Close Review Window', style: InsightTheme.openSans(13, w: FontWeight.w700, c: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleForceSync(Map<String, dynamic> row) async {
    final id = row['id'] as String?;
    if (id == null || id.isEmpty) return;
    await DBHelper.markActionForceSync(id);
    await _refresh();
    if (!mounted) return;
    _showToast('Conflict marked for force sync on next drain.', color: InsightTheme.amberInk);
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

  /// Builds the "Sync Performance" card (segmented queue-distribution bar
  /// + legend), replacing the old solid gradient hero card. Uses only the
  /// live counts already computed in `_refresh()` — no simulated/fake
  /// values. Reuses existing theme tokens for the 4 categories instead of
  /// introducing new hex values: green (synced), blue1 (photos), blueInk
  /// (checklists), amber (GPS) — flagged to Master as a deliberate
  /// simplification vs. the reference mockup's extra sky/indigo hues.
  Widget _buildSyncPerformanceCard() {
    final syncedCount = _syncedRows.length;
    final totalItems = syncedCount + _pendingRows.length;
    final segments = <Widget>[];
    void addSegment(int count, Color color) {
      if (count <= 0) return;
      segments.add(
        Expanded(
          flex: count,
          child: Container(
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
          ),
        ),
      );
      segments.add(const SizedBox(width: 3));
    }

    addSegment(syncedCount, InsightTheme.green);
    addSegment(_photosWaiting, InsightTheme.blue1);
    addSegment(_checklistWaiting, InsightTheme.blueInk);
    addSegment(_gpsWaiting, InsightTheme.amber);
    if (segments.isNotEmpty) segments.removeLast();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: InsightTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: InsightTheme.line),
        boxShadow: const [
          BoxShadow(color: Color(0x08141628), blurRadius: 14, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: InsightTheme.blueTint, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.insights_rounded, size: 16, color: InsightTheme.blue1),
              ),
              const SizedBox(width: 10),
              Text('Sync Performance', style: InsightTheme.urbanist(14, w: FontWeight.w700, c: InsightTheme.ink)),
            ],
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              padding: const EdgeInsets.only(top: 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: InsightTheme.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _PerfMetric(label: 'SYNCED ITEMS', value: '$syncedCount', color: InsightTheme.ink),
                  ),
                  Container(width: 1, height: 26, color: InsightTheme.line),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: _PerfMetric(label: 'PENDING QUEUE', value: '${_pendingRows.length}', color: InsightTheme.blue1),
                    ),
                  ),
                  Container(width: 1, height: 26, color: InsightTheme.line),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: _PerfMetric(label: 'PENDING SIZE', value: _formatBytes(_pendingBytes), color: InsightTheme.ink),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Queue Record Distribution', style: InsightTheme.openSans(12, w: FontWeight.w600, c: InsightTheme.ink2)),
              Text('$totalItems total', style: InsightTheme.jetBrains(12, c: InsightTheme.ink3)),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: 14,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(color: InsightTheme.surface2, borderRadius: BorderRadius.circular(10)),
            child: totalItems == 0
                ? const SizedBox.shrink()
                : Row(children: segments),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _PerfLegendItem(color: InsightTheme.green, label: 'Synced Data', value: syncedCount)),
              const SizedBox(width: 8),
              Expanded(child: _PerfLegendItem(color: InsightTheme.blue1, label: 'Photos', value: _photosWaiting)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _PerfLegendItem(color: InsightTheme.blueInk, label: 'Checklists', value: _checklistWaiting)),
              const SizedBox(width: 8),
              Expanded(child: _PerfLegendItem(color: InsightTheme.amber, label: 'GPS Coordinates', value: _gpsWaiting)),
            ],
          ),
        ],
      ),
    );
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
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: kInsightBottomNavReserve),
                      children: [
                        // 1. TOP UTILITY HEADER — white surface background
                        // with a bottom hairline divider, matching the
                        // Tasks screen's AppBar treatment (InsightTheme.surface
                        // + 1px InsightTheme.line divider) instead of letting
                        // the page background/decorative blur show through.
                        Container(
                          width: double.infinity,
                          decoration: const BoxDecoration(
                            color: InsightTheme.surface,
                            border: Border(bottom: BorderSide(color: InsightTheme.line, width: 1)),
                          ),
                          child: SpringSlide(
                          animation: springFor(0),
                          beginOffset: const Offset(0, -28),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                // Overflow fix (#3): let the text column take
                                // only the space left of the Sync button so a
                                // long count ("Sync 10 Queued") can never push
                                // the button past the header container edge.
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Sync Center',
                                      style: InsightTheme.urbanist(
                                        24,
                                        w: FontWeight.w700,
                                        c: InsightTheme.ink,
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
                                          style: InsightTheme.openSans(
                                            12,
                                            w: FontWeight.w600,
                                            c: InsightTheme.ink2,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '· Last sync: ${_relativeTime(_lastSync)}',
                                          style: InsightTheme.openSans(
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
                                                  style: InsightTheme.openSans(
                                                    12,
                                                    w: FontWeight.w600,
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
                                ),
                                const SizedBox(width: 12),
                                GestureDetector(
                                  onTap: (_syncingNow || _pendingRows.isEmpty) ? null : _handleSyncNow,
                                  child: Container(
                                    constraints: const BoxConstraints(minHeight: 44),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: (_syncingNow || _pendingRows.isEmpty)
                                          ? InsightTheme.blue1.withValues(alpha: 0.5)
                                          : InsightTheme.blue1,
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: InsightTheme.blue1.withValues(alpha: 0.25),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_syncingNow) ...[
                                          const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                        ] else ...[
                                          Icon(
                                            _pendingRows.isEmpty ? Icons.check_rounded : Icons.sync_rounded,
                                            size: 15,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        Text(
                                          _syncingNow
                                              ? 'Syncing...'
                                              : _pendingRows.isEmpty
                                                  ? 'All Synced'
                                                  : 'Sync ${_pendingRows.length} Queued',
                                          style: InsightTheme.openSans(
                                            13,
                                            w: FontWeight.w700,
                                            c: Colors.white,
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
                        ),

                        const SizedBox(height: 20),

                        // 2. SYNC PERFORMANCE CARD — replaces the old solid
                        // gradient hero card with a lighter card that shows
                        // the real queue distribution (mirrors the
                        // provided design reference), still built entirely
                        // from live counts computed in _refresh().
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: SpringScale(
                            animation: springFor(1),
                            beginScale: 0.92,
                            child: _buildSyncPerformanceCard(),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Entry point to full Synchronization History (deep-links to Notifications Sync tab)
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
                              constraints: const BoxConstraints(minHeight: 44),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: InsightTheme.surface,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: InsightTheme.line),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: InsightTheme.surface2,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.history_rounded, size: 16, color: InsightTheme.ink2),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Synchronization Audit History',
                                      style: InsightTheme.openSans(13, w: FontWeight.w600, c: InsightTheme.ink),
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
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: InsightTheme.line),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.sd_storage_rounded, size: 16, color: InsightTheme.ink2),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'OFFLINE STORAGE CACHE',
                                        style: InsightTheme.jetBrains(12, w: FontWeight.w700, ls: 0.6, c: InsightTheme.ink2),
                                      ),
                                    ),
                                    Text(
                                      'SQLite Active',
                                      style: InsightTheme.openSans(12, w: FontWeight.w500, c: InsightTheme.ink3),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: InsightTheme.bg,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: InsightTheme.line),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: _StorageStatItem(
                                          label: 'Cached Jobs',
                                          value: '$_cachedJobsCount',
                                        ),
                                      ),
                                      Expanded(
                                        child: _StorageStatItem(
                                          label: 'Unsynced Files',
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
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton(
                                    onPressed: (_clearingCache || _clearableBytes == 0) ? null : _handleClearCache,
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: InsightTheme.lineStrong),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      minimumSize: const Size(0, 44),
                                    ),
                                    child: _clearingCache
                                        ? const SizedBox(
                                            width: 16, height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.delete_outline_rounded, size: 15, color: InsightTheme.ink3),
                                              const SizedBox(width: 8),
                                              Text(
                                                _clearableBytes > 0
                                                    ? 'Clear ${_formatBytes(_clearableBytes.toDouble())} Photo Cache'
                                                    : 'Photo Cache Clear',
                                                style: InsightTheme.openSans(13, w: FontWeight.w600, c: InsightTheme.ink2),
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // 3. REAL DATA LOG — folded into the single outer
                        // ListView (see the RefreshIndicator's child above)
                        // so the whole screen scrolls as one continuous
                        // list. Previously this owned its own inner
                        // Expanded(ListView(...)) sitting next to fixed-size
                        // Column siblings (header/performance/history/
                        // storage cards) — once those grew taller than the
                        // available screen height, the Column had no room
                        // left for Expanded and Flutter threw the
                        // yellow/black "RenderFlex overflowed" warning at
                        // the bottom instead of letting the page scroll.
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
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
                                        12,
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
                                      12,
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
                                    style: InsightTheme.openSans(
                                      13,
                                      c: InsightTheme.ink2,
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

          // --- Floating toast (matches design reference) ---
          if (_toastMessage != null)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: SafeArea(
                bottom: false,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: _toastColor,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: const [
                        BoxShadow(color: Color(0x33000000), blurRadius: 16, offset: Offset(0, 6)),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 17, color: Colors.white),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _toastMessage!,
                            style: InsightTheme.openSans(13, w: FontWeight.w600, c: Colors.white),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            _toastTimer?.cancel();
                            setState(() => _toastMessage = null);
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.close_rounded, size: 16, color: Colors.white70),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

        ],
      ),

      // Bottom navigation now lives solely in MainShellScreen (the app
      // shell). This screen no longer renders its own nav bar — see
      // NAVIGATION_REFACTOR.md for why the duplicate, per-page nav bar
      // was removed.
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
          style: InsightTheme.openSans(12, w: FontWeight.w600, c: InsightTheme.ink3, ls: 0.3),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: InsightTheme.urbanist(14, w: FontWeight.w700, c: valueColor ?? InsightTheme.ink),
        ),
      ],
    );
  }
}

class _PerfMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _PerfMetric({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: InsightTheme.openSans(12, w: FontWeight.w600, c: InsightTheme.ink3, ls: 0.3)),
        const SizedBox(height: 3),
        Text(value, style: InsightTheme.urbanist(15, w: FontWeight.w800, c: color)),
      ],
    );
  }
}

class _PerfLegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final int value;

  const _PerfLegendItem({required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: InsightTheme.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: InsightTheme.line),
      ),
      child: Row(
        children: [
          Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: InsightTheme.openSans(12, w: FontWeight.w600, c: InsightTheme.ink2),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text('$value', style: InsightTheme.jetBrains(12, w: FontWeight.w700, c: InsightTheme.ink)),
        ],
      ),
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
              color: isPending ? accentTint : InsightTheme.greenTint,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 16,
              color: isPending ? accentInk : InsightTheme.greenInk,
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
                        style: InsightTheme.openSans(
                          13.5,
                          w: FontWeight.w700,
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
                        12,
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
                        style: InsightTheme.openSans(12, c: InsightTheme.ink2),
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
                              size: 11,
                              color: InsightTheme.amberInk,
                            ),
                          ] else if (!isFailed) ...[
                            const SizedBox(
                              width: 9,
                              height: 9,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: InsightTheme.amberInk,
                              ),
                            ),
                          ] else ...[
                            Icon(
                              Icons.error_rounded,
                              size: 11,
                              color: InsightTheme.redInk,
                            ),
                          ],
                          const SizedBox(width: 6),
                        ] else ...[
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 11,
                            color: InsightTheme.greenInk,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          statusText,
                          style: InsightTheme.openSans(
                            12,
                            w: FontWeight.w600,
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