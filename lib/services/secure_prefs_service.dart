import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user_profile.dart';

/// Secure replacement for SharedPreferences — used only for auth-related
/// and security-sensitive preferences. Backed by Android Keystore /
/// iOS Secure Enclave via [flutter_secure_storage].
///
/// Non-sensitive prefs (theme, notification opt-ins, etc.) still use
/// plain SharedPreferences. Only call this class for data that would
/// expose PII or unlock state if leaked.
class SecurePrefsService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // ── Key constants ───────────────────────────────────────────────────────
  static const _kSavedEmail        = 'sp_saved_email';
  static const _kBioSecret         = 'sp_bio_secret';
  static const _kCachedProfile     = 'sp_cached_profile';

  // ── Biometric enrollment ────────────────────────────────────────────────
  static const _kBioEnrolled       = 'sp_bio_enrolled';
  static const _kBioDeviceId       = 'sp_bio_device_id';
  static const _kBioRequireOnOpen  = 'sp_bio_require_on_open';
  static const _kBioRequireOnSync  = 'sp_bio_require_on_sync';
  static const _kBioRequireProfile = 'sp_bio_require_profile';
  static const _kBioAutoLockMins   = 'sp_bio_auto_lock_mins'; // '0','1','5','10','-1'=immediately

  // ── Saved Email & Encrypted Biometric Secret ────────────────────────────

  static Future<String?> getSavedEmail() =>
      _storage.read(key: _kSavedEmail);

  static Future<void> setSavedEmail(String email) =>
      _storage.write(key: _kSavedEmail, value: email.trim().toLowerCase());

  static Future<void> removeSavedEmail() =>
      _storage.delete(key: _kSavedEmail);

  static Future<String?> getBioSecret() =>
      _storage.read(key: _kBioSecret);

  static Future<void> setBioSecret(String secret) =>
      _storage.write(key: _kBioSecret, value: secret);

  static Future<void> removeBioSecret() =>
      _storage.delete(key: _kBioSecret);

  // ── Cached profile (offline fallback) ───────────────────────────────────
  // Written after every successful profile fetch. Read only as a fallback
  // when a fresh fetch fails specifically because there's no connectivity —
  // never used to override a genuine server-side rejection (e.g. a
  // deactivated account), since the caller is expected to check the id
  // matches the currently-authenticated user before trusting it.

  static Future<UserProfile?> getCachedProfile() async {
    final raw = await _storage.read(key: _kCachedProfile);
    if (raw == null) return null;
    try {
      return UserProfile.fromMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> setCachedProfile(UserProfile profile) =>
      _storage.write(key: _kCachedProfile, value: jsonEncode(profile.toMap()));

  static Future<void> removeCachedProfile() =>
      _storage.delete(key: _kCachedProfile);



  // ── Biometric enrollment ────────────────────────────────────────────────

  static Future<bool> isBioEnrolled() async =>
      (await _storage.read(key: _kBioEnrolled)) == 'true';

  static Future<String?> getBioDeviceId() =>
      _storage.read(key: _kBioDeviceId);

  static Future<void> setBioEnrolled({
    required bool enrolled,
    required String deviceId,
  }) async {
    await _storage.write(key: _kBioEnrolled, value: enrolled ? 'true' : 'false');
    await _storage.write(key: _kBioDeviceId, value: deviceId);
  }

  // ── Biometric behaviour toggles ─────────────────────────────────────────

  static Future<bool> getBioRequireOnOpen() async =>
      (await _storage.read(key: _kBioRequireOnOpen)) == 'true';

  static Future<void> setBioRequireOnOpen(bool v) =>
      _storage.write(key: _kBioRequireOnOpen, value: v ? 'true' : 'false');

  static Future<bool> getBioRequireOnSync() async =>
      (await _storage.read(key: _kBioRequireOnSync)) == 'true';

  static Future<void> setBioRequireOnSync(bool v) =>
      _storage.write(key: _kBioRequireOnSync, value: v ? 'true' : 'false');

  static Future<bool> getBioRequireProfile() async =>
      (await _storage.read(key: _kBioRequireProfile)) == 'true';

  static Future<void> setBioRequireProfile(bool v) =>
      _storage.write(key: _kBioRequireProfile, value: v ? 'true' : 'false');

  /// Auto-lock minutes: 0=never, 1=1min, 5=5min, 10=10min, -1=immediately.
  static Future<int> getBioAutoLockMins() async {
    final raw = await _storage.read(key: _kBioAutoLockMins);
    return int.tryParse(raw ?? '0') ?? 0;
  }

  static Future<void> setBioAutoLockMins(int minutes) =>
      _storage.write(key: _kBioAutoLockMins, value: minutes.toString());

  // ── Bulk clear ──────────────────────────────────────────────────────────

  /// Call on logout / account switch. Wipes all auth prefs.
  static Future<void> clearAuthPrefs() async {
    await _storage.delete(key: _kSavedEmail);
    await _storage.delete(key: _kCachedProfile);
  }

  /// Call when biometric is disabled or the device changes.
  static Future<void> clearBioPrefs() async {
    await _storage.delete(key: _kBioEnrolled);
    await _storage.delete(key: _kBioDeviceId);
    await _storage.delete(key: _kBioRequireOnOpen);
    await _storage.delete(key: _kBioRequireOnSync);
    await _storage.delete(key: _kBioRequireProfile);
    await _storage.delete(key: _kBioAutoLockMins);
  }

  /// Full wipe — used on signOut.
  static Future<void> clearAll() async {
    await clearAuthPrefs();
    await clearBioPrefs();
  }
}