import 'package:flutter/foundation.dart';
import '../services/supabase_service.dart';
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

  /// Makes sure progress belongs to the task currently open. If the
  /// inspector opens a different task, progress starts fresh instead of
  /// carrying over from whatever they were last inspecting.
  void ensureActiveInspection(String taskId, {String? label}) {
    if (_activeTaskId != taskId) {
      _activeTaskId = taskId;
      _highestCompleted = 0;
    }
    _activeTaskLabel = label ?? _activeTaskLabel;
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