enum InspectionAuthorityResult {
  authorized,
  notAssignedOrUnavailable,
  authRequired,
  serverRejected,
  offlineOrUnverifiable,
  localOwnershipIncomplete;

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
