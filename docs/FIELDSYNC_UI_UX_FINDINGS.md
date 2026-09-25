# FieldSync UI/UX findings and implementation requirements

Prepared: 2026-09-20. Target repository: `C:\Users\Ralph Lauren\imaps_fieldsync_main`.

Companion: [FIELDSYNC_UI_UX_PROGRESS.md](FIELDSYNC_UI_UX_PROGRESS.md). Read both documents before implementation and before resuming work. This file defines the requirements; the companion records execution and evidence. A checkbox or a claim in the tracker is not proof that the application satisfies a requirement.

These documents were requested as a handoff for future Cline code changes. Preparing them did not implement any of the fixes. The original diagnostic was read-only; a subsequent instruction to implement this handoff authorizes the bounded code changes below. It does not authorize deployment, production data changes, or changes to business policy.

## Evidence, authority, and limitations

The source material consists of the user's original read-only audit brief, the earlier UI/UX diagnostic, the supplied application screenshots, and the later report that reconciled those findings with the working-tree source. The later report is preserved at the end of this file as the original consolidated audit. Its historical statements describe the audit session, not completion of this implementation project.

The audit used the actual Flutter repository named above. Source locations below are navigation anchors from that audit, not a guarantee of unchanged line numbers. Reopen the current implementation and its callers before editing. Screenshots may represent another build; they demonstrate rendered observations but cannot establish current persistence behavior. No device run, build, test run, contrast measurement, backend verification, or field-usability certification was performed to prepare this handoff.

The repository already contains substantial modified, deleted, and untracked files, including inspection/provider/photo/sync work and additional tests. Capture the current baseline at implementation start. Do not discard, overwrite wholesale, or claim ownership of those changes.

Use this precedence when resolving disagreements: the user's latest explicit instruction; verified existing domain contracts and tests; these consolidated requirements; the historical reports. Existing code is evidence, not an excuse to retain a confirmed UI defect. If satisfying a requirement would change an unresolved domain contract, record the decision needed and continue independent work without inventing a policy.

### Corrections that must survive implementation

| Concern | Current interpretation and constraint |
|---|---|
| Started scheduled tasks | Current mapping places `in_progress` in Ongoing, including self-scheduled tasks. Preserve it and its tests. The older `My tasks status design spec.md` disagrees; do not restore its outdated rule as a visual fix. |
| Review photographs | Current Review code already contains thumbnails and a viewer. Extend its evidence review; do not replace or remove working photo behavior based on the earlier report. |
| Floating red camera control | The screenshot-protection toggle is debug-only. Exclude it from production clutter requirements; do not weaken screenshot protection. |
| Upward floating arrow | It opens Quick actions, not scroll-to-top. Correct discoverability without silently changing its purpose. |
| Zero-photo Continue | The current handler requires a photo. Improve advance communication; the screenshot does not prove a bypass. |
| Assessment changes on submit | Screenshots show a discrepancy, but the inspected UI passes the selected value to submission, queueing, and the success screen. Investigate the whole path before claiming a defect or changing persistence. |
| Missing thumbnail | A missing display is not proof of deleted evidence. Preserve the local/remote resolver and establish loading/error/recovery states. |
| Different totals across screenshots | Different capture times, scopes, and filters prevent concluding that arithmetic is broken. Define each metric's scope and reproduce any inconsistency. |
| Typography | Urbanist and Inter are implemented; legacy font helper names are aliases. The helper enforces a minimum requested size. Do not infer rendered fonts or sizes from method names alone. |
| Layout and performance | Large-text clipping, keyboard obstruction, contrast, glove use, and motion performance need rendered/device checks. Resized screenshots do not establish exact logical-pixel measurements. |
| Offline maps | Cached jobs and working GPS do not prove offline basemap availability. Do not promise offline tiles or add a mapping subsystem in this scope. |

## Product and implementation contract

The design direction is an evidence-first field notebook: inspection identity, recorded evidence, assessment, and delivery state. Use instrument-like clarity inside map/GPS/camera and comparable operational records inside Home/Tasks/Sync. Keep the blue identity, Urbanist/Inter foundation, four destinations, six inspection steps, existing evidence capabilities, bilingual help, and targeted rework.

Emphasize the inspection reference, applicant, site, current work, and next action. Reduce decorative paper, grain, glow, nested elevated containers, redundant pills, and routine entrance effects. Use bounded surfaces for actionable records, evidence, decisions, and map overlays. Use spacing and separators for ordinary document content. Do not remove meaningful information to achieve visual density.

Status wording must distinguish task lifecycle, urgency, assessment, local persistence, delivery, and connectivity. Reaching step six is not successful submission; being online is not proof of delivery; a captured photograph is not necessarily attached or uploaded. Describe only states supported by the current data.

Changes may adjust Flutter presentation, UI state, navigation continuity, formatting, recovery handling, and narrow return-value contracts needed for accurate feedback. Preserve the existing authentication, scheduling, inspection lifecycle, GPS threshold, checklist semantics/defaults, submission/outbox behavior, storage format, and server contracts. A return-type refactor must update all callers and demonstrate unchanged successful online/offline behavior. Do not invent new server statuses, database fields, migrations, role ranks, assessment choices, verification requirements, or data sources.

Keep changes small and reviewable. Reuse existing widgets, providers, resolvers, and tests where practical; establish components as relevant screens are touched. Do not perform a repository-wide rewrite, unrelated cleanup, mass formatting, or dependency upgrade. Add a dependency only if the existing stack cannot support a required behavior and document why.

Preserve the working tree. Do not stage, commit, push, merge, reset, clean, stash, switch branches, deploy, change remote configuration, clear user evidence, or mutate production records. Use local fixtures or an explicitly authorized test environment for behavioral checks. Do not expose credentials in logs or documentation. Routine code work inside this scope does not need per-loop approval; tool permissions and truly out-of-scope changes are separate constraints.

The core findings FS-001 through FS-031 are in scope when implementation is invoked. Optional P3 ideas are recorded separately and are not an instruction to expand the project.

## Reading the register

P0 means usability/product-coherence priority, not a security vulnerability rating. P1 addresses hierarchy and generic visual presentation. P2 addresses consistency, legibility, and interaction polish. Dependencies determine sequencing even when priorities differ.

Each finding has stable acceptance labels A, B, and C. Cite them as, for example, `FS-001.A` in the tracker. Evidence classifications distinguish source-supported findings, screenshot observations, and unconfirmed runtime risks. Revalidate all findings against the current working tree. Preserve original observations; record changed evidence in the tracker instead of silently weakening acceptance criteria.

### FS-001 — Accurate save and exit feedback

Priority P0. Source-supported. Anchors: `lib/modules/inspection/widgets/exit_confirm_dialog.dart` around 45–109 and `lib/modules/inspection/providers/inspection_provider.dart` around 464–587. Some false results mean failed queueing, while other methods use false for an offline outcome. An intermediate exit path also needs an awaited-save review.

