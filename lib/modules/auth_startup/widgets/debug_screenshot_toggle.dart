import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/screen_protection_service.dart';

/// Phase 3b — temporary debug-only override for screenshot protection, so
/// documentation/thesis screenshots can be taken of screens that are
/// normally FLAG_SECURE-protected (see AUTH_SECURITY_MASTER_DOC.md §Phase
/// 3b for the full writeup and requirements).
///
/// Restricted to debug builds: the `if (!kDebugMode)` check below returns
/// [child] completely untouched — no button, no state, nothing added to
/// the widget tree — and because `kDebugMode` is a compile-time constant,
/// the Dart compiler tree-shakes everything past that check out of
/// release/profile builds entirely. This isn't "hidden by a flag that
/// could be flipped," the button code itself isn't present in a release
/// binary. `ScreenProtectionService.setDebugOverride()` independently
/// re-checks `kDebugMode` too, so even a hypothetical stray call to it
/// from somewhere else would still be a no-op outside debug.
///
/// Hidden from normal users: never referenced by any production screen or
/// navigation path — it's wired once, globally, via MaterialApp's
/// `builder:` in main.dart, so it isn't part of any screen's own UI that
/// a normal user's build would ever render.
///
/// To remove once documentation screenshots are done: delete this file,
/// remove the `builder:` wiring in main.dart, and (optionally — these are
/// already permanently inert outside kDebugMode) remove
/// ScreenProtectionService.setDebugOverride()/isDebugOverrideActive and
/// the two `if (kDebugMode && _debugOverrideDisabled)` checks in
/// enter()/exit().
class DebugScreenshotToggle extends StatefulWidget {
  final Widget child;
  const DebugScreenshotToggle({super.key, required this.child});

  @override
  State<DebugScreenshotToggle> createState() => _DebugScreenshotToggleState();
}

class _DebugScreenshotToggleState extends State<DebugScreenshotToggle> {
  bool _disabled = false;

  @override
  Widget build(BuildContext context) {
    // Compile-time gate, not just a runtime one — see class doc above.
    if (!kDebugMode) return widget.child;

    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 8,
          bottom: 96,
          child: SafeArea(
            child: Material(
              color: Colors.transparent,
              child: FloatingActionButton.small(
                heroTag: 'debug_screenshot_toggle',
                backgroundColor: _disabled ? Colors.red[700] : Colors.black54,
                onPressed: () async {
                  final next = !_disabled;
                  await ScreenProtectionService.setDebugOverride(next);
                  if (!mounted) return;
                  setState(() => _disabled = next);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        next
                            ? 'DEBUG ONLY: screenshot protection OFF'
                            : 'DEBUG ONLY: screenshot protection restored',
                      ),
                      duration: const Duration(seconds: 2),
                      backgroundColor: next ? Colors.red[700] : Colors.green[700],
                    ),
                  );
                },
                child: Icon(
                  _disabled ? Icons.no_photography : Icons.camera_alt_outlined,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}