# POST-MIGRATION VALIDATION PLAN

## InSight – iMAPS FieldSync

### Status: NOT STARTED — begins only after MIGRATION_CLOSURE_REPORT.md Section E is signed

**Governing relationship:** This is a **separate** plan from
MASTER_MERGE_PLAN.md. It does not reopen migration work. Its only job is
to verify that migration did not introduce regressions in previously
working application behavior. Any fix made here must be traceable to a
confirmed regression (Section 2 below) — never a general "improvement."

---

## 0. Precondition

Do not begin this plan until `MIGRATION_CLOSURE_REPORT.md` Section E is
signed (`MASTER_MERGE_PLAN v1.0: CLOSED`). Testing against a tree that
still contains unresolved Gate 0 items would make it impossible to tell
whether a bug is a real pre-existing/migration issue or an artifact of
those unresolved items.

---

## 1. Test Areas and Cases

Testing is manual, performed by the Master (not the agent) on the
physical device, unless otherwise noted. The agent's role in this phase
is limited to: fixing confirmed regressions once explicitly instructed,
and never touching code proactively.

### A. Authentication
- Normal login (correct credentials)
- Incorrect password handling
- Logout
- Session expiry
- Session refresh
- Offline login behavior
- Network unavailable during login
- Supabase unavailable during login

### B. Biometric Security
- Biometric enrollment
- Biometric login (success path)
- Biometric login (failure path)
- Cancelled biometric prompt
- Device without biometric hardware/enrollment
- Logout while biometric is enrolled
- Biometric enrollment state persists across app restarts

### C. Security (general)
- Screenshot / screen-recording protection (`ScreenProtectionService` / `SensitiveScreen`)
- Auth guards on protected routes
- Token/session handling correctness
- Logout fully clears expected state
- Security/audit event logging (if applicable)
- Local data protection (`LocalDataGuardService` — cross-inspector device reconciliation)
- Unauthorized navigation attempts blocked
- Offline security behavior (lock screen, resume lock)

### D. Tasks
- Task creation
- Task loading
- Status transitions (Pending → Ongoing → Scheduled → Completed, as applicable)
- Current step / remaining steps display
- Task completion
- Reopening a task
- Persistence across app restarts

### E. Inspection Workflow
- Create inspection
- Checklist flow
- Field findings entry
- GPS verification
- Photo capture / evidence attachment
- Local save
- Reopening an in-progress inspection
- Progress persistence

### F. Offline Mode
- Online → cache → offline transition
- Data collection while offline
- Offline → online transition
- Sync trigger on reconnect
- Server-side verification of synced data

### G. Sync Center
- Pending sync queue display
- Photo upload
- Inspection upload
- Failed sync handling
- Retry behavior
- Successful sync confirmation
- Duplicate-sync prevention
- Local cleanup after successful sync

### H. General UI/UX
- Navigation between screens
- Pull-to-refresh where applicable
- Animations (motion widgets)
- Responsiveness / layout on device
- Orientation changes
- Keyboard behavior on forms
- Long-text handling
- GPS coordinate display
- Charts/dashboard widgets render correctly
- Buttons, dialogs, snackbars behave as before

---

## 2. Result Classification

Every test case result is recorded using exactly one of these four
labels — no other categories:

| Label | Meaning | Action |
|---|---|---|
| ✅ PASS | Works as it did before migration | None |
| 🔴 MIGRATION REGRESSION | Worked before migration, broken now | Fix, per priority order in Section 3 |
| 🟡 PRE-EXISTING BUG | Broken before migration too | Log only — out of scope for this plan unless Master separately authorizes a fix |
| 🔵 NEW IMPROVEMENT OPPORTUNITY | Works, but could be better | Log only — no action under this plan |

This classification is what prevents scope creep: only 🔴 items get
fixed here. 🟡 and 🔵 are recorded for a future, separate task.

### 2.1 Regression Verification Rule

An issue may be classified as **🔴 MIGRATION REGRESSION** only when there
is sufficient evidence that:

1. the functionality worked before migration;
2. the same functionality is broken after migration;
3. the failure is reproducible on the migrated baseline; and
4. the failure can reasonably be associated with a migration-time change
   rather than environment, server, configuration, credentials, network,
   device state, or a pre-existing defect.

If these four conditions cannot be established, the issue must not be
labeled a migration regression without Master review — default to
🟡 PRE-EXISTING BUG / investigation pending instead.

**Example (why this rule matters):** a login attempt during validation
may surface an error such as a failed DNS host lookup against the
Supabase project URL, or an `AuthRetryableFetchException`. These are
network/connectivity/service-availability symptoms — on their own they
do **not** satisfy condition 4 above, since they are not evidence of a
migration-time source change. Such findings should be logged and
investigated (network state, credentials, Supabase project status)
before any 🔴 label is applied.

---

## 3. Fix Priority Order (for 🔴 MIGRATION REGRESSION items only)

1. Security / authentication regressions
2. Core workflow regressions (Tasks, Inspection)
3. Offline / sync regressions
4. UI/UX regressions
5. (Everything else stays logged, not fixed, under this plan)

No feature expansion. No refactors. A fix here means: restore the
pre-migration behavior, using the same content-diff discipline that
found the Gate 0 issues in the first place — i.e. any fix patch should
be reviewed for import-only vs. logic-touching scope before being
applied.

---

## 4. Test Log Template

For each test case actually run, record:

```
Area: _______________
Case: _______________
Date: _______________
Pre-Migration Evidence: _______________
  (how do we know this worked before? e.g. prior test result, prior
  build, screenshot, log, existing documentation, Master confirmation,
  prior commit — required before a 🔴 label is applied, per Rule 2.1)
Result: PASS / MIGRATION REGRESSION / PRE-EXISTING BUG / NEW IMPROVEMENT
Observed Behavior: _______________
Expected Behavior: _______________
Evidence: _______________
Notes: _______________
```

---

## 5. Completion Criteria

This plan is complete when:
- Every test case in Section 1 has a recorded result (Section 4).
- Every 🔴 MIGRATION REGRESSION has been fixed and re-tested to PASS.
- Every 🟡 and 🔵 item is logged in a backlog, explicitly out of scope here.
- The Master signs off on a final "Post-Migration Baseline."

Only after this plan is complete does the project return to normal
feature/bug-fix development outside any migration-specific process.
