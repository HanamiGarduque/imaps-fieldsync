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
    } catch (_) {
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
    } catch (_) {
      return 'Biometric';
    }
  }

  /// Shows the native OS biometric prompt. Returns true only on a
  /// genuine successful match — never on error/cancel.
  static Future<bool> authenticate({
    String reason = 'Verify your identity to continue',
  }) async {
    try {
      return await _auth.authenticate(
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
    } catch (_) {
      return false;
    }
  }
}
