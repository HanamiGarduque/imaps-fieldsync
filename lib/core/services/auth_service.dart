import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/user_profile.dart';
import '../../modules/auth_startup/services/secure_prefs_service.dart';
import 'supabase_service.dart';
import 'auth_failure.dart';
import '../../modules/auth_startup/services/biometric_service.dart';
import '../../modules/auth_startup/services/screen_protection_service.dart';

class AuthService {
  static final SupabaseClient _client = SupabaseService.client; //[cite: 2]

  // In-memory cache of the soft-logout flag (see signOut() below). Kept as
  // a plain static bool, not read from storage on every access, because
  // isLoggedIn is a synchronous getter called directly from build()
  // methods throughout the UI — it can't become async without rippling
  // through a lot of screens. loadSoftLogoutState() populates this once at
  // startup, before anything else needs it.
  static bool _softLoggedOut = false;
  static const _recoveryBudget = Duration(seconds: 8);
  static final _profileRefusedOwner = ValueNotifier<String?>(null);
  static ValueListenable<String?> get profileRefusedOwner => _profileRefusedOwner;

  static void _requireSessionOwner(String uid, {bool allowSoftLogout = false}) {
    if (_client.auth.currentSession?.user.id != uid ||
        (!allowSoftLogout && !isLoggedIn)) {
      throw AuthFailure.sessionRestoreFailed;
    }
  }

  /// Local navigation/fallback only; a preference never invents a session.
  static Future<UserProfile?> getCachedProfileForCurrentInspector() async {
    final uid = _client.auth.currentSession?.user.id;
    if (uid == null || !isLoggedIn || _profileRefusedOwner.value == uid) return null;
    final cached = await SecurePrefsService.getCachedProfile()
        .timeout(const Duration(seconds: 2));
    _requireSessionOwner(uid);
    if (_profileRefusedOwner.value == uid) return null;
    return cached?.id == uid && cached!.isInspector && cached.fullName.trim().isNotEmpty
        ? cached : null;
  }

