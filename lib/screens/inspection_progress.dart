import 'package:flutter/foundation.dart';
import '../services/supabase_service.dart';
import '../services/db_helper.dart';
import '../services/sync_outbox_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
/// ==================================================================
/// INSPECTION PROGRESS TRACKER
/// ==================================================================
/// A single, shared source of truth for how far the inspector has
/// gotten through the 6-step inspection workflow:
///   1. Site verification   4. Checklist
///   2. GPS verification    5. Findings
///   3. Photos               6. Review & submit
///
/// Every screen in the workflow reads/writes this instead of guessing
/// its own step number, which is what caused the step labels and
/// progress bars to disagree with each other before.
class InspectionProgress extends ChangeNotifier {
  InspectionProgress._();
  static final InspectionProgress instance = InspectionProgress._();

  static const int totalSteps = 6;

  static const List<String> stepTitles = [
    'Site verification',
    'GPS verification',
    'Photos',
    'Checklist',
    'Findings',
    'Review & submit',
  ];

  int _highestCompleted = 0; // 0 = nothing done yet

  // Keyed by task.id (the real field_jobs primary key) — NOT inspectionNo
  // (reference_number). Reference numbers can repeat across different
  // field_jobs rows (e.g. two jobs pointing at the same application, which
  // is exactly what our own test data did), and keying by that caused
  // progress to silently carry over into an unrelated task.
  String? _activeTaskId;
  String? _activeTaskLabel;

  int get highestCompleted => _highestCompleted;
  int get currentStep => (_highestCompleted + 1).clamp(1, totalSteps);
  bool get isComplete => _highestCompleted >= totalSteps;
  bool isDone(int step) => step <= _highestCompleted;
  bool isCurrent(int step) => step == currentStep;
  bool isLocked(int step) => step > currentStep;
  String get currentStepTitle => stepTitles[currentStep - 1];

  /// Call when a step's "Continue" action fires, right before navigating
  /// forward. Steps can only be completed in order.
  void markStepComplete(int step) {
    if (step == _highestCompleted + 1) {
      _highestCompleted = step;
      notifyListeners();

      if (_activeTaskId != null) {
        _persistCurrentStep(_activeTaskId!, step);
      }

      if (step < totalSteps && _activeTaskId != null) {
        SupabaseService.logActivity(
          eventType: 'step_completed',
          title: 'Completed Step $step: ${stepTitles[step - 1]}',
          subtitle: _activeTaskLabel,
          fieldJobId: _activeTaskId,
        );
      }
    }
  }

  /// Saves the exact step number to SQLite (always) and Supabase (best-
  /// effort, if online). This gives us a real stored value alongside the
  /// derivedHighestStep heuristic — belt-and-suspenders, doesn't replace it.
  Future<void> _persistCurrentStep(String taskId, int step) async {
    try {
      final db = await DBHelper.database;
      final existing = await DBHelper.getLocalInspection(taskId);
      if (existing != null) {
        await db.update(
          'local_inspections',
          {'current_step': step, 'updated_at': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [taskId],
        );
      } else {
        await db.insert('local_inspections', {
          'id': taskId,
          'current_step': step,
          'is_synced': 0,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint('_persistCurrentStep (SQLite) failed: $e');
    }

    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      final online = connectivityResult is List
          ? (connectivityResult as List).any((r) => r != ConnectivityResult.none)
          : connectivityResult != ConnectivityResult.none;
      if (online) {
        await SupabaseService.updateJobInspectionProgress(
          jobId: taskId,
          updateData: {'current_step': step},
        );
      } else {
        await SyncOutboxService.enqueueCurrentStepUpdate(jobId: taskId, step: step);
      }
    } catch (e) {
      // ROOT-CAUSE FIX (2026-07-23): this used to be a dead-end — if this
      // call failed (most commonly because the device was offline, but
      // also on any transient Supabase error), the exception was just
      // debugPrint'd and the step update was lost forever. There was no
      // outbox fallback here, unlike every other offline-capable write in
      // the app (GPS confirm, checklist, submit). That's why current_step
      // in Supabase could stay stuck at 0 (or any earlier value)
      // indefinitely even after the inspector had clearly moved forward,
      // online or offline — this function is the one every screen actually
      // calls (via InspectionProgress.instance.markStepComplete()).
      // (2026-07-24: the old duplicate persistence path,
      // InspectionProvider.updateStep(), was confirmed unused and removed —
      // this is now the only writer of current_step.)
      debugPrint('_persistCurrentStep (Supabase) failed, queuing for retry — $e');
      try {
        await SyncOutboxService.enqueueCurrentStepUpdate(jobId: taskId, step: step);
      } catch (e2) {
        debugPrint('_persistCurrentStep: failed to queue current_step update — $e2');
      }
    }
  }

  /// Makes sure progress belongs to the task currently open. If the
  /// inspector opens a different task, progress starts fresh instead of
  /// carrying over from whatever they were last inspecting.
  ///
  /// FIX (2026-07-24) — Finding B (Pending audit): this used to only reset
  /// `_highestCompleted` when `taskId` differed from whatever was already
  /// active. Since this singleton's `_activeTaskId` is never cleared just by
  /// backing out of the hub screen (only `reset()` does, called from the
  /// review/submit screen), re-opening the SAME task a second time in one
  /// app session — without opening a different task in between — hit the
  /// `_activeTaskId == taskId` case and silently kept whatever stale
  /// in-memory `_highestCompleted` was left over, ignoring the freshly
  /// re-fetched `initialStep` entirely. That could show the wrong current
  /// step if the real progress had changed in the meantime (a sync from
  /// another device, or a rework flow completing steps) — a direct
  /// violation of "status must depend only on stored data, never the
  /// screen/session." Now every call with a non-null `initialStep` — i.e.
  /// every real entry into the hub screen — re-syncs from that fresh value,
  /// whether or not the task id changed. `initialStep` is itself derived
  /// from `task.currentStep`/`derivedHighestStep`, which are already kept
  /// current by the Bug 1 fix, so trusting it here is exactly "always read
  /// from the database, not from what the UI happened to have in memory."
  void ensureActiveInspection(String taskId, {String? label, int? initialStep}) {
    final isDifferentTask = _activeTaskId != taskId;
    _activeTaskId = taskId;
    _activeTaskLabel = label ?? _activeTaskLabel;
    if (initialStep != null) {
      _highestCompleted = initialStep;
    } else if (isDifferentTask) {
      // No fresh step data supplied — fall back to "different task, start
      // fresh" rather than carrying over the previous task's progress.
      _highestCompleted = 0;
    }
  }

  void reset() {
    _highestCompleted = 0;
    _activeTaskId = null;
    _activeTaskLabel = null;
    notifyListeners();
  }

  /// Used when opening an already-completed inspection for viewing/rework.
  /// Every step has real submitted data, so every step should be tappable —
  /// unlike a fresh inspection, the inspector shouldn't have to redo step 1
  /// just to look at (or fix) step 5.
  void unlockAllForReview(String taskId, {String? label}) {
    _activeTaskId = taskId;
    _activeTaskLabel = label ?? _activeTaskLabel;
    _highestCompleted = totalSteps;
    notifyListeners();
  }
}