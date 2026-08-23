import 'package:flutter/material.dart';
import '../services/sync_outbox_service.dart';

import '../theme/insight_theme.dart';

/// Phase 5 — Sync Progress Indicator (compact variant).
///
/// A thin, dismissible-feeling banner that shows live outbox-drain
/// progress ("Submitting inspection (2 of 5) — Uploading photo 3 of 12")
/// on screens *other* than the Sync Center itself — Home, Tasks, Profile.
/// Collapses to zero height when nothing is syncing, so it never reserves
/// dead space on screens where sync isn't relevant right now.
///
/// Usage: drop `const SyncProgressBanner()` near the top of a screen's
/// body (e.g. wired once into `MainShellScreen` so all four tabs get it
/// for free, rather than each screen needing to add it individually).
class SyncProgressBanner extends StatelessWidget {
  const SyncProgressBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SyncProgress?>(
      valueListenable: SyncOutboxService.progress,
      builder: (context, syncProgress, _) {
        if (syncProgress == null) return const SizedBox.shrink();
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: InsightTheme.blue1,
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    syncProgress.displayText,
                    style: InsightTheme.inter(12.5, w: FontWeight.w600, c: Colors.white),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}