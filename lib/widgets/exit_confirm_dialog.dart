import 'package:flutter/material.dart';

/// BUG FIX #2 — Defective Tab Lifecycle State Machine & Missing Exit
/// Confirmation Gate.
///
/// Every inspection step screen (GPS, Photos, Checklist, Findings, Review)
/// must call this instead of `Navigator.pop(context)` directly, and must
/// wrap its Scaffold in `PopScope(canPop: false, onPopInvokedWithResult: ...)`
/// so the hardware/gesture back action goes through the same gate.
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
    builder: (_) => const Center(child: CircularProgressIndicator()),
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
