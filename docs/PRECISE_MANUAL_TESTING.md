# iMaps FieldSync: Precise Manual Testing (Tasks)

Detailed QA record for the My Tasks section. Each test lists the objective, steps, expected result, actual result, verdict, and verification notes. Fixed issues keep their history and are marked as fixed and retested.

# iMaps FieldSync: Precise Manual Testing (Tasks)

Detailed QA record for the My Tasks section. Each test lists the objective, steps, expected result, actual result, verdict, and verification notes. Fixed issues keep their history and are marked as fixed and retested.
Sections covered in this documentation set:



## Security Considerations

- All testing phases should also check the current security posture, especially concerning data exposure and access control. 
- Prioritize testing for RLS access restrictions and authenticated user capabilities.

Sections covered in this documentation set:
1. Login


Legend: PASS, FAIL, PARTIAL, NEEDS VERIFICATION.

## QUICK MANUAL TEST CHECKLIST

Use this as the short execution list for the verified Route Map / Site Verification flow.
---
2. Home
- [ ] Open assigned task and enter Site Verification
- [ ] Confirm the red target site marker is visible
- [ ] Confirm the blue "You are here" marker is visible
- [ ] Verify the device marker updates while moving
- [ ] Confirm the authoritative distance to parcel boundary updates during movement
- [ ] With internet ON, confirm the road-route line appears after map usability
- [ ] Confirm route distance / ETA is shown separately from the authoritative distance
- [ ] With internet OFF, confirm the app shows fallback schematic guidance instead of a live road route
- [ ] Confirm no crash or freeze when routing is unreachable / bounded timeout occurs
- [ ] Confirm the app keeps the direct verification distance as the real decision metric
- [ ] Move meaningfully and confirm a controlled route refresh can occur
- [ ] Confirm route requests are not made on every GPS event and respect the cooldown
- [ ] Confirm a failed route refresh keeps the previous successful route
- [ ] Tap Confirm Site Location manually when the user is within the verification pass range
- [ ] Validate the GPS verification screen shows live coordinates, accuracy, distance, and bearing
- [ ] Confirm the location stream is cleaned up correctly on screen exit

---
## ROUTE MAP / SITE VERIFICATION VERIFIED SCOPE

This cycle verifies the following checkpointed work in the canonical worktree:

* Phase A: **374654a — feat(inspection): harden site verification route preview**
* Phase B: **9575103 — feat(inspection): add live GPS tracking to site verification**
* Phase C: Site Verification arrival detection at the shared 30-meter threshold
* Phase D: Controlled dynamic route refresh

Verified behavior includes:

* asynchronous route loading without blocking the map
* map usability before route preview appears
* online road route preview plus route guidance distance and ETA
* offline fallback for direct distance and schematic guidance
* live movement of the blue "You are here" marker
* authoritative boundary distance refresh while moving
* GPS stream lifecycle cleanup on screen dispose
* Phase C arrival indicator at the shared 30-meter threshold
* controlled route refresh after meaningful movement, subject to a separate cooldown

Testing status in this section distinguishes code/architecture verification from physical-device testing; the phases above were confirmed during manual device testing; exact movement measurements and timestamps were not recorded.
3. Tasks
4. Sync
5. Profile
6. Settings
1. Login
2. Home
3. Tasks
4. Sync
5. Profile
6. Settings

Legend: PASS, FAIL, PARTIAL, NEEDS VERIFICATION.

---

## QUICK MANUAL TEST CHECKLIST

Use this as the short execution list for the verified Route Map / Site Verification flow.

- [ ] Open assigned task and enter Site Verification
- [ ] Confirm the red target site marker is visible
- [ ] Confirm the blue "You are here" marker is visible
- [ ] Verify the device marker updates while moving
- [ ] Confirm the authoritative distance to parcel boundary updates during movement
- [ ] With internet ON, confirm the road-route line appears after map usability
- [ ] Confirm route distance / ETA is shown separately from the authoritative distance
- [ ] With internet OFF, confirm the app shows fallback schematic guidance instead of a live road route
- [ ] Confirm no crash or freeze when routing is unreachable / bounded timeout occurs
- [ ] Confirm the app keeps the direct verification distance as the real decision metric
- [ ] Move meaningfully and confirm a controlled route refresh can occur
- [ ] Confirm route requests are not made on every GPS event and respect the cooldown
- [ ] Confirm a failed route refresh keeps the previous successful route
- [ ] Tap Confirm Site Location manually when the user is within the verification pass range
- [ ] Validate the GPS verification screen shows live coordinates, accuracy, distance, and bearing
- [ ] Confirm the location stream is cleaned up correctly on screen exit

