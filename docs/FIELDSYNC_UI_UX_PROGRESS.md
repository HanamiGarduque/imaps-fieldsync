# FieldSync UI/UX implementation and verification tracker

Prepared: 2026-09-20. Target repository: `C:\Users\Ralph Lauren\imaps_fieldsync_main`.

Requirements: [FIELDSYNC_UI_UX_FINDINGS.md](FIELDSYNC_UI_UX_FINDINGS.md).

Initial state: documentation handoff prepared; no application changes or implementation verification performed for this handoff. All core findings are pending. Earlier source inspection and supplied screenshots are audit evidence, not passing implementation checks. Existing working-tree changes belong to their original work and must be preserved.

## Instructions for the implementing agent

When the user asks you to implement these documents, read both and execute the loop below. Continue beyond planning into scoped code changes and verification. Do not request approval after every loop or stop simply because the first batch is complete. Use the files as durable memory, particularly after context loss or a new session.

Start by confirming the actual repository root. Do not edit the similarly named `C:\Users\Ralph Lauren\iMAPS` project merely because it is the terminal's default directory. Read applicable repository instructions and relevant implementation guidance, inspect current source and tests, and record the dirty-worktree baseline. Preserve all existing modifications and untracked files. Do not roll back somebody else's work to establish a clean baseline.

Apply the scope and business-contract constraints in the findings document. Routine implementation, narrow refactoring needed for truthful UI feedback, and appropriate verification are authorized by the implementation command. Production actions, deployments, Git history operations, and domain/backend policy changes are not. If a tool requires permission, explain the actual permission boundary. If a product decision is missing, identify the exact affected requirement and continue independent authorized work.

Keep finding IDs and acceptance conditions stable. Do not turn a requirement into an easier one, delete an inconvenient finding, or mark a task verified because a file was edited. Append evidence and corrections here. Add newly discovered directly related regressions to the relevant loop; record unrelated discoveries separately rather than expanding scope silently.

## The implementation loop

1. Read both documents and the latest checkpoint. Check the current diff/source, not only the tracker. Confirm whether another contributor changed previously verified code since the last recorded snapshot.
2. Before starting loop N, review every earlier completed or implemented loop for possible impact. Record which shared widgets, providers, models, helpers, routes, state, or persistence paths connect the proposed change to earlier requirements. Identify checks to rerun; explain why other earlier loops are unaffected. Before Loop 03, this explicitly includes Loops 01 and 02.
3. If that review exposes a regression or invalidated assumption, reopen the affected finding/loop and resolve it before moving ahead with dependent work. Do not build another change on a known broken prerequisite. Independent work may continue if the dependency and remaining limitation are recorded.
4. Choose the next small coherent batch from the schedule. Inspect its current implementation, callers, existing tests, and relevant screenshot/audit evidence. Record the exact finding/acceptance IDs, plan, likely affected files, and baseline failures before editing. Reproduce a suspected defect where possible.
5. Implement the smallest complete change for that batch, preserving in-progress user work and domain contracts. Prefer complete behavior over superficial label changes when the underlying UI state is wrong. Keep unrelated refactors out of the diff.
6. Verify the new behavior against each acceptance condition, then check affected earlier loops on the changed code. A shared theme/header/navigation change requires checks of its consumers, even if their own files were not edited. Use suitable analyzer/tests, rendered inspection, and device checks; distinguish what each proves.
7. If loop N breaks loop K, mark K reopened, record the cause, fix the interaction, and verify both K and N plus their affected dependents. Only then close the loop and start dependent work. Do not hide the failure by weakening tests or assertions.
8. Update the finding register, loop log, regression matrix, and next-action checkpoint. Re-read the requirements and confirm that the recorded results actually meet them. Continue to the next eligible batch until core work is accounted for.

The intended sequence is: inspect prior work -> implement one batch -> verify that batch -> verify affected prior work -> repair regressions -> update evidence -> repeat. Reading a Markdown file alone is never regression verification.

Review all earlier loops for impact every time; do not rerun every unrelated test blindly. Run affected checks when code or dependencies change, and the agreed cumulative smoke checks at integration checkpoints. Once relevant checks pass, repeat only for new changes, new failures, stale evidence, or unresolved concerns. Run the full appropriate integration pass at the end.

