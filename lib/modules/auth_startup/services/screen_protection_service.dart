import 'package:flutter/foundation.dart';
import 'package:screen_protector/screen_protector.dart';

/// Reference-counted wrapper around screenshot/screen-recording protection
/// (FLAG_SECURE on Android, screen-recording block on iOS).
///
/// Why reference-counted rather than a simple on/off toggle: several
/// "sensitive" screens can be stacked at once (e.g. Task Details -> Photo
/// Capture -> back to Task Details). A naive "turn on in initState, turn
/// off in dispose" per screen would flip protection OFF the moment the top
/// screen is popped, even though the screen underneath is still sensitive
/// and still on-screen. Counting active sensitive screens and only calling
/// through to the OS when the count crosses 0 <-> 1 avoids that flicker.
///
/// Usage: wrap a sensitive screen's returned widget with [SensitiveScreen]
/// (see sensitive_screen.dart) rather than calling this directly.
class ScreenProtectionService {
  ScreenProtectionService._();

  static int _activeCount = 0;

  // ── Phase 3b: temporary debug-only override ─────────────────────────────
  // For taking documentation/thesis screenshots during development.
  // Hard-gated by kDebugMode (from package:flutter/foundation.dart), a
  // compile-time constant — in release/profile builds this is `false` and
  // the Dart compiler tree-shakes the `if (kDebugMode)` branches below
  // entirely. That's the actual requirement here: "cannot ship in
  // release," not merely "defaults to off in release." Every entry point
  // to this override (this flag, setDebugOverride() below, and the
  // DebugScreenshotToggle widget in main.dart) re-checks kDebugMode
  // independently, so there's no single guard that, if bypassed, would
  // leave production unprotected.
  //
  // To remove after documentation is done: delete this block, delete
  // setDebugOverride()/isDebugOverrideActive below, remove the two
  // `if (kDebugMode && _debugOverrideDisabled)` checks in enter()/exit(),
  // delete lib/modules/auth_startup/widgets/debug_screenshot_toggle.dart,
  // and remove the `builder:` wiring for it in main.dart's MaterialApp.
  static bool _debugOverrideDisabled = false;

  static Future<void> enter() async {
    _activeCount++;
    if (_activeCount == 1) {
      if (kDebugMode && _debugOverrideDisabled) {
        debugPrint('[SCREEN_PROTECTION] DEBUG override active — skipping FLAG_SECURE.');
        return;
      }
      try {
        await ScreenProtector.preventScreenshotOn();
      } catch (e) {
        debugPrint('[SCREEN_PROTECTION] enable error: $e');
      }
    }
  }

  static Future<void> exit() async {
    if (_activeCount == 0) return; // guard against unmatched exit() calls
    _activeCount--;
    if (_activeCount == 0) {
      if (kDebugMode && _debugOverrideDisabled) return;
      try {
        await ScreenProtector.preventScreenshotOff();
      } catch (e) {
        debugPrint('[SCREEN_PROTECTION] disable error: $e');
      }
    }
  }

  /// DEBUG-ONLY. Hard no-op outside kDebugMode — calling this from a
  /// release/profile build (it shouldn't be reachable there at all, see
  /// DebugScreenshotToggle) does nothing.
  static Future<void> setDebugOverride(bool disabled) async {
    if (!kDebugMode) return;
    _debugOverrideDisabled = disabled;
    if (disabled) {
      try {
        await ScreenProtector.preventScreenshotOff();
      } catch (e) {
        debugPrint('[SCREEN_PROTECTION] debug override (off) error: $e');
      }
    } else if (_activeCount > 0) {
      try {
        await ScreenProtector.preventScreenshotOn();
      } catch (e) {
        debugPrint('[SCREEN_PROTECTION] debug override (on) error: $e');
      }
    }
  }

  static bool get isDebugOverrideActive => kDebugMode && _debugOverrideDisabled;
}