A. Trace every affected exit/save callback and distinguish confirmed local persistence, queued delivery, remote acknowledgement, and unsuccessful saving. A single Boolean interpretation must not label a failed write/queue operation “Saved offline.” Introduce an explicit result contract only where needed and update all callers.

B. Await the required save before navigating or claiming success. When saving cannot be confirmed, preserve entered data and expose retry/stay; if explicit discard is available, state its consequence. Do not claim the task moved to Ongoing unless that change occurred.

C. Verify online success, offline success, local/queue failure, thrown failure, repeated taps, and normal/rework exit paths with controlled failures. Existing offline retention behavior must remain intact.

### FS-002 — Real route geometry and honest fallback

Priority P0. Source-supported. Anchor: `lib/modules/inspection/screens/site_map_screen.dart`, especially `_buildRoutePath` around 279 and polyline construction around 487. The screenshot cannot identify which route implementation produced its line.

A. Draw road guidance only from successfully obtained route geometry. Remove fabricated intermediate points. When routing is unavailable, show that state or a distinctly styled and explicitly labelled direct bearing/distance; never imply a traversable road route.

B. Preserve target/user markers, actual routing, recenter, fullscreen, and existing arrival behavior. Route distance/ETA must be tied to a valid route and must not remain stale after a target change or failed request.

C. Verify route success, missing/empty geometry, failure/offline, changed target, and near-site cases. Format distances with understandable units. Name the next action after GPS verification where that is its destination; do not promise offline basemaps.

### FS-003 — GPS proximity, direction, and uncertainty

Priority P0. Source and screenshot evidence. Anchors: `lib/modules/inspection/screens/gps_verification_screen.dart` around 52, 59, 84, 929, and 1064; `compass_preview_screen.dart`; `lib/modules/inspection/inspection_constants.dart`.

A. Derive proximity wording from distance, not heading alignment. Separate current heading, target bearing, accuracy, within-distance readiness, and an actually saved verification. “Aligned” must not be inferred from proximity alone.

B. Normalize headings consistently into the displayed degree range before deriving cardinal direction, including the standalone compass. Make threshold wording agree with the existing inclusive 30 m rule. Do not introduce a heading/accuracy gate or alter the distance policy as a UI fix.

C. Verify negative and wraparound headings, unavailable sensors/position, permission denial, and distances just below/at/above 30 m. Keep units and uncertainty readable at large text sizes; unknown accuracy must not imply high accuracy.

### FS-004 — Sync summary explains all outstanding work

Priority P0. Source and screenshot evidence. Anchor: `lib/modules/offline_sync/screens/updates_screen.dart` around 64, 230, 1183, and 1326. “All Synced” is based on the action queue while unsynced-file counts are separate.

A. Trace what the action queue and file count represent. An unconditional all-clear must not coexist with unexplained unsynced evidence. Distinguish drafts, pending uploads, failed/conflicting work, and completed delivery only when existing data supports those distinctions.

B. If a file cannot be classified reliably, present a qualified status and actionable details rather than inventing a draft/upload state. Connectivity and last-sync time must remain separate from confirmation of delivery. Do not change queue semantics to make counters agree.

C. Verify an empty queue with zero files, an empty queue with remaining files, queued actions, retry/failure/conflict, and post-sync refresh. Preserve grouping, selective sync, retry, retention, and existing audit history.

### FS-005 — Forced-overwrite consequence and confirmation

Priority P0. Source-supported. Anchor: `lib/modules/offline_sync/screens/updates_screen.dart` around 580, 728, and `_handleForceSync` around 816.

A. Before marking an action for forced overwrite, identify the inspection and explain the consequence using available conflict information. Keep cancellation and existing non-overwrite recovery options understandable.

B. Confirmation queues/marks the operation under the existing contract; it must not claim that the server was immediately overwritten. Cancellation must not mutate the queued action. Avoid double scheduling from repeated taps.

C. Verify cancel, confirm, marking failure, offline state, and subsequent retry/drain feedback. Current conflict data may expose only timestamps; do not fabricate field differences or build an unrequested conflict-resolution backend.

### FS-006 — Security summary reflects actual settings

Priority P0. Source and screenshot evidence. Anchor: `lib/modules/auth_startup/screens/security_settings_screen.dart` around 153 and 335.

A. Summarize launch authentication separately from inactivity locking. “Never” must not be presented as inactivity lock enabled because launch authentication is enabled.

B. Distinguish supported authentication hardware/method, enrollment, activation/readiness, and the selected preference. Do not call all protection disabled when only one login option is off. Explain any existing need to sign in before activation.

C. Verify launch on/off crossed with inactivity Never/timed/immediate and available/unavailable device authentication. Preserve enrollment, native authentication, lock timing, and return-to-current-route behavior.

### FS-007 — Analytics period controls actually control the view

Priority P0. Source-supported. Anchors: `lib/modules/profile_settings/screens/profile_screen.dart` around 601–719 and `lib/modules/profile_settings/models/dashboard_stats.dart` around 75–102.

A. A displayed Week/Month selection must determine the displayed period's data, totals, labels, and boundaries. If a view has no supported period, remove or scope its selector rather than leaving an inert control.

B. Retain task-derived data and document the denominator, time basis, and empty-state behavior. Do not invent a target, goal, trend, or data history that does not exist.

C. Verify with fixtures containing different records in each period, boundary dates, and no records. Ensure selection changes the actual analysis rather than only the pill styling. Cover other chart views sharing the control.

### FS-008 — Investigate assessment consistency; correct result navigation

Priority P0 investigation. Screenshot discrepancy is unconfirmed in current code. Anchor: `lib/modules/inspection/screens/review_submit_screen.dart` around 47–117, 203, and 324–382. The inspected submission, offline queue, and success screen receive the same selected value.

A. For every currently supported assessment, trace selection/provider state through submit payload, offline serialization, success wording, saved/reopened record, and rework. Investigate with an authorized test environment or fixtures, including interruption/restart. Do not assume a root cause from the screenshots.

B. If reproducible, make the smallest contract-preserving fix and verify affected online/offline paths. If not reproduced, retain the evidence and untested boundaries; do not claim the whole persistence chain is verified from static inspection. Never force “Compliant,” remove options, or change assessment policy to resolve a display mismatch.

C. Make the success button's wording agree with its destination. The audited “Back to Home” opens Tasks; label that action accurately unless an explicit navigation decision changes the destination. Preserve distinct saved-offline and acknowledged-submission outcomes.

### FS-009 — Checklist answers are not verification progress

Priority P0. Source and screenshot evidence. Anchors: `lib/modules/inspection/providers/inspection_provider.dart` around 18 and 64; `lib/modules/inspection/screens/inspection_checklist_screen.dart`; Review and completed details.

A. Describe true/false values as existing answers, not proof that the inspector verified every item. Show each question and its stored answer where reviewed. Explain checked/unchecked values in language that does not equate false with unfinished or automatically noncompliant.

