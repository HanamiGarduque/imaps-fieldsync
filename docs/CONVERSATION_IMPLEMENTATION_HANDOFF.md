# iMAPS FieldSync Implementation Handoff

## Purpose

This document records the important implementation work, diagnostics, manual test flows, architectural decisions, and remaining risks from the current engineering conversation. It is intended as a handoff and manual QA guide for the canonical workspace:

`C:\Users\Ralph Lauren\imaps_fieldsync_main`

This document does not replace the design specifications. It summarizes what was investigated or changed and what an inspector or developer needs to know before further testing.

## Important Rules

- Preserve the existing Flutter architecture.
- Reuse the existing `UserProfile` model and `MainShellScreen` state ownership.
- Do not create duplicate profile stores or global state systems.
- Do not infer task category from `scheduled_date` alone.
- `is_self_scheduled` is the deliberate scheduling flag.
- Do not treat Android system logs as iMAPS application failures without checking the process name.
- Do not commit, push, reset, stash, or discard unrelated worktree changes.

## Main Areas Covered

1. My Tasks category and indicator semantics.
2. My Tasks contextual information popup.
3. Sync Center informational explanations.
4. Profile and Home Dashboard profile propagation.
5. Automatic app locking after inactivity.
6. Profile and App Lock logout semantics.
7. ListTile ink/ripple framework exception.
8. Analyzer cleanup and focused validation.

---

# 1. My Tasks Category Truth

## Category Rules

The category logic is owned by `TaskItem.category` in:

`lib/modules/tasks/screens/tasks_screen.dart`

The current intended order is:

```text
status completed/done              -> Completed
is_self_scheduled = true           -> Scheduled
status in_progress/ongoing         -> Ongoing
otherwise                          -> Pending
```

The critical rule is:

```text
status = in_progress
AND
is_self_scheduled = false
=> Ongoing
```

A populated `scheduled_date` must not independently make a task Scheduled.

## Scheduled In Progress

A task with:

```text
status = in_progress
is_self_scheduled = true
```

remains Scheduled and may show the Scheduled-only `In Progress` indicator when:

```text
category == Scheduled
AND current_step >= 1
AND current_step <= 5
```

Ongoing tasks must not receive that Scheduled-only indicator.

## Loading and Filtering

Online tasks are loaded through:

`SupabaseService.fetchMyJobs()`

The query is scoped to the assigned inspector and does not intentionally limit or paginate the Ongoing records.

`TasksScreen._categorizeAndFilter()` applies user-selected search, barangay, date, and urgency filters before adding tasks to their category list. When diagnosing a missing Ongoing task, first clear all filters and confirm the app is using fresh online data rather than an incomplete local cache.

## Supabase Fields Used

The task model reads these fields:

- `status`
- `scheduled_date`
- `deadline_date`
- `is_self_scheduled`
- `current_step`
- `started_at`
- `rework_started_at`
- `submitted_at`

The offline task mapping also passes `status`, `scheduled_date`, `deadline_date`, and `is_self_scheduled` from `local_jobs`.

---

# 2. My Tasks Visit Row Fix

## Problem

The old helper was:

```dart
bool get isScheduledPlan => scheduledDate.isNotEmpty || isSelfScheduled;
```

The Visit row used that helper, so an Ongoing task with a populated `scheduled_date` could show a Visit row even though it was not deliberately self-scheduled.

## Implemented Rule

The Visit row now requires deliberate scheduling:

```dart
category == 'Scheduled'
AND
isSelfScheduled == true
AND
scheduledDate.isNotEmpty
```

This preserves the category logic and only changes the rendering condition for the Visit row.

## Manual Test: Ongoing Visit Row

1. Use an `in_progress` task with `is_self_scheduled = false` and a populated `scheduled_date`.
2. Open My Tasks.
3. Open the Ongoing tab.
4. Find the task.
5. Confirm it does not show `Visit: ...`.
6. Confirm it does not show the Scheduled-only `In Progress` pill.
7. Confirm its category remains Ongoing.
8. Confirm the task can still show deadline-based Due Today or Overdue indicators when applicable.

## Manual Test: Scheduled In Progress Visit Row