## Status and evidence rules

| Finding status | Meaning |
|---|---|
| Pending | Not implemented or not yet revalidated against current code. |
| In progress | An active bounded change/investigation is underway. |
| Implemented — awaiting verification | Code is changed but one or more required acceptance checks have not passed or cannot yet run. |
| Verified | All applicable acceptance conditions have evidence for the relevant current code snapshot; required runtime/device checks are included. |
| Blocked | A specific external dependency, permission, or product decision prevents the remaining work. State what is needed; continue independent tasks. |
| Already resolved | Current code already satisfies every applicable acceptance condition, supported by verification. Do not implement a duplicate fix. |
| Not reproduced | Use only for an explicitly suspected defect, with scenario/environment/evidence and limits. This does not close other requirements in the same finding or prove untested paths correct. |
| Reopened | A later change, failed check, or stale assumption invalidated prior completion. Keep the previous evidence as history. |

Statuses belong to findings and, when needed, individual conditions. For example, FS-008.A may be “Not reproduced” in tested conditions while FS-008.C still needs a navigation-label fix. The overall finding cannot be marked complete just because its suspected bug was not reproduced.

Loop states are Planned, In progress, Awaiting verification, Verified, Blocked, or Reopened. Keep a loop Awaiting verification if its implementation is finished but required device checks are unavailable. You may work on independent loops, but never claim those outstanding checks passed.

Record command, working directory, result/exit status, and a concise meaningful output summary. For visual evidence, record screen/state, build or source snapshot, device/viewport, text scale, navigation mode, and a local evidence path when captured. For a dirty worktree, a commit hash alone is insufficient: retain a scoped diff/patch or appropriate file hashes alongside the baseline. Avoid secrets and unnecessary personal data in evidence.

An existing failure must be recorded before it is used as a baseline exception. A newly introduced failure cannot be relabelled “pre-existing” after the change. Do not remove assertions just to make a suite pass.

After repeated failed attempts, stop applying the same unproductive fix: document the observed failure, attempts, and root-cause evidence, then change the approach or mark the specific dependency blocked. Never use an arbitrary retry count to claim completion. Do not spend an indefinite loop rereading the same Markdown with no new evidence or changes.

## Baseline to record when implementation starts

| Item | Initial value / required entry |
|---|---|
| Correct repository | Expected `C:\Users\Ralph Lauren\imaps_fieldsync_main`; confirm before editing. |
| Start time and branch/HEAD | Not captured for implementation yet. |
| Working-tree baseline | Known dirty from audit; capture current modified/deleted/untracked paths and preserve relevant diff evidence. |
| Instructions and domain contracts | Read current applicable instructions, tests, and source; record conflicts with old design documents. |
| Flutter/Dart availability | Not checked for implementation; discover installed tools before issuing commands. |
| Existing checks | Read project configuration and tests; record appropriate analyzer/test baseline, including pre-existing failures. |
| Device/emulator and test data | Not established. Identify available local/authorized environment; never use production submission as a test. |
| Baseline UI evidence | Historical user screenshots available in the conversation; confirm local availability or capture current UI. Do not claim unseen attachments were inspected. |
| Implementation changes so far | None in this handoff. |

Useful existing tests to inspect if still present include `test/task_category_ground_truth_test.dart`, `test/downstream_scheduled_alignment_test.dart`, `test/offline_completion_persistence_test.dart`, `test/offline_start_atomicity_test.dart`, `test/inspection_job_retention_test.dart`, `test/interrupted_drain_verification_test.dart`, `test/photo_presentation_test.dart`, `test/photo_source_resolver_test.dart`, `test/r4_photo_loopback_test.dart`, `test/r4_recovery_test.dart`, `test/profile_display_name_test.dart`, and `test/login_terms_checkbox_test.dart`. Assignment/provenance tests and `test/widget_test.dart` may also protect touched flows. These names are discovery pointers, not a claim that they pass or must all run in every loop.

