import 'package:flutter/material.dart';

import '../theme/insight_theme.dart';

/// Compact "● Offline mode" banner shown by the app shell whenever the device
/// has no network connectivity.
///
/// One compact row and nothing else. It deliberately owns the status-bar top
/// inset via its own [SafeArea] so the bar never renders under the system
/// clock/battery, and so the same rule applies to all four main tabs.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: InsightTheme.redTint,
        border: Border(
          bottom: BorderSide(color: InsightTheme.red.withValues(alpha: 0.25)),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: InsightTheme.red,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Offline mode',
              style: InsightTheme.inter(
                11.5,
                w: FontWeight.w700,
                c: InsightTheme.redInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wraps the shell's page content so the status-bar top inset is applied
/// EXACTLY ONCE, whichever way connectivity is pointing.
///
/// Why this exists: [OfflineBanner] clears the status bar through its own
/// [SafeArea], and every main page (Home, Tasks, Sync, Profile) ALSO applies
/// that same inset through its own `SafeArea(bottom: false)`. With the banner
/// in the tree the inset was therefore applied twice, which opened a full
/// extra status-bar band of dead space above the page header and made the app
/// look like it had a tall empty strip at the top whenever it went offline.
///
/// Rule, in one place so all four tabs behave identically:
///  * online  → the banner is absent, so the page keeps its own single inset.
///  * offline → the banner already consumed the inset, so it is stripped from
///    the page instead of stacking a second copy.
///
/// Online leaves no reserved banner height and no invisible box, because
/// nothing is added to the tree at all in that state.
class PageUnderOfflineBanner extends StatelessWidget {
  const PageUnderOfflineBanner({
    super.key,
    required this.isOnline,
    required this.child,
  });

  final bool isOnline;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (isOnline) return child;
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      child: child,
    );
  }
}

/// One non-blocking row explaining that what is on screen is locally saved
/// data and whether the remote refresh has completed.
class SavedDataNotice extends StatelessWidget {
  const SavedDataNotice({super.key, required this.message, this.onRetry});

  static const saved = 'Showing saved task data.';
  static const refreshing = 'Showing saved task data. Checking for updates…';
  static const noCacheOffline =
      'You are offline and no saved tasks are on this device yet. Connect to the internet to load your assignments.';
  static const noCacheFailure =
      'Could not load your tasks. Check your connection and try again.';
  static const cacheReadFailed =
      'Could not read saved tasks on this device. Retry to load your assignments.';
  static const ownerChanged =
      'Inspector session changed. Reopen this screen from your current account.';

  /// No usable connection, so no refresh was possible.
  static const offline =
      'Offline. Showing saved task data. Some details are not available.';

  /// A refresh was attempted and failed while the device still had a
  /// connection. A genuine backend problem is never hidden as normal offline.
  static const refreshFailed =
      'Could not refresh from the server. Showing saved task data.';

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: InsightTheme.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: InsightTheme.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.cloud_off_rounded, size: 16, color: InsightTheme.ink3),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: InsightTheme.inter(12, c: InsightTheme.ink2),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(minimumSize: const Size(64, 44)),
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}
