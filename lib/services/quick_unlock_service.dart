import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages the device-local "quick unlock" configuration: whether
/// biometric and/or pattern unlock are enabled, and the salted hash of
/// the pattern (the raw pattern itself is never stored or transmitted).
///
/// IMPORTANT: this only gates the *locally cached* Supabase session
/// (the "stay signed in" auto-login). The inspector's real credential
/// is still the Supabase account managed on the MPDO intranet — quick
/// unlock never talks to the server and never replaces that account.
class QuickUnlockService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kBiometricEnabled = 'qu_biometric_enabled';
  static const _kPatternEnabled = 'qu_pattern_enabled';
  static const _kPatternHash = 'qu_pattern_hash';
  static const _kPatternSalt = 'qu_pattern_salt';
  static const _kBoundEmail = 'qu_bound_email'; // which account this device's quick unlock belongs to

  static Future<bool> isBiometricEnabled() async =>
      (await _storage.read(key: _kBiometricEnabled)) == 'true';

  static Future<bool> isPatternEnabled() async =>
      (await _storage.read(key: _kPatternEnabled)) == 'true';

  static Future<bool> isAnyEnabled() async =>
      (await isBiometricEnabled()) || (await isPatternEnabled());

  static Future<String?> boundEmail() => _storage.read(key: _kBoundEmail);

  static Future<void> setBiometricEnabled(bool enabled, {required String email}) async {
    await _storage.write(key: _kBiometricEnabled, value: enabled.toString());
    await _storage.write(key: _kBoundEmail, value: email);
  }

  /// pattern = ordered list of dot indices, e.g. [0,1,2,5,8]
  static Future<void> setPattern(List<int> pattern, {required String email}) async {
    final salt = _randomSalt();
    final hash = _hashPattern(pattern, salt);
    await _storage.write(key: _kPatternSalt, value: salt);
    await _storage.write(key: _kPatternHash, value: hash);
    await _storage.write(key: _kPatternEnabled, value: 'true');
    await _storage.write(key: _kBoundEmail, value: email);
  }

  static Future<bool> verifyPattern(List<int> pattern) async {
    final salt = await _storage.read(key: _kPatternSalt);
    final storedHash = await _storage.read(key: _kPatternHash);
    if (salt == null || storedHash == null) return false;
    return _hashPattern(pattern, salt) == storedHash;
  }

  static Future<void> disablePattern() async {
    await _storage.delete(key: _kPatternEnabled);
    await _storage.delete(key: _kPatternHash);
    await _storage.delete(key: _kPatternSalt);
  }

  static Future<void> disableBiometric() async {
    await _storage.delete(key: _kBiometricEnabled);
  }

  /// Wipe everything — call this on sign-out / switch-account so the
  /// next inspector on a shared device doesn't inherit a quick unlock.
  static Future<void> clearAll() async {
    await _storage.delete(key: _kBiometricEnabled);
    await _storage.delete(key: _kPatternEnabled);
    await _storage.delete(key: _kPatternHash);
    await _storage.delete(key: _kPatternSalt);
    await _storage.delete(key: _kBoundEmail);
  }

  static String _hashPattern(List<int> pattern, String salt) {
    final raw = '$salt:${pattern.join(",")}';
    return sha256.convert(utf8.encode(raw)).toString();
  }

  static String _randomSalt() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return sha256.convert(utf8.encode('salt-$now-${now.hashCode}')).toString().substring(0, 16);
  }
}
