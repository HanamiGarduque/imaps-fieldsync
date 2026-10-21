import 'dart:convert';

import 'package:flutter/foundation.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/db_helper.dart';
import '../../../core/services/sync_outbox_service.dart';
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

  /// Steps 3, 4 and 5 are independent: once Step 2 is verified the
  /// inspector may complete them in any order. Steps 1 and 2 stay strictly
  /// sequential because Step 2 is the verified anchor of the whole protocol.
  static const List<int> flexibleSteps = [3, 4, 5];

  int _highestCompleted = 0; // 0 = nothing done yet

  /// The real, per-step completion of the independent steps 3, 4 and 5.
  /// This is never inferred from "a later step was reached": the persisted
  /// step_timestamps map is the record, so finishing Step 5 first does not
  /// pretend that Steps 3 and 4 are done.
  final Set<int> _completedSteps = {};

  // F1 fix (per-step saved times): records the real moment each step's
  // save/proceed button fired, for the ACTIVE task only. Keyed by step
  // number (1-6), value is a UTC ISO8601 string. Persisted alongside
  // current_step into both SQLite (local_inspections.step_timestamps) and
  // Supabase (field_jobs.step_timestamps) so Task Overview can show real
  // per-task, per-step times instead of simulated ones.
  final Map<int, String> _stepCompletedAt = {};

  // Keyed by task.id (the real field_jobs primary key) — NOT inspectionNo
  // (reference_number). Reference numbers can repeat across different
  // field_jobs rows (e.g. two jobs pointing at the same application, which
  // is exactly what our own test data did), and keying by that caused
  // progress to silently carry over into an unrelated task.
  String? _activeTaskId;
  String? _activeTaskLabel;
  String? _inspectorId;

  // FIX (device-test finding — "progress showed 1/6 after reaching step 2"):
  // markStepComplete() used to fire _persistCurrentStep() unawaited, so two
  // steps completed in quick succession (e.g. Step 1 → Step 2, normal
  // fast navigation) started two independent, concurrent background
  // writes to the *same* outbox row (current_step_update is deduped per
  // job). There's no ordering guarantee between two unawaited async
  // calls — Step 1's write (which also does its own connectivity check)
  // could finish *after* Step 2's, silently overwriting the newer step
  // with the older one. Root cause was a race in write ordering, not a
  // missed write or a Sync Center conflict — this queue makes every
  // persistence call for this task wait for the previous one to finish
  // first, so writes always apply in the order steps were actually
  // completed, regardless of how fast each one's own I/O happens to be.
  Future<void> _persistQueue = Future.value();

  int get highestCompleted => _inspectorId == DBHelper.currentInspectorId ? _highestCompleted : 0;

  /// How many of the six steps are genuinely complete. For a sequential
  /// inspection this equals the highest reached step; for the independent
  /// steps 3-5 it counts the ones that really have a saved completion.
  int get completedStepCount {
    var count = 0;
    for (var step = 1; step <= totalSteps; step++) {
      if (isDone(step)) count++;
    }
    return count;
  }

  /// The next step the inspector should work on: the first one that is not
  /// complete yet. With independent steps 3-5 this is the lowest unfinished
  /// one, not simply "the step after the highest reached".
  int get currentStep {
    for (var step = 1; step < totalSteps; step++) {
      if (!isDone(step)) return step;
    }
    return totalSteps;
  }

  bool get isComplete => highestCompleted >= totalSteps;

  /// True only when this step really has a saved completion of its own.
  bool isDone(int step) {
    if (step <= 2) return step <= _highestCompleted;
    if (step <= 5) return _completedSteps.contains(step);
    return _highestCompleted >= totalSteps;
  }

  bool isCurrent(int step) => step == currentStep;

  /// Steps 3-5 unlock together once Step 2 is verified. Step 6 stays locked
  /// until every one of them is genuinely complete.
  bool isLocked(int step) {
    if (step <= 2) return step > _highestCompleted + 1;
    if (step <= 5) return _highestCompleted < 2;
    return !_allFlexibleStepsComplete;
  }

  bool get _allFlexibleStepsComplete =>
      flexibleSteps.every(_completedSteps.contains);

  /// The first of the independent steps that still needs work, or null when
  /// Steps 3, 4 and 5 are all complete (the review is next).
  int? get nextIncompleteFlexibleStep {
    for (final step in flexibleSteps) {
      if (!_completedSteps.contains(step)) return step;
    }
    return null;
  }

  String get currentStepTitle => stepTitles[currentStep - 1];

  /// Real saved time for a step of the ACTIVE task, if recorded this
  /// session. Callers fall back to the task's stored step_timestamps for
  /// times saved in earlier sessions.
  String? completedAtFor(int step) => _stepCompletedAt[step];

  Map<int, String> get stepCompletedAt => Map.unmodifiable(_stepCompletedAt);

  /// Call when a step's "Continue" action fires, right before navigating
  /// forward. Steps 1 and 2 must be completed in order; steps 3, 4 and 5 may
  /// be completed in any order once Step 2 is verified.
  void markStepComplete(int step) {
    if (_inspectorId == null || _inspectorId != DBHelper.currentInspectorId) {
      return;
    }
    if (step < 1 || step > totalSteps) return;
    if (step == 1) {
      if (_highestCompleted >= 1) return;
    } else if (step == 2) {
      // Step 2 is the verified anchor; it needs a completed Step 1.
      if (_highestCompleted < 1) return;
    } else if (step <= 5) {
      // The independent steps need a verified Step 2, and each one counts
      // only once.
      if (_highestCompleted < 2) return;
      if (_completedSteps.contains(step)) return;
    } else {
      // Step 6 needs every earlier step, whatever order they were done in.
      if (!_allFlexibleStepsComplete) return;
      if (_highestCompleted >= totalSteps) return;
    }
    _completeStep(step);
  }

  void _completeStep(int step) {
    // F1 fix: stamp the real moment this save/proceed happened. Every
    // task gets its own times because this map is cleared whenever the
    // active task changes and each entry is persisted per job id.
    _stepCompletedAt[step] = DateTime.now().toUtc().toIso8601String();
    if (step >= 3 && step <= 5) _completedSteps.add(step);
    if (step > _highestCompleted) _highestCompleted = step;
    notifyListeners();

    if (_activeTaskId != null) {
      // Capture taskId now, not inside the deferred closure below — by
      // the time this queued write actually runs, the inspector could
      // have already switched to a different task, and _activeTaskId
      // would no longer be the one this particular step belongs to.
      final taskId = _activeTaskId!;
      final uid = _inspectorId!;
      final timestamps = _stepCompletedAt.map((k,v) => MapEntry(k.toString(),v));
      // current_step is the highest step reached and never regresses; the
      // independent completion of steps 3-5 travels in step_timestamps.
      final reached = _highestCompleted;
      _persistQueue = _persistQueue.then((_) => _persistCurrentStep(taskId, reached, uid, timestamps));
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

  /// Saves the exact step number to SQLite (always) and Supabase (best-
  /// effort, if online). This gives us a real stored value alongside the
  /// derivedHighestStep heuristic — belt-and-suspenders, doesn't replace it.
  Future<void> _persistCurrentStep(String taskId, int step, String uid,
      Map<String,String> timestamps) async {
    try {
      await DBHelper.saveInspectionStep(taskId, step, timestamps, uid);
    } catch (e) {
      debugPrint('_persistCurrentStep (SQLite) failed: $e');
      return;
    }

    try {
      final dynamic connectivityResult = await Connectivity().checkConnectivity();
      final online = connectivityResult is List
          ? connectivityResult.any((r) => r != ConnectivityResult.none)
          : connectivityResult != ConnectivityResult.none;
      DBHelper.requireSameInspector(uid);
      if (online) {
        final result = await SupabaseService.advanceJobInspectionProgress(
          jobId: taskId,
          currentStep: step,
          stepTimestamps:
               timestamps,
        );
        result.requireAuthorized();
      } else {
        await SyncOutboxService.enqueueCurrentStepUpdate(
          jobId: taskId,
          step: step,
          stepTimestamps:
               timestamps,
        );
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
        DBHelper.requireSameInspector(uid);
        await SyncOutboxService.enqueueCurrentStepUpdate(
          jobId: taskId,
          step: step,
          stepTimestamps:
               timestamps,
        );
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
  void ensureActiveInspection(
    String taskId, {
    String? label,
    int? initialStep,
    Map<String, String>? stepTimestamps,
  }) {
    final uid = DBHelper.currentInspectorId;
    final isDifferentTask = _activeTaskId != taskId || _inspectorId != uid;
    _inspectorId = uid;
    _activeTaskId = taskId;
    _activeTaskLabel = label ?? _activeTaskLabel;
    // F1 fix: per-step saved times belong to one task only — a different
    // task must never inherit another task's timestamps.
    if (isDifferentTask) {
      _stepCompletedAt.clear();
      _completedSteps.clear();
    }
    if (initialStep != null) {
      _highestCompleted = initialStep;
    } else if (isDifferentTask) {
      // No fresh step data supplied — fall back to "different task, start
      // fresh" rather than carrying over the previous task's progress.
      _highestCompleted = 0;
    }
    _hydrateCompletedSteps(initialStep ?? _highestCompleted, stepTimestamps);
  }

  /// Restores the independent completion of steps 3-5 from the persisted
  /// per-step times. A draft saved before the steps became independent has
  /// no per-step times for them, and its highest reached step therefore
  /// stands for all of them — that is the historical meaning of a sequential
  /// inspection, and it is honoured only for those drafts.
  void _hydrateCompletedSteps(int highestReached, Map<String, String>? times) {
    _completedSteps.removeWhere((step) => step > 5);
    times?.forEach((key, value) {
      final step = int.tryParse(key);
      if (step == null || value.isEmpty) return;
      if (step >= 1 && step <= totalSteps) {
        _stepCompletedAt.putIfAbsent(step, () => value);
      }
    });
    _completedSteps.addAll(
      deriveCompletedSteps(
        highestReached,
        times?.map(
              (key, value) => MapEntry(int.tryParse(key) ?? 0, value),
            ) ??
            const <int, String>{},
      ),
    );
  }

  /// Decodes a stored step_timestamps value (JSON object of step -> time).
  static Map<int, String> decodeStepTimestamps(Object? raw) {
    final times = <int, String>{};
    if (raw is! String || raw.isEmpty) return times;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return times;
      decoded.forEach((key, value) {
        final step = int.tryParse(key.toString());
        if (step != null && value is String && value.isNotEmpty) {
          times[step] = value;
        }
      });
    } catch (_) {
      // An unreadable record simply proves nothing.
    }
    return times;
  }

  /// The independent steps that are genuinely complete for a stored draft.
  ///
  /// A record that carries the sequential prefix (steps 1 and 2) was written
  /// by the app that knows the independent steps, so its per-step times for
  /// steps 3-5 are authoritative. A record without that prefix predates
  /// them, and its highest reached step then stands for all of them - the
  /// historical meaning of a sequential inspection.
  static Set<int> deriveCompletedSteps(
    int highestReached,
    Map<int, String>? stepTimes,
  ) {
    final completed = <int>{};
    stepTimes?.forEach((step, value) {
      if (step >= 3 && step <= 5 && value.isNotEmpty) completed.add(step);
    });
    final hasSequentialPrefix = (stepTimes?[1]?.isNotEmpty ?? false) &&
        (stepTimes?[2]?.isNotEmpty ?? false);
    if (hasSequentialPrefix) return completed;
    for (var step = 3; step <= 5; step++) {
      if (step <= highestReached) completed.add(step);
    }
    return completed;
  }

  /// The inspection this progress belongs to.
  String? get activeTaskId => _activeTaskId;

  /// The independent steps completed in this session.
  Set<int> get completedSteps => Set.unmodifiable(_completedSteps);

  void reset() {
    _highestCompleted = 0;
    _activeTaskId = null;
    _activeTaskLabel = null;
    _inspectorId = null;
    _stepCompletedAt.clear();
    _completedSteps.clear();
    notifyListeners();
  }

  /// Used when opening an already-completed inspection for viewing/rework.
  /// Every step has real submitted data, so every step should be tappable —
  /// unlike a fresh inspection, the inspector shouldn't have to redo step 1
  /// just to look at (or fix) step 5.
  void unlockAllForReview(String taskId, {String? label}) {
    final isDifferentTask = _activeTaskId != taskId;
    _activeTaskId = taskId;
    _activeTaskLabel = label ?? _activeTaskLabel;
    _highestCompleted = totalSteps;
    _completedSteps.addAll(flexibleSteps);
    // F1 fix: same per-task isolation as ensureActiveInspection.
    if (isDifferentTask) _stepCompletedAt.clear();
    notifyListeners();
  }
}
