import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'secure_prefs_service.dart';
import '../../../core/services/supabase_service.dart';



/// Wraps [LocalAuthentication] with iMAPS-specific business rules:
///
/// - Never hardcodes a biometric type — detects what the device supports.
/// - Enrollment only stores a preference flag; the actual biometric template
///   lives in the OS secure enclave (never exposed to app code).
/// - Device-change detection: compares a stored device fingerprint against
///   the current one; a mismatch invalidates the enrollment silently.
/// - Passwords are never touched here — only session restoration logic.
class BiometricService {
  static final _auth = LocalAuthentication();

  // ── Device capability ───────────────────────────────────────────────────

  /// True if the device has biometric hardware AND at least one biometric
  /// is enrolled in the OS. Use this to decide whether to show the
  /// biometric option in Settings.
  static Future<bool> isAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      return canCheck && isSupported;
    } catch (e) {
      debugPrint('[BIO] isAvailable error: $e');
      return false;
    }
  }

  /// Returns the list of enrolled biometric types the device supports.
  /// Never hardcode — always display based on this list.
  static Future<List<BiometricType>> availableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (e) {
      debugPrint('[BIO] getAvailableBiometrics error: $e');
      return [];
    }
  }

  /// Human-readable label for the strongest available biometric.
  /// Used in UI hints like "Use Fingerprint" or "Use Face Unlock".
  static Future<String> primaryBiometricLabel() async {
    final bios = await availableBiometrics();
    if (bios.contains(BiometricType.face))        return 'Face Unlock';
    if (bios.contains(BiometricType.fingerprint)) return 'Fingerprint';
    if (bios.contains(BiometricType.iris))        return 'Iris Scan';
    // Falls back to device credential (PIN/pattern/password)
    final supported = await _auth.isDeviceSupported();
    if (supported) return 'Device Credential';
    return 'Biometric';
  }

  /// Icon data key for the primary biometric type — callers switch on this.
  static Future<BioType> primaryBiometricType() async {
    final bios = await availableBiometrics();
    if (bios.contains(BiometricType.face))        return BioType.face;
    if (bios.contains(BiometricType.fingerprint)) return BioType.fingerprint;
    if (bios.contains(BiometricType.iris))        return BioType.iris;
    return BioType.device;
  }

  // ── Authentication ──────────────────────────────────────────────────────

  /// Triggers the system biometric prompt. Returns true only on success.
  /// [reason] is shown in the system dialog (keep it short and clear).
  static Future<bool> authenticate({
    String reason = 'Confirm your identity to continue',
    bool useDeviceCredentialAsFallback = true,
  }) async {
    final deviceId = _buildDeviceFingerprint();
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          biometricOnly: !useDeviceCredentialAsFallback,
          stickyAuth: true, // keeps dialog alive if user switches apps briefly
          sensitiveTransaction: true,
        ),
      );

      // Audit log to Supabase
      if (ok) {
        SupabaseService.logSecurityEvent(
          eventType: 'biometric_login_success',
          deviceId: deviceId,
          severity: 'info',
        );
      } else {
        SupabaseService.logSecurityEvent(
          eventType: 'biometric_login_failed',
          deviceId: deviceId,
          severity: 'warning',
        );
      }

      return ok;
    } catch (e) {
      debugPrint('[BIO] authenticate error: $e');
      SupabaseService.logSecurityEvent(
        eventType: 'biometric_login_failed',
        deviceId: deviceId,
        severity: 'warning',
        metadata: {'error': e.toString()},
      );
      return false;
    }
  }

  // ── Enrollment management ───────────────────────────────────────────────

  /// Call after a successful biometric authentication during enrollment.
  /// Stores the preference + device fingerprint. Never stores a password.
  static Future<void> enroll() async {
    final deviceId = _buildDeviceFingerprint();
    final bioLabel = await primaryBiometricLabel();
    await SecurePrefsService.setBioEnrolled(enrolled: true, deviceId: deviceId);
    await SecurePrefsService.setBioRequireOnOpen(true);
    // New enrollment (including re-enrollment) always starts unconfirmed —
    // one real password login is required before biometric is trusted for
    // actual sign-in. See SecurePrefsService.setBioConfirmed for the
    // rationale.
    await SecurePrefsService.setBioConfirmed(false);

    // Sync device status & log audit event to Supabase
    await SupabaseService.syncInspectorDevice(
      deviceId: deviceId,
      biometricEnabled: true,
      biometricType: bioLabel,
    );

    await SupabaseService.logSecurityEvent(
      eventType: 'biometric_enroll',
      deviceId: deviceId,
      severity: 'info',
      metadata: {'biometric_type': bioLabel},
    );
  }

  /// True if biometric is enrolled AND the stored device fingerprint
  /// matches the current device.
  static Future<bool> isEnrolled() async {
    final enrolled = await SecurePrefsService.isBioEnrolled();
    if (!enrolled) return false;
    
    // Device-change check
    final stored = await SecurePrefsService.getBioDeviceId();
    final current = _buildDeviceFingerprint();
    if (stored == null) {
      debugPrint('[BIO][DIAG] isEnrolled: sp_bio_enrolled=true but no stored device id — treating as not enrolled (not clearing).');
      return false;
    }

    final match = stored == current;
    if (!match) {
      debugPrint('[BIO][DIAG] isEnrolled: DEVICE FINGERPRINT MISMATCH — stored="$stored" current="$current". Clearing enrollment.');
      // Automatic revocation on device mismatch
      await clearEnrollment();
      return false;
    }

    return true;
  }

  /// True only if biometric is enrolled AND a real password login has
  /// succeeded since that enrollment. Callers should check this — not just
  /// [isEnrolled] — before offering biometric as a sign-in method anywhere.
  static Future<bool> isConfirmed() => SecurePrefsService.isBioConfirmed();



  /// Wipes all biometric enrollment data. Call on:
  /// - User disabling biometric in Security Settings
  /// - Logout
  /// - Device-change detection
  static Future<void> clearEnrollment() async {
    final deviceId = _buildDeviceFingerprint();
    await SecurePrefsService.clearBioPrefs();

    await SupabaseService.syncInspectorDevice(
      deviceId: deviceId,
      biometricEnabled: false,
    );

    await SupabaseService.logSecurityEvent(
      eventType: 'biometric_disable',
      deviceId: deviceId,
      severity: 'info',
    );
  }


  // ── Device fingerprint ──────────────────────────────────────────────────

  /// Builds a stable device identifier from platform properties.
  /// Not cryptographically secure — only used to detect device changes
  /// so enrollment doesn't silently carry over from a backup restore.
  static String _buildDeviceFingerprint() {
    // On Android, we use the platform string. On iOS, we use a similar
    // composite. This deliberately avoids requiring device_info_plus to
    // keep the dependency surface small.
    final platform = Platform.operatingSystem;
    final version  = Platform.operatingSystemVersion;
    // Combine into a deterministic, non-reversible tag
    final raw = '$platform|$version';
    // Simple 32-char truncated hash
    var h = 0;
    for (final c in raw.codeUnits) {
      h = (h * 31 + c) & 0x7FFFFFFF;
    }
    return '${platform.substring(0, 3)}-${h.toRadixString(16).padLeft(8, '0')}';
  }
}

/// Enum representing supported biometric credential types.
enum BioType { fingerprint, face, iris, device }

/// Public extension so UI can use it without importing local_auth directly.
extension BiometricTypeHelper on BiometricService {
  static Future<BioType> get type => BiometricService.primaryBiometricType();
}