B. Preserve the current questions, defaults, Boolean storage, and whole-row interaction. Do not require all values to be true, reset defaults, add N/A/unanswered states, or infer a new compliance policy without an explicit product decision.

C. Verify untouched defaults, mixed answers, all true, all false, resume, Review, and completed-record display. The same count must not be labelled “checked” in one place and “verified/completed” elsewhere without evidence for that meaning.

### FS-010 — Camera and geolocation failure recovery

Priority P0. Source-supported, with device checks required. Anchor: `lib/modules/inspection/screens/capture_photo_screen.dart` around 55–82 and 562.

A. Render explicit discovery, permission, unavailable-camera, initialization, capture, and save-failure states with suitable retry/back/settings actions. A failed future must not remain an indefinite spinner or be treated as an initialized preview.

B. Expose locating, available, unavailable/denied, and failed geotag states accurately. Preserve the current capture/metadata policy; do not fabricate coordinates or silently create a new mandatory location requirement. Stop/reinitialize resources appropriately across retry, retake, pause, and resume.

C. Verify failure branches with meaningful tests and camera/permission/lifecycle behavior on a device when available. Retain unsaved content on recoverable failures and keep action controls usable when the keyboard is visible.

### FS-011 — Photo requirements and save states are explicit

Priority P1. Source and screenshot evidence. Anchor: `capture_photo_screen.dart` around 138, 152, and 316–331, plus the evidence grid's current implementation.

A. Communicate the existing minimum one photo and maximum ten before Continue is tapped. Retain handler validation and readable feedback even if button state is improved.

B. Distinguish captured, attached/saved locally, and delivered states using actual persistence results. Retake, removal confirmation, notes, and full-image viewing must remain available. Closing with an unattached capture must make retention or discard consequences explicit.

C. Verify zero/one/ten photos, cancelled capture, repeated Save, retake, long notes, keyboard, back navigation, interruption, and resume. “Save Photo” must be reachable by the intended scroll/action layout; the screenshot alone does not prove it is permanently obstructed.

### FS-012 — Photo loading errors are recoverable and specific

Priority P2. Source and screenshot evidence. Anchors: `lib/modules/inspection/widgets/photo_viewer.dart`, `lib/modules/inspection/services/photo_source_resolver.dart`, Review, and completed details.

A. Preserve local/remote resolution and working full-image viewing. Present distinguishable loading, unavailable, and failed-loading states with context and retry where retry can help; do not use a generic image icon as the only explanation.

B. A rendering failure must not imply that evidence was deleted. Never remove an attachment or clear its file automatically merely because loading failed. Keep associated notes and identity available.

C. Verify local files, remote sources, offline cached access, temporarily unreachable sources, missing files, retry, and reopen using controlled fixtures. Check every consumer of the shared viewer/resolver.

### FS-013 — Review presents the evidence behind the decision

Priority P1. Source-supported; older “no photo preview” finding is superseded. Anchor: `lib/modules/inspection/screens/review_submit_screen.dart` around 172–203. Depends on FS-008, FS-009, and evidence handling.

A. Show existing inspection identity, site/GPS confirmation with uncertainty/time as available, photographs and notes, actual checklist answers, observations, discrepancies, recommendations, and selected assessment. Present missing values honestly; distinguish a missing record from an affirmative “none.”

B. Provide direct correction paths to existing steps with state retention and a predictable return to review. Preserve the existing photo thumbnails/viewer, assessment options, submission safeguards, and queue handling.

C. Verify that long evidence can be read, changes made through correction paths return accurately, duplicate submission is prevented, and submission feedback describes the actual online/offline result. A full positional step bar must not claim successful submission.

### FS-014 — Findings inputs support narrative work

Priority P2. Source and screenshot evidence. Anchor: `lib/modules/inspection/screens/field_findings_screen.dart` around 157–214.

A. Give observations, discrepancy title/details, and recommendations persistent labels. Allow narrative discrepancy detail to wrap and grow/scroll appropriately; hints must not be the only way to identify a filled field.

B. Present an empty optional discrepancy neutrally. Use warning treatment for an actual relevant issue, without changing validation or deciding that an issue exists. Correct singular/plural photo wording and checklist wording under FS-009.

C. Verify empty/long values, keyboard reachability, save failure, interruption/resume, Review, and rework. Preserve the content and existing optionality; do not synthesize findings from placeholder text.

### FS-015 — Completed records are readable and honest about rework

Priority P2. Source-supported. Anchor: `lib/modules/inspection/screens/completed_inspection_detail_screen.dart` around 73, 281–325, 409, and 502–513.

A. Retain identity-first evidence sections; show actual checklist answers and available evidence context. Format timestamps consistently for local reading, preserve chronological meaning/timezone, and handle missing/invalid values without inventing times.

B. Explain when edits from “Rework this step” actually persist. Do not promise that all changes wait until resubmission if step saves already persist them. Preserve targeted rework, history, and lifecycle contracts.

C. Verify expansion, long values, photograph failures/retry, each rework route, assessment display, and reopen. Apply FS-008/009/012 contracts rather than implementing competing interpretations.

### FS-016 — Apply a small shared component contract

Priority P1. Source-supported and visual judgment. Anchors: `lib/core/theme/insight_theme.dart` around 73; `lib/main.dart` around 64; shared widgets and touched screens.

A. Establish consistent action hierarchy, input labels/errors, task-summary ordering, section hierarchy, surfaces, spacing, radii, and state presentation. Reuse the current color/font foundations and shared tokens. Record the chosen reusable rules and their implementation paths in the tracker.

B. Use boundaries/elevation where they communicate a record, evidence, overlay, or decision. Reduce repeated glows, nested cards, decorative gradients, and redundant icon/pill framing. Keep important metadata and comfortable text/touch sizes.

C. Migrate components incrementally across the screens in scope. Verify their actual consumers when shared code changes. Preserve loading/disabled/error/semantic behavior and reduced-motion needs; do not mass-refactor unrelated code or add visual assets for decoration.

### FS-017 — Status, metric, date, and identifier conventions

Priority P1. Cross-screen consistency requirement derived from the audit. Anchors: theme/shared widgets; Tasks, inspection flow, Home, Sync, and Profile.

A. Keep lifecycle, urgency, assessment, save state, delivery, and connectivity independently named. Color supplements text; an interactive filter must not look identical to a read-only state without another interaction cue.

B. Metrics state their unit, denominator, and period when applicable. Format dates/distances consistently. Long references and names must remain available through wrapping, expansion, or a clear full-value route; do not shrink essential readings indefinitely to fit a decorative box.

C. Verify representative states together: overdue plus Ongoing, completed but delivery pending, offline with local work, and loading/empty/failed data. Preserve valid category mappings and unknown-state handling; do not alter persistence enums for display terminology.

### FS-018 — Compact identity and truthful step headers

Priority P1. Source and screenshot evidence. Anchor: `lib/modules/inspection/widgets/inspection_step_header.dart` around 28–88 and its consumers.

