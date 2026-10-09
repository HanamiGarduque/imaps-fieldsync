# FieldSync composition and sizing audit

Date: 2026-10-09. Branch: `feature/site-verification-approved-ui`.

## Brief and evidence

The user approved the compact Site Verification composition and requested an application-wide audit followed by manageable refinement groups, with visual review and preserved functionality between groups. Premium UI means appropriately sized, purposeful composition. It does not mean uniformly smaller text, controls, cards, or padding.

The Calendar has an additional explicit sample-first requirement: its full-month card should become more proportionate, and a believable ID-lanyard attachment should participate in a subtle reversible hanging reveal. Preserve the existing Calendar button location, compact preview, swipeable Time and Date, selected-view preference, selection, task indicators and actual data.

Evidence used:

- Actual production Flutter Site Verification renders and measured widget geometry at 360/390dp, landscape, 320dp/2× text, disclosure and offline states.
- The user's `Screenshot 2026-10-09 205845.png` for the current expanded Calendar.
- Source inventory of all 28 files under `lib/**/screens/` and targeted inspection of the active compositions, theme, shared form widgets, map panel and navigation patterns. `inspection_progress.dart` is state, not a screen; the two legacy zoning/result screens are not called by the active wizard.
- Source candidates elsewhere are **improvement opportunities**, not claims of measured handset defects. Each group's first render must confirm the actual composition before implementation.

Reusable evidence: `C:/Users/Ralph Lauren/AppData/Local/Temp/opencode/fieldsync-composition-refinement-20261009/`. Open its `index.html` through the local gallery at `http://127.0.0.1:8875/`.

## Recurring causes

1. **The layout responds to a device category instead of actual content.** A normal-width phone can display two short related metrics clearly; unconditional portrait stacking spends height without improving readability.
2. **Supporting text repeats the same meaning.** A title, value, caption, divider, note and action can create six vertical groups for two facts. Remove redundancy before reducing type sizes.
3. **Nested surfaces multiply insets and visual weight.** A small supporting task summary does not automatically need its own card, border, generous padding and shadow inside another card.
4. **A height suitable for rich content is also used for an empty/loading state.** Preserve room needed by a populated carousel or chart, but do not inherit that footprint for a short status message.
5. **Hero treatment is reused for utility information.** A 24–32dp radius and broad shadow may be intentional for an established hero; they over-emphasize a compact map readout or simple metadata group.
6. **A responsive split reserves space beyond the actual card.** A content-sized landscape map panel should not erase an entire full-height strip of useful map underneath it.

## Findings and review groups

### Group 1 — Site Verification: implemented; visual review ready

**PASS — measured correction.** `lib/modules/inspection/widgets/site_verification_view.dart:351` pairs site distance and road estimate at normal phone widths and stacks only when the scaled content needs the space. Site distance is the prominent value; road estimate is secondary. Duplicate captions and the unnecessary divider were removed. One GPS note remains near the action.

- Normal online panel: **201dp high** at both 360×800 and 390×844. The prior 360dp panel was 330.9dp: **129.9dp / 39.3% less panel height**. This comparison is for the normal route state, not every error or enlarged-text state.
- Saved/offline route: **243dp**, retaining the cache provenance and offline limitations.
- Landscape: **201dp** content-sized right panel, with the map visible beneath it and fit geometry reserved in the clear working area.
- Disclosure: **50dp**, preserving its 48dp target. Map controls retain 48dp targets around 40dp visual plates; the primary action retains its 52dp minimum.
- Enlarged text grows and scrolls inside bounded surfaces; type scaling is not suppressed. At 320×568/2×, both the established context header and details body need scrolling.

The data owner, map controller, services, geometry, GPS threshold, route refresh/cache, normal progression and rework callbacks remain in the existing screen. The initial-fit/control-overlap Important findings were fixed with regression proof. Near-coincident marker-label collision remains a recorded Minor; the pre-existing late-cache/fresh-route race remains a separate functional finding.

### Group 2 — Home Calendar/lanyard: approval sample ready

**PRE-EXISTING ISSUE — user screenshot and source.** The full-month card in `lib/modules/analytics_dashboard/screens/home_dashboard_screen.dart:2052` combines 12dp padding above and below, an extra header/grid gap, 4dp gaps between week rows and a selected circle that visually fills its 48dp cell. The 48dp date target itself is purposeful.

**PRE-EXISTING ISSUE — attachment/motion.** The existing `AnimatedSwitcher` around lines 762–794 moves the calendar card while `_CalendarTetherPainter` at line 1989 remains a separate decorative element. The lines do not show a card slot/clip or a shared suspended pivot.

