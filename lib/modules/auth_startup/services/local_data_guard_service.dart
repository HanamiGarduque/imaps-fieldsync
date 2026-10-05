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

/// v17 row-level ownership replaces destructive account-switch reconciliation.
/// Foreign and unattributed evidence stays stored and is inaccessible to the
/// new session. The original inspector can return to their own rows later.
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
    // v17 isolates by the durable row owner, not a device-wide preference.
    // Account changes never authorize destructive cleanup or legacy backfill.
    return LocalDataReconcileResult.ok;
  }
}
