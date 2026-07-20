/// Temporary kill-switch for the Quick Unlock (pattern) login feature.
///
/// Set back to `true` to restore it — the underlying implementation
/// (QuickUnlockService, QuickUnlockScreen, QuickUnlockSetupScreen, the
/// pattern lock UI) is untouched and still fully wired up; this flag
/// only hides the entry points in login_screen.dart and
/// profile_screen.dart so users can't reach a feature that isn't
/// working yet.
const bool kQuickUnlockEnabled = false;