The appearance sample proposes:

- A compact month/selected-date header; readable date values; 32px selected visual plates inside **48px date targets**.
- Only the 4, 5 or 6 week rows required by the displayed month, with no added row gaps. Selected task information appears below when there is actual content, without another heavy nested card.
- A short FieldSync-blue strap meeting a visible clip and card slot. Strap and card share one top pivot, settle once over 420ms and follow the same motion in reverse on close. No persistent sway or new drag interaction.
- Reduced motion opens/closes immediately. A narrow grid scrolls instead of shrinking dates or touch targets.

The HTML sample's five-week card measures **328px**. This is a browser-prototype measurement, **not a Flutter or handset claim**. The sample uses explicit demonstration dates/task content. Production Calendar changes await approval of the appearance and interaction; its real data and preference state remain in the existing Home owner.

### Group 3 — Home assignments + Tasks: next density review

**IMPROVEMENT OPPORTUNITY — state-dependent sizing.** Home's `SizedBox` at `home_dashboard_screen.dart:835` reserves a scaled 244dp even for the loading/empty message. A populated assignment carousel legitimately needs a bounded height; the empty state need not occupy the same space. Confirm the established populated folder-card presentation before changing it.

**IMPROVEMENT OPPORTUNITY — repeated metadata groups.** Task cards at `lib/modules/tasks/screens/tasks_screen.dart:2032` are already content-sized and expand on demand. In their collapsed header around lines 2216–2384, labeled dates, related reference/type/location metadata, urgency and progress use separate vertical groups. Prefer a deliberate date/reference grouping and one metadata rhythm when values fit, rather than reducing the entire 14dp card inset. The expanded body at lines 2403–2488 contains contact, application, inspection-round and scheduling actions; preserve that purposeful progressive disclosure.

Keep applicant identity, lifecycle priority, overdue information, schedule/reschedule controls, progress and existing card disclosure obvious. Verify long applicant/location text and the Pending, Ongoing, Completed and rework states before selecting any tighter arrangement. The scheduling picker's working area is not empty padding to remove.

### Group 4 — Profile overview + analytics: value grouping

**IMPROVEMENT OPPORTUNITY — vertical icon/value/label stacks.** `lib/modules/profile_settings/screens/profile_screen.dart:447` displays **two statistics in one equal-height row**. `_buildStatCard` at line 996 is already content-sized, with a 12dp inset and left-aligned 40dp icon, count and label. Confirm whether an icon/value row can improve proportion at the actual card width without crowding its two-line labels. First verify realistic number lengths and enlarged text; a more compact card is an opportunity, not an already measured defect.

**PASS — patterns worth keeping.** `ProfileIdentityCard` at line 1124 already responds to width/text scaling and has an intentional scroll-triggered compact form. The analytics branch at line 804 leaves the **Activity calendar** content-sized and gives the other chart tabs a 250dp drawing area, because those charts use bounded expanded layouts. Chart/calendar working space and compact identity behavior have functional reasons; do not flatten them indiscriminately.

Review the 24dp analytics-card radius and repeated section insets in context. Keep analytics period/view selection, account identity, edit affordance and role/status content intact.

### Group 5 — Login + Profile Edit: form rhythm

**IMPROVEMENT OPPORTUNITY — stacked supporting blocks.** Login in `lib/modules/auth_startup/screens/splash_screen.dart:854` combines a 64dp brand mark, an Email/Passcode card with online/offline status, an optional offline note, form errors, a primary sign-in action, an eligibility-gated biometric action and legal notice. It has **no authentication tab strip**. Evaluate close label/input grouping and a clearly dominant sign-in action using actual keyboard/error/offline states, while keeping status/supporting content subordinate but readable.

**PASS — existing reusable controls.** Login already uses `compactFormInput` and `FieldPrimaryButton`; Profile Edit at `lib/modules/profile_settings/screens/profile_edit_screen.dart:299` uses `FieldFormBody`. The 48dp input floor and 52dp primary actions are intentional. A profile avatar/photo-edit area also has a real visual and interaction purpose.

Apply approved visual judgment only. Keep auth, biometrics, legal navigation, validation, password visibility, profile-save/cancel behavior and screen protection. Earlier deferred legal-link corrections are not silently included in this group.

### Group 6 — Inspection forms: checklist + findings, then evidence + review