1. Use an `in_progress` task with `is_self_scheduled = true` and a populated `scheduled_date`.
2. Open the Pending tab and Scheduled section.
3. Confirm the Visit row is visible.
4. If `current_step` is 1 through 5, confirm `In Progress` is visible.
5. Confirm the task is not classified as Ongoing.

---

# 3. My Tasks Contextual Information Popup

The popup is opened by the single `Icons.info_outline_rounded` control beside the applicant/task name in `_CompactTaskCard`.

It must explain only indicators applicable to the current card.

## Current Indicator Conditions

### Available Anytime

Condition:

```text
task.category == Pending
```

Meaning: no deliberate visit date; inspection may be done before the admin deadline.

### Scheduled

Condition:

```text
task.category == Scheduled
AND task.isSelfScheduled == true
```

Meaning: inspector deliberately selected a visit date.

### Ongoing

Condition:

```text
task.category == Ongoing
```

Meaning: work has started without a deliberate fixed visit date.

### Completed

Condition:

```text
task.category == Completed
```

Meaning: inspection was finished and submitted.

### Modified

Condition:

```text
task.category == Completed
AND task.reworkStartedAt != null
```

Meaning: submitted information was edited after completion.

### In Progress

Condition:

```text
task.category == Scheduled
AND currentStep >= 1
AND currentStep <= 5
```

Ongoing must never receive this Scheduled-only explanation.

### Visit Row

Condition:

```text
task.category == Scheduled
AND task.isSelfScheduled
AND task.scheduledDate.isNotEmpty
```

The popup should explain Visit only when this condition is true.

### Deadline Row

Condition:

```text
task.category != Completed
AND deadlineDate is not empty
```

Meaning: admin-set completion deadline.

### Due Today

The meaning depends on the source:

- Scheduled task with visit date today: visit is due today.
- Available Anytime or Ongoing task with deadline today: admin deadline is due today.

The popup must not always call the date a scheduled visit.

### For Reschedule

Visible for a Scheduled task when the visit date has passed but the admin deadline has not passed.

The popup must use the same Scheduled applicability as the visible pill.

### Overdue

Condition:

```text
active task
AND admin deadline has passed
```

Only one Overdue explanation should appear.

### Blue Border

Blue is the normal state:

- Scheduled visit is not close.
- Available Anytime has no urgent deadline.
- Ongoing is not deadline-urgent.

### Orange Border

Scheduled visit date is 2 to 3 days away.

### Red Border

Red can come from two different meanings:

1. Scheduled visit date is today, tomorrow, or already passed.
2. Active admin deadline is overdue.

These meanings should not be collapsed into one explanation.

### Full Red Container/Tint

Condition:

```text
active task
AND admin deadline has passed
```

This is separate from a Scheduled visit-date Red border. The full red treatment communicates active deadline overdue status.

### Deadline Today / Deadline Tomorrow

These labels are deadline-based urgency indicators and need their own explanation when visible.

### Progress Indicator

The card always displays a step progress bar and `STEP n/total`. This is workflow progress rather than a category or urgency tag. Decide explicitly whether the popup scope includes it; if it does, add a matching explanation.

## Manual Test: Popup Coverage

Test at least these cards:

1. Available Anytime, normal deadline.
2. Available Anytime, deadline today.
3. Available Anytime, overdue deadline.
4. Scheduled with far visit date.
5. Scheduled with visit 2 to 3 days away.
6. Scheduled with visit today.
7. Scheduled with passed visit and future deadline.
8. Scheduled with overdue deadline.
9. Scheduled in progress with `current_step` 1 to 5.
10. Ongoing with populated `scheduled_date` but `is_self_scheduled = false`.
11. Completed without rework.
12. Completed with `reworkStartedAt != null`.

For each card:

- Tap the single info icon.
- Compare the popup entries against the pills, border, tint, Visit row, Deadline row, and progress state actually visible.
- Confirm no irrelevant Scheduled-only entry appears on Ongoing.
- Confirm no Due Today, For Reschedule, or Overdue entry appears on Completed.
- Confirm Overdue appears only once.

---

# 4. Sync Center Informational Flow

File:

`lib/modules/offline_sync/screens/updates_screen.dart`

The Sync Center uses one information control per meaningful section, using:

```dart
Icons.info_outline_rounded
```

## Intended Inspector Explanation