A. Ordinary form screens should establish readable inspection/site identity and current step without two oversized decorative panels. Map/camera overlays can differ where legibility and content need it; keep their behavior consistent.

B. Express “Step N of 6” as workflow position. Do not imply that arrival at step six means six saved/verified/completed steps. Preserve actual saved-step evidence and navigation semantics.

C. Verify all six steps, rework, long identity values, small screens, text scaling, back controls, and map/camera variants. Apply the shared spacing and touch rules without reducing important information.

### FS-019 — Navigation, Quick actions, and bottom clearance

Priority P1. Source and screenshot evidence; precise obstruction needs device verification. Anchors: `lib/core/widgets/insight_bottom_nav.dart` around 41 and 249; `lib/core/navigation/main_shell_screen.dart` around 368 and 428; screen-specific bottom padding.

A. Keep Home, Tasks, Sync, and Profile with stable readable labels. Make Quick actions visually identifiable as a menu/tool entry rather than scroll-to-top. Preserve its useful destinations and accessible controls.

B. Use one consistent inset/layout rule accounting for navigation, Quick actions, safe area, scrolling, and keyboard where relevant. Replace conflicting independent 140/180 padding assumptions with measured/shared behavior. Final records and actions must be reachable without overlap.

C. Reduce navigation/menu animation that adds repeated blur/scale/entrance distraction. Verify selected/unselected tabs, sheets/dialogs, portrait/landscape where supported, gesture/three-button navigation, and larger text. Preserve useful state-change feedback and avoid unmeasured performance claims.

### FS-020 — Tab continuity and meaningful attention indicators

Priority P1. Source-supported risk, requiring interaction reproduction. Anchor: `lib/core/navigation/main_shell_screen.dart` around 298–428 and the navigation indicator's current state source.

A. Preserve search, filter, selected calendar date, active category, and scroll position across normal tab changes where those states remain relevant. Restore/reuse screen state deliberately without retaining duplicate listeners, streams, or stale data.

B. Do not present “not yet visited this session” as an unread-assignment notification. Tie attention indicators to supported information or clarify/remove the unsupported cue.

C. Verify repeated tab switches, refresh/data changes, inspection completion, logout/account change, and app resume. Preserve the proper reset boundaries between users. A disposed widget does not by itself prove persisted inspection data loss.

### FS-021 — Tasks support scanning without losing domain information

Priority P1. Source and screenshot evidence. Anchor: `lib/modules/tasks/screens/tasks_screen.dart` around 46, 226, 1253, and 2006; `test/task_category_ground_truth_test.dart`.

A. Use stable hierarchy for reference, applicant, site, visit/deadline, lifecycle/urgency, progress, and next action. Reduce avatar/decorative emphasis and unnecessary spacing while preserving meaningful metadata and contextual help.

B. Preserve current Pending/Ongoing/Completed mapping, scheduling subgroups, counters, search, and unknown-state behavior. Avoid redundant status tags where the context already states the same fact. Overdue state must remain clear without relying on an entire red card.

C. Enlarge the explicitly small information-control hit area and retain distinct help/expand actions. Verify long values, all categories, overdue/due-today/scheduled/anytime cases, zero results, filters, and resumption without changing lifecycle rules.

### FS-022 — Filters explain their date and sorting behavior

Priority P2. Source-supported. Anchor: `lib/modules/tasks/screens/tasks_screen.dart` around 944 and the filter sheet. The audited date filter uses `scheduledDate`; relative presets apply a lower bound; sorting is fixed by category.

A. State which date is filtered and define inclusive boundaries, local-day handling, and behavior for missing dates. A label such as “Last 30 days” must match a past-window filter; if upcoming dates intentionally remain included, name that behavior accurately. Determine intended semantics from current contracts before adjusting UI-level predicates; do not redefine backend date fields.

B. Preserve urgency/barangay filtering, search, custom range, and reset. Reject or explain invalid/reversed ranges. Rename “Filter & Sort” if no user-controlled sorting is exposed, or expose only a justified existing sort choice; do not invent a new ordering policy.

C. Verify start/end boundaries, today, future dates, missing scheduled dates, custom dates, combined filters, cancel/apply/reset, and empty results. Counts and displayed records must refer to the same declared scope.

### FS-023 — Task overview establishes the inspection before its process

Priority P1. Source-supported. Anchor: `lib/core/navigation/parcel_detail_screen.dart` around 294 and 435.

A. Put existing reference, applicant, site, and relevant property/application identity before the full workflow timeline. Make the current/next action and resume point obvious.

B. Preserve step access, real saved timestamps, photos, application details, resume/rework routes, and assignment provenance/instructions. Replace vague process copy with accurate task-specific wording using existing data.

C. Verify new, ongoing, scheduled, and completed entries; interruption/resume; long identity values; and all step links. Avoid treating current position as proof that preceding steps are durably saved.

### FS-024 — Home assignment and date claims match the data

Priority P0. Source-supported. Anchor: `lib/modules/analytics_dashboard/screens/home_dashboard_screen.dart` around 21, 219, 895, and 917. The audited assignment selection excludes Ongoing; the “today” language does not describe its actual filter.

A. Surface unfinished inspections with a clear resume route, or explicitly label a narrower pending-only list while retaining visible access to ongoing work. Do not report “No active assignments” merely because a pending-only subset is empty.

B. Make the selected day and “today” wording agree with the records actually displayed. Keep a deliberately independent list explicitly independent from the calendar rather than implying a date filter it does not use.

C. Verify ongoing-only, pending-only, mixed, no assignments, selected non-today dates, scheduled/unscheduled, and completed cases. Preserve scheduling rules and correct record totals; this is presentation/selection alignment, not lifecycle reclassification.

### FS-025 — Home prioritizes unfinished inspections

Priority P1. Source-supported visual judgment. Anchors: `home_dashboard_screen.dart` around 906 and 1015; `lib/modules/analytics_dashboard/widgets/active_assignments_folder_card.dart` around 129. Depends on FS-024 and shared contracts.

A. Put useful current work, resumption, and time-sensitive assignments ahead of decorative summary content. Keep scheduling context, history, real counts, and useful overdue reminders accessible.

B. Replace or substantially simplify oversized folder/carousel emphasis, paper layers, grain, glow, and concentric tally presentation. Use comparable inspection summaries with stable identity/date/action order. Do not call a category tally a process flow.

C. Verify quick comparison and navigation to the right inspection with realistic long records, multiple assignments, empty states, and large text. Retest FS-024 and any shared task-summary consumers after layout changes.

### FS-026 — Sync prioritizes waiting work and exceptions

Priority P1. Source-supported. Anchor: `lib/modules/offline_sync/screens/updates_screen.dart` around 1214–1405. Depends on FS-004/005.

A. Surface waiting, failed, and conflicting work with meaningful next actions ahead of performance/storage panels. Preserve inspection grouping, selective sync, retry, audit access, and confirmed cache/history actions.

