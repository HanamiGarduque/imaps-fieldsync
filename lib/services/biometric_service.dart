import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';

/// Thin wrapper around local_auth. Uses the device's own OS-level
/// biometric stack (Android BiometricPrompt / iOS Face ID & Touch ID),
/// so fingerprint, face, or iris all work automatically depending on
/// whatever hardware the inspector's phone actually has — we never
/// need to know which one it is.
class BiometricService {
  static final LocalAuthentication _auth = LocalAuthentication();

  /// Whether this device has usable biometric hardware AND at least
  /// one fingerprint/face/iris already enrolled in the OS settings.
  static Future<bool> isAvailable() async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      if (!supported || !canCheck) return false;
      final enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } catch (e) {
      debugPrint('[BIOMETRIC] isAvailable() failed: $e');
      return false;
    }
  }

  /// Human-readable label of the strongest biometric available on this
  /// device, for UI copy ("Enable Face Unlock" vs "Enable Fingerprint").
  static Future<String> primaryBiometricLabel() async {
    try {
      final list = await _auth.getAvailableBiometrics();
      if (list.contains(BiometricType.face)) return 'Face';
      if (list.contains(BiometricType.iris)) return 'Iris';
      if (list.contains(BiometricType.fingerprint) ||
          list.contains(BiometricType.strong) ||
          list.contains(BiometricType.weak)) {
        return 'Fingerprint';
      }
      return 'Biometric';
    } catch (e) {
      debugPrint('[BIOMETRIC] primaryBiometricLabel() failed: $e');
      return 'Biometric';
    }
  }

  /// Result of an authenticate() attempt: whether it succeeded, and — if
  /// not — a short reason code so the UI can tell "no hardware"/"none
  /// enrolled"/"platform not configured" apart from "user cancelled",
  /// instead of every failure looking identical.
  static Future<BiometricResult> authenticateDetailed({
    String reason = 'Verify your identity to continue',
  }) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true, // don't fall back to device PIN — we have our own pattern lock for that
          stickyAuth: true,
          useErrorDialogs: true,
        ),
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: 'InSight — Biometric Unlock',
            cancelButton: 'Use passcode instead',
          ),
          IOSAuthMessages(
            cancelButton: 'Use passcode instead',
          ),
        ],
      );
      return BiometricResult(success: ok, code: ok ? null : 'user_cancelled_or_failed_match');
    } on PlatformException catch (e) {
      // Most common real-world codes here:
      //  - NotAvailable / NoHardware: device has no biometric sensor
      //  - NotEnrolled: sensor exists but no fingerprint/face registered in OS settings
      //  - PasscodeNotSet: device has no lock screen set up at all
      //  - LockedOut / PermanentlyLockedOut: too many failed attempts, OS temporarily disabled it
      //  - no_fragment_activity (Android): MainActivity doesn't extend
      //    FlutterFragmentActivity — local_auth requires it. This is the
      //    #1 cause of "nothing happens, no prompt at all" on Android.
      debugPrint('[BIOMETRIC] authenticate() PlatformException: ${e.code} — ${e.message}');
      return BiometricResult(success: false, code: e.code, message: e.message);
    } catch (e) {
      debugPrint('[BIOMETRIC] authenticate() failed: $e');
      return BiometricResult(success: false, code: 'unknown', message: e.toString());
    }
  }

  /// Back-compat shim for existing callers that just want a bool.
  static Future<bool> authenticate({String reason = 'Verify your identity to continue'}) async {
    final result = await authenticateDetailed(reason: reason);
    return result.success;
  }
}

class BiometricResult {
  final bool success;
  final String? code;
  final String? message;
  const BiometricResult({required this.success, this.code, this.message});

  /// Short, user-safe message for the cases worth telling the inspector
  /// about specifically (vs. a generic cancel).
  String? get userFacingMessage {
    switch (code) {
      case 'NotAvailable':
      case 'NoHardware':
        return 'This device has no biometric sensor.';
      case 'NotEnrolled':
        return 'No fingerprint/face is registered on this device yet. Set one up in your phone\'s settings first.';
      case 'PasscodeNotSet':
        return 'Set up a screen lock on your device first.';
      case 'LockedOut':
      case 'PermanentlyLockedOut':
        return 'Biometric unlock is temporarily disabled after too many failed attempts. Use your device passcode to reset it.';
      default:
        return null; // plain cancel/mismatch — no need to alarm the user
    }
  }
}