Sync Center is the place to understand what happens to inspection information while working offline and after the internet returns.

The explanation should communicate:

1. Information completed offline stays safely on the phone while waiting.
2. The inspector can continue working without a connection.
3. When connectivity returns, waiting information can be sent to the main system.
4. The Sync Center shows whether updates are already sent or still waiting.

## Sections

### Sync Center

Explains the complete offline-to-online lifecycle.

### Sync Performance

Explains whether updates are being sent successfully and that offline work may wait until connectivity returns.

### Synchronization Audit History

Explains attempts to send information and whether each attempt succeeded.

### Offline Storage Cache

Explains that task information is stored on the phone for offline work.

### Completed Audit Log

Explains that successfully sent updates are recorded so the inspector can confirm receipt.

## Manual Test: Sync Center

1. Open Sync Center while online.
2. Tap the main Sync Center information icon.
3. Confirm the explanation describes both offline and online behavior.
4. Disable connectivity.
5. Open or update an inspection.
6. Confirm the inspector can continue working.
7. Open Sync Center and inspect waiting/pending information.
8. Restore connectivity.
9. Wait for automatic synchronization or use the existing sync action.
10. Confirm the waiting item moves to the completed audit history when successful.
11. Confirm no sync behavior was changed by wording-only edits.

---

# 5. Profile Data Propagation

## Authoritative Model

`lib/core/models/user_profile.dart` defines `UserProfile` with:

- `id`
- `fullName`
- `role`
- `phoneNumber`
- `avatarUrl`
- `email`

Supabase `profiles` already contains the corresponding fields:

- `id`
- `full_name`
- `role`
- `phone_number`
- `avatar_url`

## Intended Flow

```text
Profile/Edit Profile
  -> update profiles row / avatar storage
  -> Navigator.pop(updated UserProfile)
  -> parent receives UserProfile
  -> MainShellScreen updates _currentProfile
  -> HomeDashboardScreen receives new profile
  -> greeting, avatar, and future edit form use new data
```

## Profile Tab Path

`ProfileScreen._openEditScreen()` awaits `ProfileEditScreen`, updates its local profile, and calls the existing parent callback.

## Home Avatar Path

`HomeDashboardScreen` must await the existing `ProfileEditScreen` route and pass the returned `UserProfile` through `onProfileUpdated`.

`MainShellScreen` must accept that profile and replace `_currentProfile`.

## Manual Test: Profile Refresh

1. Start on Home.
2. Record the greeting name and avatar/initials.
3. Open the main Profile tab.
4. Open Edit Profile.
5. Change full name.
6. Change phone number.
7. Change profile photo if supported.
8. Save.
9. Return to Home.
10. Confirm the greeting uses the new name.
11. Confirm the avatar uses the new URL/photo or new initials.
12. Tap the Home avatar again.
13. Confirm Edit Profile opens with the new name and phone number.
14. Confirm Recent Activity contains the existing profile update event when logging succeeds.

## Important Unresolved Environment Note

During this conversation, the editor buffer and analyzer-visible filesystem for `main_shell_screen.dart` repeatedly diverged. The editor view showed the intended `UserProfile` callbacks while direct disk reads and Flutter analyzer still saw the old no-argument callbacks:

```dart
onProfileUpdated: () => setState(() {}),
```

Before considering the profile fix complete, verify the actual saved file on disk and ensure both Home Dashboard callback assignments are:

```dart
onProfileUpdated: (profile) => setState(() => _currentProfile = profile),
```

Then run focused analysis. Do not trust only the editor tab contents.

---

# 6. Automatic App Lock

## Intended Behavior

Automatic locking has two paths:

1. App background/resume path.
2. Foreground inactivity path.

The shell owns the timer and lifecycle observer in:

`lib/core/navigation/main_shell_screen.dart`

## Settings

`SecurePrefsService` stores:

- `-1`: immediately
- `0`: never
- `1`: one minute
- `5`: five minutes
- `10`: ten minutes

The `shouldLockAfterElapsed` helper is the threshold source.

## Foreground Inactivity

The shell starts an inactivity timer using the stored setting. Pointer activity resets it. The timer rechecks:

- Require-on-open setting.
- Auto-lock minutes.
- Biometric enrollment.
- Biometric confirmation.

