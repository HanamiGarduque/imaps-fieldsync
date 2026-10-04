import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/models/user_profile.dart';

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
  static const _kDbEncryptionKey   = 'sp_db_encryption_key';
  static const _kAcceptedLegalVersion = 'sp_accepted_legal_version';

  static const int currentLegalVersion = 1;

  static Future<int?> getAcceptedLegalVersion() async {
    final raw = await _storage.read(key: _kAcceptedLegalVersion);
    return raw == null ? null : int.tryParse(raw);
  }

  static Future<void> setAcceptedLegalVersion(int version) =>
      _storage.write(key: _kAcceptedLegalVersion, value: version.toString());

  // ── Biometric enrollment ────────────────────────────────────────────────
  static const _kBioEnrolled       = 'sp_bio_enrolled';
  static const _kBioConfirmed      = 'sp_bio_confirmed';
  static const _kBioDeviceId       = 'sp_bio_device_id';
  static const _kBioRequireOnOpen  = 'sp_bio_require_on_open';
  static const _kBioAutoLockMins   = 'sp_bio_auto_lock_mins'; // '0','1','5','10','-1'=immediately
  static const _kSoftLoggedOut     = 'sp_soft_logged_out';
  static const _kLocalDataOwnerId  = 'sp_local_data_owner_id';
  static const _kLocalPasscodeSalt = 'sp_local_passcode_salt';
  static const _kLocalPasscodeHash = 'sp_local_passcode_hash';
  static const _kLocalPasscodeFailCount = 'sp_local_passcode_fail_count';
  static const _kLocalPasscodeCooldownUntil = 'sp_local_passcode_cooldown_until';

  static Future<String?> getLocalPasscodeSalt() =>
      _storage.read(key: _kLocalPasscodeSalt);

  static Future<void> setLocalPasscodeSalt(String salt) =>
      _storage.write(key: _kLocalPasscodeSalt, value: salt);

  static Future<String?> getLocalPasscodeHash() =>
      _storage.read(key: _kLocalPasscodeHash);

  static Future<void> setLocalPasscodeHash(String hash) =>
      _storage.write(key: _kLocalPasscodeHash, value: hash);

  static Future<int> getLocalPasscodeFailCount() async =>
      int.tryParse(await _storage.read(key: _kLocalPasscodeFailCount) ?? '0') ?? 0;

  static Future<void> incrementLocalPasscodeFailCount() async {
    final count = await getLocalPasscodeFailCount();
    await _storage.write(key: _kLocalPasscodeFailCount, value: (count + 1).toString());
  }

  static Future<void> clearLocalPasscodeFailCount() =>
      _storage.delete(key: _kLocalPasscodeFailCount);

  static Future<DateTime?> getLocalPasscodeCooldownUntil() async {
    final raw = await _storage.read(key: _kLocalPasscodeCooldownUntil);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  static Future<void> setLocalPasscodeCooldownUntil(DateTime until) =>
      _storage.write(key: _kLocalPasscodeCooldownUntil, value: until.toIso8601String());

  static Future<void> clearLocalPasscodeCooldownUntil() =>
      _storage.delete(key: _kLocalPasscodeCooldownUntil);


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

  // ── Legacy pattern-lock data cleanup ────────────────────────────────────
  // The App Pattern (Quick Unlock) feature was removed entirely — see
  // AUTH_SECURITY_MASTER_DOC.md §Phase 3a. Its own service
  // (quick_unlock_service.dart, deleted) used a separate FlutterSecureStorage
  // instance under these key names. Deleting the *code* doesn't retroactively
  // wipe data already written to a device that had a pattern set up before
  // this removal — this purges those specific keys directly, satisfying
  // "no pattern exists in Secure Storage" as an actual on-device fact, not
  // just as a statement about current source code. Idempotent — a no-op on
  // any device that never had a pattern set up, and harmless to call
  // repeatedly (each key simply won't exist after the first successful run).
  static Future<void> purgeLegacyPatternLockData() async {
    const legacyKeys = [
      'qu_pattern_enabled',
      'qu_pattern_hash',
      'qu_pattern_salt',
      'qu_bound_email',
    ];
    for (final key in legacyKeys) {
      try {
        await _storage.delete(key: key);
      } catch (e) {
        debugPrint('[SECURE_PREFS] Legacy pattern-key purge error ($key): $e');
      }
    }
  }

  // ── Local database encryption key ───────────────────────────────────────
  // Generated once (cryptographically random, 32 bytes) and reused for the
  // life of the install — this is the SQLCipher passphrase for the local
  // SQLite database (see db_helper.dart). Deliberately NOT included in
  // clearAuthPrefs()/clearAll(): the encrypted database file survives
  // logout and password-reset the same way it always did unencrypted —
  // losing this key would make the entire local cache unreadable, which is
  // a data-loss bug, not a security feature. It's still Keystore-backed and
  // never leaves the device or touches Supabase.

  static Future<String?> getDbEncryptionKey() =>
      _storage.read(key: _kDbEncryptionKey);

  static Future<void> setDbEncryptionKey(String key) =>
      _storage.write(key: _kDbEncryptionKey, value: key);



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

  /// New request: biometric enrollment alone isn't enough to trust it for
  /// actual sign-in yet — one normal email+password login has to succeed
  /// *after* enrolling first, to confirm the person who enrolled it still
  /// knows their real credentials. Every biometric entry point (Login
  /// screen button, app-resume lock, cold-start gate) checks this before
  /// offering biometric at all. Starts false on every fresh enrollment.
  static Future<bool> isBioConfirmed() async =>
      (await _storage.read(key: _kBioConfirmed)) == 'true';

  static Future<void> setBioConfirmed(bool v) =>
      _storage.write(key: _kBioConfirmed, value: v ? 'true' : 'false');

  // ── Biometric behaviour toggles ─────────────────────────────────────────

  static Future<bool> getBioRequireOnOpen() async =>
      (await _storage.read(key: _kBioRequireOnOpen)) == 'true';

  static Future<void> setBioRequireOnOpen(bool v) =>
      _storage.write(key: _kBioRequireOnOpen, value: v ? 'true' : 'false');

  /// Auto-lock minutes: 0=never, 1=1min, 5=5min, 10=10min, -1=immediately.
  static Future<int> getBioAutoLockMins() async {
    final raw = await _storage.read(key: _kBioAutoLockMins);
    return int.tryParse(raw ?? '0') ?? 0;
  }

  static bool shouldLockAfterElapsed({
    required int minutes,
    required Duration elapsed,
  }) {
    if (minutes == 0) return false;
    if (minutes < 0) return true;
    return elapsed >= Duration(minutes: minutes);
  }

  static Future<void> setBioAutoLockMins(int minutes) =>
      _storage.write(key: _kBioAutoLockMins, value: minutes.toString());

  // ── Soft logout flag ─────────────────────────────────────────────────────
  // Replaces an earlier (broken) design that tried to save a copy of the
  // Supabase refresh token to restore after logout — that doesn't work:
  // Supabase's signOut() revokes the CURRENT session's refresh token
  // server-side regardless of scope ('local' vs 'global' only changes
  // whether OTHER devices/sessions are also revoked — the current one is
  // always killed, since that's what "signing out" means). So a saved
  // copy of that same token is worthless the moment signOut() runs.
  //
  // This flag instead means: "the real Supabase session is still fully
  // alive underneath, the person just asked to look logged-out on this
  // device." AuthService.signOut() sets this instead of calling Supabase's
  // real signOut() at all, whenever biometric is enrolled+confirmed — see
  // AUTH_SECURITY_MASTER_DOC.md §14. Biometric login then just clears this
  // flag; there's no token to restore because nothing was ever revoked.

  static Future<bool> isSoftLoggedOut() async =>
      (await _storage.read(key: _kSoftLoggedOut)) == 'true';

  static Future<void> setSoftLoggedOut(bool v) =>
      _storage.write(key: _kSoftLoggedOut, value: v ? 'true' : 'false');

  // ── Local data ownership (Known Issue #4) ───────────────────────────────
  // Tracks which inspector's user id the locally-cached inspection data
  // (local_jobs/local_inspections/local_photos in DbHelper) currently
  // belongs to. Used to detect a *different* inspector logging in on a
  // device that still has another inspector's cached data — see
  // LocalDataGuardService for what actually happens with that.

  static Future<String?> getLocalDataOwnerId() =>
      _storage.read(key: _kLocalDataOwnerId);

  static Future<void> setLocalDataOwnerId(String userId) =>
      _storage.write(key: _kLocalDataOwnerId, value: userId);

  // ── Task acknowledgement (Tasks tab attention dot) ───────────────────────
  // The orange dot on the Tasks nav item means "there is a NEW assignment you
  // have not looked at yet". Once the inspector opens Tasks, the assignments
  // that were awaiting are acknowledged — and that must survive an app restart,
  // so the state cannot live in a widget field.
  //
  // Stored in this service (rather than a new DB table) because it is already
  // the app's per-identity preference store and it needs no schema change.
  //
  // PER-USER NAMESPACE: the value is a JSON map keyed by the authenticated
  // Supabase user id — the same identity LocalDataGuardService uses. On a
  // shared device, Inspector A's acknowledgement therefore can never suppress
  // Inspector B's badge.
  //
  // Deliberately NOT cleared on logout: an assignment the inspector already
  // reviewed must not come back as "new" when they sign in again. Isolation
  // comes from the namespacing, not from wiping.

  static const _kAcknowledgedTaskIds = 'sp_acknowledged_task_ids';

  /// In-memory stand-in for the platform keystore, used by tests only.
  /// Mirrors DBHelper.useDatabaseForTesting so no test needs a real device.
  @visibleForTesting
  static Map<String, String>? storageOverrideForTesting;

  @visibleForTesting
  static void useStorageForTesting(Map<String, String>? initial) =>
      storageOverrideForTesting = initial == null ? null : Map.of(initial);

  static Future<String?> _read(String key) async {
    final override = storageOverrideForTesting;
    if (override != null) return override[key];
    return _storage.read(key: key);
  }

  static Future<void> _write(String key, String value) async {
    final override = storageOverrideForTesting;
    if (override != null) {
      override[key] = value;
      return;
    }
    await _storage.write(key: key, value: value);
  }

  /// Task ids this inspector has already opened in the Tasks tab.
  /// Returns an empty set for an unknown id or unreadable/corrupt value —
  /// a broken preference must never crash startup or invent a badge.
  static Future<Set<String>> getAcknowledgedTaskIds(String userId) async {
    if (userId.isEmpty) return <String>{};
    final raw = await _read(_kAcknowledgedTaskIds);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String>{};
      final mine = decoded[userId];
      if (mine is! List) return <String>{};
      return mine.whereType<String>().toSet();
    } catch (_) {
      return <String>{};
    }
  }

  /// Replaces this inspector's acknowledged set, leaving other inspectors'
  /// entries untouched. [pruneTo] opportunistically drops ids that are no
  /// longer awaiting, so the stored set cannot grow without bound; ids for
  /// other inspectors are never pruned from here.
  static Future<void> setAcknowledgedTaskIds(
    String userId,
    Set<String> ids, {
    Set<String>? pruneTo,
  }) async {
    if (userId.isEmpty) return;
    final raw = await _read(_kAcknowledgedTaskIds);
    final all = <String, dynamic>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) all.addAll(decoded.cast<String, dynamic>());
      } catch (_) {
        // Corrupt value: start clean rather than propagate it.
      }
    }
    final kept = pruneTo == null
        ? ids
        : ids.where(pruneTo.contains).toSet();
    all[userId] = kept.toList()..sort();
    await _write(_kAcknowledgedTaskIds, jsonEncode(all));
  }

  /// Marks [taskIds] as seen for this inspector, unioned with whatever was
  /// already acknowledged so a concurrent arrival is never dropped.
  static Future<void> acknowledgeTasks(
    String userId,
    Iterable<String> taskIds,
  ) async {
    if (userId.isEmpty) return;
    final ids = taskIds.toSet();
    if (ids.isEmpty) return;
    final existing = await getAcknowledgedTaskIds(userId);
    await setAcknowledgedTaskIds(userId, {...existing, ...ids});
  }

  // ── Bulk clear ──────────────────────────────────────────────────────────

  /// Call on logout / account switch. Wipes all auth prefs.
  static Future<void> clearAuthPrefs() async {
    await _storage.delete(key: _kSavedEmail);
    await _storage.delete(key: _kCachedProfile);
    await _storage.delete(key: _kLocalPasscodeSalt);
    await _storage.delete(key: _kLocalPasscodeHash);
    await _storage.delete(key: _kLocalPasscodeFailCount);
    await _storage.delete(key: _kLocalPasscodeCooldownUntil);
  }

  /// Call when biometric is disabled or the device changes.
  static Future<void> clearBioPrefs() async {
    await _storage.delete(key: _kBioEnrolled);
    await _storage.delete(key: _kBioConfirmed);
    await _storage.delete(key: _kBioDeviceId);
    await _storage.delete(key: _kBioRequireOnOpen);
    await _storage.delete(key: _kBioAutoLockMins);
    await _storage.delete(key: _kSoftLoggedOut);
  }

  /// Full wipe — used on signOut.
  static Future<void> clearAll() async {
    await clearAuthPrefs();
    await clearBioPrefs();
  }
}