/// Server revisions this device itself produced or accepted through an
/// authoritative write.
///
/// The outbox stores an `updated_at` snapshot when an action is queued, then
/// compares it with the server before replaying. That snapshot alone is not
/// enough: a successful write from this same device (a direct start/GPS write,
/// or an earlier action in the same drain) advances the row's revision, and a
/// queued sibling action would otherwise mistake its own predecessor's write
/// for an external edit. Tracking the revision accepted by each authoritative
/// write keeps those ordinary offline updates in "waiting to sync".
///
/// In-memory only, per session; it is never treated as a durable receipt.
class JobRevisionTracker {
  JobRevisionTracker._();

  static final Map<String, String> _accepted = {};

  /// The latest revision this device accepted for [jobId], if any.
  static String? revisionFor(String jobId) {
    final value = _accepted[jobId];
    return value != null && value.isNotEmpty ? value : null;
  }

  /// Remembers the revision returned by an accepted write. Invalid or missing
  /// values are ignored so a bad response cannot weaken later conflict checks.
  static void record(String jobId, Object? updatedAt) {
    if (updatedAt is! String) return;
    final value = updatedAt.trim();
    if (value.isEmpty || DateTime.tryParse(value) == null) return;
    _accepted[jobId] = value;
  }

  static void clear() => _accepted.clear();
}