---

## ROUTE MAP / SITE VERIFICATION VERIFIED SCOPE

This cycle verifies the following checkpointed work in the canonical worktree:

* Phase A: **374654a — feat(inspection): harden site verification route preview**
* Phase B: **9575103 — feat(inspection): add live GPS tracking to site verification**
* Phase C: Site Verification arrival detection at the shared 30-meter threshold
* Phase D: Controlled dynamic route refresh

Verified behavior includes:

* asynchronous route loading without blocking the map
* map usability before route preview appears
* online road-route preview plus route guidance distance and ETA
* offline fallback for direct distance and schematic guidance
* live movement of the blue "You are here" marker
* authoritative boundary-distance refresh while moving
* GPS stream lifecycle cleanup on screen dispose
* Phase C arrival indicator at the shared 30-meter threshold
* controlled route refresh after meaningful movement, subject to a separate cooldown

Testing status in this section distinguishes code/architecture verification from physical-device testing. Phase A and Phase B device results are recorded below. Phase C and Phase D were also confirmed during manual device testing; exact movement measurements and timestamps were not recorded.

Phase purposes and status:

| Phase | Purpose | Status |
|---|---|---|
| A — Route Preview | Display an asynchronous OSRM road route, route distance, and optional ETA without blocking the map | Code/architecture verified and manually device-tested |
| B — Live GPS Tracking | Keep the device marker and Site Verification distance updating while Step 1 is open | Code/architecture verified and manually device-tested |
| C — Arrival Detection | Show an informational arrival state at the shared 30-meter Site Verification threshold | Manually device-tested; exact measurement not recorded |
| D — Controlled Route Refresh | Refresh stale road-route geometry after meaningful movement with request controls | Manually device-tested; exact measurement and request timing not recorded |

The Site Verification distance and road-route distance are separate measurements. The 4-second interval controls authoritative-distance recalculation; the approximately 30-second cooldown controls road-route requests. The 50-meter movement trigger is a route-refresh condition, not an arrival threshold.

Phase failure indicators:

* **Phase A:** map is blocked by route loading, no road route appears when routing succeeds, route guidance replaces the Site Verification distance, or routing failure crashes the screen.
* **Phase B:** the device marker does not move, the target marker disappears, distance stops updating, or the location stream continues after leaving the screen.
* **Phase C:** **Arrived at Site** appears outside the 30-meter threshold, uses road-route distance, or automatically verifies/submits/advances the inspection.
* **Phase D:** OSRM is called on every GPS event, simultaneous requests occur, a failed refresh erases the previous route, a stale response replaces a newer route, or OSRM is called while offline.

---

## TEST 1: Scheduling a Pending Task


* **Objective:** Confirm a new assignment can be scheduled and moves to Pending, Scheduled.
* **Preconditions:** One new task exists under Pending, Available Anytime with an admin deadline of 2026-08-31.
* **Actions:** Tap "Reschedule Inspection Date" on Task 1. Pick Wednesday, August 26 in the calendar. Type a note. Save.
* **Expected:** Modal opens with calendar, deadline reminder, and Notes field. After saving, the task appears under Pending, Scheduled.
* **Actual:** Same as expected.
* **Result:** PASS
* **Code verification:** The schedule function updates only scheduled_date, is_self_scheduled, and remarks in field_jobs. It never touches status.
* **Supabase verification:** Columns exist: scheduled_date (date), deadline_date (date), is_self_scheduled (boolean), remarks (text). Status stays at its previous value.
* **Root cause:** Not applicable, working feature.

## TEST 2: Schedule Note Persistence

