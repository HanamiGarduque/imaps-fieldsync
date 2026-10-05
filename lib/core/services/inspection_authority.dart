enum InspectionAuthorityResult {
  authorized,
  notAssignedOrUnavailable,
  authRequired,
  offlineOrUnverifiable;

  String get message => switch (this) {
    authorized => '',
    notAssignedOrUnavailable => 'This job is no longer available to start or update from your account. '
      'Your local work is preserved. Refresh assignments or contact the Planning Office.',
    authRequired => 'Your session has expired. Please sign in again.',
    offlineOrUnverifiable => 'Connect to verify this job before continuing remote writes. '
      'Your local work is preserved.',
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
