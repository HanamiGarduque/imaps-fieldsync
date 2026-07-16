import 'package:flutter/foundation.dart';

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
/// progress bars to disagree with each other before. It's plain
/// in-memory state (no backend) — good enough for a static prototype,
/// but structured so a real persistence layer could slot in later.
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
  String? _activeInspectionNo;

  /// Highest step number (1-6) the inspector has finished.
  int get highestCompleted => _highestCompleted;

  /// The step the inspector should land on next.
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
    }
  }

  /// Makes sure progress belongs to the parcel currently open. If the
  /// inspector opens a different parcel, progress starts fresh instead
  /// of carrying over from whatever they were last inspecting.
  void ensureActiveInspection(String inspectionNo) {
    if (_activeInspectionNo != inspectionNo) {
      _activeInspectionNo = inspectionNo;
      _highestCompleted = 0;
    }
  }

  void reset() {
    _highestCompleted = 0;
    _activeInspectionNo = null;
    notifyListeners();
  }
}