* **Objective:** Verify the optional note typed during scheduling is stored.
* **Result:** PASS
* **Verification:** The app writes the note into the existing remarks column of field_jobs. No separate schedule-note column exists or is needed. Confirmed against schema and code before documenting.

## TEST 3: Repeated Rescheduling

* **Objective:** Confirm a scheduled task can be rescheduled again.
* **Actions:** Open the schedule dialog again on a scheduled task, pick a different valid date, save.
* **Expected:** New date replaces the old one; task stays under Pending, Scheduled; deadline rule enforced every time.
* **Actual:** Same as expected.
* **Result:** PASS
* **Notes:** The old date and note are overwritten. There is no schedule history table, so previous values are not archived. This is current design, not a bug.

## TEST 4: Visit and Deadline Display

* **Objective:** Confirm the card shows Visit only for scheduled tasks and Deadline for active tasks.
* **Initial finding (fixed):** Dates were mapped in the data model but not rendered on the card.
* **Fix applied:** Added Visit and Deadline rows using existing theme tokens.
* **Retest:** PASS
* **Final behavior:** Visit shows only when category is Scheduled. Deadline shows on all non-completed tasks. Completed cards show neither.

## TEST 5: Priority Colors

* **Objective:** Verify card colors follow the approved lifecycle model.
* **Confirmed logic from code (border-signal model, REVISED latest cycle after field feedback):**
  * Scheduled: Visit-date urgency drives the border — blue when normal, orange at 2–3 days, and red today/tomorrow/past.
  * Pending/Available Anytime and Ongoing: Deadline drives Due Today and Overdue indicators; normal cards remain blue.
  * Active Overdue: full red container, red border, red applicant initials/icon, red progress indicator, and one Overdue tag.
  * Green: completed, never active Overdue even if old dates have passed.
  * The standalone "Scheduled" pill was REMOVED — redundant inside the Pending tab's Scheduled section (section header + orange border + Visit row already carry the signal) and it added clutter on urgent cards.
* **Manual finding that led to a fix:** A started scheduled task stayed blue because the color check required the Scheduled category. Fixed so orange follows plan membership and red follows the deadline threshold.
* **Result after fix:** PASS
* **Key distinction documented:** Scheduled urgency uses the Visit date. Available Anytime and Ongoing Due Today/Overdue status uses the admin Deadline. Completed tasks have no active urgency indicators.

## TEST 6A: Final Category Ground Truth

* **Objective:** Verify the five display states derived from the confirmed database fields.
* **Cases:** Available Anytime (`assigned`, not self-scheduled); Scheduled (self-scheduled); Scheduled started (self-scheduled, step 1/6–5/6); Ongoing (`in_progress`, not self-scheduled); Completed (`completed`).
* **Expected:** Available Anytime and Scheduled appear under Pending; Scheduled remains Scheduled after work starts; Ongoing has no In Progress or Ongoing tag; Completed is green and inactive.
* **Actual:** PASS / WORKING during manual device testing; category regression test passed with `00:08 +4: All tests passed!`.
* **Result:** PASS / WORKING

## TEST 6B: Final Indicator and Contextual Help Behavior

* **Objective:** Verify state indicators are present only when applicable and are not duplicated.
* **Cases:** Blue, Orange, Red, Due Today, For Reschedule, Overdue, Scheduled + In Progress, Ongoing without In Progress, active Overdue red override, and Completed without active urgency indicators.
* **Expected:** Scheduled In Progress appears only at steps 1/6–5/6; Ongoing never shows In Progress or Ongoing; active Overdue uses the full red treatment; Completed remains green without historical urgency details.
* **Contextual `!` checks:** exactly one standalone `!` per card; never beside or inside a tag; relevant explanations only; multiple current indicators produce multiple explanations in one popup; no duplicate Overdue or indicator tags.
* **Actual:** PASS / WORKING during manual device testing.
* **Result:** PASS / WORKING

## TEST 6C: Final Calendar and Active Assignment Date Sources

* **Objective:** Verify calendar and Active Assignments dates follow task category.
* **Expected:** Scheduled uses Visit date. Available Anytime and Ongoing use Deadline. Completed tasks do not create active calendar entries. Selecting a dotted date in the full calendar keeps the calendar open and shows the `Tasks for ...` details.
* **Actual:** Implemented for the current dashboard flow; device confirmation is recorded separately from this QA entry.
* **Result:** NEEDS DEVICE CONFIRMATION

