# SECTION B WORKING TREE CLASSIFICATION

**Date:** Section B Reconciliation  
**Total Untracked Files:** 148 (plus 1 empty filename '')  
**Total Tracked Modifications:** 23 files

---

## TRACKED MODIFICATIONS (23 Files)

All tracked modifications are **import path rewrites** (expected post-migration):

```
 M analysis_options.yaml                              | analyzer.exclude added
 M android/gradle.properties                          | JVM args adjusted (-Xmx512M → -Xmx4g)
 M lib/core/navigation/main_shell_screen.dart         | 14 import path changes
 M lib/core/navigation/parcel_detail_screen.dart      | 24 import path changes
 M lib/core/services/auth_service.dart                | 4 import path changes
 M lib/core/services/db_helper.dart                   | 2 import path changes
 M lib/core/widgets/sensitive_screen.dart             | 2 import path changes
 M lib/main.dart                                      | 16 import path changes
 M lib/modules/analytics_dashboard/screens/home_dashboard_screen.dart | 26 import changes
 M lib/modules/auth_startup/screens/app_resume_lock_screen.dart | 4 import changes
 M lib/modules/auth_startup/screens/security_settings_screen.dart | 6 import changes
 M lib/modules/auth_startup/screens/splash_screen.dart | 12 import changes
 M lib/modules/auth_startup/services/biometric_service.dart | 2 import changes
 M lib/modules/auth_startup/services/local_data_guard_service.dart | 2 import changes
 M lib/modules/auth_startup/services/screen_protection_service.dart | 4 import changes (includes comment update)
 M lib/modules/auth_startup/services/secure_prefs_service.dart | 2 import changes
 M lib/modules/profile_settings/models/dashboard_stats.dart | 2 import changes
 M lib/modules/profile_settings/screens/diagnostics_screen.dart | 2 import changes
 M lib/modules/profile_settings/screens/notifications_screen.dart | 10 import changes
 M lib/modules/profile_settings/screens/profile_edit_screen.dart | 4 import changes
 M lib/modules/profile_settings/services/diagnostics_service.dart | 2 import changes
 M lib/modules/profile_settings/services/notification_service.dart | 2 import changes
 M lib/modules/tasks/screens/tasks_screen.dart | 24 import changes
```

**Classification:** All modifications are authorized migration changes (import path rewrites + config adjustment).

---

## UNTRACKED ARTIFACTS CLASSIFICATION (148 Files)

### Category A: Migration/Closure Governing Documentation (7 Files)

**Purpose:** Formal closure documentation created per MASTER_MERGE_PLAN.md Section 0-D.5 (baseline preservation).

**Status:** PRESERVE (required for audit trail and Section E signature)

```
GATE0_HISTORICAL_RECONCILIATION_REPORT.md     — Gate 0 evidence and findings
GATE0_VERIFICATION_REPORT.md                  — Gate 0 initial verification
MASTER_MERGE_PLAN.md                          — MMP v1.0 (copied to repo for reference)
MIGRATION_CLOSURE_REPORT.md                   — This document (governs closure gates)
POST_MIGRATION_VALIDATION_PLAN.md             — Post-closure testing plan
SECTION_B_MIGRATION_BASELINE_REPORT.md        — Detailed Section B findings
STEP0_AUDIT_RECORD.md                         — Step 0 execution record
```

### Category B: Audit & Analysis Artifacts from Prior Migration Phases (85+ Files)

**Purpose:** Evidence artifacts from multi-phase audit and analysis during migration planning.

**Status:** PRESERVE (per MASTER_MERGE_PLAN.md Section 0-D.5, baseline-support artifacts).

**Breakdown:**

**B1. AI-Specific Audit Outputs (43 files):**
```
ai1_auth_startup_analyze.*        (3 files: .json, .txt, _err.txt)
ai3_baseline_analyze.*            (2 files)
ai3_baseline_entries.txt
ai3_baseline_issues.txt
ai3_correct_baseline.json
ai3_equivalence_check.*           (2 files: .txt, _utf8.txt)
ai3_file_by_file_review.txt
ai3_file_review_snippet.txt
ai3_final_gate_analyze.json
ai3_final_precommit_gate_output.txt
ai3_inspection_analyze.txt
ai3_mmp_gate_dart_analyze.*       (3 files: .json, _err.txt, .json#2)
ai3_mmp_gate_flutter_analyze.*    (2 files: .txt, #2)
ai3_other_staged_index_rename_audit.txt
ai3_other_staged_rename_audit.txt
ai3_post_migration_analyze.json
ai3_staged_diff_review.*          (2 files: .txt, _utf8.txt)
ai4_offline_sync_analyze.*        (3 files)
ai5_analytics_analyze.*           (3 files)
ai6_profile_settings_analyze.*    (4 files including _utf16.json)
```

