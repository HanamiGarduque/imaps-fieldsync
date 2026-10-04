# REPOSITORY_CLEANUP_PLAN

## Status

This is a non-destructive repository cleanup classification only.

- No file deletion was performed.
- No revert, reset, restore, checkout, or move was performed.
- No source-code changes were made.
- Cleanup remains pending explicit Master authorization under MASTER_MERGE_PLAN.md Section 0-D.4.

---

## Required provenance text from MASTER_MERGE_PLAN.md

### Section 0-D.1 — Mandatory Provenance Classification

> Before any cleanup, deletion, revert, reset, checkout, or other working-tree
> mutation is authorized, every working-tree anomaly discovered during the
> migration audit must be classified as exactly one of:
>
> 1. MIGRATION-RELATED
>      - An approved migration change covered by the MMP.
>      - Must be preserved.
>
> 2. PRE-EXISTING / BASELINE
>      - Present before the current migration/audit work.
>      - Must be preserved unless the Master explicitly authorizes otherwise.
>
> 3. AUDIT/TOOL-GENERATED
>      - Created by an audit, verification, shell command, diagnostic,
>          reporting process, or temporary tooling.
>      - Must not automatically be deleted.
>      - Deletion requires explicit authorization under this section.
>
> 4. UNKNOWN PROVENANCE
>      - Origin cannot be established with sufficient evidence.
>      - Must be preserved.
>      - No AI may delete, revert, reset, overwrite, or otherwise modify it
>          merely because it appears unrelated to the migration.
>
> No AI may classify an item as disposable solely because it is untracked,
> unexpected, or appears unnecessary.

### Section 0-D.2 — Current Provenance Audit Findings