## TEST 6: Filter by Urgency

* **Objective:** Verify filter options match the finalized model.
* **Old behavior (superseded):** All, Overdue, Due Today filtered by visit-date lateness among scheduled tasks. Available Anytime tasks could never match even with a passed deadline.
* **New behavior (revised latest cycle):** All, Urgent (deadline today or tomorrow, not yet past), Scheduled (plan members), Overdue (deadline already passed). Urgent and Overdue no longer overlap. Completed tasks never match any option.
* **Revision reason:** the previous Urgent definition (within 1 day or passed) contained all Overdue tasks, so whenever no task was due today or tomorrow the two chips returned identical counts and looked redundant during testing. Split into a disjoint model that matches the card badges (Deadline today / Deadline tomorrow vs Overdue).
* **Result:** PASS

## TEST 7: Task Overview Initial State

* **Objective:** Confirm overview content for a new inspection.
* **Expected:** Step counter shows 0/6, six step cards listed, Photos section present, Application Details present.
* **Actual:** Same as expected.
* **Result:** PASS
* **Note on Application Details:** Classification comes from application_type while Land Use Focus comes from land_use_class. In one test both showed "Commercial". Verified this was equal test data, not a mapping error, because the two values come from different sources.

## TEST 8: Photos in Task Overview

* **Objective:** A photo saved in Step 3 should appear in the Overview Photos section.
* **Bug history:** Photo appeared inside Step 3 but not in the Overview. Root cause: the Overview did not reload on return and only rendered remote image URLs, so freshly captured local photos were invisible there.
* **Fix applied:** Reload when returning from any step, read live captured photos during an active inspection, render both local files and network URLs through the shared photo widget.
* **Retest:** Photo now appears immediately after saving in Step 3 and returning to the Overview. PASS
* **Persistence note:** Camera save stores the photo locally first. Upload happens on proceeding to the next step, on early exit, or on submit, with offline queueing as fallback. This is intentional design.

## TEST 9: Photographic Evidence Details

* **Objective:** Verify camera flow, notes, geotag, and sync.
* **Verified chain:** Capture with camera, add inspection note, save shows photo with note and geotag in Step 3. The note travels with the photo record to the database and back when reopened.
* **Database detail:** Photo notes are stored in the notes column of field_job_photos. This column was added through migration because earlier photos had no place to store notes. Older photos legitimately show "No inspection note for this photo."
* **Result:** PASS

## TEST 10: Zoning Checklist

* **Objective:** Verify toggles, live counter, persistence, and rehydration.
* **Behavior:** Every toggle saves right away. A live counter shows checked items instantly. Answers persist locally and remotely. Reopening loads the saved answers instead of defaults.
* **Result:** PASS

## TEST 11: Field Findings Fields

* **Objective:** Verify observations, discrepancies, and recommendation storage.
* **UI structure:** Discrepancies has two inputs, Issue Title and Details.
* **Storage mapping:** The database stores findings related text in combined text columns rather than separate title and detail columns. Title and details are preserved together and both come back correctly on reopen and rework. Documented here so no one expects two separate columns.
* **Result:** PASS

## TEST 12: Review and Submit

* **Objective:** Confirm Steps 1 to 5 answers surface correctly and submission works.
* **Actual:** Summary reflected all prior answers. Submission succeeded with message "Inspection submitted" and result recorded as Compliant. Task left the active workflow and appeared under Completed.
* **Result:** PASS
* **Ordering note (revised latest cycle):** Completed tab is NEWEST-FIRST (LIFO) by submission time — the most recently completed inspection is always the first card; tasks without a submission timestamp sort last. Confirmed in code (descending submitted_at sort). Previously the list was oldest-first.

## TEST 13: Step Timestamps