Use commands supported by the actual project, such as `flutter analyze` and targeted `flutter test <existing-test-path>` when appropriate. Do not invent scripts or assume device plugins run in a host-only test. Add meaningful behavioral tests for result contracts, branching, formatting, state retention, and failures when warranted. Do not add brittle source-string or implementation-mirroring tests merely to count tests, or tests solely for low-impact cosmetic edits. Visually inspect cosmetic changes in a rendered application when available.

## Planned loop schedule

This is a dependency-aware starting schedule. Split an oversized batch using suffixes (for example L09a/L09b), or reorder independent work with a recorded reason. Preserve coverage of all findings. P0 corrections come first; visual changes later must recheck them.

| Loop | Scope | Finding IDs | Important prior contracts to recheck | State |
|---|---|---|---|---|
| L01 | Save-result contracts and exit/recovery | FS-001 | Existing offline retention and lifecycle tests | Planned |
| L02 | Map route truth and GPS presentation | FS-002, FS-003 | L01: saved verification and exit paths | Planned |
| L03 | Sync summary and overwrite consequences | FS-004, FS-005 | L01 and L02: save/queue claims and verification data | Planned |
| L04 | Security wording and state summary | FS-006 | Existing launch/resume policy; earlier loops if navigation changes | Planned |
| L05 | Home assignment/date/empty-state truth | FS-024 | Existing lifecycle/scheduling; earlier state/navigation changes | Planned |
| L06 | Functional analytics period controls | FS-007 | Existing task counts and date contracts, L05 where shared | Planned |
| L07 | Assessment investigation and checklist meaning | FS-008, FS-009 | L01/L03 save-delivery contracts; L02 GPS record semantics | Planned |
| L08 | Camera, photo requirements, and display recovery | FS-010, FS-011, FS-012 | L01/L03/L07: persistence, delivery, and assessment state | Planned |
| L09 | Evidence review, narrative findings, completed records | FS-013, FS-014, FS-015 | L01–L03 and L07–L08: saved evidence and rework | Planned |
| L10 | Shared components, status/formatting rules, step headers | FS-016, FS-017, FS-018 | All earlier loops using changed components/formatters | Planned |
| L11 | Shell, navigation clearance, tab continuity, motion | FS-019, FS-020 | All prior rendered flows; L04 launch/resume; state retention | Planned |
| L12 | Task summaries, filters, and overview | FS-021, FS-022, FS-023 | L05/L07/L09–L11 plus canonical lifecycle tests | Planned |
| L13 | Home and Sync hierarchy/presentation | FS-025, FS-026 | L03/L05/L10–L12; truthful state summaries must survive | Planned |
| L14 | Profile hierarchy and analytics presentation | FS-027, FS-028 | L04/L06/L10/L11; period controls must remain functional | Planned |
| L15 | Login and supporting screens/dialogs | FS-029, FS-030 | L01/L04/L10/L11/L14 and authentication/account isolation | Planned |
| L16 | Cumulative rendered/device and workflow verification | FS-031 and every earlier finding | All previous loops, combined diff, remaining acceptance gaps | Planned |

Apply FS-031 checks to each changed screen from the beginning; L16 consolidates the evidence and remaining integration checks. It is not permission to postpone obvious clipping/reachability regressions.

## Finding register

Update this register after each loop. “Evidence” should point to a loop log and acceptance conditions, not simply say “done.” All A/B/C conditions are initially unverified.