## Manual Test: One-Minute Lock

1. Enable biometric protection.
2. Complete biometric confirmation with a normal password login.
3. Enable `Require When Opening App`.
4. Select `1 Minute` under Automatic Lock.
5. Open the main app/dashboard.
6. Do not touch the app for slightly longer than one minute.
7. Confirm `App Locked` appears.
8. Confirm the biometric prompt starts.
9. Confirm successful biometric authentication returns to the app.
10. Confirm tapping Log Out exits to the Login screen.

## Manual Test: Never

1. Set Automatic Lock to `Never`.
2. Leave the app untouched for longer than the previous threshold.
3. Confirm no lock screen appears.

## Manual Test: Background Resume

1. Set a one-minute lock period.
2. Put the app in the background.
3. Wait longer than one minute.
4. Resume the app.
5. Confirm the lock screen appears.

---

# 7. Logout Semantics

## Profile Page

The Profile action label is `Log Out`, not `Sign out`.

The action uses the red destructive semantic color.

## App Lock

The App Lock action label is `Log Out` and uses the red destructive semantic color.

The existing callbacks and logout behavior remain unchanged.

## Manual Test

1. Open Profile.
2. Tap `Log Out`.
3. Confirm the confirmation modal appears.
4. Confirm the action button is red and labeled `Log out`.
5. Cancel and confirm the account remains in the app.
6. Repeat and confirm logout returns to Login.
7. Trigger App Lock.
8. Tap `Log Out`.
9. Confirm the app returns to Login.

---

# 8. ListTile Ink/Ripple Exception

## Observed Exception

Flutter reported:

```text
ListTile background color or ink splashes may be invisible.
```

## Confirmed Cause

In `ProfileEditScreen._pickAvatarSource()`, the avatar-source bottom sheet had:

```text
Decorated Container with background and rounded corners
  -> ListTile
```

The ListTile had no local Material ancestor, so its ink splash could be hidden by the decorated parent.

## Implemented Fix

Each avatar-source ListTile is wrapped in:

```dart
Material(
  color: Colors.transparent,
  child: ListTile(...),
)
```

The bottom-sheet background, radius, spacing, icons, labels, and actions are unchanged.

## Manual Test

1. Open Edit Profile.
2. Tap the avatar.
3. Confirm the photo-source bottom sheet opens.
4. Tap `Take a photo` and confirm the camera path works.
5. Reopen and tap `Choose from gallery`.
6. Confirm the gallery path works.
7. Confirm no ListTile ink/background exception appears in the Flutter log.

---

# 9. Logout and Profile Activity Logging

The existing `SupabaseService.logActivity(...)` path is used for Recent Activity.

Profile-related events include:

- Profile information updated.
- Profile photo updated.

Manual verification:

1. Save a name or phone change.
2. Open Home Recent Activity.
3. Filter to Profile if the filter is available.
4. Confirm the profile update event appears after the backend insert succeeds.

Activity logging is best effort and must not block profile saving.

---

# 10. Android and Device Log Interpretation

The following log lines are not automatically iMAPS application failures:

### OnBackInvokedCallback

Android warning about enabling predictive back support. Treat separately unless back navigation is functionally broken.

### Realme Link ARouter

If the process is:

```text
com.realme.link:link.monitor
```

it belongs to the device companion process, not:

```text
com.example.imaps_fieldsync
```

Do not attribute that crash to iMAPS without matching the process name.

### Compass calibration

`FlutterCompassPlugin` may report unreliable sensor calibration. Calibrate the device before treating it as an app bug.

### Skipped frames / IME jank

These indicate performance pressure or dropped frames. Investigate separately from functional errors.

### SQLite JNI lock

A long Sqflite JNI critical lock may contribute to startup or interaction jank. It does not by itself prove data corruption.

### OneSignal HTTP 200

OneSignal feature-flag responses with HTTP 200 are successful network activity.

### Impeller opt-out

Flutter reports that explicit Impeller opt-out is deprecated. This is a future compatibility cleanup, not the current UI exception.

---

# 11. Validation Commands

Focused analyzer examples:

```powershell
Set-Location 'C:\Users\Ralph Lauren\imaps_fieldsync_main'
flutter analyze lib/modules/tasks/screens/tasks_screen.dart
flutter analyze lib/modules/offline_sync/screens/updates_screen.dart
flutter analyze lib/modules/profile_settings/screens/profile_edit_screen.dart
flutter analyze lib/core/navigation/main_shell_screen.dart lib/modules/analytics_dashboard/screens/home_dashboard_screen.dart
```

Diff validation:

```powershell
git diff --check -- lib/modules/tasks/screens/tasks_screen.dart
git diff --check -- lib/modules/offline_sync/screens/updates_screen.dart
git diff --check -- lib/modules/profile_settings/screens/profile_edit_screen.dart
git diff --check -- lib/core/navigation/main_shell_screen.dart lib/modules/analytics_dashboard/screens/home_dashboard_screen.dart
```

Important: some analyzer commands previously reported existing infos such as deprecated `withOpacity`, unnecessary imports, and style preferences. Distinguish those from compile errors and task-specific failures.

The focused My Tasks validation after the indicator changes passed:

```text
flutter analyze lib/modules/tasks/screens/tasks_screen.dart
No issues found!
```

---

# 12. Final QA Checklist

## My Tasks

- [ ] Ongoing is based on `in_progress` plus `is_self_scheduled = false`.
- [ ] Ongoing never shows Visit.
- [ ] Ongoing never shows Scheduled-only In Progress.
- [ ] Scheduled in-progress tasks remain Scheduled.
- [ ] Visit only appears for deliberate Scheduled tasks.
- [ ] Due Today explains visit date or admin deadline correctly.
- [ ] For Reschedule appears only for Scheduled tasks.
- [ ] Overdue appears once.
- [ ] Full red treatment means admin deadline overdue.
- [ ] Red visit urgency and red deadline overdue meanings are distinguishable.
- [ ] Completed has no active priority explanations.
- [ ] Modified appears only for completed rework state.
- [ ] Popup entries match visible indicators.

## Sync Center

- [ ] Sync Center popup explains offline-to-online lifecycle.
- [ ] Sync Performance explains waiting updates.
- [ ] Offline Storage Cache explains offline work availability.
- [ ] Audit History explains send attempts and success.
- [ ] Completed Audit Log explains received updates.
- [ ] Exactly one info icon appears per intended section.

## Profile and Home

- [ ] Profile save persists full name and phone.
- [ ] Avatar upload persists `avatar_url`.
- [ ] Updated `UserProfile` returns from Edit Profile.
- [ ] MainShell updates `_currentProfile`.
- [ ] Home greeting updates.
- [ ] Home avatar/initials updates.
- [ ] Edit Profile opened from Home receives current data.
- [ ] Recent Activity receives profile update event.

## Automatic Lock

- [ ] One-minute foreground inactivity locks.
- [ ] Background resume lock works.
- [ ] Never does not lock.
- [ ] Biometric unlock returns to the app.
- [ ] Log Out from App Lock returns to Login.

## Device Log

- [ ] No ListTile ink exception after opening avatar source picker.
- [ ] Ignore unrelated Realme Link process crash.
- [ ] Treat compass calibration as device state.
- [ ] Track skipped frames separately from correctness.

---

# 13. Current Caveats

- The supplied database export was a `field_jobs` export, not a `profiles` export. Profile schema support was verified from local schema files and Flutter mappings.
- The 8-versus-9 Ongoing discrepancy could not be proven to a specific record without the runtime-loaded task IDs or local cache snapshot, although the source contains no intentional Ongoing pagination or limit.
- The editor buffer and analyzer-visible filesystem repeatedly diverged for `main_shell_screen.dart`. Always verify the saved disk file before trusting editor contents.
- Do not declare the Home profile propagation fix complete until the saved MainShell file contains both UserProfile-aware Home callbacks and focused analyzer confirms the two callback type errors are gone.
- Device testing remains necessary for real-time profile display, automatic lock timing, offline-to-online sync, ListTile ripple behavior, and scroll smoothness.

---

# 14. Change Safety

This handoff is documentation only. It does not authorize changing:

- Supabase schema
- SQLite schema
- Sync services
- Authentication
- Navigation architecture
- My Tasks category truth
- Inspection persistence
- Photo persistence
- Database data

Before any future implementation, inspect the current worktree and preserve unrelated user changes.