* **Finding:** The old "Verified on..." time shown per step was simulated data computed from the clock, not a real record.
* **Current status:** That label is known mock output. It must not be treated as a real completion timestamp. Replacing it needs a decision on where real per-step times will be stored, since none exist yet.
* **Related facts that ARE real:** Last saved reflects the latest modification time and changes during rework. Completed cards use the true original submission timestamp.
* **Resolution (F1, latest cycle):** Real per-step saved times are now implemented. Every Proceed writes the actual wall-clock time into step_timestamps on field_jobs when online, mirrored locally and drained through the offline queue. Task Overview shows "Saved on <real time>" per finished step, isolated per task.
* **Supabase verification:** the live production field_jobs table contains step_timestamps (confirmed by a read-only REST probe).
* **Caveat:** the production column was applied out-of-band; the repository SQL/migration files still need to be synchronized with it.
* **Result:** PASS (implemented and verified; migration documentation sync pending)

## TEST 14: Completed Step Rework

* **Objective:** Verify rework entry, confirmation, single save, and Modified logic.
* **Entry:** Each completed step exposes "Rework this step" with a confirmation dialog explaining only that step will be redone.
* **Save behavior:** Each step screen shows exactly one button during rework which saves and returns to the summary.
* **Test 14a, unchanged Step 1 rework:** Opened Step 1, pressed Save without changes. Task did NOT receive the Modified tag. PASS. Change detection fires only on real edits.
* **Test 14b, checklist change:** Changed Step 4 checklist from 5/5 to 3/5 and saved. New values displayed immediately, persisted across reload, and the Modified tag appeared because a genuine data change occurred. PASS.

---

## TEST 15: GPS Verification Screen Details

* **Objective:** Document what the GPS screen shows and its pass condition.
* **On-screen elements verified from code:** live tracking indicator, current coordinates, accuracy in meters, distance to parcel boundary in meters, and a compass bearing label such as NE with degree value.
* **Pass condition:** distance of 30 meters or less from the parcel boundary marks verification as achieved.
* **Offline path:** if confirmation fails due to no signal, the check-in is stored offline with a message that it will sync automatically.
* **Data written on confirm:** latitude, longitude, accuracy, check-in time, plus an activity log entry.
* **Result:** PASS

## TEST 16: Site Verification Screen Details

* **Objective:** Document what the map step shows.
* **On-screen elements verified from code:** titled header "Site Verification" with task location subtitle, step progress bar, a red Target Site marker at the parcel coordinates, and a separate marker for the device position.
* **Latest verified behavior (canonical worktree):** the device position updates live during the Site Verification check, and the map supports the authenticated Route Map flow by loading the road route asynchronously after the map is already usable.
* **Note:** target coordinates appear visually through the map marker. They are not rendered as numeric text on this screen.
* **Update (route preview, Phase A):** when online, the map additionally draws a road-network route between the device position and the target after the map is already usable, plus a road-route distance and estimated travel time row beside the authoritative boundary distance. Offline or on routing failure, a schematic bent fallback line and the straight-line/haversine distance remain. Routing/provider logic is isolated in core/services/route_service.dart; flutter analyze reports no issues on both Route Map files.
* **Result:** PASS

## TEST 17: Completed Tab Ordering (Newest-First)

* **Objective:** Confirm the Completed tab lists the most recently submitted inspection first.
* **Initial finding (fixed):** The Completed sort was ascending by submitted_at, so the OLDEST completed task appeared first and a freshly submitted inspection landed at the bottom of the list.
* **Fix applied:** Reversed the Completed sort to descending submitted_at (LIFO / newest-first). ISO-8601 timestamp strings compare correctly in lexicographic descending order; tasks with no submitted_at sort last.
* **Expected:** After submitting an inspection, it appears as the FIRST card under Completed, above previously completed tasks.
* **Result:** PASS
* **Sequence rule (for future reference):** Completed = newest-first (LIFO). Pending sorts by creation date (oldest-first). Ongoing sorts by start time (oldest-first). Scheduled sorts by deadline (earliest deadline first).

## TEST 18: Route Preview Online (Real Device)

