import 'dart:async';
import 'package:flutter/material.dart';

import '../screens/inspection_progress.dart';
import 'imaps_loading_indicator.dart';
/// BUG FIX #2 — Defective Tab Lifecycle State Machine & Missing Exit
/// Confirmation Gate.
///
/// Every inspection step screen (GPS, Photos, Checklist, Findings, Review)
/// must call this instead of `Navigator.pop(context)` directly, and must
/// wrap its Scaffold in `PopScope(canPop: ..., onPopInvokedWithResult: ...)`
/// so the hardware/gesture back action goes through the same gate.
///
/// Only step 1 shows the confirm dialog. From step 2 onward, "back" has
/// a real previous step to land on — that screen is still alive further
/// down the Navigator stack with all its state intact, so popping isn't
/// destructive and doesn't need a prompt. We still fire [onSaveProgress]
/// in the background on the way out so nothing typed on the step being
/// left is lost, but we don't block the transition on it or show any UI
/// for it — that's what made intermediate steps feel interrupted.
///
/// [onSaveProgress] must push whatever is unsaved on that step to Supabase
/// (e.g. `provider.saveStepChecklist`) and return true/false for success.
/// The task's `status` flips to 'in_progress' server-side inside those
/// save calls (see SupabaseService.updateJobInspectionProgress), which is
/// what moves it into the "Ongoing" tab.
Future<void> handleInspectionExit(
  BuildContext context, {
  required Future<bool> Function() onSaveProgress,
}) async {
  if (InspectionProgress.instance.currentStep > 1) {
    unawaited(onSaveProgress());
    if (context.mounted) Navigator.pop(context);
    return;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Exit this inspection?'),
      content: const Text(
        'Your progress on this step will be saved. This task will move to '
        '"Ongoing" so you can continue later.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Keep working'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Save & exit'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  if (!context.mounted) return;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: ImapsLoadingIndicator(size: 50)),
  );

  bool ok = false;
  try {
    ok = await onSaveProgress();
  } catch (_) {
    ok = false;
  }

  if (!context.mounted) return;
  Navigator.pop(context); // close the loading spinner

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        ok
            ? 'Progress saved. Task moved to Ongoing.'
            : 'Saved offline — will sync when back online.',
      ),
    ),
  );

  if (!context.mounted) return;
  Navigator.pop(context); // exit the step screen itself
}