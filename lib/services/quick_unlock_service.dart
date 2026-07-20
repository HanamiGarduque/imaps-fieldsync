import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages the device-local "quick unlock" configuration: whether
/// pattern unlock is enabled, and the salted hash of the pattern (the
/// raw pattern itself is never stored or transmitted).
///
/// IMPORTANT: this only gates the *locally cached* Supabase session
/// (the "stay signed in" auto-login). The inspector's real credential
/// is still the Supabase account managed on the MPDO intranet — quick
/// unlock never talks to the server and never replaces that account.
class QuickUnlockService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kPatternEnabled = 'qu_pattern_enabled';
  static const _kPatternHash = 'qu_pattern_hash';
  static const _kPatternSalt = 'qu_pattern_salt';
  static const _kBoundEmail = 'qu_bound_email'; // which account this device's quick unlock belongs to

  /// Every email in/out of this service passes through here. Root cause
  /// of a past "quick unlock icon just never appears, no error" bug: the
  /// profile screen binds using Supabase's currentUser.email (server-
  /// normalized, lowercase), while the login form saves whatever casing
  /// the inspector actually typed — an exact-string compare between the
  /// two silently failed with zero error surfaced.
  static String _norm(String email) => email.trim().toLowerCase();

  static Future<bool> isPatternEnabled() async =>
      (await _storage.read(key: _kPatternEnabled)) == 'true';

  /// Kept as its own method (rather than inlining isPatternEnabled directly
  /// at call sites) so callers asking "is *any* quick-unlock method
  /// configured" have one stable entry point if another method is added
  /// later.
  static Future<bool> isAnyEnabled() async => isPatternEnabled();

  static Future<String?> boundEmail() => _storage.read(key: _kBoundEmail);

  /// True if [email] (any casing/whitespace) matches the account this
  /// device's quick unlock is bound to. Use this instead of comparing
  /// boundEmail() directly.
  static Future<bool> isBoundTo(String email) async {
    final bound = await boundEmail();
    if (bound == null) return false;
    return bound == _norm(email);
  }

  /// pattern = ordered list of dot indices, e.g. [0,1,2,5,8]
  static Future<void> setPattern(List<int> pattern, {required String email}) async {
    final salt = _randomSalt();
    final hash = _hashPattern(pattern, salt);
    await _storage.write(key: _kPatternSalt, value: salt);
    await _storage.write(key: _kPatternHash, value: hash);
    await _storage.write(key: _kPatternEnabled, value: 'true');
    await _storage.write(key: _kBoundEmail, value: _norm(email));
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

  /// Wipe everything — call this on sign-out / switch-account so the
  /// next inspector on a shared device doesn't inherit a quick unlock.
  static Future<void> clearAll() async {
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