* **Objective:** Confirm Step 1 shows a real road-route preview without delaying the map.
* **Environment:** physical realme RMX3085, debug APK of commit 374654a, internet ON.
* **Actions:** open an assigned task and enter Step 1 Site Verification.
* **Expected:** the map becomes usable immediately with both markers visible; afterwards a blue road-following route line appears asynchronously; a separate Road-route distance and estimated travel time row appears without replacing the authoritative distance.
* **Actual:** same as expected.
* **Result:** PASS

## TEST 19: Offline Fallback (Real Device)

* **Objective:** Confirm graceful degradation with no internet.
* **Environment:** same device; WiFi and mobile data OFF, GPS ON; fresh app restart.
* **Actions:** reopen Step 1 for the same task.
* **Expected:** map opens fast from cached parcel coordinates; both markers render; schematic bent fallback line instead of a road route; haversine/boundary distance still shown; no Road-route row; no crash.
* **Actual:** same as expected.
* **Result:** PASS
* **Note:** the basemap tiles themselves are not guaranteed offline; this test passed with previously viewed/partially cached tiles only. See DOCUMENTATION section 5.3 for the offline basemap limitation.

## TEST 20: Routing Unreachable (Real Device)

* **Objective:** Confirm the bounded routing-failure path while the device believes it is connected.
* **Environment:** connected-but-no-internet network (no uplink); GPS ON.
* **Actions:** fresh restart, open Step 1.
* **Expected:** routing fails within its bounded timeout (max 8 seconds) silently; map opens instantly regardless; fallback line and authoritative distance persist; no hang, crash, or ANR; at most one route request per screen open.
* **Actual:** same as expected on controlled re-run. An initial attempt coincided with wireless-ADB loss during network toggling and was diagnosed as not app-related: process continuity was proven by identical PID and start time across all tests, zero ANR/crash records in dropbox and /data/anr for that day, and zero Flutter exceptions in logcat.
* **Result:** PASS

## TEST 21: Live GPS Marker Movement (Step 1)

* **Objective:** Verify that the device marker on the Site Verification map tracks the inspector's physical movement in real time.
* **Actions:** Open Step 1 (Site Verification) on a real device with GPS enabled, walk/move across the property/street beyond the 4-meter movement threshold.
* **Expected:** The blue "You are here" marker moves continuously across the map canvas without requiring manual reload or reopening the screen; the map remains smooth and responsive.
* **Actual:** Marker position updates smoothly on location stream ticks.
* **Result:** PASS

## TEST 22: Authoritative Distance Refresh Throttling (Step 1)

* **Objective:** Confirm authoritative parcel boundary distance recalculates during movement while respecting the 4-second throttling and reentrancy protections.
* **Actions:** Move continuously across physical space while monitoring network requests and UI distance metrics.
* **Expected:** Distance metric updates periodically (minimum 4 seconds apart); rapid GPS movement ticks update marker immediately but do not spam Supabase RPC calls; transient failures retain previous distance value without crashing.
* **Actual:** Supabase RPC boundary distance refreshes at the throttled interval; Haversine fallback calculates smoothly when offline; no RPC flooding.
* **Result:** PASS

## TEST 23: Live GPS Stream Lifecycle and Teardown (Step 1)

* **Objective:** Verify location stream subscription cancels cleanly upon screen exit and resumes correctly on app-resume.
* **Actions:** Open Step 1, background app, return to foreground; navigate back to Task Overview; inspect memory/logcat.
* **Expected:** `_positionSub` subscription restarts idempotently on app resume; subscription cancels immediately on screen dispose; zero background GPS leaks or dangling listeners.
* **Actual:** Stream subscription tears down cleanly on dispose; zero background leaks.
* **Result:** PASS

## TEST 24: Arrival Detection (Phase C)

* **Objective:** Confirm the Phase C arrival indicator and the remaining Phase D boundary.
* **Actions:** Test distances above 30 meters, at or below 30 meters, and after moving away. Repeat with internet disabled when cached parcel coordinates and GPS are available.
* **Expected:** **Arrived at Site** appears at 30 meters or less and disappears after moving beyond the threshold once the distance refreshes. Online distance uses the parcel-boundary RPC; offline distance is a best-effort Haversine estimate. The app does not auto-advance; manual tap on "Confirm Site Location" remains required. Any Phase D route refresh remains separate from this arrival state.
* **Actual:** Device testing confirmed the Phase C arrival behavior; exact measurement was not recorded.
* **Result:** PASS during manual device testing.