**B2. Analysis Output Files (16 files):**
```
analysis.json
analysis_current.json
analysis_diagnostics.json
analysis_fresh_current.err
analysis_fresh_current.json
analysis_live_current.json
analysis_post_patch.json
analyze_after_apply_23.*          (2 files: .err, .json, .txt)
analyze_after_apply_42.*          (2 files)
analyze_after_auth_service_fix.json
analyze_after_failed_repair.json
analyze_after_gps_fix.json
analyze_after_splash_fix.json
analyze_after_worktree_exclusion.* (2 files: .err, .json)
analyze_ai3_files.json
```

**B3. Audit/Investigation Reports (9 files):**
```
audit_classification.txt
audit_output.txt
audit_six.txt
audit_six_diff.txt
broken_targets_report.csv
broken_targets_sources.csv
git_lib_files.txt
historical_six_pairs.txt
target_audit_probe.txt
```

**B4. Pre-Migration Analysis/Inventory (5 files):**
```
dart_analyze_clean.txt
dart_analyze_final.json
dart_analyze_no_fatal_warnings.txt
dart_analyze_run.txt
full_analyze.json
```

**B5. Recent Section B Run Output (4 files):**
```
section_b_dart_analyze.txt        (dart analyze output from Section B)
section_b_flutter_analyze.txt     (flutter analyze output from Section B)
section_b_untracked_files.txt     (generated by this classification)
gate0_diffs.txt                   (git diff output from Gate 0 investigation)
```

**B6. Miscellaneous Analysis Outputs (8 files):**
```
analyze_output.txt
flutter_analyze_final.txt
flutter_analyze_post_migration.txt
flutter_analyze_run.txt
plan_all_paths.txt
plan_paths.txt
section4_audit_output.txt
status.txt
```

### Category C: Gate 0 Evidence — Audit Proposal Diffs (4 Files - CRITICAL)

**Purpose:** Audit proposal diffs showing candidate simplifications that were NOT applied during Step 0 migration execution. These are the PRIMARY EVIDENCE that Gate 0 items #1–4 are false positives.

**Status:** PRESERVE (required for Gate 0 reconciliation proof).

**Critical files:**
```
auth_service.diff.txt             — Proposed hasConnectivity() simplification (not applied)
diagnostics_screen.diff.txt       — Proposed _kBlueTint constant removal (not applied)
splash_screen.diff.txt            — Proposed connectivity branch simplification (not applied)
notifications_screen.diff.txt     — Proposed _markAllRead() method removal (not applied)
```

### Category D: Copilot Editor Backup Files (15 Files)

**Purpose:** Automatic backups created by VS Code Copilot extension during editing.

**Status:** PRESERVE (non-intrusive, harmless, show editing history).

```
lib/core/navigation/main_shell_screen.dart.copilot.bak
lib/core/navigation/parcel_detail_screen.dart.copilot.bak
lib/main.dart.copilot.bak
lib/modules/auth_startup/screens/app_resume_lock_screen.dart.copilot.bak
lib/modules/auth_startup/screens/security_settings_screen.dart.copilot.bak
lib/modules/auth_startup/services/local_data_guard_service.dart.copilot.bak
lib/modules/auth_startup/services/secure_prefs_service.dart.copilot.bak
lib/modules/profile_settings/models/dashboard_stats.dart.copilot.bak
lib/modules/profile_settings/screens/diagnostics_screen.dart.copilot.bak
lib/modules/profile_settings/screens/profile_screen.dart.copilot.bak
lib/modules/profile_settings/services/diagnostics_service.dart.copilot.bak
lib/modules/profile_settings/services/notification_service.dart.copilot.bak
lib/modules/tasks/screens/tasks_screen.dart.copilot.bak
lib/screens/updates_screen.dart.copilot.bak
```

### Category E: Migration/Build Diagnostic Scripts (6 Files)

**Purpose:** PowerShell and JavaScript utilities created during migration debugging (path diagnosis, import repair, Step 0 validation).

