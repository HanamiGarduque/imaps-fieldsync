import 'package:flutter/material.dart';

import '../../../modules/tasks/screens/tasks_screen.dart';
import '../providers/inspection_provider.dart';
import 'field_findings_screen.dart';
import 'inspection_checklist_screen.dart';
import 'inspection_progress.dart';
import 'review_submit_screen.dart';

/// Steps 3, 4 and 5 are independent: once Step 2 is verified the inspector
/// may complete them in any order. These helpers answer one question for
/// every step screen: after this step is saved, where does the inspector go
/// next?
///
/// The Continue button keeps its familiar meaning: it moves forward through
/// the protocol and skips the steps that are already complete. To work on an
/// earlier step, the Task Overview timeline is the switcher - it lists every
/// step with its real status and opens any of Steps 3-5 once Step 2 is
/// verified.

/// The step to open after [currentStep] has been completed and saved.
int nextStepAfter(int currentStep) {
  final progress = InspectionProgress.instance;
  const forward = {
    3: [4, 5],
    4: [5],
    5: <int>[],
  };
  for (final step in forward[currentStep] ?? const <int>[]) {
    if (!progress.isDone(step)) return step;
  }
  return 6;
}

/// The label of the Continue button, matching the screen it opens.
String nextStepLabel(int currentStep) {
  switch (nextStepAfter(currentStep)) {
    case 4:
      return 'Continue to Checklist';
    case 5:
      return 'Continue to Findings';
    default:
      return 'Continue to Review';
  }
}

/// The screen for the step that follows [currentStep].
Widget buildNextInspectionStep({
  required int currentStep,
  required TaskItem task,
  required InspectionProvider provider,
}) {
  switch (nextStepAfter(currentStep)) {
    case 4:
      return InspectionChecklistScreen(
        task: task,
        capturedPhotos: provider.capturedPhotos,
      );
    case 5:
      final legacy = <String, bool>{
        ...provider.siteCondition,
        ...provider.zoningObservations,
      };
      return FieldFindingsScreen(
        task: task,
        capturedPhotos: provider.capturedPhotos,
        checklistDone: legacy.values.where((value) => value).length,
        checklistTotal: legacy.length,
      );
    default:
      return ReviewSubmitScreen(task: task);
  }
}
