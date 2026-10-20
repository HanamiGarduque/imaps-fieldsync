enum InspectionAuthorityResult {
  authorized,
  notAssignedOrUnavailable,
  authRequired,
  serverRejected,
  offlineOrUnverifiable,
  localOwnershipIncomplete,

  /// The requested visit date is outside the window the PO deadline allows:
  /// not after today, or later than the PO deadline itself.
  visitDateNotAllowed,

  /// The PO deadline could not be read or parsed, so no verified upper bound
  /// exists. Scheduling stays closed rather than inventing one.
  deadlineUnavailable,

  /// The PO deadline is today or has already passed, so no further visit may
  /// be scheduled. The inspection itself may still continue.
  deadlinePassed;

  String get message => switch (this) {
    authorized => '',
    notAssignedOrUnavailable =>
      'This job is no longer available to start or update from your account. '
          'Your local work is preserved. Refresh assignments or contact the Planning Office.',
    authRequired => 'Your session has expired. Please sign in again.',
    serverRejected =>
      'The server rejected this update. Your local work is preserved. '
          'Review the inspection details and your assignment, or contact the Planning Office before retrying.',
    offlineOrUnverifiable =>
      'Connect to verify this job before continuing remote writes. '
          'Your local work is preserved.',
    localOwnershipIncomplete =>
      "This older task can't be safely resumed on this device because its "
          'local ownership information is incomplete. Your local data is preserved.',
    visitDateNotAllowed =>
      'The visit date is not allowed. Choose a date after today and on or '
          'before the PO deadline.',
    deadlineUnavailable =>
      'The PO deadline could not be verified, so scheduling is unavailable. '
          'Continue your inspection or ask the Planning Office to confirm the deadline.',
    deadlinePassed =>
      'The PO deadline is today or has passed. You cannot schedule another '
          'visit. Continue your inspection or coordinate with the Planning Officer.',
  };

  void requireAuthorized() {
    if (this != authorized) throw InspectionAuthorityException(this);
  }
}

class InspectionAuthorityException implements Exception {
  final InspectionAuthorityResult result;
  const InspectionAuthorityException(this.result);
  @override
  String toString() => result.message;
}

// Compatibility for the closed #8 pre-start API.
typedef InspectionStartResult = InspectionAuthorityResult;

/// Compare the complete submitted evidence, including nested checklist values.
/// Map ordering is irrelevant; photo/checklist list ordering is preserved.
bool sameInspectionEvidence(dynamic a, dynamic b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every(
          (key) => b.containsKey(key) && sameInspectionEvidence(a[key], b[key]),
        );
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!sameInspectionEvidence(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