B. Translate internal event names into readable activity descriptions. Put infrastructure details such as “SQLite Active” in secondary diagnostics. Retain technical information where it helps support without making it the primary success signal.

C. Verify empty/queued/failing/conflicting states, refresh, expanded records, long labels, and navigation clearance. Summary wording and overwrite confirmation from FS-004/005 must remain correct after rearrangement.

### FS-027 — Profile prioritizes account, settings, and an actual role

Priority P1. Source and screenshot evidence. Anchor: `lib/modules/profile_settings/screens/profile_screen.dart` around 314 and its settings sections; `lib/core/models/user_profile.dart` for available role/display fields.

A. Keep identity/editing and account, security, and support access prominent; move analytics into a clearly secondary place without removing useful data or destinations.

B. Display only a role/title supported by the current profile contract. Do not assign “Zoning Officer I” to every non-admin when rank is not known. Use an accurate generic fallback if necessary; do not add backend fields or invent rank.

C. Verify long names/roles, missing values, different supported roles, edit/save/error feedback, settings routes, and text scaling. Avoid orphaned role fragments and retain full text access.

### FS-028 — Analytics answer named operational questions

Priority P2. Source-supported with layout risks requiring rendering. Anchors: `lib/modules/profile_settings/widgets/dashboard_widgets.dart` around 127 and 456–488; Profile charts and `dashboard_stats.dart`.

A. Name views by their question or metric rather than only “Bars,” “Gauge,” or “Sectors.” Show completion as the actual completed/assigned ratio, not progress toward an invented goal. Keep the period and denominator explicit.

B. Prefer comparable, readable values over decorative rings. Make heatmap geometry respond consistently to available width/height and text size; a fixed height must not clip width-derived cells. Provide readable text summaries where chart interpretation otherwise depends on color alone.

C. Verify empty/small/large datasets, long labels, changed periods, and narrow/large-text layouts. Recheck FS-007 after every analytics presentation change; do not replace real statistics with demonstration values.

### FS-029 — Startup and sign-in are direct and credible

Priority P2. Source-supported. Anchor: `lib/modules/auth_startup/screens/splash_screen.dart` around 76, 865, 960, and 1060.

A. Reduce repetitive verification/login/sign-in framing and replace demonstration account hints with neutral useful input guidance. Use consistent credential terminology and explain existing administrator-assisted recovery accurately.

B. Remove the intentional three-second branding wait only after separating it from required initialization/session/security work. Do not bypass authentication, consent, offline sign-in handling, or device authentication to make startup appear faster.

C. Verify startup success/error, existing-session routing, offline login, recovery, keyboard, submission loading, and device-auth entry. Preserve existing login/terms and account-isolation tests.

### FS-030 — Supporting screens and dialogs share the same rules

Priority P2. Source-supported component inconsistency; individual behaviors need regression checks. Anchors: `lib/modules/profile_settings/screens/` for edit profile, help/FAQ, diagnostics, legal/about; `lib/modules/auth_startup/screens/` for lock/security-related presentation; shared dialogs/sheets.

A. Apply established typography, spacing, field labels, action hierarchy, target sizes, error presentation, and keyboard-safe layout to these supporting flows. Keep the scope proportional; do not rebuild working screens.

B. Preserve English/Tagalog help/search, diagnostics validation/report history, profile editing, system information, legal text, logout semantics, and consequence-specific confirmation for deletion/cache/history actions. Do not rewrite legal policy or create extra confirmation steps for harmless actions.

C. Verify meaningful routes and errors, long translated text, search/no results, form validation, save/report failure, modal cancellation, and logout cancellation/completion using local or authorized test contexts. Shared visual changes must not hide critical actions or discard inputs.

### FS-031 — Rendered field usability and final integration

Priority P2, required across all loops rather than postponed to the end. Screenshot-supported risks and device-dependent verification. Applies to every touched screen.

A. Preserve readable body/measurement text and comfortable touch areas. Use a consistent approximately 48 logical-pixel standalone control target as this project's design target, enlarging hit regions where appropriate; it is not a claim of measured platform compliance. Use semantics/labels, focus behavior, and text plus color for important states.

B. Test a small phone and representative target phone; normal and large system text (including about 200% where supported); long names/references/locations/narratives; keyboard open; system safe areas and navigation modes; portrait/landscape where supported; bright-light readability when a device is available. Essential actions and last records must remain accessible. Check reduced-motion behavior and screen-reader order for changed custom controls.

C. Run the combined inspection journey and regression matrix in the progress document. Record actual device/build/environment and evidence. If hardware, permissions, backend fixture access, or screenshot capture is unavailable, leave the relevant acceptance condition awaiting verification; static code reading, analyzer success, and old screenshots do not close a rendered/device requirement.

## Optional P3 ideas, excluded from automatic implementation

Richer evidence indexing, additional spatial context using existing data, and secondary analytics exploration may be useful later. They are not prerequisites for this handoff and must not delay the core fixes or lead to new backend/mapping work. Revisit them only after the core findings are accounted for and the user explicitly extends the scope.

## Source preservation

The appendix below is the user's supplied consolidated report preserved as historical audit text. It includes earlier priorities, design alternatives, source links, and audit limitations. The stable requirements above operationalize that report; the tracker records subsequent discoveries without rewriting its history. The earlier diagnostic and original brief informed consolidation, but outdated claims must be interpreted using the corrections above.

<!-- ORIGINAL_CONSOLIDATED_AUDIT_START -->

Tama ang main diagnosis ng previous report: **FieldSync already has a useful inspection workflow, but the UI gives too much emphasis to decorative containers, dashboard widgets, and navigation.** The next improvement should make inspection identity, evidence, next actions, and saved/synced state more prominent.

I’ve now compared your screenshots, the previous findings, and the current source in `C:\Users\Ralph Lauren\imaps_fieldsync_main`. **The earlier report is a useful baseline, but several statements need updating before you use it as an implementation checklist.**

“AI-designed” here describes a visual impression; it does not establish who or what created the interface.

The previous findings need these corrections:

| Earlier finding or screenshot concern | Final assessment |
|---|---|
| Started scheduled tasks should remain under Pending. | **The old specification and current implementation disagree.** Current code maps `in_progress` to Ongoing regardless of scheduling, and current tests explicitly expect that. Do not restore the older behavior during a UI cleanup. |
| Review contains no actual photographs. | **Partly outdated.** Current code includes photo thumbnails and a fullscreen viewer. Actual checklist answers, findings, and recommendations are still missing from the review body. |
| The red camera button clutters every screen. | It is the app’s **debug-only screenshot-protection toggle**, excluded outside debug mode. Exclude it from production UI criticism. |
| The floating upward arrow returns to the top. | It actually opens **Quick actions**. Its appearance suggests another behavior, which is itself a discoverability problem. |
| The active Continue button allows proceeding with zero photographs. | The current handler requires at least one photograph. The requirement is communicated too late, but the screenshot does **not** establish a validation bypass. |
| With Discrepancy changes to Compliant during submission. | The screenshots warrant investigation, but this is **not confirmed by the current UI code**. The same selected value is passed to submission, offline queuing, and the success screen. A selection change between screenshots or a different build remains possible. |
| The missing photo thumbnail proves evidence was lost. | It proves the photo was not displayed in that capture. Current code has local/remote photo resolution, but its error presentation still gives almost no explanation or recovery. |