> The following findings are now part of the working-tree baseline record.
>
> ### A. `analysis_options.yaml`
>
> Classification:
> `AUDIT/TOOL-GENERATED — BASELINE SUPPORT`
>
> Observed change:
>
>         analyzer:
>             exclude:
>                 - pre_ai1_worktree/**
>
> This modification appears associated with the pre-AI baseline worktree
> and audit tooling.
>
> It is NOT part of the approved Section 4 migration changes.
>
> Therefore:
>
> - Preserve it.
> - Do not revert it.
> - Do not overwrite it.
> - Do not include it as a migration file change.
> - Do not treat it as an unauthorized migration modification.
> - Do not delete it during working-tree cleanup unless the Master explicitly
>     authorizes its removal after the baseline purpose is no longer required.
>
> ### B. `main.dart`
>
> Classification:
> `MIGRATION-RELATED IMPORT/PATH CHANGE`
>
> The observed changes are import-path migrations from the former flat
> locations:
>
>         services/
>         providers/
>         screens/
>         widgets/
>
> to the frozen destination structure:
>
>         core/
>         modules/
>
> Therefore:
>
> - Preserve `main.dart`.
> - Do not revert it as an audit artifact.
> - Its changes are migration-related and must be included in final
>     migration validation and `git diff` review.
>
> ### C. Zero-byte file named `'`
>
> Classification:
> `AUDIT ARTIFACT`
>
> Observed:
>
> - Path: `'`
> - Size: 0 bytes
> - Created during the audit period
> - Contents: empty
>
> The file is considered an accidental shell/command/audit artifact.
>
> However:
>
> - It MUST NOT be deleted during the current audit.
> - It MUST NOT be reverted or modified by an AI.
> - It may be deleted only after explicit Master authorization during the
>     authorized working-tree cleanup phase.
>
> ### D. Confirmed Audit-Generated Artifacts
>
> The following are classified as:
>
> `AUDIT ARTIFACT — SAFE TO REMOVE AFTER EXPLICIT AUTHORIZATION`
>
> - `section4_audit_output.txt`
> - `status.txt`
> - `auth_service.diff.txt`
> - `splash_screen.diff.txt`
> - `diagnostics_screen.diff.txt`
> - `notifications_screen.diff.txt`
>
> These files are not migration outputs.
>
> However, classification does NOT itself authorize deletion.
>
> They remain protected until the Master explicitly authorizes cleanup.
>
> ### E. `section4_audit_result.txt`
>
> This file is currently absent from the working tree.
>
> Its absence must NOT be interpreted as proof that:
>
> - it never existed,
> - it was never generated,
> - it was already deleted intentionally, or
> - its contents can be reconstructed from memory.
>
> Record:
>
> `NOT PRESENT — PROVENANCE UNVERIFIABLE FROM CURRENT WORKING TREE`
>
> No AI may recreate, delete, or replace it merely to make the audit
> appear complete.
>
> ### F. Other Untracked Analysis/Report Files
>
> All other untracked root-level, tools-tree, diagnostic, report, or
> analysis files not explicitly classified above must remain:
>
> `UNKNOWN PROVENANCE`
>
> until independently classified.
>
> Rules:
>
> - Do not delete.
> - Do not revert.
> - Do not rename.
> - Do not move.
> - Do not overwrite.
> - Do not add to the migration.
> - Do not assume they are audit artifacts merely because their names look
>     temporary.
>
> The owning AI must report them to the Master if their provenance is
> required for execution or validation.

### Section 0-D.3 — No Cleanup During Provenance Audit

> The following actions are PROHIBITED during provenance classification:
>
> - `git clean`
> - `git reset --hard`
> - blanket `git restore`
> - deleting all untracked files
> - deleting all `.txt`, `.diff`, `.log`, `.yaml`, or diagnostic files
> - reverting files merely because they are outside the Migration Inventory
> - moving files merely to make the working tree appear clean
>
> A clean working tree is NOT itself a requirement for migration execution.
> Provenance correctness takes priority over cosmetic cleanliness.

### Section 0-D.4 — Explicit Cleanup Authorization

> Cleanup of confirmed audit artifacts may occur only after the Master gives
> explicit authorization.
>
> The authorization must identify the cleanup scope.
>
> For example:
>
>         AUTHORIZED CLEANUP:
>         - section4_audit_output.txt
>         - status.txt
>         - auth_service.diff.txt
>         - splash_screen.diff.txt
>         - diagnostics_screen.diff.txt
>         - notifications_screen.diff.txt
>         - '
>
> An AI may delete ONLY the explicitly authorized artifacts.
>
> It may not expand the cleanup scope automatically.

---

## Classification result

### MUST PRESERVE

This category includes all migration-related tracked changes and all baseline/provenance-preserved items that must remain as-is unless Master explicitly authorizes otherwise.

- All tracked modifications in the migration inventory, including import-path rewrites in:
  - [lib/main.dart](lib/main.dart)
  - [lib/core/services/auth_service.dart](lib/core/services/auth_service.dart)
  - [lib/core/navigation/main_shell_screen.dart](lib/core/navigation/main_shell_screen.dart)
  - [lib/core/navigation/parcel_detail_screen.dart](lib/core/navigation/parcel_detail_screen.dart)
  - [lib/modules/auth_startup/screens/splash_screen.dart](lib/modules/auth_startup/screens/splash_screen.dart)
  - [lib/modules/profile_settings/screens/diagnostics_screen.dart](lib/modules/profile_settings/screens/diagnostics_screen.dart)
  - [lib/modules/profile_settings/screens/notifications_screen.dart](lib/modules/profile_settings/screens/notifications_screen.dart)
  - all other files in the migration inventory listed in SECTION_B_WORKING_TREE_CLASSIFICATION.md
- [analysis_options.yaml](analysis_options.yaml)
- [pre_ai1_worktree](pre_ai1_worktree)
- [MASTER_MERGE_PLAN.md](MASTER_MERGE_PLAN.md)
- [MIGRATION_CLOSURE_REPORT.md](MIGRATION_CLOSURE_REPORT.md)
- [POST_MIGRATION_VALIDATION_PLAN.md](POST_MIGRATION_VALIDATION_PLAN.md)
- [SECTION_B_WORKING_TREE_CLASSIFICATION.md](SECTION_B_WORKING_TREE_CLASSIFICATION.md)
- [GATE0_HISTORICAL_RECONCILIATION_REPORT.md](GATE0_HISTORICAL_RECONCILIATION_REPORT.md)
- [GATE0_VERIFICATION_REPORT.md](GATE0_VERIFICATION_REPORT.md)
- [STEP0_AUDIT_RECORD.md](STEP0_AUDIT_RECORD.md)

### SAFE TO KEEP

These items are not currently authorized for deletion. They may remain in-place until explicit cleanup authorization is given, but they are not being treated as migration work.

- The zero-byte file named ' at the repository root.
  - Classification: AUDIT ARTIFACT
  - Status: must remain preserved until explicit Master authorization
- Confirmed audit artifacts that are explicitly protected by Section 0-D.2 and 0-D.4:
  - section4_audit_output.txt
  - status.txt
  - auth_service.diff.txt
  - splash_screen.diff.txt
  - diagnostics_screen.diff.txt
  - notifications_screen.diff.txt
- Build and generated directories such as build/, .dart_tool/, .agents/, .idea/, .qodo/, .vscode/, and the Android/iOS/macOS/Linux/Windows generated outputs.
- VS Code Copilot backup files with .copilot.bak suffix.
- Temporary analysis and validation scripts under tools/ and root-level diagnostic artifacts.

### CANDIDATE FOR DELETION

None at this stage.

Per MASTER_MERGE_PLAN.md Section 0-D.4, deletion requires explicit Master authorization and must be limited to the explicitly authorized scope. Nothing in this repository has been authorized for deletion, and no deletion action was performed.

### UNKNOWN PROVENANCE

These items are not individually proven to be migration-related, baseline, or authorized cleanup targets and therefore must stay untouched pending further classification.

- Untracked root-level analysis/report files not specifically named in Section 0-D.2.
- Non-source diagnostic artifacts and tool-generated outputs whose provenance has not been independently established.
- Any temporary report, JSON, CSV, or diagnostic file created by audit tooling but not explicitly classified elsewhere.

This classification is intentionally conservative: unknown files remain preserved rather than guessed at and deleted.

---

## Required execution constraint

This plan is classification-only and does not authorize any deletion, repair, rename, move, restore, or reset operation.

The repository remains in its preserved state until the Master explicitly authorizes a cleanup batch.

## OPEN ITEM — future cleanup pass only

The prior cleanup review flagged bare directory names without full-path confirmation, including `lib/services/`, `lib/screens/`, `lib/models/`, `lib/providers/`, and `lib/theme/`. These were classified as REQUIRED in the current non-destructive pass without proving whether any of the old top-level pre-migration folders are actually empty and genuinely removable.

This should be resolved in a future cleanup pass only, not during migration validation or any current cleanup action.

Required future determination:
- confirm whether the old top-level pre-migration folders are empty and removable;
- confirm whether nested directories under lib/core/ and lib/modules/ must remain intact;
- preserve the migration directory structure until validation confirms the app works correctly.