## TEST 25: Controlled Route Refresh — Initial Route (Phase D)

* **Objective:** Confirm the initial road route still loads normally after the Phase D refresh controls are present.
* **Actions:** Enable internet, open an assigned task, and enter Step 1 Site Verification.
* **Expected:** The map becomes usable first; the road route and route guidance values load asynchronously when OSRM succeeds.
* **Actual:** Passed during manual device testing; exact measurement not recorded.
* **Result:** PASS during manual device testing.

## TEST 26: Controlled Route Refresh — Meaningful Movement (Phase D)

* **Objective:** Confirm the route can refresh after meaningful movement from the latest route-request origin.
* **Actions:** Move approximately 50 meters from the route-request origin and continue receiving GPS updates.
* **Expected:** A controlled refresh may replace the displayed route. GPS accuracy and update timing may affect the exact observed distance; refresh is not required at exactly 50.0 meters.
* **Actual:** Passed during manual device testing; exact measurement not recorded.
* **Result:** PASS during manual device testing.

## TEST 27: Controlled Route Refresh — Cooldown and Request Guard (Phase D)

* **Objective:** Confirm route requests are not made on every GPS event or run simultaneously.
* **Actions:** Generate multiple GPS updates while moving, including updates within the cooldown window.
* **Expected:** The live marker and authoritative distance continue independently, while route requests remain controlled by the approximately 30-second route cooldown and in-flight guard.
* **Actual:** Passed during manual device testing; exact request count and timestamps were not recorded.
* **Result:** PASS during manual device testing.

## TEST 28: Controlled Route Refresh — Failed Refresh (Phase D)

* **Objective:** Confirm a failed route refresh does not erase the previous successful route.
* **Actions:** Make a refresh eligible, then interrupt routing connectivity or use a connected-but-unreachable network.
* **Expected:** No crash or hang; the previous successful route remains, while GPS and Site Verification distance continue.
* **Actual:** Passed during manual device testing; exact failure timing was not recorded.
* **Result:** PASS during manual device testing.

## TEST 29: Controlled Route Refresh — Offline Movement (Phase D)

* **Objective:** Confirm offline movement never calls OSRM and does not interrupt local Site Verification behavior.
* **Actions:** Disable connectivity while GPS remains available, then move the device.
* **Expected:** No OSRM route request; GPS marker, local distance, schematic fallback, and arrival logic continue as available.
* **Actual:** Passed during manual device testing; exact network trace was not recorded.
* **Result:** PASS during manual device testing.

## TEST 30: Controlled Route Refresh — Reconnection (Phase D)

* **Objective:** Confirm routing can resume after connectivity returns.
* **Actions:** Restore connectivity after offline movement and continue receiving GPS updates.
* **Expected:** A route refresh can occur when movement and cooldown conditions permit; it is not forced on every reconnect or GPS event.
* **Actual:** Passed during manual device testing; exact measurement and timing were not recorded.
* **Result:** PASS during manual device testing.

## TEST 31: Route Distance and Arrival Independence (Phase D)

* **Objective:** Confirm route distance never becomes the Site Verification arrival authority.
* **Actions:** Observe route guidance distance separately while approaching the site, including offline operation where applicable.
* **Expected:** Arrival remains based on the Site Verification distance. The 30-meter arrival threshold, offline local fallback, and manual continuation behavior remain unchanged.
* **Actual:** Passed during manual device testing; exact measurement was not recorded.
* **Result:** PASS during manual device testing.

---

## FINAL DOCUMENTATION: UI Accessibility / Visual Comfort — Priority Color

* **Context:** Primary inspectors are adults ~30-50 working long sessions in outdoor/field conditions. Priority colors communicate urgency with both color and text/icon signals.
* **Current treatment (verified by manual device testing):**
  * Active Overdue: full red container treatment, red border, red applicant initials/icon, red progress indicator, and one Overdue tag.
  * Scheduled non-overdue: Visit-date border urgency (blue, orange, or red), with In Progress only at steps 1/6 through 5/6.
  * Ongoing non-overdue: blue border and blue avatar, with no In Progress or Ongoing tag.
  * Completed: green treatment and no historical urgency indicators in Task Details.
