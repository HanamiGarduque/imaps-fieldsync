import 'package:flutter/foundation.dart';
import 'db_helper.dart';
import 'secure_prefs_service.dart';

/// Result of a reconciliation check — tells the caller what happened so
/// it can decide what (if anything) to show the person.
enum LocalDataReconcileResult {
  /// First run on this device, or same inspector as last time — nothing
  /// to do, most common case by far.
  ok,

  /// A different inspector just logged in, and the previous inspector's
  /// local data was successfully cleared.
  wipedForNewOwner,

  /// A different inspector just logged in, but the previous inspector had
  /// unsynced work (pending_actions) still on this device — nothing was
  /// touched, on purpose. See class doc below.
  blockedPendingSync,
}

/// Known Issue #4 (AUTH_SECURITY_MASTER_DOC.md §17) — a normal logout
/// never cleared local SQLite inspection data (applicant names, GPS,
/// findings, photos), so on a device shared between different
/// inspectors, one inspector's data could remain visible/present after
/// another logs in. §4.7 already encrypts that data at rest, but
/// encryption alone doesn't stop it from still being *there* for whoever
/// is legitimately using the app next.
///
/// This does NOT wipe on every logout — that would break the offline-
/// continuity model §14 is built around (a soft logout is meant to let
/// the *same* inspector come straight back in via biometric with all
/// their cached work intact). It only fires when a **different**
/// inspector's user id successfully authenticates on this device than
/// whichever one's data is currently cached — which can only actually
/// happen via a fresh password login, since biometric/cold-start-valid-
/// session paths can only ever resume the one single live session already
/// on the device, never introduce a different person's.
class LocalDataGuardService {
  LocalDataGuardService._();

  /// Call this once, right after a successful password login, with the
  /// just-authenticated user's id. Never call this from the biometric or
  /// cold-start-valid-session paths — there's no "different user" case to
  /// detect there, and calling it defensively anyway would just add a
  /// pointless local query to the hot path.
  static Future<LocalDataReconcileResult> reconcileLocalDataOwnership(
    String authenticatedUserId,
  ) async {
    final currentOwner = await SecurePrefsService.getLocalDataOwnerId();

    if (currentOwner == null) {
      // First login ever on this device install — nothing to reconcile,
      // just start tracking.
      await SecurePrefsService.setLocalDataOwnerId(authenticatedUserId);
      return LocalDataReconcileResult.ok;
    }

    if (currentOwner == authenticatedUserId) {
      return LocalDataReconcileResult.ok;
    }

    // A different inspector than whoever's data is cached locally.
    final pending = await DBHelper.getPendingActionsCount();
    if (pending > 0) {
      // Refuse to touch anything — this would be real, possibly
      // unrecoverable field-inspection work. Surface this to the person
      // instead of silently doing nothing or silently destroying it.
      debugPrint('[DATA_GUARD] Different inspector logged in, but $pending '
          'unsynced action(s) belong to the previous one — refusing to wipe.');
      return LocalDataReconcileResult.blockedPendingSync;
    }

    await DBHelper.wipeAllLocalData();
    await SecurePrefsService.setLocalDataOwnerId(authenticatedUserId);
    debugPrint('[DATA_GUARD] Different inspector logged in, previous '
        "inspector's local data cleared (nothing was pending sync).");
    return LocalDataReconcileResult.wipedForNewOwner;
  }
}