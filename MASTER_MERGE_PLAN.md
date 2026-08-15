# MASTER_MERGE_PLAN

InSight – iMAPS FieldSync
Master Merge Plan (MMP v1.0)

Status: EXECUTION AUTHORIZED — Ownership FROZEN, Dry Run PASSED (8/8),
Turn 1 Execution Authorization GRANTED. Physical migration (Step 0) has been initiated and the Step 0 rename footprint is present in the current tree; import repair and validator confirmation are in progress.
Governing Document: Master Architecture Specification (MAS v1.0)
Precedence: MAS > MMP > Approved MMS > Migration Reports (per MAS Rule 10)

Purpose: This document is the execution contract for the Frontend/Backend
Separation Project. It converts the rules and layer definitions of MAS v1.0
into a deterministic, reproducible, auditable, rollback-safe, conflict-free,
AI-safe sequence of actions. It contains no new architectural decisions.
Where a decision is missing, this document marks it PENDING and blocks
execution until resolved by the Master (per MAS Rule 9 / Rule 11).

Source data for this plan: static analysis of the actual `lib/` archive
(46 Dart files + 2 non-source `.bak` files), performed directly against the
repository rather than assumed from module descriptions.

---

# SECTION 1 — Migration Authority

- Only the Master (this document's author/approver) may issue execution
authorization for a batch.
- Each of the six module AIs (AI#1–AI#6) may act only within the batch and
file list explicitly assigned to them in Section 6.
- No module AI may move, rename, delete, duplicate, or edit a file not
listed under its own batch entry.
- No module AI may modify a Shared/Core file (Section 4) once this plan
enters execution — Shared/Core moves are performed only in the batch
explicitly designated for them, under Master supervision.
- No module AI may reinterpret, extend, or "fix" this plan. Deviations are
reported, not resolved locally (see Section 13).

# SECTION 2 — Execution Preconditions

Automatic checklist. If any item fails, STOP — do not proceed to Section 3.

- [ ] MAS v1.0 approved
- [ ] All 6 MMS approved and frozen
- [ ] MMP approved (this document)
- [x] Repository working tree clean (`git status` clean) — **RESOLVED.**
`local_data_guard_service.dart` committed at
`81e6e2ef78fbc9a833f2b775895f8c43189bb335`. `lib/`-scope working
tree is clean; remaining non-`lib/` items (zips, `.sql` files) are
pre-existing and out of migration scope (MAS Rule 6).
- [ ] Git branch created (`migration/master-merge`, see Section 10)
- [ ] Backup of full repository created outside the git history
- [ ] Reference Matrix (Section 5) reviewed and locked — `lib/`-scope
version complete; full repository-wide version still pending
(Outstanding Item 3)
- [x] Current physical location of every file in the Migration Inventory
recorded against live Git HEAD (Section 0-C) — **RESOLVED, all 54
files verified**, 0 discrepancies (Outstanding Item 1).
- [x] Dry Run (Section 0-A) completed with zero blocking findings —
**PASSED, 8/8**, re-run in full after the
`local_data_guard_service.dart` commit.
- [x] Ownership column in Migration Inventory (Section 4) confirmed —
**OWNERSHIP FROZEN.** All 14 Ownership Resolution Pass decisions
finalized and synced across Section 4, Section 5-C, and Section 6.
Per the Ownership Resolution Pass Rule, no further ownership
changes without a formal change request.

# SECTION 0-A — Dry Run Phase (no files moved)

**No Step 0, Step 0.5, or AI turn may begin until this Dry Run passes.**
This applies to the entire execution sequence, including Turn 1 — Step
0.5 is itself part of execution (it physically moves files), so it is
also gated by this Dry Run, not exempt from it.

Before any of the above is authorized, the Master performs a Dry Run:

1. Confirm the live repository's current file locations against the
Migration Inventory (Section 0-C) — flag any file not found at either
its archive-based Old Path or its Section 4 destination, so its real
current path can be recorded before Step 1 of that file's move.
2. Validate every destination path in Section 4 — no two files may resolve
to the same destination.
3. Validate ownership — every file has exactly one owner or is classified
Shared/Core; no file is unassigned. (Satisfied — Ownership Freeze,
see the Ownership Freeze — Declaration section.)
4. Validate dependencies — every import edge in Section 5 has both
endpoints present in Section 4.
5. Validate the Reference Matrix against Section 0-B (repository scope
notice) — confirm what is in scope and what is explicitly deferred.
6. Confirm no orphaned file (a file with no owner and no Shared/Core
classification) exists in the inventory.
7. Confirm the cross-layer and cross-module dependencies (Section 5-C)
are acknowledged and their turn-ordering implication is applied.
8. **Resolve the `local_data_guard_service.dart` untracked-baseline
question (Section 0-C) — either commit it into the repository baseline
before migration, or explicitly classify it as a working-tree
addition to be preserved and incorporated into the baseline.** Until
one of these is chosen, Section 2's "working tree clean" precondition
cannot be satisfied, and an uncontrolled `git reset --hard` (Section 9
rollback) could silently delete this file since it isn't committed.

If any check fails, migration does not start. Findings are reported back
to the Master for a plan revision (not a live in-flight fix).

**Dry Run re-run in full (all 8 items) after the `local_data_guard_service.dart`
commit — RESULT: ✅ PASS.**

Item
Result

1. Live file locations vs. Migration Inventory
✅ PASS — 54 files unaffected by the commit; `local_data_guard_service.dart` remains at its expected `lib/services/` path, now tracked

2. Destination path collisions
✅ PASS — no duplicates

3. Ownership completeness
✅ PASS — Ownership Freeze intact, no unassigned file

4. Dependency-graph consistency (Section 5)
✅ PASS — no imports changed by this commit

5. Reference Matrix vs. Section 0-B scope
✅ PASS (`lib/`-scope; full repo-wide remains a separate Gate F precondition, Outstanding Item 3 — does not block Turn 1)

6. No orphaned files
✅ PASS

7. Cross-layer/cross-module dependencies acknowledged
✅ PASS

8. `local_data_guard_service.dart` baseline resolved
✅ **PASS — committed at `81e6e2ef78fbc9a833f2b775895f8c43189bb335`, confirmed via `git status` and `git rev-parse HEAD`**

**8 of 8 items pass.** All Section 0-A Dry Run checks are satisfied.
**Execution Authorization for Turn 1 is now possible** — this document
does not self-authorize it; the Master gives that authorization
explicitly, separately, when ready.

> NOTE: The Step 0 rename footprint is currently present in the working
> tree. The migration script and validator have been corrected for the
> post-move import path rewrite bug that previously produced malformed
> stringified directory tails.

## ✅ Execution Authorization — GRANTED

The Master has explicitly authorized Turn 1 to proceed, following the
Dry Run PASS above. **This authorization covers the start of physical
migration execution — it is a distinct, separate decision from the Dry
Run passing, and is recorded here as its own event, not inferred.**

- Authorized by: the Master, this session.
- Precondition state at authorization: Ownership Freeze in effect (14
decisions, Section 4 synced), Dry Run 8/8 PASS,
`local_data_guard_service.dart` committed at
`81e6e2ef78fbc9a833f2b775895f8c43189bb335` on `main`.
- **What this authorization does NOT do by itself:** it does not create
the `architecture-lock` tag, does not execute Step 0, does not move any
file. Per Section 10, the `architecture-lock` tag is the first physical
action, performed by the Master, before Step 0 begins — that is a
separate, subsequent action from this authorization record.

# SECTION 0-B — Repository Scope Notice

This MMP's Migration Inventory and Reference Matrix were built from the
`lib/` directory only (the same archive scope the six MMS documents were
authored against). Per MAS Section 8 and Rule 6, the following remain
**out of scope** for this plan and are **not** touched by any module AI:
`test/`, `integration_test/`, `example/`, `tool/`, `scripts/`, platform
folders (`android/`, `ios/`, `windows/`, `linux/`, `macos/`, `web/`), CI/CD
config, generated files, build scripts, IDE metadata.

Per MAS Phase 0.5, a full repository-wide reference scan (beyond `lib/`)
is still required before any original file is deleted (Gate F). That scan
is **not** performed by this document — it is a separate, later step run
by the Master once Batch execution begins, using this document's
Migration Inventory as its input list of migrated paths.

Two files were found that are excluded from migration entirely as
non-source artifacts:

- `lib/screens/login_screen.dart.bak`
- `lib/screens/reset_password_screen.dart.bak`

These are `.bak` files, not active Dart source (not part of any build
target). No AI may move, delete, or otherwise act on them under this plan.
If they need to be addressed, that requires an explicit, separate Master
decision — they are flagged here, not resolved here.

**Document convention:** content in this MMP is always written in
third person, referencing the module by name/number ("AI#1's MMS
states...") — never first-person ("my MMS," "I own," "I analyzed").
First-person phrasing belongs only in an AI's own report to the Master,
never copied into this governing document.

# SECTION 0-C — Repository Baseline

The execution baseline is the **current Git HEAD of the working
repository**, not the original archive this MMP's Migration Inventory was
built from.

**🔴 CORRECTED (supersedes the entry below it) — verified directly
against `git status` / `Get-ChildItem` output from the live repository,
branch `main`, commit `29a892d`:**

File
Verified current path
Notes

auth_service.dart
lib/services/auth_service.dart
Tracked, at commit `29a892d`

biometric_service.dart
lib/services/biometric_service.dart
Tracked, at commit `29a892d`

secure_prefs_service.dart
lib/services/secure_prefs_service.dart
Tracked, at commit `29a892d`

screen_protection_service.dart
lib/services/screen_protection_service.dart
Tracked, at commit `29a892d`

local_data_guard_service.dart
lib/services/local_data_guard_service.dart
**Present in the live working tree, but `git status` lists it as Untracked — not yet committed at `29a892d`.** Do not treat as part of the committed repository baseline until it is committed; this distinction matters for the Dry Run.

None of the 5 are at `lib/backend/services/...` — that path, previously
reported as "confirmed" by AI#1, does not match the live repository and
is retracted below.

**This is a path-verification correction only — ownership is
unaffected.** All 5 files remain AI#1-owned per the Ownership Resolution
Pass (Section 4, §4.2), which was decided on business capability and
dependency evidence, not physical location. The earlier
`lib/services/*` → `lib/backend/services/*` narrative (a previously
executed migration under an older MMS) is not supported by this live
data and should not be relied on for Section 7 Step 1 — the paths above
are.

**✅ Live-path verification — COMPLETE for all remaining files**, using
the Master's `Get-ChildItem -Recurse lib -Filter *.dart` output (branch
`main`, same session as the `git status` above, so the same commit
context — `29a892d` plus the one untracked file noted). Every `.dart`
file's live path was cross-checked against this MMP's archive-based
Migration Inventory:

- **54 files total** in the live listing — matches the archive's file
count exactly.
- **0 discrepancies** — every file's live path is identical to its
archive-based "Old Path" in Section 4. No file has moved from its
archive-assumed location (the `lib/backend/services/` narrative was
specific to AI#1's earlier, incorrect self-report — not a general
pattern, and no other file shows it).
- **0 missing files** — every file expected in Section 4 is present live.
- **0 unexpected files** — the live listing contains no `.dart` file
outside what Section 4 already accounts for.
- **0 duplicate locations.**
- **Tracked/untracked status:** `git status` (same session) lists only
`local_data_guard_service.dart` as untracked among `lib/*.dart` files.
By omission from that output, all other 53 `.dart` files are tracked
and clean at commit `29a892d`. (Files outside `lib/` noted in the same
`git status` — `lib3.zip` deleted, plus untracked `full.sql`,
`lib (security - setting).zip`, `lib(used for B&F).zip`, `schema.sql`
— are out of migration scope per MAS Rule 6 and require no action.)

**Conclusion: Section 4's "Old Path" column is accurate as the real
Section 7 Step 1 move source for every file except the general caution
already noted** (verify against live HEAD at execution time, since time
may pass between this verification and Turn 1 actually running).

**✅ `local_data_guard_service.dart` — baseline decision MADE by the
Master: COMMIT. Evidence chain that supported it:**

- Present in the live working tree at `lib/services/local_data_guard_service.dart`
with real, substantive content (79 lines) — a complete, documented
`LocalDataGuardService` class implementing a specific, named fix:
"Known Issue #4" per `AUTH_SECURITY_MASTER_DOC.md §17" — a different-
inspector-same-device local data reconciliation check.
- **Actually called**, not just present — `splash_screen.dart` (AI#1's
own file) invokes `LocalDataGuardService.reconcileLocalDataOwnership(...)`
directly inside its login flow. Not orphaned.
- `git status` lists it as Untracked at commit `29a892d26cbed4429d69d5e803b279696f9cc6af`
(full hash, branch `main`, verified via `git rev-parse HEAD`).
- **`git log --all --oneline` and `git log -1 --format="%H %ai %an"`,
both scoped to this file, returned zero commits** — this file has no
Git history at all in this repository, at any point, on any branch.
Verified directly from terminal output (screenshot), not inferred.
- The most recent commit on `main` is thematically adjacent
(security-settings/biometric fix) — consistent with active,
in-progress security work in the same domain.

**Decision basis:** legitimate, functional, documented, actively-called
source code with zero commit history is the profile of **new
work-in-progress that hasn't been committed yet** — not an accidental
artifact (accidental artifacts don't typically contain named references
to a tracked issue number and get called from production login flow).
**This decision covers baseline/ownership status only — it does not
constitute a correctness or security review of the implementation
itself; that remains a separate concern, out of scope for this Dry Run
gate.**

**✅ EXECUTED — commit confirmed.** New commit `81e6e2ef78fbc9a833f2b775895f8c43189bb335`
on branch `main` ("feat(security): add LocalDataGuardService for
cross-inspector local data reconciliation (AUTH_SECURITY_MASTER_DOC.md
#17, Known Issue #4)" — 1 file changed, 80 insertions). `git status`
confirms: branch ahead of `origin/main` by 1 commit;
`local_data_guard_service.dart` no longer appears anywhere in the
output — it is now tracked and clean. Remaining `git status` entries
(`lib3.zip` deleted, `full.sql`, 2 `.zip` files, `schema.sql`) are
pre-existing, outside `lib/`, and out of migration scope per MAS Rule 6
— they do not affect this precondition. **The `lib/`-scope working tree
is now clean.**

- Before any AI's turn is authorized (and before Step 0 / Step 0.5 run),
the Master records the **current actual location** of every file in
the Migration Inventory against the live repository. Section 7 Step 1
for each file uses its verified live path as the real move source, not
Section 4's "Old Path" column (which reflects the original archive,
used only for lookup/identification).
- This check is now part of the Section 2 preconditions and the Section
0-A Dry Run (see additions there).
- A discrepancy between the archive-based Old Path and the live
repository is a **repository-state fact to reconcile, not an ownership
or architecture conflict.**

**Superseded architecture note:** an earlier `lib/frontend/` /
`lib/backend/` split (client-server-style separation) was evaluated and
explicitly rejected by the Master in favor of the layered/modular
structure this MMP implements (`core/`, `modules/<feature>/`) — see MAS
§15 decision (frontend/backend split superseded by feature-based +
layered architecture; rationale: a Flutter app has no server-side
backend of its own, so a client-server-style split misclassifies local
services, forces Shared/Core files like UserProfile/DBHelper/AuthService
into an awkward home, and re-mixes unrelated features under two giant
buckets instead of isolating them by module).

Consequently: **if any file currently sits under `lib/backend/...` or
`lib/frontend/...` from that earlier, now-superseded migration attempt,
# that location is not a valid destination under this MMP** — it is simply
# wherever the file happens to be right now (its current physical location,
# per the check above), and it still needs to move to its real Section 4
# destination (`core/...` or `modules/<feature>/...`) like every other
# file. This does not change what is being asked of AI#1 in the pending
# follow-up (their files' current actual paths still need to be reported)
# — it only confirms that whatever that current path turns out to be, the
# target is unchanged from Section 4.

# SECTION 0-D — Working Tree Provenance & Baseline Control

This section governs all files currently modified, untracked, generated,
or otherwise anomalous in the working tree.

Its purpose is to prevent audit/verification tooling from accidentally
being treated as migration work, and to prevent legitimate migration
changes from being reverted during cleanup.

## 0-D.1 — Mandatory Provenance Classification

Before any cleanup, deletion, revert, reset, checkout, or other working-tree
mutation is authorized, every working-tree anomaly discovered during the
migration audit must be classified as exactly one of:

1. MIGRATION-RELATED
     - An approved migration change covered by the MMP.
     - Must be preserved.

2. PRE-EXISTING / BASELINE
     - Present before the current migration/audit work.
     - Must be preserved unless the Master explicitly authorizes otherwise.

3. AUDIT/TOOL-GENERATED
     - Created by an audit, verification, shell command, diagnostic,
         reporting process, or temporary tooling.
     - Must not automatically be deleted.
     - Deletion requires explicit authorization under this section.

4. UNKNOWN PROVENANCE
     - Origin cannot be established with sufficient evidence.
     - Must be preserved.
     - No AI may delete, revert, reset, overwrite, or otherwise modify it
         merely because it appears unrelated to the migration.

No AI may classify an item as disposable solely because it is untracked,
unexpected, or appears unnecessary.

## 0-D.2 — Current Provenance Audit Findings

The following findings are now part of the working-tree baseline record.

### A. `analysis_options.yaml`

Classification:
`AUDIT/TOOL-GENERATED — BASELINE SUPPORT`

Observed change:

        analyzer:
            exclude:
                - pre_ai1_worktree/**

This modification appears associated with the pre-AI baseline worktree
and audit tooling.

It is NOT part of the approved Section 4 migration changes.

Therefore:

- Preserve it.
- Do not revert it.
- Do not overwrite it.
- Do not include it as a migration file change.
- Do not treat it as an unauthorized migration modification.
- Do not delete it during working-tree cleanup unless the Master explicitly
    authorizes its removal after the baseline purpose is no longer required.

### B. `main.dart`

Classification:
`MIGRATION-RELATED IMPORT/PATH CHANGE`

The observed changes are import-path migrations from the former flat
locations:

        services/
        providers/
        screens/
        widgets/

to the frozen destination structure:

        core/
        modules/

Therefore:

- Preserve `main.dart`.
- Do not revert it as an audit artifact.
- Its changes are migration-related and must be included in final
    migration validation and `git diff` review.

### C. Zero-byte file named `'`

Classification:
`AUDIT ARTIFACT`

Observed:

- Path: `'`
- Size: 0 bytes
- Created during the audit period
- Contents: empty

The file is considered an accidental shell/command/audit artifact.

However:

- It MUST NOT be deleted during the current audit.
- It MUST NOT be reverted or modified by an AI.
- It may be deleted only after explicit Master authorization during the
    authorized working-tree cleanup phase.

### D. Confirmed Audit-Generated Artifacts

The following are classified as:

`AUDIT ARTIFACT — SAFE TO REMOVE AFTER EXPLICIT AUTHORIZATION`

- `section4_audit_output.txt`
- `status.txt`
- `auth_service.diff.txt`
- `splash_screen.diff.txt`
- `diagnostics_screen.diff.txt`
- `notifications_screen.diff.txt`

These files are not migration outputs.

However, classification does NOT itself authorize deletion.

They remain protected until the Master explicitly authorizes cleanup.

### E. `section4_audit_result.txt`

This file is currently absent from the working tree.

Its absence must NOT be interpreted as proof that:

- it never existed,
- it was never generated,
- it was already deleted intentionally, or
- its contents can be reconstructed from memory.

Record:

`NOT PRESENT — PROVENANCE UNVERIFIABLE FROM CURRENT WORKING TREE`

No AI may recreate, delete, or replace it merely to make the audit
appear complete.

### F. Other Untracked Analysis/Report Files

All other untracked root-level, tools-tree, diagnostic, report, or
analysis files not explicitly classified above must remain:

`UNKNOWN PROVENANCE`

until independently classified.

Rules:

- Do not delete.
- Do not revert.
- Do not rename.
- Do not move.
- Do not overwrite.
- Do not add to the migration.
- Do not assume they are audit artifacts merely because their names look
    temporary.

The owning AI must report them to the Master if their provenance is
required for execution or validation.

## 0-D.3 — No Cleanup During Provenance Audit

The following actions are PROHIBITED during provenance classification:

- `git clean`
- `git reset --hard`
- blanket `git restore`
- deleting all untracked files
- deleting all `.txt`, `.diff`, `.log`, `.yaml`, or diagnostic files
- reverting files merely because they are outside the Migration Inventory
- moving files merely to make the working tree appear clean

A clean working tree is NOT itself a requirement for migration execution.
Provenance correctness takes priority over cosmetic cleanliness.

## 0-D.4 — Explicit Cleanup Authorization

Cleanup of confirmed audit artifacts may occur only after the Master gives
explicit authorization.

The authorization must identify the cleanup scope.

For example:

        AUTHORIZED CLEANUP:
        - section4_audit_output.txt
        - status.txt
        - auth_service.diff.txt
        - splash_screen.diff.txt
        - diagnostics_screen.diff.txt
        - notifications_screen.diff.txt
        - '

An AI may delete ONLY the explicitly authorized artifacts.

It may not expand the cleanup scope automatically.

## 0-D.5 — Baseline Preservation Rule

The following must be preserved unless separately authorized:

- `analysis_options.yaml`
- `pre_ai1_worktree/`
- all Migration Inventory files
- all approved migration-related changes
- all files with UNKNOWN provenance

The existence of baseline/audit support files does not invalidate the
migration.
The migration must be validated against the frozen inventory rather than
against an artificially cleaned working tree.

## 0-D.6 — Provenance Audit Completion Criteria

The Working Tree Provenance Audit passes only when:

- every known working-tree anomaly has a provenance classification;
- migration-related files are distinguished from audit artifacts;
- baseline-support artifacts are distinguished from migration changes;
- unknown-provenance files are explicitly preserved;
- no unauthorized file was deleted or reverted;
- no migration file was accidentally classified as an audit artifact;
- no audit artifact was silently incorporated into the migration;
- no cleanup occurred without explicit authorization.

A provenance audit PASS does NOT authorize cleanup.

Cleanup requires a separate explicit Master authorization.

# SECTION 3 — Repository Lock

No AI may act on a file that has not been explicitly scheduled in an
authorized batch. Authorization is granted per-batch, not for the whole
plan at once — completion and validation of batch N is required before
batch N+1 is authorized (Section 8).

# SECTION 4 — Migration Inventory

**Ownership Resolution rule (governs every conflict noted below):**
Per MAS Rule 10, ownership stated in an approved MMS is superseded — not
"in conflict with" — whenever the **MAS itself** has already classified
that file. Reported mismatches against an already-decided MAS
classification are architecture updates and require no further debate.
This applies to two files below: `auth_service.dart` and
`sensitive_screen.dart`, both explicitly listed as Shared/Core examples
in MAS §5.

It does **not** apply automatically to files where this MMP is the first
document proposing Shared/Core status — MAS §5's list explicitly says
"subject to final validation," and MAS Rule 9 reserves final Shared/Core
approval to the Master via the MAS decision log (§15), not to the MMP
unilaterally. Three files fell in this second category:
`biometric_service.dart`, `secure_prefs_service.dart`, and
`screen_protection_service.dart` — originally proposed Shared/Core here
based on fan-in analysis (Section 5-A). **RESOLVED via the Ownership
Resolution Pass: ratified to AI#1** (no competing MMS claim existed), not
Shared/Core — see §4.2 and the Ownership Resolution Pass log. This
paragraph is retained for historical context on why the question arose;
it is not an open item.

**Ownership note:** the module→file mapping below reflects the completed
Ownership Resolution Pass — all six approved MMS documents were obtained,
cross-checked, and every conflict or gap arbitrated or ratified (see the
Ownership Resolution Pass log, following Section 4.8). Where a fan-in
count or MMS excerpt is cited under a specific file, it is the verified
evidence that decision was based on, not a live proposal. The
`⚠ UNCLEAR` marker below no longer appears anywhere in Section 4 — every
such case was resolved during the pass.

Target layer directories (per MAS Section 4 layers):
`core/services/`, `core/models/`, `core/widgets/`, `core/theme/` (Shared),
`modules/<module>/screens/`, `modules/<module>/services/`,
`modules/<module>/models/`, `modules/<module>/providers/`,
`modules/<module>/widgets/`.

## 4.1 Shared/Core (per MAS Section 5 + Ownership Resolution Pass decisions)

File
Old Path
New Path

SupabaseService
lib/services/supabase_service.dart
core/services/supabase_service.dart

DBHelper
lib/services/db_helper.dart
core/services/db_helper.dart

AuthService
lib/services/auth_service.dart
core/services/auth_service.dart

SyncOutboxService
lib/services/sync_outbox_service.dart
core/services/sync_outbox_service.dart

UserProfile (D-001)
lib/models/user_profile.dart
core/models/user_profile.dart

InsightBottomNav
lib/widgets/insight_bottom_nav.dart
core/widgets/insight_bottom_nav.dart

SensitiveScreen
lib/widgets/sensitive_screen.dart
core/widgets/sensitive_screen.dart

ImapsLoadingIndicator
lib/widgets/imaps_loading_indicator.dart
core/widgets/imaps_loading_indicator.dart

Motion widgets (4 files)
lib/widgets/motion/*.dart
core/widgets/motion/*.dart

InsightTheme
lib/theme/insight_theme.dart
core/theme/insight_theme.dart

InsightWidgets
lib/widgets/insight_widgets.dart
core/widgets/insight_widgets.dart

MainShellScreen (Ownership Resolution Pass #6)
lib/screens/main_shell_screen.dart
core/navigation/main_shell_screen.dart

SyncProgressBanner (Ownership Resolution Pass #7)
lib/widgets/sync_progress_banner.dart
core/widgets/sync_progress_banner.dart

ParcelDetailScreen (Ownership Resolution Pass #8, D-010)
lib/screens/parcel_detail_screen.dart
core/navigation/parcel_detail_screen.dart (Shared/Core, RESOLVED, HIGH confidence)

*`biometric_service.dart`, `secure_prefs_service.dart`,
`screen_protection_service.dart` — removed from this table. Ratified to
AI#1 (Ownership Resolution Pass ratifications), not Shared/Core — see
§4.2.*

## 4.2 Module: Authentication & Startup (AI#1) — PROPOSED, PARTIALLY CONFIRMED

*Module name/scope note:* AI#1's approved MMS is titled "Authentication &
Security" and explicitly owns exactly 8 files: `auth_service.dart`,
`biometric_service.dart`, `secure_prefs_service.dart`,
`screen_protection_service.dart`, `local_data_guard_service.dart`,
`security_settings_screen.dart`, `app_resume_lock_screen.dart`,
`sensitive_screen.dart`. Comparing to MAS §3 / this document's
"Authentication & Startup" list below: **only 3 files overlap**
(`app_resume_lock_screen.dart`, `local_data_guard_service.dart`,
`security_settings_screen.dart`) — a genuinely different file scope, not
just a naming difference. AI#1's approved MMS lists 8 owned files;
Ownership Resolution Pass additionally confirmed `splash_screen.dart`
and `debug_screenshot_toggle.dart` as AI#1-owned, and ratified
`biometric_service.dart`, `secure_prefs_service.dart`, and
`screen_protection_service.dart` to AI#1 rather than Shared/Core (see
Ownership Resolution Pass log). `auth_service.dart` and
`sensitive_screen.dart` remain Shared/Core per MAS §5 (§4.1) — that
MAS-level classification supersedes AI#1's MMS ownership per the
Ownership Resolution rule (Section 4 preamble) and was never in dispute.

**3 files moved to §4.7 (AI#6), no conflict:** `terms_privacy_screen.dart`,
`about_insight_screen.dart`, `notification_service.dart` — AI#1 never
claimed them; AI#6's MMS does. `main.dart` is the entrypoint, handled
separately (Section 6, Step 7).

✅ **`SecuritySettingsScreen` — RESOLVED (Ownership Resolution Pass #3).**
Was dual-claimed with AI#6; decided AI#1 per the tiebreaker rule
(business capability — biometric enrollment, require-on-open, secure
prefs — outweighs its `profile_screen.dart` navigation entry point).
Final, not subject to further dispute.

File
Old Path (archival)
Confirmed Current Path
New Path

main.dart
lib/main.dart
(unconfirmed)
(entrypoint — stays at lib/main.dart, imports updated only)

SplashScreen ✅ Ownership Resolution Pass #9
lib/screens/splash_screen.dart
(unconfirmed — physical location check still pending, Outstanding Item 7)
modules/auth_startup/screens/splash_screen.dart

AppResumeLockScreen
lib/screens/app_resume_lock_screen.dart
(unconfirmed — not among the 5 AI#1 reported)
modules/auth_startup/screens/app_resume_lock_screen.dart

SecuritySettingsScreen ✅ Ownership Resolution Pass #3
lib/screens/security_settings_screen.dart
(unconfirmed)
modules/auth_startup/screens/security_settings_screen.dart

DebugScreenshotToggle ✅ Ownership Resolution Pass #10
lib/widgets/debug_screenshot_toggle.dart
(unconfirmed)
modules/auth_startup/widgets/debug_screenshot_toggle.dart

LocalDataGuardService
lib/services/local_data_guard_service.dart
**lib/services/local_data_guard_service.dart** (verified live — untracked at commit `29a892d`, see Section 0-C)
modules/auth_startup/services/local_data_guard_service.dart

BiometricService ✅ Ratified (D-003)
lib/services/biometric_service.dart
**lib/services/biometric_service.dart** (verified live, commit `29a892d`)
modules/auth_startup/services/biometric_service.dart

SecurePrefsService ✅ Ratified (D-004)
lib/services/secure_prefs_service.dart
**lib/services/secure_prefs_service.dart** (verified live, commit `29a892d`)
modules/auth_startup/services/secure_prefs_service.dart

ScreenProtectionService ✅ Ratified (D-005)
lib/services/screen_protection_service.dart
**lib/services/screen_protection_service.dart** (verified live, commit `29a892d`)
modules/auth_startup/services/screen_protection_service.dart

*Moved to §4.7 (AI#6), no longer listed here: `terms_privacy_screen.dart`,
`about_insight_screen.dart`, `notification_service.dart`.*

## 4.3 Module: Task Management (AI#2) — CONFIRMED

*Module name/scope note:* AI#2's approved MMS is titled **"My Tasks"**,
not "Task Management" (MAS §3 wording). MMS-stated scope: "Pending • On
Process • Completed • Task Progress • Step Tracking • Task Restoration •
Task Transition • Task Cards • Task List." MMS's "Files Owned" list
(verbatim) was 3 files — 2 of the 3 were reassigned during the
Ownership Resolution Pass:

File
Old Path
Confirmed Current Path
New Path

TasksScreen (incl. TaskItem class)
lib/screens/tasks_screen.dart
(unconfirmed — presumed lib/screens/)
modules/tasks/screens/tasks_screen.dart

*`InspectionProgress` (`inspection_progress.dart`) — RESOLVED
(Ownership Resolution Pass #1) → AI#3, see §4.4. Removed from this
module.*

*`CompletedInspectionDetailScreen` — RESOLVED (Ownership Resolution Pass
#2) → AI#3, see §4.4. Removed from this module. Initial evidence
(sole importer `tasks_screen.dart`) leaned AI#2, but was reversed under
the tiebreaker rule once its deep import coupling to 6 of AI#3's wizard
screens plus `inspection_provider.dart`/`inspection_progress.dart` was
weighed — see Ownership Resolution Pass log for the full re-evaluation.*

*`UpdatesScreen` — RESOLVED (Ownership Resolution Pass #8) → AI#4, see
§4.5. Never in AI#2's MMS "Files Owned" list; removed from this module.*

*`photo_viewer.dart`* — AI#2's MMS listed this as a dependency (not an
owned file) of `tasks_screen.dart`/`completed_inspection_detail_screen.dart`;
verified usage does not include `tasks_screen.dart` as an importer.
Ratified to AI#3 (D-009) — see §4.4.

## 4.4 Module: Inspection Workflow (AI#3) — CONFIRMED

*AI#3's MMS title: "Inspection Workflow (AI #3)." Its "Files Owned" list
(§4 of its MMS) is 16 files.*

File
Confirmed
New Path

SiteMapScreen
✅ owned
modules/inspection/screens/site_map_screen.dart

GpsVerificationScreen
✅ owned
modules/inspection/screens/gps_verification_screen.dart

CapturePhotoScreen
✅ owned
modules/inspection/screens/capture_photo_screen.dart

InspectionChecklistScreen
✅ owned
modules/inspection/screens/inspection_checklist_screen.dart

FieldFindingsScreen
✅ owned
modules/inspection/screens/field_findings_screen.dart

ReviewSubmitScreen
✅ owned
modules/inspection/screens/review_submit_screen.dart

InspectionProgress ✅ Ownership Resolution Pass #1
resolved to AI#3
modules/inspection/screens/inspection_progress.dart

CompletedInspectionDetailScreen ✅ Ownership Resolution Pass #2
resolved to AI#3
modules/inspection/screens/completed_inspection_detail_screen.dart

InspectionResultScreen
✅ owned
modules/inspection/screens/inspection_result_screen.dart

ZoningComparisonScreen
✅ owned (confirmed dead code)
modules/inspection/screens/zoning_comparison_screen.dart

InspectionProvider
✅ owned
modules/inspection/providers/inspection_provider.dart

LocationService
✅ owned
modules/inspection/services/location_service.dart

GeotagService
✅ owned
modules/inspection/services/geotag_service.dart

SpatialOfflineService
✅ owned
modules/inspection/services/spatial_offline_service.dart

ExitConfirmDialog
✅ owned
modules/inspection/widgets/exit_confirm_dialog.dart

PhotoViewer ✅ Ratified (D-009)
ratified to AI#3
modules/inspection/widgets/photo_viewer.dart

**Removed from this module, per Ownership Resolution Pass:**

- `ParcelDetailScreen` → Shared/Core (Ownership Resolution Pass #8,
D-010) — see §4.1.
- `DiagnosticsScreen`, `DiagnosticsService` — confirmed **not** in AI#3's
owned list; resolved to AI#6 (Profile & Settings) — see §4.7. Not part
of this module.

**`InspectionProgress` decision basis:** verified 10 importers, 8 of
which are AI#3's own files. AI#2's `tasks_screen.dart` import treated as
a cross-module read-only dependency (MAS Rule 4), not joint ownership.

**`CompletedInspectionDetailScreen` decision basis:** re-evaluated under
the tiebreaker rule — imports 6 of AI#3's inspection wizard screens plus
`inspection_provider.dart`/`inspection_progress.dart`, deep architectural
coupling to Inspection Workflow outweighing its single navigation source
(`tasks_screen.dart`, AI#2). Sole importer (`tasks_screen.dart`, AI#2) is
reachability only, now lowest priority. Shared/Core: rejected, single entry
point. **FINAL.**

**`PhotoViewer` decision basis:** AI#3's MMS confirms ownership with one
cross-module consumer noted (`parcel_detail_screen.dart`, now
Shared/Core). No competing MMS claim — ratified as-is.

## 4.5 Module: Offline Sync Center (AI#4) — CONFIRMED

*Module name — CONFIRMED matching MAS §3 exactly* ("Offline Sync Center
Module (AI #4)"). MMS "Files Owned" (§3) is explicit and narrow: only
`db_helper.dart` and `sync_outbox_service.dart` — both already Shared/Core
(§4.1), confirmed rather than disputed by AI#4's own MMS (every §7
cross-module entry anticipates "Final location... resolved during the
Master Merge"). The MMS also explicitly disclaims
`spatial_offline_service.dart` (correctly under AI#3),
`local_data_guard_service.dart` (correctly under AI#1), and
`sync_progress_banner.dart`.

✅ **`sync_progress_banner.dart` — RESOLVED (Ownership Resolution Pass
#7) → Shared/Core**, not AI#4. See §4.1.

✅ **`updates_screen.dart` — RESOLVED (Ownership Resolution Pass #8) →
AI#4.** AI#4's MMS characterizes it as "effectively the Sync Center UI
screen" and its heaviest dependent, calling
`drain`/`getSyncCenterQueueActions`/`getRecentSyncedActions`/
`getCacheStats`/`clearSyncedPhotoCache`/`getLastSuccessfulSync`/
`isDraining` — the full user-facing surface of Sync Center functionality.

File
Old Path
New Path

UpdatesScreen ✅ Ownership Resolution Pass #8
lib/screens/updates_screen.dart
modules/offline_sync/screens/updates_screen.dart

**AI#4's turn is no longer empty** — `updates_screen.dart` is its one
confirmed file for its own turn (Section 6).

## 4.6 Module: Analytics & Dashboard (AI#5) — CONFIRMED

*Module name — CONFIRMED matching MAS §3 exactly* ("Analytics &
Dashboard"). MMS "Files Owned" list was 4 files; 2 were reassigned during
the Ownership Resolution Pass.

File
Old Path
New Path

HomeDashboardScreen
lib/screens/home_dashboard_screen.dart
modules/analytics_dashboard/screens/home_dashboard_screen.dart

ActiveAssignmentsFolderCard
lib/widgets/active_assignments_folder_card.dart
modules/analytics_dashboard/widgets/active_assignments_folder_card.dart

✅ **`DashboardStats` and `DashboardWidgets` — RESOLVED (Ownership
Resolution Pass #4) → AI#6.** Removed from this module. See §4.7.
Initial report found no conflict (AI#5's MMS matched this document
exactly at the time); AI#6's later report revealed the dual claim.

**D-006 (MainShellScreen) — RESOLVED (Ownership Resolution Pass #6) →
Shared/Core.** AI#5's MMS contributed a confirmed cross-module link
(`main_shell_screen.dart` imports/instantiates `HomeDashboardScreen`) —
one of 4 confirmed links that led to this decision. See §4.1.

**Confirms, does not newly establish:** `dashboard_stats.dart`'s (now
AI#6-owned) `TaskItem` import (Section 5-C, finding 1);
`imaps_loading_indicator.dart`, `motion/spring_entrance.dart`,
`motion/updating_tile.dart`, `insight_bottom_nav.dart` usage — all
Shared/Core (§4.1), with fan-in counts from AI#5's own MMS (9, 5, 3, and
constant-only respectively). `parcel_detail_screen.dart` confirmed as a
navigation target from `home_dashboard_screen.dart` — consistent with
its resolved Shared/Core status (§4.1, D-010). `notifications_screen.dart`
(AI#6), `updates_screen.dart` (AI#4) confirmed navigation targets, both
now resolved elsewhere.

## 4.7 Module: Profile & Settings (AI#6) — CONFIRMED

*Module name — CONFIRMED matching MAS §3 exactly* ("Profile & Settings").
MMS "Files Owned" (§4) was 11 files; 1 (`security_settings_screen.dart`)
was arbitrated to AI#1 during the Ownership Resolution Pass.

**Cleanly resolved (no conflict) — files previously unowned or
tentative, now claimed solely by AI#6:**

- `about_insight_screen.dart`, `terms_privacy_screen.dart`,
`notification_service.dart` — previously in AI#1's "no MMS owner"
list; AI#1 never claimed them, so no conflict.
- `diagnostics_screen.dart`, `diagnostics_service.dart` — AI#3's MMS
explicitly disclaimed both; AI#6 is the sole claimant.
- `notifications_screen.dart` — previously ⚠ UNCLEAR; confirmed.

✅ **`SecuritySettingsScreen` — RESOLVED (Ownership Resolution Pass #3) →
AI#1.** Removed from this module. See §4.2.

✅ **`DashboardWidgets` and `DashboardStats` — RESOLVED (Ownership
Resolution Pass #4) → AI#6, confirmed.** Sole importer of both is
`profile_screen.dart` (AI#6's own file); `dashboard_stats.dart`'s doc
comment explicitly states "All numbers the Profile analytics dashboard
needs." D-002's Domain-layer classification for `dashboard_stats.dart`
is unaffected — only the mover/owner was in question.

**`main_shell_screen.dart` — confirmed not in AI#6's MMS**, consistent
with it being resolved to Shared/Core (Ownership Resolution Pass #6,
§4.1) rather than any single module.

**New evidence used elsewhere (not an ownership question for this
module):** `biometric_service.dart`/`secure_prefs_service.dart` also used
by `main_shell_screen.dart` (supporting evidence for their AI#1
ratification, §4.2); `profile_screen.dart` imports `splash_screen.dart`
for a `LoginScreen` class (context for `splash_screen.dart`'s AI#1
resolution, §4.2).

File
New Path

ProfileScreen
modules/profile_settings/screens/profile_screen.dart

ProfileEditScreen
modules/profile_settings/screens/profile_edit_screen.dart

AboutInsightScreen
modules/profile_settings/screens/about_insight_screen.dart

TermsPrivacyScreen
modules/profile_settings/screens/terms_privacy_screen.dart

DiagnosticsScreen
modules/profile_settings/screens/diagnostics_screen.dart

NotificationsScreen
modules/profile_settings/screens/notifications_screen.dart

DiagnosticsService
modules/profile_settings/services/diagnostics_service.dart

NotificationService
modules/profile_settings/services/notification_service.dart

DashboardWidgets ✅ Ownership Resolution Pass #4
modules/profile_settings/widgets/dashboard_widgets.dart

DashboardStats ✅ Ownership Resolution Pass #4 (D-002, Domain layer)
modules/profile_settings/models/dashboard_stats.dart

## 4.8 Excluded (not migrated under this plan)

File
Reason

lib/screens/login_screen.dart.bak
Non-source `.bak` artifact — see Section 0-B

lib/screens/reset_password_screen.dart.bak
Non-source `.bak` artifact — see Section 0-B

# SECTION 5 — Reference Matrix (lib/ scope)

Built from actual `import` statements in the archive. This is a partial
Reference Matrix — internal Dart imports only, within `lib/`. It does not
yet cover exports, `part`/`part of`, tests, or repository-wide references
outside `lib/` (see Section 0-B — that full scan is a separate later
step). Do not treat this section as satisfying MAS Gate F.

## 5-A. Fan-in count for Shared/Core candidates (files imported by 3+ other files)

File
Imported by (count)

sensitive_screen.dart
14 files

supabase_service.dart
11 files

imaps_loading_indicator.dart
8 files

db_helper.dart
6 files

user_profile.dart
6 files

exit_confirm_dialog.dart
5 files

inspection_provider.dart
5 files

sync_outbox_service.dart
5 files

biometric_service.dart
4 files

secure_prefs_service.dart
3 files

motion/spring_entrance.dart
4 files

This fan-in data is what drove the Shared/Core classification in Section
4.1 — it should be checked against the MMS-stated ownership, not the
other way around.

## 5-B. Full edge list

Available in full inside the repository scan output; summarized per-file
under each file's entry in Section 4. Request the complete edge list
separately if a raw table is needed for tooling (e.g. a CSV for the
Reference Lock step) — it is intentionally not duplicated here to keep
this document usable as a manual reference.

## 5-C. ⚠ Critical Findings — Cross-Layer & Cross-Module Dependencies (flag, not fix)

Per Rule 2 (No Refactoring), none of the findings below are corrected
during migration — they are preserved exactly as-is, with import paths
updated only. They are flagged here because they constrain batch/turn
ordering. Ownership labels below reflect the finalized Ownership
Resolution Pass — the underlying import facts are unchanged from the
original scan, only the module attribution is updated where ownership
moved.

**Cross-layer violations of MAS's layer rules** (Section 4: "Domain
Layer... No Flutter UI") — a Domain-layer or State-layer file importing a
Presentation-layer file to reach a class defined there:

1. `lib/models/dashboard_stats.dart` (Domain layer, **AI#6** — reassigned
from AI#5 during Ownership Resolution Pass #4) imports
`lib/screens/tasks_screen.dart` (Presentation layer, AI#2) for the
`TaskItem` class.
2. `lib/providers/inspection_provider.dart` (State layer, AI#3) imports
the same file for the same reason.
3. `lib/screens/profile_screen.dart` (Presentation layer, AI#6) also
imports `tasks_screen.dart` for `TaskItem` — confirmed via AI#2's MMS
§6 reverse-dependency note and verified directly in the archive.
4. **`lib/screens/home_dashboard_screen.dart` (Presentation layer, AI#5)
— newly verified during Section 4 sync.** Imports `tasks_screen.dart`
and uses `TaskItem` directly (`List<TaskItem>`,
`TaskItem.fromJob(...)`), not just for navigation. This was missed in
the original Section 5-C scan and is added here as a demonstrable gap
found during verification, not an assumption.

**`TaskItem` fan-in is far larger than originally scanned — confirmed via
AI#3's MMS ("nearly every owned screen... constructor/parameter
dependency") and verified directly:** 7 of AI#3's Inspection Workflow
screens import `tasks_screen.dart` directly for `TaskItem`:
`site_map_screen.dart`, `gps_verification_screen.dart`,
`capture_photo_screen.dart`, `inspection_checklist_screen.dart`,
`field_findings_screen.dart`, `review_submit_screen.dart`,
`completed_inspection_detail_screen.dart` (all confirmed AI#3-owned per
Ownership Resolution Pass — no longer contested).

**Batch/turn-ordering implication:** `tasks_screen.dart` must be at its
final location before AI#3, AI#5, **and AI#6's** turns — all three now
confirmed via findings 1–4 above. Turn *ordering* (AI#2 first) does the
real work here, since each dependent file's import update happens inside
that file's own owning module's turn (editing your own file's import
line is not editing another AI's file — no Rule 3 issue). Step 0.5 is
reserved only for genuine two-way/mutual references, per the circular
dependency below.

1. **Circular dependency (via AI#3's MMS forward-dependency evidence,
verified):** `lib/screens/tasks_screen.dart` (AI#2) imports
`lib/screens/parcel_detail_screen.dart` (**Shared/Core, Ownership
Resolution Pass #8, D-010 — resolved**) , and `parcel_detail_screen.dart`
imports `tasks_screen.dart` back. This is the one case that needs
coordinated handling — see Section 6 Step 0.5. `parcel_detail_screen.dart`
also imports 6 of AI#3's owned screens plus `inspection_provider.dart`
— none of those are mutual/circular, just one-directional dependencies
on already-ordered files.

**Cross-module fan-in for `inspection_progress.dart` and
`photo_viewer.dart` — RESOLVED (see §4.4 for full detail).** Both were
originally flagged here as Shared/Core candidates (D-008, D-009) based on
raw fan-in count from AI#2's report alone. Ownership Resolution Pass
confirmed both as AI#3-owned (`inspection_progress.dart` arbitrated as
decision #1; `photo_viewer.dart` ratified as D-009, no competing claim
existed) — the underlying fan-in facts (10 importers for
`inspection_progress.dart`, 8 of them AI#3's own; 3 importers for
`photo_viewer.dart` across 2 modules) are unchanged, only the ownership
question is now closed.

This is reported as a structural fact for the Master's awareness; whether
to raise any of this as a future (post-migration, out-of-scope)
architecture concern is a decision for the Master, not for any module AI.

# SECTION 6 — Execution Order

Execution is **sequential by AI**, not parallel and not purely by-layer.
Each AI completes its ENTIRE turn (all files it owns: services, models,
providers, widgets, screens — whatever it owns per Section 4) — move,
import rewrite, `flutter analyze`, commit — before the next AI's turn
begins. No two AIs work at the same time. This removes the merge-conflict
and cross-edit risk that per-layer parallel batching would carry.

**Step 0 — Shared/Core (Section 4.1), performed once, before any AI's
turn.** Owner: Master (Shared/Core is frozen to module AIs per MAS Rule
8). Covers all of §4.1: `supabase_service.dart`, `db_helper.dart`,
`auth_service.dart`, `sync_outbox_service.dart`, `user_profile.dart`,
`insight_bottom_nav.dart`, `sensitive_screen.dart`,
`imaps_loading_indicator.dart`, the 4 motion widgets, `insight_theme.dart`,
`insight_widgets.dart`, `biometric_service.dart` is **not** here (ratified
to AI#1, §4.2) — nor are `secure_prefs_service.dart` /
`screen_protection_service.dart` (same, AI#1). `main_shell_screen.dart`
and `sync_progress_banner.dart` **are** here (Ownership Resolution Pass
#6, #7). `parcel_detail_screen.dart` is Shared/Core (#8) but physically
moved in Step 0.5 below, not Step 0, due to its circular dependency.

**Step 0.5 — Coordinated circular-dependency pair, performed once, before
any AI's turn, by the Master directly:** `tasks_screen.dart` (AI#2) and
`parcel_detail_screen.dart` (Shared/Core, D-010 — RESOLVED, final
destination `lib/core/navigation/parcel_detail_screen.dart`) are moved and
have their imports rewritten together, as one unit, because they import
each other. **AI#2's ownership of `tasks_screen.dart` is unaffected by
this** — ownership (per Section 4) and physical execution (per this
step) are separate questions. The Master pre-executes this one move
solely because of the circular dependency, which cannot be cleanly
resolved by turn ordering alone; AI#2's turn (item 1 below) has no file
left to move as a result, not because AI#2 lost ownership. This step is
validated as a unit (Section 8) before Step 0 concludes.

**AI turn order — determined by dependency direction.** Confirmed via
Section 5-C (findings 1–4): AI#3, AI#5, and AI#6 each depend directly on
`tasks_screen.dart` (AI#2) for `TaskItem`. AI#2's `tasks_screen.dart` is
handled in Step 0.5, ahead of every turn, so no later turn needs to touch
another AI's file — each later turn updates its own files' import lines
during its own Section 7 steps. No dependency was found requiring AI#1,
AI#4 to run in a particular order relative to the others.

1. **AI#2 — Task Management ("My Tasks" per its own MMS — §4.3).**
`tasks_screen.dart` handled in Step 0.5. **Turn is otherwise empty** —
its other 2 originally-considered files
(`inspection_progress.dart`, `completed_inspection_detail_screen.dart`)
were arbitrated to AI#3 (Ownership Resolution Pass #1, #2).
2. **AI#3 — Inspection Workflow (§4.4).** 16 confirmed files:
SiteMapScreen, GpsVerificationScreen, CapturePhotoScreen,
InspectionChecklistScreen, FieldFindingsScreen, ReviewSubmitScreen,
InspectionProgress, CompletedInspectionDetailScreen,
InspectionResultScreen, ZoningComparisonScreen (confirmed dead code —
low risk), InspectionProvider, LocationService, GeotagService,
SpatialOfflineService, ExitConfirmDialog, PhotoViewer.
3. **AI#5 — Analytics & Dashboard (§4.6).** 2 confirmed files:
HomeDashboardScreen, ActiveAssignmentsFolderCard.
`DashboardWidgets`/`DashboardStats` moved to AI#6 (Ownership Resolution
Pass #4) — no longer part of this turn.
4. **AI#6 — Profile & Settings (§4.7).** 10 confirmed files: ProfileScreen,
ProfileEditScreen, AboutInsightScreen, TermsPrivacyScreen,
DiagnosticsScreen, NotificationsScreen, DiagnosticsService,
NotificationService, DashboardWidgets, DashboardStats.
`SecuritySettingsScreen` moved to AI#1 (Ownership Resolution Pass #3)
— no longer part of this turn. `MainShellScreen` confirmed Shared/Core
(#6) — never part of this turn.
5. **AI#1 — Authentication & Startup / "Authentication & Security" per
its own MMS (§4.2).** 8 confirmed files: `app_resume_lock_screen.dart`,
`local_data_guard_service.dart`, `security_settings_screen.dart`,
`splash_screen.dart`, `debug_screenshot_toggle.dart`,
`biometric_service.dart`, `secure_prefs_service.dart`,
`screen_protection_service.dart`. (`auth_service.dart` and
`sensitive_screen.dart` remain Shared/Core, Step 0 — not this turn.)
6. **AI#4 — Offline Sync Center (§4.5).** 1 confirmed file:
`updates_screen.dart` (Ownership Resolution Pass #9). Turn is no
longer empty. `db_helper.dart`/`sync_outbox_service.dart` remain
Shared/Core (Step 0) — not this turn.

**Step 7 — Entry point.** `main.dart` import updates only (no move),
performed last, by the Master, once all six turns are complete.

Each AI's turn is authorized individually by the Master. Turn N+1 is not
authorized until Turn N passes Section 8 gates and is committed. **No
files remain unassigned** — every file in Section 4 now has exactly one
home (a specific turn, Step 0, or Step 0.5).

# SECTION 7 — Import Rewrite Procedure

Exact order, per file, no deviation. **Correction:** the original wording
of Step 3 below ("rewrite every other in-scope file's import") would have
required an AI to edit files it doesn't own — a direct violation of Rule
3 and Section 12 ("An AI cannot edit a file owned by another module").
Corrected to match the actual mechanism already established in Section 6:
turn *ordering* guarantees a dependency is at its final path before the
dependent's own turn, so the dependent updates its own import line
itself, in its own file, during its own turn.

1. Move the file to its new path (`git mv`, preserving history).
2. Rewrite that file's own internal imports to reflect its new location.
3. **Within the moving AI's own turn, rewrite only the moving AI's own
files' imports** of anything that has already relocated (Shared/Core
files from Step 0, `tasks_screen.dart`/`parcel_detail_screen.dart`
from Step 0.5, or files moved earlier in this same turn). Do not edit
any file outside the current turn's own ownership scope. If a
cross-module file (owned by an AI whose turn hasn't run yet) still
imports the file just moved, that import is corrected later, during
the *other* AI's own turn, by that AI, in its own file — not now, not
by this turn.
4. Run `flutter analyze` scoped to the affected files at minimum.
5. Commit with a message identifying turn, file, old path, new path.
6. Move to the next file in the turn. Do not begin the next turn until
every file in the current turn has completed steps 1–5 and passed
Section 8.

**Exception — Step 0 and Step 0.5 only:** the Master, not a module AI,
performs these steps, and is not bound by single-module ownership. When
the Master moves a Shared/Core file (Step 0) or the
`tasks_screen.dart`/`parcel_detail_screen.dart` pair (Step 0.5), the
Master may update import lines across any file that references them,
since no module AI has started its turn yet at that point.

# SECTION 8 — Verification Gates (per batch)

After each batch:

- `flutter analyze` — zero new errors/warnings attributable to the batch
- `dart analyze` — zero new errors
- Grep-verify no remaining old import path for any file moved in this
batch, anywhere in `lib/`
- Confirm no duplicate file exists at both old and new path
- For Step 0.5 specifically: verify both files
(`tasks_screen.dart`, `parcel_detail_screen.dart`) analyze cleanly
together before any AI's turn is authorized — this step is validated
as a unit, not file-by-file, and it gates the entire sequence below it.

A turn (or Step) is not complete until all checks above pass. No partial
turn proceeds to the next.

# SECTION 9 — Rollback Procedure (per turn/step)

If a turn (an AI's full set of files) or Step (0, 0.5, 7) fails
verification:

1. `git reset --hard` to the commit immediately before that turn/step
started.
2. Confirm working tree matches the pre-turn state (`git status` clean,
`git diff` empty against the pre-turn commit).
3. Re-run `flutter analyze` / `dart analyze` to confirm baseline is
restored (zero migration-related errors).
4. Report the failure and its cause to the Master before re-attempting.
Do not silently retry with a different destination or ownership.

Rollback is scoped to the failed turn/step only — it never touches
commits from prior, already-verified turns. This is also why the git tag
`architecture-lock` (Section 10) exists: a full-project restore point
independent of any individual turn's commits.

# SECTION 10 — Git Workflow

Before Step 0 begins, the Master creates a full-project restore point:

```
git add .
git commit -m "Architecture Locked - Before Master Merge"
git tag architecture-lock
```

If anything goes wrong at any point in the sequence in a way that a
single turn/step rollback (Section 9) doesn't cleanly resolve, the Master
can return to this exact state instead of unwinding commits by hand.

```
main
 │
 └── migration/master-merge      (branched from tag: architecture-lock)
          │
          ├── step-0-shared-core
          ├── step-0.5-taskitem-dependency-group
          ├── ai3-inspection-workflow
          ├── ai5-analytics-dashboard
          ├── ai6-profile-settings
          ├── ai1-auth-startup
          ├── ai4-offline-sync
          ├── step-7-entrypoint
          └── final-merge
```

No AI works directly on `main`. Each step/turn is its own branch off
`migration/master-merge`, merged in strictly in the order shown, after
passing Section 8 for that step/turn. A branch for turn N is not created
until turn N-1 has merged. **No separate `ai2-tasks` branch exists** —
AI#2's own turn (Section 6, item 1) is empty; its one file
(`tasks_screen.dart`) is fully handled in `step-0.5-taskitem-dependency-group`.

# SECTION 11 — Acceptance Criteria (final, after all batches)

- `flutter analyze` — clean
- `dart analyze` — clean
- `flutter test` — passing (scope limited to whatever test coverage
    exists; migration introduces no new failures)
- Android build succeeds
- Windows build succeeds
- Repository-wide search for any old `lib/...` path — zero hits (Gate F)
- Repository-wide search for duplicate files at old+new path — zero hits
- Shared/Core list matches Section 4.1 exactly — no additions, no
    omissions
- No orphan files (present in repo, absent from Migration Inventory)
- Reference Matrix (full repo-wide version, not just Section 5) verified
    against final `git diff`
- Full `git diff` reviewed by the Master before merge to `main`

Additional Acceptance Criteria (Working-Tree Provenance & Baseline Control):

- Working Tree Provenance Audit — PASS
- Every working-tree anomaly has a recorded provenance classification
- No migration-related file was reverted or deleted during audit
- No baseline-support file was reverted or deleted during audit
- No UNKNOWN-provenance file was deleted or modified
- No audit artifact was incorporated into the Migration Inventory
- No audit artifact was deleted without explicit Master authorization
- Final `git diff` distinguishes migration changes from baseline/audit
    artifacts before merge

Important note: `flutter analyze` / `dart analyze` are validated against
the frozen Migration Inventory and the preserved working-tree provenance
baseline. Do not require these analyzers to run against an artificially
cleaned working tree when `analysis_options.yaml` intentionally carries
baseline exclusions (for example, `pre_ai1_worktree/**`).

# SECTION 12 — Execution Rules (binding on all 6 AIs)

- An AI cannot skip a batch or reorder its own files ahead of schedule.
- An AI cannot move a file not listed under its own module in Section 4.
- An AI cannot edit a file owned by another module or by Shared/Core.
- An AI cannot change architecture, layer classification, or destination
path — those come only from this document or a Master revision to it.
- An AI cannot infer a destination for a file this document does not
list — it must report the gap instead (Section 13).
- An AI must stop at the first validation failure in its own batch work
and report rather than attempt a workaround.

# SECTION 13 — Exception Handling

Automatic STOP conditions (no AI proceeds past these without Master
input): missing dependency, duplicate ownership claim, unknown/unlisted
reference discovered mid-batch, broken import after rewrite, cyclic
dependency discovered during Batch 4 validation, a file whose MMS-stated
owner conflicts with this document's PROPOSED owner (Section 4).

On any STOP condition: halt work on the affected file, do not touch
adjacent files "to be safe," report the exact condition to the Master.

# SECTION 14 — Completion Report (per batch, filled in by the owning AI)

- Batch number and files moved (old path → new path)
- Imports updated (count, list)
- Validation results (Section 8 checklist, pass/fail per item)
- Remaining work in this batch, if any
- Issues found, if any (cross-reference Section 13 if a STOP occurred)

---

# CURRENT EXECUTION STATUS

Ownership Resolution Pass:
COMPLETE

Ownership Freeze:
COMPLETE

Live Physical-Location Verification:
COMPLETE

Untracked-file / baseline decision:
RESOLVED

Working Tree Provenance Audit:
PASS

Current classified migration change:
- `main.dart`

Current preserved baseline/audit-support artifact:
- `analysis_options.yaml`
- `pre_ai1_worktree/`

Confirmed audit artifacts awaiting explicit cleanup authorization:
- `section4_audit_output.txt`
- `status.txt`
- `auth_service.diff.txt`
- `splash_screen.diff.txt`
- `diagnostics_screen.diff.txt`
- `notifications_screen.diff.txt`
- `'

Missing/unverifiable audit artifact:
- `section4_audit_result.txt`

Unknown-provenance files:
- preserved; no deletion or modification authorized

NO FILES WERE DELETED OR REVERTED DURING THE PROVENANCE AUDIT.

Next mandatory step:
→ Re-run the Section 0-A Dry Run against the frozen Migration Inventory
    and the now-established working-tree provenance baseline.

No execution turn may begin until the Dry Run passes.

Cleanup of confirmed audit artifacts is a separate operation and is NOT
part of Turn 1 authorization unless explicitly authorized by the Master.

# Ownership Resolution Pass — Process (governs how Outstanding Item 1–5 get resolved)

Formalized process for closing out ownership questions, agreed with the
Master. Five steps, each file touched exactly once:

1. **Ownership Resolution Pass.** Evaluate every dual-ownership conflict,
unowned file, and Shared/Core candidate in one pass. Each file gets
exactly one final decision — assigned to a specific module, or
promoted to Shared/Core. No file is revisited in a later step once
decided here. Each decision is weighed against: (a) MMS ownership
assignment, (b) actual verified dependency evidence, (c) architectural
responsibility per MAS §3/§5, (d) whether Shared/Core status is
actually warranted by the evidence, not just proposed.

**Permanent tiebreaker rule (Master decision, applies to every
arbitration in this pass):** when dependency count alone doesn't
settle a case, priority order is: (1) MAS architectural
responsibility/business capability — primary; (2) functional
responsibility — secondary; (3) dependency evidence (fan-in,
consumers, imports) — supporting; (4) reachability/navigation path
(which screen calls `Navigator.push` to reach it) — last resort only.
**Navigation ownership does not imply module ownership.** A screen is
owned by the module whose business capability it represents, not
necessarily by the module containing its navigation entry point — UI
placement can change without the underlying responsibility changing.

**Ownership Resolution Pass Rule (provisional-until-freeze):**
decisions recorded during this pass are provisional until the
Ownership Freeze milestone (step 2 below) — they may be revised only
if (1) a new governing rule is adopted during the same pass, (2) new
repository evidence is discovered, or (3) an inconsistency with an
earlier arbitration is identified. Once Ownership Freeze executes, all
decisions become final and are not revisited except through a formal
change request. This is why the tiebreaker rule above triggered a
re-open of an earlier decision (see log entry 2) — that isn't
reversing a final decision, it's applying a rule adopted mid-pass to
keep every arbitration on the same standard before freezing.
2. **Freeze Ownership.** Update Section 4 (Migration Inventory) and the
Shared/Core list (§4.1) to match every decision from step 1. Clear the
corresponding Outstanding Items.
3. **Refresh Execution Plan.** Regenerate Section 6 (turn order, per-turn
file lists, Step 0/0.5/7) to match the frozen ownership from step 2.
4. **Dry Run.** Re-validate per Section 0-A against the frozen inventory:
destination-path collisions, dependency-graph consistency, live
physical-location checks, duplicate-destination checks.
5. **Execution Authorization.** Only after step 4 passes clean does the
MMP freeze as execution-ready and Step 0 begin.

**Log of Ownership Resolution Pass decisions (filled in as each file is
decided; nothing here is provisional — once entered, it's final):**

1. **`inspection_progress.dart` → AI#3 (Inspection Workflow).** Decided:
8 of 10 importers are AI#3's own files; matches MAS §3 module theme;
insufficient cross-module spread for Shared/Core (single external
consumer + one unowned file). Final.
2. **`completed_inspection_detail_screen.dart` → AI#3 (Inspection
Workflow).** *Re-evaluated under the tiebreaker rule (provisional
until Ownership Freeze — see rule above); this reverses the initial
reachability-based lean, not a change of mind but a change in
evidence quality.* Decided: imports 6 of AI#3's inspection wizard
screens plus `inspection_provider.dart` and `inspection_progress.dart`
— deep architectural coupling to Inspection Workflow. Sole importer
(`tasks_screen.dart`, AI#2) is reachability only, now lowest priority.
Shared/Core: rejected, single entry point. **FINAL.**

*Supporting heuristic surfaced here (not a new hard rule — informal
guidance for remaining arbitrations only):* task/launcher modules tend
to own entry points (lists, dashboards, launchers, status tracking);
feature modules own the feature implementation itself (wizards,
review, processing). `TasksScreen → CompletedInspectionDetailScreen → Inspection Workflow` is the pattern: the launcher isn't the same as
the feature it launches into.
3. **`security_settings_screen.dart` → AI#1 ("Authentication & Security",
AI#1's module).** Decided per the tiebreaker rule above: business
capability (biometric enrollment, require-on-open, secure
prefs — a security-subsystem UI) outweighs its navigation entry point (currently
only reachable via `profile_screen.dart`). Verified imports
(`biometric_service.dart`, `secure_prefs_service.dart`) confirm AI#1's
stated rationale. Shared/Core: rejected — single navigation source,
no cross-module fan-in beyond the one entry point. Final.
4. **`dashboard_stats.dart` AND `dashboard_widgets.dart` → AI#6 (Profile
& Settings). Single combined arbitration (not two separate cases) —
both files serve one business capability.** Decided: the code's own
doc comment on `dashboard_stats.dart` states "All numbers the Profile
analytics dashboard needs" — explicit architectural intent, not
inferred. Sole importer of both files is `profile_screen.dart` (AI#6).
Distinct from `home_dashboard_screen.dart`'s (AI#5) own dashboard —
two different "dashboard" concepts in this codebase. D-002's
Domain-layer classification for `dashboard_stats.dart` is unaffected
— only the mover/owner was in question. Shared/Core: rejected, single entry
point, no cross-module fan-in. **FINAL.**

**All 5 dual-ownership conflicts are now resolved.** Remaining in this
pass: the unowned/D-candidate files (`main_shell_screen.dart` — D-006,
`parcel_detail_screen.dart` — D-010, `updates_screen.dart`,
`splash_screen.dart`, `debug_screenshot_toggle.dart`) before Ownership
Freeze.

1. **`main_shell_screen.dart` → Shared/Core (`core/navigation/`).**
Decided: MAS §4 Shared Layer explicitly lists "bottom navigation" as
an example; this file's own doc comment states "Single shell for the
4 primary tabs"; it imports screens from 4 different modules
(Analytics, Task Management, unowned Updates, Profile & Settings) plus
2 Shared/Core-candidate services; imported by files from 2 different
modules (Inspection, unowned Auth entrypoint). All 4 criteria
unambiguous. Confirmed unowned by all 6 MMS. **FINAL.**

*`sync_progress_banner.dart` — explicitly held out of this decision,
not auto-promoted.* Master's note: a file's dependency relationship to
an already-decided file does not by itself transfer that file's
ownership outcome — each file gets its own objective 4-criteria
evaluation. Arbitrated separately as item 6 below.
2. **`sync_progress_banner.dart` → Shared/Core (`core/widgets/`).**
Decided: cross-cutting UI, not a Sync Center feature — the file's own
doc comment explicitly states it's for Home/Tasks/Profile screens,
not the Sync Center screen itself; reads only shared state
(`sync_outbox_service.dart`, already Shared/Core), no coupling to any
specific module's screens; wired through `main_shell_screen.dart` for
app-wide visibility. This is shared UI infrastructure, not Offline
Sync Center business logic — different reasoning from
`main_shell_screen.dart` (that one is a container by structure; this
one is a generic widget by design intent, per its own documentation).
**FINAL.**
3. **`parcel_detail_screen.dart` → Shared/Core (D-010,
`core/navigation/parcel_detail_screen.dart`).** Decided: no single
module owns its business capability — AI#3's own MMS explicitly
disclaims it as "the (external) entry point into this module," not part
of Inspection Workflow, despite heavy import coupling to 6 of AI#3's
wizard screens + `inspection_provider.dart` + `inspection_progress.dart`.
Genuinely multi-module reachability (navigated to from both
`tasks_screen.dart` — AI#2 — and `home_dashboard_screen.dart` — AI#5),
unlike prior single-source cases. Bridges Task Management and
Inspection Workflow rather than belonging to either. Strongest
Shared/Core candidate found — both dependency evidence and
reachability point to genuine cross-module status, not a
single-true-owner-obscured-by-reachability situation like the earlier
arbitrations. **FINAL.**
4. **`updates_screen.dart` → AI#4 (Offline Sync Center).** Decided: AI#4's
own MMS characterizes this file as "effectively the Sync Center UI
screen" and its heaviest consumer, calling
`drain`/`getSyncCenterQueueActions`/`getRecentSyncedActions`/
`getCacheStats`/`clearSyncedPhotoCache`/`getLastSuccessfulSync`/
`isDraining` — the full user-facing surface of Sync Center
functionality, not incidental usage. Unlike `parcel_detail_screen.dart`
(explicitly disclaimed by AI#3), AI#4 never disclaimed this file —
it simply wasn't in the archive-derived "Files Owned" table, but its
own MMS content identifies it as belonging to Sync Center's domain.
Imports only Shared/Core services + one navigation target
(`notifications_screen.dart`, AI#6) — no feature-specific coupling to
any other module. **FINAL.** Resolves AI#4's previously-empty turn
(§4.5, Section 6) as a side effect, not the basis for the decision.
5. **`splash_screen.dart` → AI#1 (Authentication & Startup /
"Authentication & Security").** Decided: clearest case in this pass —
all 4 criteria align. Contains both `SplashScreen` (startup sequence)
and `LoginScreen` (auth UI) classes — the literal definition of the
module's purpose. Imports `auth_service.dart`, `biometric_service.dart`,
`secure_prefs_service.dart`, `notification_service.dart`,
`local_data_guard_service.dart`, `app_resume_lock_screen.dart` — all
AI#1-owned or AI#1-originated. Reachability (`main.dart`,
`main_shell_screen.dart`, `app_resume_lock_screen.dart`,
`profile_screen.dart` for the `LoginScreen` class only) is consistent
with, not contrary to, the other 3 criteria. **FINAL.** Structural
note (not an ownership factor): `auth_service.dart` imports
`splash_screen.dart` back — an unusual service-imports-screen
direction, left as-is per Rule 2 (Move Only), not corrected.
6. **`debug_screenshot_toggle.dart` → AI#1 (Authentication & Startup).**
Decided: doc comment cites "AUTH_SECURITY_MASTER_DOC.md §Phase 3b" —
AI#1's own documentation. Imports `screen_protection_service.dart`
(AI#1-originated). Global debug utility for security behavior, not a
reusable Shared/Core framework — no competing module has a stronger
business claim. **FINAL.**

**⚠️ Before declaring the pass complete — 2 items surfaced as supporting
evidence during arbitration were never given their own final decision:**

- `biometric_service.dart`, `secure_prefs_service.dart`,
`screen_protection_service.dart` (D-003–D-005) — originally proposed
Shared/Core based on fan-in, but AI#1's MMS explicitly claims direct
ownership of all three (a single-MMS conflict, not dual-claimed like
the 5 above). Used repeatedly as supporting evidence in this pass
(e.g., for `security_settings_screen.dart` and
`debug_screenshot_toggle.dart`) but never arbitrated on their own.
- `photo_viewer.dart` (D-009) — AI#3's MMS claims direct ownership;
earlier analysis found the Shared/Core case "weaker than originally
proposed," with a recommendation (not a decision) to leave it with
AI#3.
These need their own pass through the same 4-criteria framework before
Ownership Freeze — otherwise the freeze would lock in an inconsistent
state where similar single-MMS-conflict files were resolved by different
standards (explicit arbitration vs. leftover proposal).

**Ratification (not full arbitration) — no competing claim exists for
any of these 4, so the sole MMS claim is ratified rather than run through
the full 4-criteria framework:**

- `biometric_service.dart` (D-003) → **AI#1.** Sole claimant, no
competing MMS. Fan-in was only to other now-confirmed AI#1 files
(`splash_screen.dart`, `app_resume_lock_screen.dart`,
`security_settings_screen.dart`) plus `main_shell_screen.dart`
(Shared/Core) — a Shared/Core file consuming a module-owned service is
normal, not grounds to promote the service itself. **RATIFIED, FINAL.**
- `secure_prefs_service.dart` (D-004) → **AI#1.** Same reasoning.
**RATIFIED, FINAL.**
- `screen_protection_service.dart` (D-005) → **AI#1.** Same reasoning.
**RATIFIED, FINAL.**
- `photo_viewer.dart` (D-009) → **AI#3.** Sole claimant (AI#3's MMS),
no competing MMS; AI#3's own MMS already accounted for its one
cross-module consumer and still claimed direct ownership.
**RATIFIED, FINAL.**

**✅ Ownership Resolution Pass fully complete — 14 total decisions (10
arbitrated + 4 ratified). Nothing further pending before Ownership
Freeze.**

# Ownership Freeze — Declaration

**Executed.** Per the 5-step process (Ownership Resolution Pass → Freeze
Ownership → Refresh Execution Plan → Dry Run → Execution Authorization)
agreed with the Master:

- **Step 1 (Ownership Resolution Pass): complete.** 14 decisions, 15
files, logged in full above.
- **Step 2 (Freeze Ownership): complete, as of this revision.** Section 4
(Migration Inventory, §4.1–§4.8) reflects every decision. Section 2's
ownership precondition is now checked.
- **Step 3 (Refresh Execution Plan): complete.** Section 6 regenerated —
6 turns, Step 0, Step 0.5, Step 7, no unassigned files.
- **Section 5-C synced** to the same 14 decisions, including one
genuinely new finding (`home_dashboard_screen.dart`'s `TaskItem`
dependency) discovered during verification, not assumed.

**Effective now:** per the Ownership Resolution Pass Rule, every
ownership decision in Section 4 is final. None may be revisited except
through a formal change request to the Master — not through further
discussion, new AI reports, or re-analysis of evidence already weighed.

**Not yet done — Steps 4 and 5 remain:** live physical-location
verification (Outstanding Item 1) and the Dry Run (Section 0-A) must both
complete before Execution Authorization for any turn.

# Outstanding Items Before Turn 1 Authorization

**Status: Ownership Resolution Pass complete — all ownership questions
(items 1–6 in prior revisions of this list) are resolved.** See the
Ownership Resolution Pass log (following §4.8) for the full record of
all 14 decisions. Section 4, Section 5-C, and Section 6 have been synced
to reflect every decision. Only non-ownership items remain open below.

1. ~~Record current physical file locations against live Git HEAD~~ —
**RESOLVED.** Verified against `git status` / `Get-ChildItem` output,
branch `main`, commit `29a892d`, for **all 54 files** in the Migration
Inventory (Section 0-C) — not just AI#1's 5. Result: 0 discrepancies
between archive-based "Old Path" and live path for any file; AI#1's
earlier `lib/backend/services/...` self-report is confirmed retracted
(5 files, all actually at `lib/services/...`); 0 missing files, 0
unexpected files, 0 duplicates.
2. ~~`local_data_guard_service.dart` baseline decision~~ — **RESOLVED.**
Committed at `81e6e2ef78fbc9a833f2b775895f8c43189bb335`. `lib/`-scope
working tree confirmed clean. See Section 0-C for the full evidence
chain and commit confirmation.
3. **Run the full repository-wide Reference Matrix** (beyond `lib/`) per
MAS Phase 0.5 before Gate F can be satisfied — this MMP's Section 5 is
`lib/`-scope only. This is a precondition for Gate F (final deletion
of original file locations), not for Turn 1 authorization itself.

**Next step per the agreed sequence:** Ownership Freeze is already
executed. Live-path verification (item 1) is complete. Remaining:
resolve item 2 (the untracked-file baseline decision) → the Dry Run
(Section 0-A, re-run against the frozen inventory and the resolved
baseline) → Execution Authorization for Turn 1.