* **Concern:** card-WIDE orange/red tint fills make priority states visually dominant across large surfaces; with many cards on screen the whole list turns warm/noisy; saturated orange border on white vibrates in bright sunlight; large low-contrast tinted areas are fatiguing over long sessions; Scheduled state is close to color-only (Visit row is its only non-color signal).
* **Verified treatment:**
  * Scheduled border urgency is based on the Visit date; Overdue is based on the Deadline date.
  * Any active Overdue task, including Ongoing, uses the full red container treatment and red avatar/icon.
  * The contextual `!` popup is card-level and lists only indicators currently present. It is never embedded in a tag.
* **Accessibility reasoning:** text-bearing tags and icons supplement color. Active Overdue uses a red container, border, avatar/icon, and progress indicator; non-overdue Ongoing remains blue; Completed remains green. The single contextual `!` provides explanations without duplicating tags.
* **Exact files/functions affected (identified, NOT edited):**
  * lib/modules/tasks/screens/tasks_screen.dart → _CompactTaskCardState.build() (final card colors, state badges, and contextual popup).
  * _CompactTaskCardState._getStatusColor() — Scheduled visit urgency and normal lifecycle colors.
  * Documentation reconciled after manual device testing passed.
* **Explicitly out of scope:** task lifecycle logic, Visit/Deadline logic, Completed-date logic, urgency threshold, filter behavior, F2, GAP-9.5, F1/F4/F5, Supabase/schema, new dependencies, new theme tokens.
* **Cost:** none. No new dependencies, no new tokens.
* **Status:** HISTORICAL REVIEW RECORD — superseded by the final manually tested behavior above.

### HISTORICAL PROPOSAL (superseded by final manual testing)

The proposal below is retained as audit history only. It is not the current UI specification; the verified treatment above takes precedence.

* **Historical design notes:** earlier accent-only and neutral-border proposals are superseded. They are not current UI requirements.
* **Final visual state:** active Overdue uses the full red container treatment; non-overdue Scheduled uses Visit-date border urgency; non-overdue Ongoing uses blue; Completed uses green.
* **Current signals:** Scheduled uses its section and Visit row; urgency uses the applicable tag; active Overdue uses the full red container treatment and red applicant icon.
* **Per-state treatment:** Normal Pending = blue. Scheduled uses Visit-date border urgency and may show In Progress only at steps 1/6 through 5/6. Ongoing uses blue with no In Progress or Ongoing tag. Any active Overdue task uses the full red treatment. Completed uses green and no historical urgency indicators.
* **Why scannable:** every state has text/icon signals, and the single contextual `!` explains only indicators currently present on the card.
* **Implementation scope:** final task-card state rendering and contextual information behavior were verified in `tasks_screen.dart`; no further implementation is pending.
* **Still out of scope:** lifecycle/category logic, Visit/Deadline logic, Completed-date logic, urgency threshold, filter behavior, F1/F2/F4/F5, GAP-9.5, Supabase/schema, new hex values, new dependencies.
* **Status:** HISTORICAL PROPOSAL — superseded by the final manually tested behavior above.
* **Final field feedback:** the standalone Scheduled pill is not used inside the Scheduled section. Active Overdue takes precedence over all other border and container colors, including for Ongoing tasks; the applicant initials/icon also turn red.

---

| Item | Status |
|---|---|
| Real per-step completion timestamp | IMPLEMENTED (F1, step_timestamps verified live); repository migration docs pending sync |
| Route Map Phase A hardening (async route load, body timeout, User-Agent, dead-code removal, connectivity dedup) | COMMITTED 374654a; PASS on realme RMX3085 (Tests 18-20) |
| Offline map visual (basemap tiles) | NOT available offline; compliant offline basemap strategy documented as future architectural requirement |
| Offline scheduling | Not supported yet, noted for future work |
| Schedule history archive | Not part of current design, reschedule overwrites |
| Priority color redesign (accent-only → border-signal revision, see Design Review above) | IMPLEMENTED this cycle |