  /// Call once at app startup (see main.dart), before runApp(). Loads the
  /// persisted soft-logout flag so isLoggedIn is already correct for
  /// Splash's very first _checkSession() call on a cold start.
  static Future<void> loadSoftLogoutState() async {
    _softLoggedOut = await SecurePrefsService.isSoftLoggedOut();
  }

  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    ScreenProtectionService.instance.invalidateDocumentation();
    final AuthResponse res;
    try {
      res = await _client.auth.signInWithPassword( //[cite: 2]
        email: email,
        password: password,
      );
    } catch (e) {
      throw AuthFailure.classify(e,
          fallback: AuthFailure.unknownPostAuth, credentialRequest: true);
    }
    // Any real password login — including the one-time biometric
    // confirmation login — means the session should read as logged in.
    try {
      await _setSoftLoggedOut(false);
    } catch (e) {
      // The session is already live; only the local flag failed.
      throw AuthFailure.classify(e, fallback: AuthFailure.unknownPostAuth);
    }
    return res;
  }

  /// "Logs out." If biometric is enrolled AND confirmed, this deliberately
  /// does NOT call Supabase's real signOut() at all — it only flags the
  /// session as hidden on this device (see [_setSoftLoggedOut]).
  ///
  /// Why: Supabase's signOut() revokes the CURRENT session's refresh token
  /// server-side no matter what scope is passed — 'local' vs 'global' only
  /// changes whether OTHER sessions/devices are also revoked, not whether
  /// this one survives. Confirmed directly from a device log: a 'local'
  /// sign-out followed by a biometric attempt failed with the server's own
  /// "Invalid Refresh Token: Refresh Token Not Found" — the token was
  /// genuinely gone, not just stale from a timing race. There is no
  /// signOut() scope that means "sign out but leave this session usable" —
  /// that would defeat the actual meaning of signing out. So the only way
  /// to let biometric bring someone back in without a network round-trip
  /// (and without ever risking a rejected/rotated token) is to never
  /// destroy the real session in the first place, and just hide it.
  ///
  /// Pass [revokeEverywhere]: true for flows that should actually kill the
  /// session for real — password reset, explicit "sign out of all
  /// devices," or a detected genuine revocation. Also falls through to a
  /// real (local-scope) sign-out automatically if biometric isn't
  /// enrolled+confirmed, since there's nothing to preserve access through
  /// in that case anyway.
  static Future<void> signOut({bool revokeEverywhere = false}) async {
    ScreenProtectionService.instance.invalidateDocumentation();
    if (!revokeEverywhere &&
        await BiometricService.isEnrolled() &&
        await BiometricService.isConfirmed()) {
      await _setSoftLoggedOut(true);
      return;
    }
    await _client.auth.signOut( //[cite: 2]
      scope: revokeEverywhere ? SignOutScope.global : SignOutScope.local,
    );
    await _setSoftLoggedOut(false); // nothing left to hide, the real session is gone
  }

  static Future<void> _setSoftLoggedOut(bool v) async {
    _softLoggedOut = v;
    await SecurePrefsService.setSoftLoggedOut(v);
  }

  /// True if the underlying Supabase session is genuinely alive on this
  /// device, regardless of the soft-logout flag. A soft logout never
  /// touches this — that's the entire point. This is what the Login
  /// screen's biometric button actually checks for, and what
  /// [clearSoftLogout] un-hides.
  static bool get hasLiveUnderlyingSession => _client.auth.currentUser != null; //[cite: 2]

  /// What the UI should treat as "is someone logged in." False while
  /// soft-logged-out, even though the real session may still be alive
  /// underneath — that's what makes Login correctly reappear after a
  /// normal logout.
  static bool get isLoggedIn => hasLiveUnderlyingSession && !_softLoggedOut; //[cite: 2]

  /// Called after a successful biometric scan when there's a live
  /// underlying session to un-hide. No network call, no token exchange —
  /// nothing was ever revoked, so there's nothing to restore.
  static Future<void> clearSoftLogout() => _setSoftLoggedOut(false);

  /// Local-only check (no network call) — true if there's no session at
  /// all, or its JWT expiry timestamp has already passed. Used to fail
  /// fast right after quick-unlock success, before spending a request on it.
  static bool get isLocalSessionExpired {
    final exp = _client.auth.currentSession?.expiresAt;
    if (exp == null) return true;
    return DateTime.fromMillisecondsSinceEpoch(exp * 1000).isBefore(DateTime.now());
  }

  /// Tries to restore an expired session using the stored refresh token.
  ///
  /// A transport failure is NOT a session failure: the refresh token may be
  /// perfectly valid and merely unredeemable right now, so the caller keeps the
  /// live session and may use the owner-matched cached profile. A server-side
  /// rejection (revoked/rotated token) throws [AuthFailure.sessionRestoreFailed],
  /// which is never presented as a credential problem.
  static Future<void> restoreSessionOfflineAware() async {
    final uid = _client.auth.currentSession?.user.id;
    if (uid == null) throw AuthFailure.sessionRestoreFailed;
    try {
      if (!await hasConnectivity().timeout(_recoveryBudget)) return;
      _requireSessionOwner(uid, allowSoftLogout: true);
      final res = await _client.auth.refreshSession().timeout(_recoveryBudget);
      if (res.session == null) throw AuthFailure.sessionRestoreFailed;
      _requireSessionOwner(uid, allowSoftLogout: true);
    } catch (e) {
      final failure = AuthFailure.classify(e,
          fallback: AuthFailure.sessionRestoreFailed);
      debugPrint('[AUTH] Session restore: ${failure.name}');
      if (failure != AuthFailure.networkUnavailable) throw failure;
      _requireSessionOwner(uid, allowSoftLogout: true);
    }
  }

  // Debug-only: prints in _checkSession() to reveal exactly why stay-signed-in
  // does or doesn't work on a given device. Remove once confirmed working.
  static String get currentUserDebug => _client.auth.currentUser?.email ?? 'null';
  static String get sessionExpiryDebug {
    final exp = _client.auth.currentSession?.expiresAt;
    if (exp == null) return 'no session';
    final expiry = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    return '$expiry (${expiry.isBefore(DateTime.now()) ? "EXPIRED" : "valid"})';
  }

  // NOTE: unused as of the admin-mediated passcode reset decision — see
  // splash_screen.dart _handleForgotPasscode and
  // AUTH_SECURITY_MASTER_DOC.md §12. Only reset_password_screen.dart.bak
  // (retired, not compiled) still references these. Left in place rather
  // than deleted outright, consistent with how login_screen.dart.bak was
  // handled — safe to remove for real once confirmed nothing else needs
  // Supabase's self-service recovery flow.
  // ADDED: Triggers Supabase's built-in password reset workflow
  static Future<void> resetPassword({required String email}) async {
    await _client.auth.resetPasswordForEmail(email);
  }

  // Called from ResetPasswordScreen (now retired — see note on
  // resetPassword() above) after the inspector follows the emailed link.
  // Requires an active recovery session (set by the deep-link handler
  // calling supabase.auth.getSessionFromUrl/exchangeCodeForSession first).
  static Future<void> updatePassword({required String newPassword}) async {
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  static Future<UserProfile?> getCurrentProfile() async {
    final user = _client.auth.currentUser; //[cite: 2]
    if (user == null) return null; //[cite: 2]

    try {
      final data = await _client //[cite: 2]
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();
      _requireSessionOwner(user.id);
      // A usable profile needs the identity, name and role the UI relies on;
      // a row that resolves but cannot fill them is not a working account.
      if (data['id'] != user.id ||
          data['full_name'] is! String ||
          (data['full_name'] as String).trim().isEmpty ||
          data['role'] is! String ||
          (data['role'] as String).trim().isEmpty) {
        throw AuthFailure.profileUnavailable;
      }
      _profileRefusedOwner.value = null;
      return UserProfile.fromMap(data, email: user.email);
    } catch (e) {
      final failure = AuthFailure.classify(e, fallback: AuthFailure.profileUnavailable);
      if (failure == AuthFailure.profileUnavailable &&
          _client.auth.currentUser?.id == user.id) {
        _profileRefusedOwner.value = user.id;
        // An observed refusal must not become an offline success next restart.
        // Local inspection rows/files are deliberately not auth-cache cleanup.
        try {
          final cached = await SecurePrefsService.getCachedProfile()
              .timeout(const Duration(seconds: 2));
          if (_client.auth.currentUser?.id == user.id && cached?.id == user.id) {
            await SecurePrefsService.removeCachedProfile()
                .timeout(const Duration(seconds: 2));
          }
        } catch (_) {}
      }
      throw failure;
    }
  }

  /// True if the device currently appears to have network connectivity.
  /// Same version-safe pattern already used elsewhere in this codebase
  /// (gps_verification_screen.dart, site_map_screen.dart) since
  /// connectivity_plus's checkConnectivity() return type changed between
  /// major versions (single ConnectivityResult pre-v5, List<> from v5+).
  static Future<bool> hasConnectivity() async {
    final dynamic result = await Connectivity().checkConnectivity();
    if (result is List) {
      return result.any((r) => r != ConnectivityResult.none);
    }
    return result != ConnectivityResult.none;
  }

  /// True if [error] looks like a connectivity failure rather than a
  /// genuine server-side rejection (wrong credentials, revoked session,
  /// deactivated account, etc.). Text-matching is a fallback signal only —
  /// callers should check [hasConnectivity] first.
  static bool looksLikeConnectivityError(Object error) {
    return AuthFailure.isNetworkError(error);
  }

  /// Like [getCurrentProfile], but falls back to the last-known-good
  /// locally-cached profile (SecurePrefsService) if the fresh fetch fails
  /// *specifically because there's no connectivity* — so a previously-
  /// authenticated inspector isn't bounced back to Login just because one
  /// network call couldn't reach the server while their session is still
  /// perfectly valid. Refreshes the cache on every successful fetch.
  ///
  /// Does NOT fall back on a genuine server-side rejection (e.g. the
  /// account row no longer exists) — that error is rethrown so the caller
  /// treats it as a real failure, not silently masked by a stale cache.
  static Future<UserProfile?> getCurrentProfileOfflineAware({
    bool restoreSession = false,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null || !isLoggedIn) return null;
    var budgetExpired = false;

    try {
      // One deadline covers connectivity, optional refresh AND profile fetch.
      // A late refresh may still be rejected by the SDK, but cannot dispatch a
      // second startup request after this caller has fallen back to local work.
      final profile = await (() async {
        if (!await hasConnectivity()) throw AuthFailure.networkUnavailable;
        _requireSessionOwner(user.id);
        if (budgetExpired) throw AuthFailure.networkUnavailable;
        if (restoreSession && isLocalSessionExpired) {
          try {
            final response = await _client.auth.refreshSession();
            if (response.session == null) throw AuthFailure.sessionRestoreFailed;
          } catch (e) {
            throw AuthFailure.classify(e, fallback: AuthFailure.sessionRestoreFailed);
          }
        }
        _requireSessionOwner(user.id);
        if (budgetExpired) throw AuthFailure.networkUnavailable;
        return getCurrentProfile();
      })().timeout(_recoveryBudget, onTimeout: () {
        budgetExpired = true;
        throw TimeoutException('Startup network recovery deadline');
      });
      _requireSessionOwner(user.id);
      if (profile != null) {
        await SecurePrefsService.setCachedProfile(profile)
            .timeout(const Duration(seconds: 2));
      }
      _requireSessionOwner(user.id);
      return profile;
    } catch (e) {
      // Only a connectivity failure may fall back to the cache. Any other
      // refusal keeps its own stage so it cannot masquerade as one.
      if (!looksLikeConnectivityError(e)) {
        throw AuthFailure.classify(e, fallback: AuthFailure.unknownPostAuth);
      }

      debugPrint('[AUTH] Profile fetch: networkUnavailable; trying cache');
      _requireSessionOwner(user.id);
      final cached = await getCachedProfileForCurrentInspector();
      _requireSessionOwner(user.id);
      if (cached != null) return cached;
      throw AuthFailure.networkUnavailable;
    }
  }
}