| Finding | Priority | Assigned loop | Status | Evidence / remaining conditions |
|---|---|---|---|---|
| FS-001 | P0 | L01 | Pending | A/B/C not verified |
| FS-002 | P0 | L02 | Pending | A/B/C not verified |
| FS-003 | P0 | L02 | Pending | A/B/C not verified |
| FS-004 | P0 | L03 | Pending | A/B/C not verified |
| FS-005 | P0 | L03 | Pending | A/B/C not verified |
| FS-006 | P0 | L04 | Pending | A/B/C not verified |
| FS-007 | P0 | L06 | Pending | A/B/C not verified |
| FS-008 | P0 investigation | L07 | Pending | Assessment defect unconfirmed; navigation requirement still applies |
| FS-009 | P0 | L07 | Pending | A/B/C not verified |
| FS-010 | P0 | L08 | Pending | A/B/C not verified; device camera checks required |
| FS-011 | P1 | L08 | Pending | A/B/C not verified |
| FS-012 | P2 | L08 | Pending | A/B/C not verified |
| FS-013 | P1 | L09 | Pending | A/B/C not verified |
| FS-014 | P2 | L09 | Pending | A/B/C not verified |
| FS-015 | P2 | L09 | Pending | A/B/C not verified |
| FS-016 | P1 | L10 | Pending | A/B/C not verified |
| FS-017 | P1 | L10 | Pending | A/B/C not verified |
| FS-018 | P1 | L10 | Pending | A/B/C not verified |
| FS-019 | P1 | L11 | Pending | A/B/C not verified |
| FS-020 | P1 | L11 | Pending | A/B/C not verified |
| FS-021 | P1 | L12 | Pending | A/B/C not verified |
| FS-022 | P2 | L12 | Pending | A/B/C not verified |
| FS-023 | P1 | L12 | Pending | A/B/C not verified |
| FS-024 | P0 | L05 | Pending | A/B/C not verified |
| FS-025 | P1 | L13 | Pending | A/B/C not verified |
| FS-026 | P1 | L13 | Pending | A/B/C not verified |
| FS-027 | P1 | L14 | Pending | A/B/C not verified |
| FS-028 | P2 | L14 | Pending | A/B/C not verified |
| FS-029 | P2 | L15 | Pending | A/B/C not verified |
| FS-030 | P2 | L15 | Pending | A/B/C not verified |
| FS-031 | P2 | All loops; L16 closure | Pending | Required rendered/device and cumulative checks not performed |

## Regression matrix

For each row, add the actual passing/failing evidence, source snapshot, and affected loop IDs as work proceeds. Initial state for every row: not run. Cover relevant rows after each change and all applicable rows at final integration.

| Area | Scenarios / invariant | Initial status |
|---|---|---|
| Lifecycle and assignment identity | Pending/Ongoing/Completed, self-scheduled in-progress remains Ongoing, scheduled/anytime, unknown values, matching record identity/provenance across screens | Not run |
| Save and exit | Online acknowledgement, confirmed offline save/queue, failed local write/queue, thrown errors, retry, stay/discard, normal/rework exits, repeated taps | Not run |
| Maps and GPS | Valid real route, unavailable/stale route, sensor/permission failure, normalized heading, inclusive 30 m, readable uncertainty, saved verification versus proximity | Not run |
| Camera and evidence | Discovery/init/permission/capture/save failures, unresolved geotag, zero/one/ten photos, retake, notes, cancel/remove, interruption and reopen, local/remote retry | Not run |
| Checklist and findings | Default and mixed Boolean answers, no all-true requirement, long narratives, actual answers/notes preserved across review and completed detail | Not run |
| Submit and reopen | Each existing assessment, selected value preserved, repeated taps prevented, acknowledged versus queued outcome, failure recovery, reopen/rework, correct result destination | Not run |
| Sync and conflict | Queue empty/nonempty with files zero/nonzero, failed/conflicting work, retry/selective sync, mark-force cancel/confirm/failure, next-drain wording, retained audit | Not run |
| Home and filters | Ongoing-only assignments, empty/filter-empty distinctions, selected day/today semantics, date range boundaries/future/missing dates, reset/cancel/apply | Not run |
| Analytics | Different week/month fixtures, real denominator, no invented goal, empty data, all shared selector consumers and adaptive chart geometry | Not run |
| Shell and continuity | Search/filter/category/calendar/scroll retained across tabs, refresh behavior, no duplicate listeners, correct reset on account change, labelled Quick actions | Not run |
| Security and login | Launch authentication versus inactivity choices, activation/capability wording, native authentication, offline login, consent, recovery, route-preserving resume lock | Not run |
| Supporting flows | Profile edit, bilingual help/search, issue-form validation/error, legal/about access, modal cancellation, logout, existing consequential confirmations | Not run |
| Layout and accessibility | Small/target phones, normal/large text, long values, keyboard, safe areas, navigation modes, supported orientation, reachable last row/action, semantic order and non-color cues | Not run |

## Loop log template

Copy this template below for each real loop, including regression repair loops. Do not fill it with anticipated results.