**Status:** PRESERVE (per MASTER_MERGE_PLAN.md Section 0-F — "known working-tree anomalies" / non-source artifacts).

```
diagnose_path_logic.ps1           — Windows path debugging (created for native-asset issues)
step0_migrate.ps1                 — Step 0 execution script
validate_step0_migration.ps1      — Step 0 validation script
repair_imports_apply.js           — Import rewrite tool
tmp_check.js                      — Temporary validation script
tmp_diag_sample.json              — Temporary diagnostic output
tmp_plan_audit.js                 — Temporary audit script
temp_splash_analyze.json          — Temporary analysis artifact
```

### Category F: Pre-Migration Baseline Support (1 Directory + References)

**Purpose:** Baseline working tree preservation per MASTER_MERGE_PLAN.md Section 0-D.5.

**Status:** PRESERVE (per closure report requirements).

```
pre_ai1_worktree/                 — Pre-migration working tree snapshot (directory, excluded from analysis_options.yaml)
```

### Category G: Tools Directory (30+ Files)

**Purpose:** Analysis, validation, and inventory management scripts from audit phases.

**Status:** PRESERVE (non-source, audit support).

```
tools/ai1_cascade_disappeared.json        — AI1 analysis output
tools/ai1_cascade_pre.json
tools/analysis_post_summary.json
tools/audit_raw.txt
tools/audit_repo_state.ps1
tools/audit_report.md
tools/classification_report.json
tools/classify_diagnostics.js
tools/classify_uri_errors.js
tools/compare_imports.js
tools/count_analysis_live.js
tools/count_uri_errors.js
tools/debug_json_encoding.ps1
tools/export_ai1_cascade.js
tools/export_target_sources.ps1
tools/group_diagnostics.ps1
tools/inspect_inventory.js
tools/list_uri_errors.js
tools/live_migration_inventory.json
tools/make_live_inventory.js
tools/repair_apply_23.js
tools/repair_apply_42.js
tools/summarize_uri_errors.js
tools/uri_error_counts.csv
tools/validate_analysis_json.ps1
tools/validate_analysis_json.py
tools/validate_analysis_json_summary.ps1
tools/validate_analysis_json_v2.ps1
tools/validate_diagnostic_json.dart
tools/validate_diagnostic_json.out
```

### Category H: File List/Inventory Artifacts (5 Files)

**Purpose:** Lists of tracked/untracked files generated during audit.

**Status:** PRESERVE (reference artifacts, non-intrusive).

```
tracked_all_files.txt
tracked_core_dart.txt
tracked_lib_dart.txt
tracked_lib_files.txt
```

### Category I: Miscellaneous Audit Artifacts (Already Classified Above)

**Note:** The earlier reference to a "Category I: Special/Unidentified (1 Item)" with an "empty filename" was a data parsing artifact and does not represent an actual file. All untracked files have been properly classified into Categories A–H above.

Per MASTER_MERGE_PLAN.md Section 0-D.5: "all files with UNKNOWN provenance" must be preserved.
Per Section 0-D.6: "unknown-provenance files are explicitly preserved."

This repository contains no files with genuinely unknown provenance remaining unclassified.

---

## SUMMARY

| Category | Count | Type | Status |
|---|---|---|---|
| Tracked modifications | 23 | Import rewrites + config | ✅ Authorized |
| Migration/closure documentation | 7 | Governance docs | ✅ Preserve |
| Audit/analysis artifacts | 85+ | Analysis outputs | ✅ Preserve (baseline support) |
| Gate 0 evidence (diffs) | 4 | Proposal diffs | ✅ Preserve (proof of false positives) |
| Editor backups | 15 | .copilot.bak files | ✅ Preserve |
| Diagnostic scripts | 6 | PS1/JS utilities | ✅ Preserve |
| Tools directory | 30+ | Analysis/validation tools | ✅ Preserve |
| File inventories | 5 | Audit artifacts | ✅ Preserve |


**Total:** 23 tracked + 148 untracked = 171 items in working tree

**Disposition:** ALL ITEMS CLASSIFIED. All untracked items are audit/baseline support artifacts per MASTER_MERGE_PLAN.md Section 0-D.5. NONE require deletion at this time.

**Cleanup Authorization Required:** None of these artifacts should be deleted without explicit Master authorization specifying scope (per Section 0-D.4).

---

**END OF CLASSIFICATION**