These corrections are supported by the [current lifecycle mapping](<C:/Users/Ralph Lauren/imaps_fieldsync_main/lib/modules/tasks/screens/tasks_screen.dart:46>), [lifecycle tests](<C:/Users/Ralph Lauren/imaps_fieldsync_main/test/task_category_ground_truth_test.dart:87>), [review implementation](<C:/Users/Ralph Lauren/imaps_fieldsync_main/lib/modules/inspection/screens/review_submit_screen.dart:50>), [debug control](<C:/Users/Ralph Lauren/imaps_fieldsync_main/lib/modules/auth_startup/widgets/debug_screenshot_toggle.dart:43>), and [photo validation](<C:/Users/Ralph Lauren/imaps_fieldsync_main/lib/modules/inspection/screens/capture_photo_screen.dart:152>).

**The strongest visual problem is hierarchy.** The blue palette and typography already provide continuity. What makes the application feel assembled from templates is how frequently unrelated information receives the same elaborate treatment.

1. **Too many elements compete for attention.** In Tasks, the monitoring pill, assigned-count block, search field, tabs, applicant avatar, reference chip, information button, status tags, progress bar, bottom navigation, and floating tool button all demand attention. Most have a legitimate purpose, but their combined emphasis weakens the distinction between the task and its controls. Preserve the information while making identity and the next action dominant.

2. **Rounded, elevated surfaces have become the default layout mechanism.** Inspection titles, progress indicators, checklist groups, findings fields, metrics, and settings all receive separate containers. The screenshots show repeated “white rounded box on pale background” compositions. Use surfaces where they establish a record, decision, or map overlay; use spacing and separators for ordinary document content.

3. **The navigation occupies disproportionate space.** The floating rail plus separate Quick actions button covers content in the supplied scroll positions. Only the selected destination has a visible label, while the upward arrow does not explain its function. Keep the four destinations, but make labels stable and auxiliary tools identifiable. The source explicitly reserves 180 logical pixels for this composition, while Tasks and Profile use separate 140-pixel bottom padding. This requires a consistent layout rule and device verification—not indiscriminate shrinking. [Navigation source](<C:/Users/Ralph Lauren/imaps_fieldsync_main/lib/core/widgets/insight_bottom_nav.dart:41>)

4. **Decorative dashboard styling weakens product specificity.** The Home assignment component contains simulated paper sheets, grain, multiple gradients, and glow. These treatments do little to help compare inspection references, sites, dates, or next actions. A restrained assignment record would communicate the domain more effectively. [Assignment component](<C:/Users/Ralph Lauren/imaps_fieldsync_main/lib/modules/analytics_dashboard/widgets/active_assignments_folder_card.dart:129>)

5. **Analytics emphasize chart formats over useful questions.** “Bars,” “Activity,” “Gauge,” and “Sectors” ask users to choose a visualization. Inspectors are more likely to need “Submitted this week,” “Outstanding inspections,” or “Inspections by application type.” The statistics are derived from task data; they should not be described as fabricated. Their presentation makes them feel generic. [Statistics model](<C:/Users/Ralph Lauren/imaps_fieldsync_main/lib/modules/profile_settings/models/dashboard_stats.dart:75>)

6. **Routine motion adds presentation without much operational value.** The shell uses animated page replacement, and Quick actions scales and blurs the underlying screen. Preserve feedback that explains a save, capture, expansion, or sync change. Repeated entrance choreography deserves less prominence in a tool used many times each day. Performance problems remain unproven without profiling. [Shell implementation](<C:/Users/Ralph Lauren/imaps_fieldsync_main/lib/core/navigation/main_shell_screen.dart:368>)

Several issues deserve attention before visual polishing because they affect what users believe the app has done:

| Finding | Screenshot and current-code evidence | Required improvement |
|---|---|---|
| **Save failure can receive success wording.** | The exit handler displays “Saved offline” when a save returns false. Relevant provider methods also return false when outbox queuing fails. This does not prove all local data is lost, but the assurance is unsupported. | Distinguish confirmed local save, queued delivery, and unsuccessful save. Keep a recovery path when success cannot be confirmed. |
| **A fabricated route can resemble road guidance.** | When real route points are unavailable, Site Map generates intermediate coordinates and draws the same styled polyline. The provided route screenshot alone cannot identify which path was used. | Show actual route geometry only when available; otherwise explain route unavailability or clearly identify a direct bearing. |
| **GPS proximity is described as directional alignment.** | The screenshot shows −135°, target 102°, and an alignment message. Code chooses that message from the distance threshold, without comparing heading and target bearing. | Say “Within verification distance” for proximity. Keep heading, target bearing, and location accuracy distinct. |
| **Checklist answers are described as verification progress.** | Three values default to true. Review counts true values and labels them “verified.” The questions also mix compliance, presence, and whether something was noted. | Describe existing answer values accurately. Do not treat unchecked as automatically unfinished or noncompliant. Any change to answer semantics needs a separate product decision. |
| **“All Synced” has a narrower meaning than users can see.** | In your screenshot it appears beside one unsynced file. The label depends on an empty action queue; the file count is tracked separately. | Explain whether remaining files belong to drafts, pending uploads, or another state. Avoid an unconditional all-clear while unexplained unsynced work remains. |
| **Camera initialization lacks actionable recovery.** | Discovery failures are logged; the preview builder does not handle initialization errors explicitly. | Provide a visible unavailable/error state with an appropriate retry or permission-recovery action. |
| **Security summary describes the wrong setting.** | “Auto-Lock On” is derived from Require When Opening App, rather than the inactivity duration. This explains the screenshot showing Never simultaneously. | Summarize launch authentication and inactivity locking separately. |
| **Week/Month is visually interactive but does not govern the dataset.** | `_analyticsIsWeek` changes the pill selection; chart construction still chooses fixed weekly/monthly datasets by chart type. | Make the selected period control the displayed analysis, or remove the unsupported choice. |

