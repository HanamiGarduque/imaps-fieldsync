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

  static Future<void> enter() async {
    _activeCount++;
    if (_activeCount == 1) {
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
      try {
        await ScreenProtector.preventScreenshotOff();
      } catch (e) {
        debugPrint('[SCREEN_PROTECTION] disable error: $e');
      }
    }
  }
}