**IMPROVEMENT OPPORTUNITY — repeated checklist rows.** `_ChecklistItem` at `lib/modules/inspection/screens/inspection_checklist_screen.dart:335` uses 16dp above and below a minimum 24dp control. Single-line rows therefore start at 56dp before any wrapping. Evaluate 48dp minimum, content-growing rows and clear statement grouping; preserve the real statement text, whole-row tap target, checked semantics and Provider ownership protections.

**PASS — keep meaningful working space.** `FieldFormBody` in `lib/core/widgets/field_form_widgets.dart:147` already splits and scrolls forms while keeping actions reachable. Field Findings uses existing section headings/inputs and actual narrative entry; Photo Capture uses real evidence thumbnails and notes. Multiline writing area and recognizable evidence are functional space, not excessive ornament.

Review image/caption/note grouping and submission summary metadata in a second small slice. The success card at `review_submit_screen.dart:654` has purposeful completion emphasis, but its 24dp padding and repeated 24dp gaps can be reconsidered independently. Preserve draft restoration, photo persistence, rework, checklist/findings integrity and offline submission semantics. Visual proof uses local fixtures; no live inspection submission is needed.

### Subsequent focused groups — spatial utilities, sync and support

- **Quick Action Map:** `site_map_preview_screen.dart:237` uses a 24dp-radius readout with 18/16dp insets and 14dp/divider/14dp separation around four values. The latitude/longitude and accuracy/heading pairings are useful; simplify the readout's visual emphasis before shrinking numeric text. `MapDetailPanel` at `lib/core/widgets/quick_actions_sheet.dart:115` stretches its right pane in wide layouts; confirm actual rendered whitespace at the calling screen before changing the shared component. Review this as its own bounded group.
- **GPS/Compass:** the dial is the primary spatial instrument. `gps_verification_screen.dart:353` already sizes it from its actual slot, and the verification details scroll independently. Keep useful dial size; examine only supporting readouts/errors after native renders. Do not change the ≤30m confirmation rule or sensor behavior.
- **Updates/Notifications:** Updates' `updates_screen.dart:1007` constrains its header to a *maximum* height and already uses compact state/filter groups. A maximum is not proof of wasted space. Review crowded/error states and relation between status, progress and queued items. Keep sync visibility, retries and delivery truth.
- **Reports/Support:** Application Support at `application_support_screen.dart:194` displays all eligible task choices before the form, followed by all category choices at line 227. Large real lists can dominate the form; first render realistic list lengths and consider layout/disclosure of existing choices, without adding a new search or changing report eligibility. Technical Issue and report-history cards are already content-growing; retained narrative space, review content and retry controls are useful.
- **Help/About/Terms/Security:** inspect text hierarchy and repeated card framing as a separate low-priority group. Keep readable document measure, discoverable disclosures, settings labels and security affordances. Do not impose a small fixed card height on documents.

## Group-level acceptance

For each bounded group: confirm the current composition with native Flutter renders; explain where space has a purpose; refine only the confirmed presentation problem; show the normal/long-content/empty or recovery state and enlarged-text/landscape behavior; run relevant existing behavior checks. Obtain visual review before proceeding to the next group. Reuse the existing palette, fonts, radii, inputs, actions and disclosure rather than inventing a new component system.

## Current verification

- Focused map/layout/navigation/geometry/cache checks: **147 passed**, eleven suites, including all fourteen layout cases and an AOSP nonlinear-scaling regression.
- Analyzer: **no issues**, exit 0.
- Broad regression: **1,268 passed / 15 failed / 0 skipped**, 80 selected suites; zero new failures and zero missing canonical-baseline failures. The suite correctly exits 1. The two user-specified excluded suites remain excluded.
- Android arm64 debug APK built and installed with `adb install -r`: **Success**. SHA-256: `DDD153EF015C1DE7CC7A0503C9D022D91ADF59174C5F2A002B02C5906982E10C`.
- Physical handset acceptance on RMX3085 completed: portrait, genuine landscape, disclosure collapse, fullscreen, and rotation restoring the disclosure state. No inspection was submitted; screenshot protection was restored (`SECURE`).
- Calendar appearance sample: real isolated Chrome verifies 320/360/390px, 48px date targets, 4/5/6 week rows, date/task selection, attached geometry across 30 captured motion frames, reverse close, reduced motion and a clean console. These are prototype checks, not production Calendar verification.
- Final visual acceptance remains the user's decision.

Baseline failure names are preserved in `composition-failures.txt` and `composition-summary.json` under the evidence directory. They comprise assignment-provenance cache (3), navigation badge/offline-banner (9) and SQLite v15 partial-upgrade (3) checks; none was weakened, skipped or repaired as part of this presentation work.