Source checks: [exit feedback](<C:/Users/Ralph Lauren/imaps_fieldsync_main/lib/modules/inspection/widgets/exit_confirm_dialog.dart:45>), [save results](<C:/Users/Ralph Lauren/imaps_fieldsync_main/lib/modules/inspection/providers/inspection_provider.dart:464>), [route fallback](<C:/Users/Ralph Lauren/imaps_fieldsync_main/lib/modules/inspection/screens/site_map_screen.dart:279>), [GPS readiness](<C:/Users/Ralph Lauren/imaps_fieldsync_main/lib/modules/inspection/screens/gps_verification_screen.dart:52>), [checklist defaults](<C:/Users/Ralph Lauren/imaps_fieldsync_main/lib/modules/inspection/providers/inspection_provider.dart:18>), [sync summary](<C:/Users/Ralph Lauren/imaps_fieldsync_main/lib/modules/offline_sync/screens/updates_screen.dart:1183>), [camera preview](<C:/Users/Ralph Lauren/imaps_fieldsync_main/lib/modules/inspection/screens/capture_photo_screen.dart:562>), [security summary](<C:/Users/Ralph Lauren/imaps_fieldsync_main/lib/modules/auth_startup/screens/security_settings_screen.dart:335>), and [analytics controls](<C:/Users/Ralph Lauren/imaps_fieldsync_main/lib/modules/profile_settings/screens/profile_screen.dart:601>).

GPS also displays raw negative headings and derives the cardinal label before normalizing them. That can produce an inconsistent direction label, as your −135°/WSW capture illustrates. Normalize the presentation consistently without changing the existing distance-based verification policy. The current threshold accepts 30 m inclusively, while the UI says “< 30 m”; that wording should agree with the rule.

For future screen work, this is the practical audit:

| Screen or flow | What should remain | What needs attention |
|---|---|---|
| **Startup / Login** | Direct sign-in, inline errors, offline guidance, device authentication. | Repeated verification/sign-in framing, demonstration email placeholder, and the deliberate three-second startup delay. Make admin-assisted passcode recovery explicit. |
| **Home / Dashboard** | Scheduling context, assignment access, real counts and activity. | Put unfinished work and the next inspection ahead of decorative summaries. Current “Active Assignments” excludes Ongoing work, and “today” wording does not describe its actual filtering. |
| **My Tasks** | Search, category counts, date labels, expandable records, contextual explanations. | In the screenshots, large cards and header controls leave limited comparison space. Reduce decorative spacing and avatar emphasis while preserving readable metadata and comfortable actions. |
| **Task details / overview** | Step access, progress, resume behavior, photos and application information. | Application identity appears after the workflow timeline and other content. Establish reference, applicant, and site before asking the inspector to enter a step. |
| **Filter sheet** | Barangay selection, reset, urgency and date filtering. | “Date range” does not identify the date being filtered. Current code uses `scheduledDate`; “last 30 days” only applies a lower bound. “Filter & Sort” also lacks a user-selectable sorting control. |
| **Site Map** | Target/user markers, real routing, recenter and fullscreen. | Reduce overlay competition with the map. Format long distances naturally and name the next action after GPS verification. Resolve misleading fallback geometry first. |
| **GPS Verification** | Distance, accuracy, coordinates, target bearing and verification action. | Give readiness and uncertainty priority over repeated heading/status displays. Correct alignment wording, direction formatting, and threshold wording. |
| **Photographic Evidence** | Capture, retake, notes, thumbnails, fullscreen inspection and removal confirmation. | State the minimum requirement before Continue is tapped. Distinguish a captured image from one attached to the inspection and from one uploaded. |
| **Camera / photo notes** | Large shutter and evidence-focused preview. | The screenshot shows Save Photo partly below the viewport. Current code is scrollable, so permanent inaccessibility is unproven. Test keyboard use and action reachability; add initialization recovery. |
| **Zoning Checklist** | Large tappable rows and relevant grouping. | Clarify what checked and unchecked mean. The counter cannot establish verification when some answers are preselected. Avoid requiring every box to be checked merely to reach 100%. |
| **Field Findings** | Observations, discrepancy details and recommendations. | Improve persistent field labels and narrative input. Discrepancy detail currently uses a single-line field. Avoid warning styling that suggests an issue exists before one is entered. |
| **Review / Submit** | Existing assessment choices and submission handling. | Add the existing checklist answers, findings, recommendations and GPS confirmation to the review. Current photo previews are progress, but counts alone still provide an incomplete review. |
| **Submission result** | Clear reference and recorded outcome; separate offline result exists in code. | “Back to Home” normally opens the Tasks tab. Correct the label or destination. Reproduce the screenshot’s assessment discrepancy before declaring a persistence defect. |
| **Completed inspection** | Identity-first ordering, evidence sections and targeted rework. | Show actual checklist answers, readable local timestamps, and an explanation when a photo cannot load. Clarify when rework changes are saved. |
| **Sync Center** | Grouping by inspection, selective sync, retry and audit history. | Put waiting, failed and conflicting work before performance/storage panels. Translate internal event names into user language. Move “SQLite Active” into technical details. |
| **Profile / Edit Profile** | Account information, editing, grouped settings and support access. | Settings are buried below analytics. The role wraps awkwardly in the screenshot and is hardcoded for non-admin users. Display a verified role, with a layout that accommodates its full text. |
| **Security** | Native switches, device test and lock choices. | Summary and explanatory text must describe the actual selected settings and available authentication method. |
| **Help / Diagnostics / Legal / About** | Bilingual help, searchable topics, issue reporting and system information. | Apply shared typography and spacing without rebuilding them. Keep technical explanations contextual; these are lower-priority visual screens. |
| **Shell / sheets / dialogs** | Four primary destinations and consequence-specific confirmations. | Clarify Quick actions, preserve tab continuity, and standardize bottom clearance. Forced overwrite currently marks a queued action without a confirmation; its consequence needs explicit presentation. |

Additional source anchors: [Home selection](<C:/Users/Ralph Lauren/imaps_fieldsync_main/lib/modules/analytics_dashboard/screens/home_dashboard_screen.dart:21>), [task overview ordering](<C:/Users/Ralph Lauren/imaps_fieldsync_main/lib/core/navigation/parcel_detail_screen.dart:294>), [date filtering](<C:/Users/Ralph Lauren/imaps_fieldsync_main/lib/modules/tasks/screens/tasks_screen.dart:944>), [findings inputs](<C:/Users/Ralph Lauren/imaps_fieldsync_main/lib/modules/inspection/screens/field_findings_screen.dart:183>), [completed-record presentation](<C:/Users/Ralph Lauren/imaps_fieldsync_main/lib/modules/inspection/screens/completed_inspection_detail_screen.dart:281>), and [conflict action](<C:/Users/Ralph Lauren/imaps_fieldsync_main/lib/modules/offline_sync/screens/updates_screen.dart:816>).

At the design-system level, **you have shared tokens, but not yet a consistently applied component system**.

The theme defines Urbanist and Inter, semantic colors, typography helpers, three radius tokens, and shared shadows. Legacy method names such as `poppins` and `jetBrains` are aliases; they do not establish additional active font families. The helpers also enforce a minimum requested size of 12, so a call containing `9.5` does not necessarily render at that size. [Theme implementation](<C:/Users/Ralph Lauren/imaps_fieldsync_main/lib/core/theme/insight_theme.dart:73>)