```markdown
### Lxx — Actual batch name

State: In progress / Awaiting verification / Verified / Blocked / Reopened
Started/updated: actual timestamp
Requirements: FS-xxx.A, FS-xxx.B, FS-xxx.C
Source snapshot/baseline: HEAD plus relevant dirty diff/file hashes and pre-existing failures

Before-change evidence:
Actual source/caller findings, reproduction, and relevant screenshot/device observations.
Record already-resolved or not-reproduced claims with their verification limits.

Prior-loop impact review:
All earlier loop IDs reviewed: ...
Affected: loop/finding IDs, shared dependency, reason, checks to run.
Unaffected: loop IDs and concrete reason their paths/contracts are isolated.
Stale or failed evidence: what must be reopened and why.

Implementation:
Files/areas changed, user-visible behavior, and scope decisions.
How existing uncommitted work and domain contracts were preserved.

Verification:
| Acceptance/check | Command or manual scenario | Result | Evidence and source snapshot |
|---|---|---|---|
| FS-xxx.A | Actual check performed | Pass / Fail / Not run | Output summary or local artifact |

Prior-loop regression results:
For each affected prior loop: checks run, results, and evidence.
If broken: reopen ID, cause, repair, and repeat verification for both old and new work.

Remaining gaps/decisions:
Exact unverified condition, blocker, practical next action, and dependent loops.

Checkpoint:
Registers/matrix updated; next eligible loop and first concrete action.
```

## Actual loop logs

No implementation loop has started. Add L01 after baseline inspection begins.

## Decisions, blockers, and corrections

No implementation decisions or blockers have been recorded yet. Record each with a stable local ID, related finding/condition, evidence, effect on dependencies, and resolution. The possibility that a tool/device is unavailable is not itself a recorded failure. Do not ask the user to decide matters already settled by current session authorization or verified contracts.

If a finding conflicts with current code, preserve both the historical observation and the new evidence. If a requirement needs a domain decision, document only the exact policy question; continue presentation fixes that do not depend on its answer.

## Completion gate

Before claiming the project complete, ensure every core finding and acceptance condition is accounted for with current evidence. Verified and Already resolved require appropriate proof. An investigated screenshot concern can be documented as Not reproduced only within the scenarios actually exercised; disclose remaining uncertainty and finish any other conditions in that finding. No unresolved implementation failure, reopened regression, or unverified required device check may be silently treated as passed.

Review the combined changes against the initial working-tree baseline, not just the most recent loop. Confirm that no existing code/test work was discarded, no unrelated files were swept into formatting/refactoring, and no business/backend contract was changed to satisfy a visual requirement. Run the appropriate project analyzer/test checks and the cumulative regression matrix. Do not repeatedly rerun already-passing checks without a reason.

Complete an online test-data journey and an offline/interrupted journey through task selection, site/GPS, capture and notes, mixed checklist answers, findings, evidence review, the selected assessment, result, reopen, and targeted rework. Exercise sync states, navigation continuity, security summaries, and the rendered layout checks. Use local fixtures or authorized test systems; if end-to-end infrastructure is unavailable, state exactly which steps remain unverified and retain the partial status.

If the work is implemented but device validation is unavailable, the honest outcome is “Implemented; device verification pending,” with a concrete manual checklist and affected IDs. If code work is blocked, identify completed versus remaining work. Neither outcome is equivalent to “all findings fixed and verified.”

The final report to the user must state what changed and why, relevant files, finding/loop completion, tests and rendered/device checks actually performed, prior-loop regressions found and repaired, and unresolved risks or required decisions. Keep it concise; link evidence and these documents rather than reproducing every log. Do not deploy or commit as an automatic final step.

## Resume checkpoint

Last completed implementation loop: none.

Active loop: none. Next action: confirm repository root and instructions, capture the existing working-tree/test baseline, then begin L01 / FS-001 by tracing each save/exit callback and its actual result contract.

Known historical cautions: started scheduled tasks remain Ongoing in current code; existing Review photo previews and photo resolver must be retained; the screenshot assessment mismatch is unconfirmed; debug-only red camera control is excluded from production criticism. No test/device success has been recorded for this handoff.
