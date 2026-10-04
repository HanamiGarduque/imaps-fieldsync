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