However, screens still supply their own radii, shadows, button treatments, backgrounds and container structures. The application theme configures Material colors and app bars, but does not establish comprehensive defaults for the main component families. Neither requested `UI_DESIGN_ARCHITECTURE.md` nor `UI_ENHANCEMENT_GLOBAL_PROMPT.md` was found. The task specification also contains behavior that no longer matches current code.

Your future component rules should address the following:

| Component family | Needed rule |
|---|---|
| **Task summaries** | Stable ordering of reference, applicant, site, dates, state and next action across Home, Tasks and details. |
| **Buttons** | Consistent primary/secondary hierarchy, loading, disabled state, touch area and action wording. |
| **Inspection headers** | Compact identity and current step; avoid two large separate surfaces on ordinary forms. |
| **Status indicators** | Separate task lifecycle, urgency, inspection outcome and delivery state. |
| **Cards and surfaces** | Define which content needs a boundary, elevation or tint. Ordinary labels should not require cards. |
| **Inputs** | Persistent labels, appropriate multiline behavior, clear errors and keyboard-safe actions. |
| **Metrics** | Stable units, time period and denominator; avoid shrinking important readings to fit decorative layouts. |
| **Navigation and overlays** | Consistent safe-area clearance, meaningful labels and predictable retained screen state. |
| **Empty/error states** | Distinguish no records, no filter matches, unavailable data and failed loading. |
| **Dates and identifiers** | Shared formatting and a way to read full values when space is constrained. |

For outdoor use, keep the large primary actions, dark text and whole-row checklist interactions. Reduce ornamental space before reducing text or touch targets. The task information control is explicitly a 20 × 20 logical-pixel container, making it a concrete precision-target concern. [Task control](<C:/Users/Ralph Lauren/imaps_fieldsync_main/lib/modules/tasks/screens/tasks_screen.dart:2006>)

The screenshots also establish awkward role wrapping and metadata truncation. They do not establish measured contrast compliance, glove usability, or permanent footer obstruction. Those require testing on the actual device with larger text, long names, the keyboard open, and different navigation modes. Similarly, cached jobs and working GPS do not establish offline basemap availability.

FieldSync’s identity should come from **the relationship between the property, inspection, evidence and recorded decision**. Without the name, Tasks and Profile could easily resemble a general task application. GPS, geotagged photographs and inspection records communicate specialization much more clearly.

That leads to this keep/change assessment:

| Treatment | Recommendation |
|---|---|
| **Keep** | Six-step workflow, current lifecycle behavior, spatial measurements, evidence capture, offline support, targeted rework and bilingual help. |
| **Refine** | Task hierarchy, inspection identity, status wording, long-value handling, evidence review and recovery messages. |
| **Rethink** | Home’s folder carousel/rings, Profile’s dashboard-first ordering, floating navigation composition and Sync’s statistics-first ordering. |
| **Reduce** | Background glow, simulated paper, repeated elevated containers, redundant badges and routine entrance animations. |
| **Correct or remove** | Misleading route geometry, unsupported success wording, inert controls and labels that promise behavior the code does not provide. |

Three future directions fit the product without requiring a complete redesign:

| Direction | How it would work |
|---|---|
| **Evidence-first field notebook** | Lead with inspection identity, recorded evidence, assessment and delivery state. Use moderate density, readable body typography, restrained headings, blue actions and clearly named statuses. Prefer continuous document flow, with surfaces for evidence and decisions. Preserve the tabs, six steps and targeted rework; use maps where they establish site context. Motion explains saves, captures and changes. Existing completed-detail sections, forms and photo viewers are reusable; Review and the shared header need the most attention. |
| **Field instrument** | Lead with the measurement or action needed on-site. Use strong numeric hierarchy, explicit units and uncertainty, opaque map panels and large reachable actions. Keep navigation stable and sensor motion meaningful. Reuse GPS, map and camera capabilities; significantly simplify repeated readouts and overlays. This is particularly suitable for verification and capture, but less suitable as the organizing model for narrative findings. |
| **Municipal operations workspace** | Lead with current assignments, deadlines, unfinished work and delivery exceptions. Use aligned record metadata, compact lists, clear status language and minimal elevation. Preserve the four tabs and existing scheduling rules, with map access tied to assignments. Reuse task filtering, calendars and grouped sync records; change Home, Sync and analytics placement most substantially. |

**I recommend the evidence-first field notebook as the overall direction**, using field-instrument presentation inside GPS/map/camera and operational lists inside Home/Tasks/Sync. This gives the app a recognizable purpose while retaining its strongest existing structures.

Using your requested priority definitions:

| Priority | Work to prioritize |
|---|---|
| **P0 — usability / product coherence** | Save-result accuracy; route fallback; GPS readiness wording; camera recovery; checklist verification claims; sync/security contradictions; functional period controls; clear overwrite consequences. |
| **P1 — generic visual appearance** | Evidence review, identity-first screen ordering, Home’s decorative assignment treatment, repeated containers and navigation footprint. |
| **P2 — consistency / polish** | Wrapping, small controls, timestamp formatting, filter/date wording, action labels, shared spacing/radii and photo-error explanations. |
| **P3 — optional refinement** | Additional spatial context, richer evidence indexing and secondary analytics improvements after the core flows are clear. |

The five highest-impact changes are:

1. **Make every status statement match the state it actually represents.** Separate saved locally, waiting to sync, delivered, failed and conflict states. Correct GPS and security summaries without changing their underlying policies.

2. **Make Review support a real decision.** Present the evidence already collected, with direct correction paths, before the final assessment. Preserve the existing assessment choices and submission workflow.

3. **Reduce the shared navigation and header footprint.** This benefits nearly every screen. Keep comfortable controls, make Quick actions understandable, and establish one bottom-clearance rule.

4. **Use a consistent inspection identity hierarchy.** Let users recognize the same reference, applicant and site across Home, Tasks, workflow steps and completed records. Improve comparison and resumption using existing data.

5. **Apply a small, explicit component contract.** Start with task summaries, inspection headers, primary actions, status indicators and error states. Refine these as their screens are touched; avoid a repository-wide cosmetic rewrite.

For focused design work, start with **Review/Submit**, then **the shared shell and inspection header**, **Tasks and task overview**, **Sync**, and **Home**. Correct P0 issues in GPS, map, camera and security wherever they occur rather than waiting for their visual turn. Supporting screens can follow once the shared rules are established.

Before accepting future changes, verify that the selected assessment survives submission and reopening; captured evidence remains viewable after interruption; save failures never report success; queue/file states explain outstanding work; long values remain readable; and bottom actions remain reachable with larger text and the keyboard open.

This report combines screenshot observations with the current working-tree source and the older findings. The screenshots are not guaranteed to represent that exact source revision, and the repository already contains substantial uncommitted changes. I did not run the app, builds, tests, accessibility measurements or backend verification. **No files, code, assets or Git state were changed.**
<!-- ORIGINAL_CONSOLIDATED_AUDIT_END -->
