import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import '../../../core/widgets/sensitive_screen.dart';
import 'package:flutter/services.dart';

import '../../../core/models/user_profile.dart';
import '../../../core/services/db_helper.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/sync_outbox_service.dart';
import '../../../core/widgets/insight_bottom_nav.dart'; // kInsightBottomNavReserve (scroll padding) only
import '../../../core/widgets/motion/spring_entrance.dart';
import '../../../core/widgets/motion/updating_tile.dart';
import '../../../core/widgets/motion/linked_list_motion.dart';
import '../../../core/widgets/imaps_loading_indicator.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/field_form_widgets.dart';
import '../../../core/layout/responsive_layout.dart';
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
  const UpdatesScreen({super.key, required this.profile});

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
  final GlobalKey _queueSectionKey = GlobalKey();

  void _showToast(String message, {Color color = InsightTheme.greenInk}) {
    if (!mounted) return;
    AppFeedback.show(context, message: message, color: color);
  }

  Widget _sectionHelpButton({required String title, required String message}) {
    return FieldInfoButton(
      label: 'About $title',
      onPressed: () => _showSectionHelp(title: title, message: message),
    );
  }

  Future<void> _showSectionHelp({
    required String title,
    required String message,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: Text(
          title,
          style: InsightTheme.urbanist(
            18,
            w: FontWeight.w700,
            c: InsightTheme.ink,
          ),
        ),
        content: Text(
          message,
          style: InsightTheme.openSans(13, c: InsightTheme.ink2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _onDrainCompleted() {
    if (!mounted) return;
    _refresh();
    unawaited(_loadCacheStats());
  }

  @override
  void initState() {
    super.initState();
    _refresh(replay: true);
    _loadCacheStats();
    SyncOutboxService.drainCompleted.addListener(_onDrainCompleted);
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
    SyncOutboxService.drainCompleted.removeListener(_onDrainCompleted);
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
    // Only this inspector's own durable receipts can prove a successful send.
    // The old global preference survived sign-out and could name another
    // account's (or a future) success.
    DateTime? lastReceipt;
    for (final row in synced) {
      final at = DateTime.tryParse(row['updated_at'] as String? ?? '');
      if (at != null && (lastReceipt == null || at.isAfter(lastReceipt))) {
        lastReceipt = at;
      }
    }

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
      _lastSync = lastReceipt;
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
          // Dialog does not make its child scrollable. min still hugs a short
          // body, but a long one (large file counts, bigger text) now scrolls
          // instead of pushing the action buttons out of the dialog.
          child: SingleChildScrollView(
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
                  child: Icon(
                    Icons.delete_outline_rounded,
                    color: InsightTheme.redInk,
                    size: 20,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Clear cached evidence files?',
                  style: InsightTheme.urbanist(
                    16,
                    w: FontWeight.w700,
                    c: InsightTheme.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'This will remove $_syncedPhotoFileCount evidence file(s) already backed up to the '
                  'server (${_formatBytes(_clearableBytes.toDouble())}) from this device. '
                  'Unsynced evidence files are never touched.',
                  style: InsightTheme.openSans(
                    13,
                    c: InsightTheme.ink2,
                    h: 1.4,
                  ),
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
                      child: Text(
                        'Keep Evidence Cache',
                        style: InsightTheme.openSans(
                          13,
                          w: FontWeight.w600,
                          c: InsightTheme.ink2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: InsightTheme.red,
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(
                        'Delete $_syncedPhotoFileCount Files',
                        style: InsightTheme.openSans(
                          13,
                          w: FontWeight.w700,
                          c: Colors.white,
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
    );
    if (confirmed != true || !mounted) return;

    setState(() => _clearingCache = true);
    final cleared = await DBHelper.clearSyncedPhotoCache();
    await _loadCacheStats();
    if (!mounted) return;
    setState(() => _clearingCache = false);
    unawaited(
      SupabaseService.logActivity(
        eventType: 'cache_cleared',
        title: 'Photo cache cleared',
        subtitle: 'Freed $cleared photo file(s)',
      ),
    );
    _showToast('Freed $cleared evidence file(s).', color: InsightTheme.greenInk);
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
    final pausedCount = _pendingRows
        .where((r) => r['status'] == 'paused')
        .length;
    final conflictCount = _pendingRows
        .where((r) => r['status'] == 'conflict')
        .length;
    _showToast(
      stillPending == 0
          ? 'All caught up — nothing left to sync.'
          : pausedCount > 0
          ? '$pausedCount item(s) paused — saved on device. Review the reason below.'
          : conflictCount > 0
          ? '$conflictCount item(s) need conflict review.'
          // Only claim a connection problem when the device really has
          // no link. A queued row can also fail on the server or on
          // task state, and blaming the connection for that sent
          // inspectors chasing a signal that was already fine.
          : _isOnline
          ? '$stillPending item(s) could not sync — see the reason below.'
          : '$stillPending item(s) still waiting (check connection).',
      color: stillPending == 0 ? InsightTheme.greenInk : InsightTheme.amberInk,
    );
    unawaited(
      SupabaseService.logActivity(
        eventType: 'sync_manual',
        title: 'Manual sync completed',
        subtitle: stillPending == 0
            ? 'All pending data synchronized'
            : '$stillPending item(s) still pending',
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
    final hasConflict = stillPendingForJob.any(
      (r) => r['status'] == 'conflict',
    );
    final hasPaused = stillPendingForJob.any((r) => r['status'] == 'paused');
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
    } else if (hasPaused) {
      message = '$label paused — saved on device. Review the reason below.';
      color = InsightTheme.amberInk;
    } else if (hasFailed) {
      message = '$label couldn\'t sync. It will retry automatically.';
      color = InsightTheme.redInk;
    } else {
      message = '$label is saved on device — waiting to send.';
      color = InsightTheme.amberInk;
    }
    _showToast(message, color: color);
    unawaited(
      SupabaseService.logActivity(
        eventType: 'sync_inspection',
        title: 'Inspection sync completed',
        subtitle: '$label: $message',
        fieldJobId: jobId,
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
      final hasPaused = rows.any((r) => r['status'] == 'paused');
      final isSyncingThisJob = _syncingJobId == jobId;

      final job = _jobLookup[jobId];
      final applicant = (job?['applicant_name'] as String?) ?? '';
      final barangay = (job?['barangay'] as String?) ?? '';
      final initial = applicant.isNotEmpty
          ? applicant.substring(0, 1).toUpperCase()
          : 'J';

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
                BoxShadow(
                  color: Color(0x06141628),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
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
                      border: Border(
                        bottom: BorderSide(color: InsightTheme.line),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                            style: InsightTheme.urbanist(
                              13,
                              w: FontWeight.w700,
                              c: InsightTheme.blue1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                applicant.isNotEmpty ? applicant : 'Job $jobId',
                                style: InsightTheme.urbanist(
                                  13.5,
                                  w: FontWeight.w700,
                                  c: InsightTheme.ink,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (barangay.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    barangay,
                                    style: InsightTheme.openSans(
                                      12,
                                      c: InsightTheme.ink2,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              if (rows.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    rows.length == 1
                                        ? '1 update'
                                        : '${rows.length} updates',
                                    style: InsightTheme.openSans(
                                      11,
                                      w: FontWeight.w600,
                                      c: InsightTheme.ink3,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: InsightTheme.surface2,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isSyncingThisJob
                                ? 'Syncing'
                                : hasConflict
                                ? 'Review'
                                : hasPaused
                                ? 'Paused'
                                : 'Queued',
                            style: InsightTheme.jetBrains(
                              11,
                              c: InsightTheme.ink2,
                            ),
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
                        statusText: _statusTextFor(row),
                        isPending: true,
                        isSyncing: row['status'] == 'syncing',
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
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TextButton(
                          style: TextButton.styleFrom(
                            backgroundColor: InsightTheme.blueTint,
                            foregroundColor: InsightTheme.blueInk,
                            minimumSize: const Size(48, 48),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () => _handleReviewConflict(
                            rows.firstWhere((r) => r['status'] == 'conflict'),
                          ),
                          child: Text(
                            'Review conflict',
                            style: InsightTheme.openSans(
                              13,
                              w: FontWeight.w700,
                              c: InsightTheme.blueInk,
                            ),
                          ),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            backgroundColor: InsightTheme.amberTint,
                            foregroundColor: InsightTheme.amberInk,
                            minimumSize: const Size(48, 48),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () => _handleForceSync(
                            rows.firstWhere((r) => r['status'] == 'conflict'),
                          ),
                          child: Text(
                            'Force overwrite',
                            style: InsightTheme.openSans(
                              13,
                              w: FontWeight.w700,
                              c: InsightTheme.amberInk,
                            ),
                          ),
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
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      children: [
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: InsightTheme.blue1,
                            minimumSize: const Size(48, 48),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color: InsightTheme.blue1.withValues(
                                  alpha: 0.2,
                                ),
                              ),
                            ),
                          ),
                          onPressed: (_syncingNow || _syncingJobId != null)
                              ? null
                              : () => _handleSyncThisInspection(jobId),
                          icon: isSyncingThisJob
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.sync_rounded, size: 16),
                          label: Text(
                            isSyncingThisJob
                                ? 'Syncing…'
                                : 'Sync Inspection (${rows.length})',
                            style: InsightTheme.openSans(
                              13,
                              w: FontWeight.w700,
                              c: InsightTheme.blue1,
                            ),
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
        return 'Full Submission — $n ${n == 1 ? 'evidence attachment' : 'evidence attachments'} + Findings';
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
    final error = row['last_error'] as String? ?? '';
    switch (status) {
      case 'syncing':
        return 'Syncing — sending to FieldSync-Supabase';
      case 'paused':
        if (retries >= 5) return 'Paused after $retries attempts';
        if (error == InspectionAuthorityResult.authRequired.message) {
          return 'Paused — sign in again';
        }
        if (error ==
            InspectionAuthorityResult.localOwnershipIncomplete.message) {
          return 'Paused — task ownership needs review';
        }
        if (error == InspectionAuthorityResult.serverRejected.message) {
          return 'Paused — server rejected this update';
        }
        return 'Paused — saved on device';
      case 'failed':
        return 'Retry waiting — saved on device';
      case 'conflict':
        return 'Conflict — saved on device';
      default:
        return _isOnline
            ? 'Saved on device — waiting to send'
            : 'Saved on device — waiting for connection';
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
          // Scrollable for the same reason as the clear-cache dialog above.
          child: SingleChildScrollView(
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
                  child: Icon(
                    Icons.warning_amber_rounded,
                    color: InsightTheme.amberInk,
                    size: 20,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Sync Conflict Review',
                  style: InsightTheme.urbanist(
                    16,
                    w: FontWeight.w700,
                    c: InsightTheme.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'This job record was modified on the remote server after local offline changes were saved.',
                  style: InsightTheme.openSans(
                    13,
                    c: InsightTheme.ink2,
                    h: 1.4,
                  ),
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(
                      'Close Review Window',
                      style: InsightTheme.openSans(
                        13,
                        w: FontWeight.w700,
                        c: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleForceSync(Map<String, dynamic> row) async {
    final id = row['id'] as String?;
    if (id == null || id.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Force overwrite?'),
        content: const Text(
          'This will replace newer server data for this item with the version '
          'saved on this device the next time it syncs. The server copy of '
          'this update cannot be recovered afterward.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm overwrite'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await DBHelper.markActionForceSync(id);
    await _refresh();
    if (!mounted) return;
    _showToast(
      'Conflict marked for force sync on next drain.',
      color: InsightTheme.amberInk,
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

  String _formatDeviceTime(DateTime dt) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  /// What this device can actually prove about a completed receipt. The
  /// server-side iMAPS import has no receipt mechanism yet, so it is never
  /// claimed here.
  List<String> _receiptLinesFor(Map<String, dynamic> row) {
    final at = DateTime.tryParse(row['updated_at'] as String? ?? '');
    final lines = <String>[
      'FieldSync-Supabase received',
      if (at != null) 'Receipt recorded on device: ${_formatDeviceTime(at)}',
    ];
    if (row['type'] == 'submit_inspection') {
      final payload = _payloadOf(row);
      final result = payload['inspectionResult'];
      lines.add(
        'Inspector assessment: '
        '${result is String && result.isNotEmpty ? result : 'Not recorded'}',
      );
      lines.add('iMAPS import: Not yet confirmed');
    }
    return lines;
  }

  String _formatBytes(double bytes) {
    if (bytes <= 0) return '0.00 B';
    if (bytes < 1024) return '${bytes.toStringAsFixed(0)} B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Rows the user must act on before the queue can drain.
  List<Map<String, dynamic>> get _attentionRows => _pendingRows
      .where((row) {
        final status = row['status'] as String?;
        return status == 'paused' || status == 'failed' || status == 'conflict';
      })
      .toList();

  String _syncHistorySummary() {
    // `_syncedRows` is the recent window (limit 20); label it as such rather
    // than claiming an exact "today" total the loaded window cannot prove.
    final receipts = _syncedRows.length;
    final attention = _attentionRows.length;
    final suffix = attention == 0
        ? ''
        : ' · $attention ${attention == 1 ? 'needs' : 'need'} attention';
    return '$receipts recent ${receipts == 1 ? 'receipt' : 'receipts'}$suffix';
  }

  void _reviewAttention() {
    final ctx = _queueSectionKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: 0.05,
    );
  }

  /// One status card: headline count, composition bar, legend and action.
  /// Built only from the live queue counts already computed in `_refresh()`.
  Widget _buildSyncStatusCard() {
    final queued = _pendingRows.length;
    final detail = <String>[
      if (_pendingBytes > 0) _formatBytes(_pendingBytes),
      if (_photosWaiting > 0)
        '$_photosWaiting ${_photosWaiting == 1 ? 'evidence attachment' : 'evidence attachments'}',
      if (_checklistWaiting > 0) '$_checklistWaiting checklists',
      if (_gpsWaiting > 0) '$_gpsWaiting GPS',
    ];
    final segments = <Widget>[];
    void addSegment(int count, Color color) {
      if (count <= 0) return;
      segments.add(
        Expanded(
          flex: count,
          child: Container(color: color),
        ),
      );
      segments.add(const SizedBox(width: 2));
    }

    addSegment(_photosWaiting, InsightTheme.blue1);
    addSegment(_checklistWaiting, InsightTheme.blueInk);
    addSegment(_gpsWaiting, InsightTheme.amber);
    if (segments.isNotEmpty) segments.removeLast();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: InsightTheme.surface,
        borderRadius: InsightTheme.roundedMd,
        border: Border.all(color: InsightTheme.line),
        boxShadow: InsightTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      queued == 0
                          ? 'No queued updates'
                          : '$queued ${queued == 1 ? 'change' : 'changes'} waiting',
                      style: InsightTheme.urbanist(
                        20,
                        w: FontWeight.w800,
                        c: InsightTheme.ink,
                        ls: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      queued == 0
                          ? 'No changes waiting to send.'
                          : detail.isEmpty
                              ? 'Saved on this device, waiting to send.'
                              : detail.join(' · '),
                      style: InsightTheme.inter(12, c: InsightTheme.ink3),
                    ),
                  ],
                ),
              ),
              _sectionHelpButton(
                title: 'Sync Performance',
                message:
                    'This shows whether your inspection updates are being sent successfully. Information completed while offline may wait here until an internet connection is available. Once you are back online, the app can send the waiting information to the system.',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _StorageStatItem(
                  label: 'Synced (recent)',
                  value: '${_syncedRows.length}',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StorageStatItem(
                  label: 'Pending queue',
                  value: '$queued',
                  valueColor: InsightTheme.blueInk,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StorageStatItem(
                  label: 'Pending size',
                  value: _formatBytes(_pendingBytes),
                ),
              ),
            ],
          ),
          if (queued > 0 &&
              (_photosWaiting + _checklistWaiting + _gpsWaiting) > 0) ...[
            const SizedBox(height: 14),
            Container(
              height: 6,
              decoration: BoxDecoration(
                color: InsightTheme.surface2,
                borderRadius: BorderRadius.circular(999),
              ),
              clipBehavior: Clip.antiAlias,
              child: segments.isEmpty
                  ? const SizedBox.shrink()
                  : Row(children: segments),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                _SyncLegendItem(
                  color: InsightTheme.blue1,
                  label: 'Evidence files',
                  value: _photosWaiting,
                ),
                _SyncLegendItem(
                  color: InsightTheme.blueInk,
                  label: 'Checklists',
                  value: _checklistWaiting,
                ),
                _SyncLegendItem(
                  color: InsightTheme.amber,
                  label: 'GPS',
                  value: _gpsWaiting,
                ),
              ],
            ),
          ],
          ValueListenableBuilder<SyncProgress?>(
            valueListenable: SyncOutboxService.progress,
            builder: (context, progress, _) {
              final busy = _syncingNow || progress != null;
              // No queue and no live drain: no dead primary action.
              if (queued == 0 && progress == null) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton(
                      onPressed: busy ? null : _handleSyncNow,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        backgroundColor: InsightTheme.blue1,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: InsightTheme.blueTint,
                        disabledForegroundColor: InsightTheme.blueInk,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: InsightTheme.inter(14, w: FontWeight.w700),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (busy)
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: InsightTheme.blueInk,
                              ),
                            )
                          else
                            const Icon(Icons.sync_rounded, size: 18),
                          const SizedBox(width: 8),
                          Flexible(child: Text(busy ? 'Syncing...' : 'Sync now')),
                        ],
                      ),
                    ),
                    if (progress != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            progress.displayText,
                            style: InsightTheme.inter(
                              12,
                              w: FontWeight.w600,
                              c: InsightTheme.blueInk,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Surfaces paused, failed and conflicted rows above the queue.
  Widget _buildAttentionCard() {
    final needsAttention = _attentionRows;
    if (needsAttention.isEmpty) return const SizedBox.shrink();
    final first = needsAttention.first;
    final jobs = needsAttention.map((row) => row['job_id']).toSet().length;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: InsightTheme.amberTint,
        borderRadius: InsightTheme.roundedMd,
        border: Border.all(color: InsightTheme.amber.withValues(alpha: 0.26)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 20,
            color: InsightTheme.amberInk,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${needsAttention.length} ${needsAttention.length == 1 ? 'update needs' : 'updates need'} attention',
                  style: InsightTheme.inter(
                    12.5,
                    w: FontWeight.w700,
                    c: InsightTheme.amberInk,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '$jobs ${jobs == 1 ? 'task' : 'tasks'} · ${_statusTextFor(first)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: InsightTheme.inter(11, c: InsightTheme.amberInk),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _reviewAttention,
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 44),
              padding: const EdgeInsets.symmetric(horizontal: 11),
              backgroundColor: InsightTheme.surface,
              foregroundColor: InsightTheme.amberInk,
              side: BorderSide(color: InsightTheme.amber.withValues(alpha: 0.30)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Review',
                  style: InsightTheme.inter(
                    11.5,
                    w: FontWeight.w700,
                    c: InsightTheme.amberInk,
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Queue section header + the existing per-task queue cards.
  Widget _buildQueueSection() {
    return Column(
      key: _queueSectionKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Waiting to sync',
                style: InsightTheme.urbanist(
                  13,
                  w: FontWeight.w700,
                  c: InsightTheme.ink2,
                ),
              ),
            ),
            Text(
              '${_pendingRows.length}',
              style: InsightTheme.inter(12, c: InsightTheme.ink3),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_pendingRows.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: InsightTheme.surface,
              borderRadius: InsightTheme.roundedMd,
              border: Border.all(color: InsightTheme.line),
            ),
            child: Text(
              'No queued inspection updates.',
              style: InsightTheme.inter(12, c: InsightTheme.ink3),
            ),
          )
        else
          ..._buildPendingCards(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    return SensitiveScreen(
      child: Scaffold(
        backgroundColor: InsightTheme.bg,
        extendBody: true,
        body: Stack(
          children: [
            SafeArea(
              bottom: false,
              child: _loading
                  ? const Center(
                      child: ImapsLoadingIndicator(
                        size: 60,
                        label: "Syncing data...",
                      ),
                    )
                  : Column(
                      children: [
                        // 1. HEADER CARD — same card language as Home, Tasks
                        // and Profile instead of a full-bleed app bar.
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                          child: Container(
                            width: double.infinity,
                            key: const ValueKey('sync_header'),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: InsightTheme.surface,
                              borderRadius: InsightTheme.roundedLg,
                              border: Border.all(color: InsightTheme.line),
                              boxShadow: InsightTheme.cardShadow,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Semantics(
                                        header: true,
                                        child: Text(
                                          'Sync Center',
                                          style: InsightTheme.urbanist(
                                            24,
                                            w: FontWeight.w800,
                                            c: InsightTheme.ink,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Row(
                                        children: [
                                          Container(
                                            width: 6,
                                            height: 6,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: _isOnline
                                                  ? InsightTheme.green
                                                  : InsightTheme.red,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            _isOnline ? 'Online' : 'Offline',
                                            style: InsightTheme.inter(
                                              12,
                                              w: FontWeight.w600,
                                              c: _isOnline
                                                  ? InsightTheme.greenInk
                                                  : InsightTheme.redInk,
                                            ),
                                          ),
                                          Text(
                                            ' · ',
                                            style: InsightTheme.inter(
                                              12,
                                              c: InsightTheme.ink3,
                                            ),
                                          ),
                                          Flexible(
                                            child: Text(
                                              'Last sync: ${_relativeTime(_lastSync)}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: InsightTheme.inter(
                                                12,
                                                w: FontWeight.w500,
                                                c: InsightTheme.ink3,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                _sectionHelpButton(
                                  title: 'Sync Center',
                                  message:
                                      'The Sync Center helps you manage your inspection information when working with or without an internet connection. When you are offline, the app keeps the information you need on your phone so you can continue working. When your internet connection returns, the app sends the information that is waiting to the system and updates the sync status.\n\nOffline to Online: If you complete or update an inspection while offline, the information stays safely on your phone while it is waiting to be sent. Once you are back online, the app can send the waiting information to the system. The Sync Center lets you check whether those updates have already been sent or are still waiting.',
                                ),
                              ],
                            ),
                          ),
                        ),

                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: () => _refresh(replay: true),
                            child: ConstrainedContent.wide(
                              child: ListView(
                                key: const ValueKey('sync_body'),
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.only(
                                  bottom: kInsightBottomNavReserve,
                                ),
                                children: [
                                  const SizedBox(height: 16),

                                  // 2. ONE STATUS CARD — headline, composition,
                                  // legend and the single primary action.
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                    ),
                                    child: SpringScale(
                                      animation: springFor(1),
                                      beginScale: 0.92,
                                      child: _buildSyncStatusCard(),
                                    ),
                                  ),

                                  if (_attentionRows.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                      ),
                                      child: _buildAttentionCard(),
                                    ),
                                  ],

                                  // 3. QUEUE FIRST — waiting items sit directly
                                  // under the status card, before history and
                                  // storage.
                                  const SizedBox(height: 16),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                    ),
                                    child: _buildQueueSection(),
                                  ),

                                  const SizedBox(height: 18),

                                  // Compressed secondary row: synchronization
                                  // history.
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                    ),
                                    child: Material(
                                      color: InsightTheme.surface,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: InsightTheme.roundedMd,
                                        side: const BorderSide(
                                          color: InsightTheme.line,
                                        ),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: InkWell(
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const NotificationsScreen(
                                                  initialMode: 1,
                                                ),
                                          ),
                                        ),
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            minHeight: 56,
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.all(16),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                Row(
                                                  children: [
                                                    const Icon(
                                                      Icons.refresh_rounded,
                                                      size: 18,
                                                      color: InsightTheme.ink2,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Column(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment.start,
                                                        children: [
                                                          Text(
                                                            'Synchronization history',
                                                            style: InsightTheme.inter(
                                                              12.5,
                                                              w: FontWeight.w600,
                                                              c: InsightTheme.ink,
                                                            ),
                                                          ),
                                                          const SizedBox(height: 4),
                                                          Text(
                                                            _syncHistorySummary(),
                                                            style: InsightTheme.inter(
                                                              12,
                                                              w: FontWeight.w500,
                                                              c: InsightTheme.ink3,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    _sectionHelpButton(
                                                      title:
                                                          'Synchronization Audit History',
                                                      message:
                                                          'This keeps a record of attempts to send your inspection information to the system. It helps you check when information was sent and whether the update was successful.',
                                                    ),
                                                    const Icon(
                                                      Icons.chevron_right_rounded,
                                                      size: 18,
                                                      color: InsightTheme.ink3,
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  _lastSync == null
                                                      ? 'Last successful action: Not recorded'
                                                      : 'Last successful action: ${_formatDeviceTime(_lastSync!)} (device time)',
                                                  style: InsightTheme.inter(
                                                    12,
                                                    w: FontWeight.w500,
                                                    c: InsightTheme.ink3,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 10),

                                  // 4. STORAGE — compact card, all three real
                                  // figures kept.
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.fromLTRB(
                                        14,
                                        10,
                                        14,
                                        10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: InsightTheme.surface,
                                        borderRadius: InsightTheme.roundedMd,
                                        border: Border.all(
                                          color: InsightTheme.line,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.sd_storage_rounded,
                                                size: 18,
                                                color: InsightTheme.blueInk,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  'Offline storage',
                                                  style: InsightTheme.inter(
                                                    12.5,
                                                    w: FontWeight.w600,
                                                    c: InsightTheme.ink,
                                                  ),
                                                ),
                                              ),
                                              _sectionHelpButton(
                                                title: 'Offline Storage Cache',
                                                message:
                                                    'This shows the inspection information currently saved on your phone for offline work. This allows you to continue accessing and working on available tasks even without an internet connection.',
                                              ),
                                              Flexible(
                                                child: Tooltip(
                                                  message: _clearableBytes > 0
                                                      ? 'Clear ${_formatBytes(_clearableBytes.toDouble())} of synced evidence cache'
                                                      : 'Evidence cache is already clear',
                                                  child: TextButton(
                                                    onPressed:
                                                        (_clearingCache ||
                                                            _clearableBytes == 0)
                                                        ? null
                                                        : _handleClearCache,
                                                    style: TextButton.styleFrom(
                                                      minimumSize:
                                                          const Size(48, 44),
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 4,
                                                          ),
                                                      foregroundColor:
                                                          InsightTheme.blueInk,
                                                      disabledForegroundColor:
                                                          InsightTheme.ink3,
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                      ),
                                                    ),
                                                    child: _clearingCache
                                                        ? const SizedBox(
                                                            width: 14,
                                                            height: 14,
                                                            child:
                                                                CircularProgressIndicator(
                                                                  strokeWidth: 2,
                                                                ),
                                                          )
                                                        : Text(
                                                            'Clear evidence cache',
                                                            textAlign:
                                                                TextAlign.right,
                                                            style:
                                                                InsightTheme.inter(
                                                                  11.5,
                                                                  w: FontWeight
                                                                      .w700,
                                                                  c: _clearableBytes >
                                                                          0
                                                                      ? InsightTheme
                                                                            .blueInk
                                                                      : InsightTheme
                                                                            .ink3,
                                                                ),
                                                          ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Container(
                                            padding: const EdgeInsets.only(
                                              top: 6,
                                            ),
                                            decoration: const BoxDecoration(
                                              border: Border(
                                                top: BorderSide(
                                                  color: InsightTheme.line,
                                                ),
                                              ),
                                            ),
                                            child: LayoutBuilder(
                                              builder: (context, constraints) {
                                                final columns =
                                                    ((constraints.maxWidth + 8) /
                                                            (MediaQuery.textScalerOf(
                                                                      context,
                                                                    ).scale(80) +
                                                                    8))
                                                        .floor()
                                                        .clamp(1, 3);
                                                final width =
                                                    (constraints.maxWidth -
                                                        (columns - 1) * 8) /
                                                    columns;
                                                return Wrap(
                                                  spacing: 8,
                                                  runSpacing: 8,
                                                  children: [
                                                    SizedBox(
                                                      width: width,
                                                      child: _StorageStatItem(
                                                        label: 'Cached jobs',
                                                        value:
                                                            '$_cachedJobsCount',
                                                      ),
                                                    ),
                                                    SizedBox(
                                                      width: width,
                                                      child: _StorageStatItem(
                                                        label: 'Unsynced files',
                                                        value:
                                                            '$_unsyncedPhotoFileCount',
                                                      ),
                                                    ),
                                                    SizedBox(
                                                      width: width,
                                                      child: _StorageStatItem(
                                                        label: 'Reclaimable',
                                                        value: _formatBytes(
                                                          _clearableBytes
                                                              .toDouble(),
                                                        ),
                                                        valueColor:
                                                            _clearableBytes > 0
                                                            ? InsightTheme
                                                                  .amberInk
                                                            : null,
                                                      ),
                                                    ),
                                                  ],
                                                );
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 18),

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
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              width: 3,
                                              height: 12,
                                              decoration: BoxDecoration(
                                                color: InsightTheme.ink3,
                                                borderRadius:
                                                    BorderRadius.circular(2),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'COMPLETED AUDIT LOG',
                                                style: InsightTheme.jetBrains(
                                                  12,
                                                  w: FontWeight.w700,
                                                  ls: 1.2,
                                                  c: InsightTheme.ink3,
                                                ),
                                              ),
                                            ),
                                            _sectionHelpButton(
                                              title: 'Completed Audit Log',
                                              message:
                                                  'This shows inspection updates that have already been successfully sent to the system. It helps you confirm that your completed work has been received.',
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),

                                        if (_syncedRows.isEmpty)
                                          Container(
                                            padding: const EdgeInsets.all(16),
                                            decoration: BoxDecoration(
                                              color: InsightTheme.surface,
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              border: Border.all(
                                                color: InsightTheme.line,
                                              ),
                                            ),
                                            child: Text(
                                              'No received updates recorded for this account. Successfully delivered updates appear here with their device receipt.',
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
                                              borderRadius:
                                                  BorderRadius.circular(16),
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
                                                    beginOffset: const Offset(
                                                      0,
                                                      22,
                                                    ),
                                                    child: UpdatingTile(
                                                      itemKey:
                                                          _syncedRows[i]['id'] ??
                                                          i,
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
                                                        receiptLines:
                                                            _receiptLinesFor(
                                                              _syncedRows[i],
                                                            ),
                                                        isPending: false,
                                                      ),
                                                    ),
                                                  ),
                                                  if (i !=
                                                      _syncedRows.length - 1)
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
                        ),
                      ],
                    ),
            ),
          ],
        ),

        // Bottom navigation now lives solely in MainShellScreen (the app
        // shell). This screen no longer renders its own nav bar — see
        // NAVIGATION_REFACTOR.md for why the duplicate, per-page nav bar
        // was removed.
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
          value,
          style: InsightTheme.urbanist(
            13,
            w: FontWeight.w700,
            c: valueColor ?? InsightTheme.ink,
            h: 1.2,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          label,
          style: InsightTheme.inter(
            10,
            w: FontWeight.w500,
            c: InsightTheme.ink3,
          ),
        ),
      ],
    );
  }
}

class _SyncLegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final int value;

  const _SyncLegendItem({
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          '$label $value',
          style: InsightTheme.inter(
            10.5,
            w: FontWeight.w600,
            c: InsightTheme.ink3,
          ),
        ),
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
  final List<String> receiptLines;
  final bool isPending;
  final bool isSyncing;
  final bool isFailed;
  final bool isConflict;

  const _LogDataRow({
    required this.icon,
    required this.title,
    required this.dataType,
    required this.dataSize,
    required this.statusText,
    required this.isPending,
    this.receiptLines = const [],
    this.isSyncing = false,
    this.isFailed = false,
    this.isConflict = false,
  });

  @override
  Widget build(BuildContext context) {
    final accentTint = isFailed ? InsightTheme.redTint : InsightTheme.amberTint;
    final accentInk = isFailed ? InsightTheme.redInk : InsightTheme.amberInk;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: isPending ? 8 : 12,
      ),
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
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dataType,
                  style: InsightTheme.inter(12, c: InsightTheme.ink2),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: InsightTheme.inter(
                    13.5,
                    w: FontWeight.w700,
                    c: InsightTheme.ink,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isSyncing && !isConflict && !isFailed)
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: InsightTheme.blueInk,
                        ),
                      )
                    else
                      Icon(
                        !isPending
                            ? Icons.check_circle_rounded
                            : isConflict
                            ? Icons.warning_rounded
                            : isFailed
                            ? Icons.error_rounded
                            : Icons.schedule_rounded,
                        size: 14,
                        color: !isPending ? InsightTheme.greenInk : accentInk,
                      ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        statusText,
                        style: InsightTheme.inter(
                          12,
                          w: FontWeight.w600,
                          c: isPending ? accentInk : InsightTheme.ink3,
                        ),
                      ),
                    ),
                  ],
                ),
                for (final line in receiptLines)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      line,
                      style: InsightTheme.inter(11.5, c: InsightTheme.ink2),
                    ),
                  ),
                if (dataSize != '—' && dataSize.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      dataSize,
                      style: InsightTheme.jetBrains(
                        12,
                        w: FontWeight.w600,
                        c: InsightTheme.ink2,
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
