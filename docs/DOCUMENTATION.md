# iMAPS:FieldSync — System Documentation

Comprehensive technical and functional documentation of the **iMAPS:FieldSync** mobile application. This document describes the system architecture, business rules, screen functions, lifecycle states, and data movement as implemented on the `main` branch.

---

## Table of Contents
1. [Module 1: Login & Authentication](#1-module-1-login--authentication)
2. [Module 2: Home Dashboard](#2-module-2-home-dashboard)
3. [Module 3: Tasks & 6-Step Inspection Protocol](#3-module-3-tasks--6-step-inspection-protocol)
4. [Module 4: Sync Center & Offline-First Architecture](#4-module-4-sync-center--offline-first-architecture)
5. [Module 5: Profile & Analytics](#5-module-5-profile--analytics)
6. [Module 6: Settings & Security Controls](#6-module-6-settings--security-controls)
7. [System Architecture & Data Flows](#7-system-architecture--data-flows)

---

## 1. Module 1: Login & Authentication

### 1.1 Purpose & Role
The Authentication module ensures that only authorized personnel from the Municipal Planning and Development Office (MPDO) can access zoning application data and submit official field inspection records.

### 1.2 Screens & Subsystems

```text
[ App Launch / Cold Start ]
            |
            v
     [ Splash Screen ]  -------- (Valid Session + Bio Lock On?) ------> [ App Resume Lock ]


## Security Overview

The application safeguards sensitive data through comprehensive security measures:
- Utilization of encrypted databases (e.g., SQLite with SQLCipher).
- Role-Based Access Control (RBAC) in effect for sensitive operations. 
- Biometric security for enhanced authentication processes. 

            |                                                                  |
    (No Valid Session)                                                    (Verified)
            |                                                                  |
            v                                                                  v
     [ Login Screen ]                                                [ Home Dashboard ]
      ├── Online Passcode Auth (Supabase Auth)
      ├── Offline Passcode Auth (Salted HMAC-SHA256)
      ├── Biometric Quick-Unlock (Fingerprint / Face ID)
      └── Legal Acknowledgement (Terms & Privacy Dialog)
```

1. **Splash Screen (`splash_screen.dart`):**
   * **Initialization:** Initializes application services, loads package version via `AppInfoService`, loads soft-logout flags, and checks local connectivity.
   * **Session Evaluation:** Evaluates whether a valid Supabase session exists in memory/storage.
   * **Expired Token Handling:** If a session is expired, it attempts a background refresh. When offline, it proceeds with cached credentials rather than locking the user out.
   * **Cold-Start Biometric Gate:** If "Require on App Open" is enabled and biometric authentication is confirmed, the app routes through `AppResumeLockScreen` before opening the dashboard.

2. **Login Screen (`LoginScreen` in `splash_screen.dart`):**
   * **Email & Passcode Authentication:** Authenticates against Supabase Auth when online. Upon successful login, the app derives and caches a salted HMAC-SHA256 verifier locally for offline authentication.
   * **Offline Passcode Authentication:** When offline, the app computes `HMAC-SHA256` (100,000 iterations) using a cryptographically generated 16-byte salt and compares it against the stored verifier in constant time.
   * **Failed Attempt Rate Limiting / Cooldown:** Failed offline attempts increment a counter:
     * 3 failed attempts: 30-second cooldown
     * 5 failed attempts: 2-minute cooldown
     * 8 failed attempts: 5-minute cooldown
   * **Biometric Quick-Unlock:** Available when biometrics are enrolled and confirmed. Re-activates the existing local session without destroying tokens or requiring a network round-trip.
   * **Terms of Use & Privacy Policy Acknowledgement:** Prompts for mandatory acknowledgement if the user has not accepted the current version (`v1`).
   * **Multi-Inspector Local Data Guard (`LocalDataGuardService`):** Prevents account switching on a shared device if the previous inspector has unsynced inspection work stored in the local outbox.

3. **Session & Logout Behavior (`AuthService`):**
   * **Soft Logout:** When an inspector with enrolled biometrics logs out, the app flags the session as hidden (`_softLoggedOut = true`) on the device rather than revoking the refresh token server-side. This allows instant biometric re-authentication without network requests.
   * **Hard Sign Out (`revokeEverywhere: true`):** Revokes tokens globally on password change or explicit security resets.

---

## 2. Module 2: Home Dashboard

### 2.1 Purpose
The Home Dashboard serves as the inspector's daily operational hub. It provides an immediate overview of assigned inspections, today's schedule, quick actions, and recent activity logs.

### 2.2 Screen Structure & Components (`home_dashboard_screen.dart`)

1. **Identity & Status Header:**
   * Displays the inspector's greeting, full name, MPDO designation, and live system time (`_LiveClock`).
   * Displays the live connectivity status (Online / Offline).
2. **Active Assignments Folder Carousel:**
   * Displays up to 6 active (Pending / Scheduled / Ongoing) inspection assignments in a pageable carousel.
   * Each card displays the applicant name, reference number, target barangay, land use class, scheduled visit date or deadline, and urgency border.
   * Tapping a card opens the **Task Overview** screen (`parcel_detail_screen.dart`).
3. **Interactive Calendar Strip & Monthly Picker:**
   * A horizontal scrollable day selector highlighting today's date.
   * Dates containing assigned tasks display blue indicator dots.
   * Tapping the calendar icon opens a full-month view showing all scheduled tasks for the month.
4. **Quick Navigation & Action Triggers:**
   * Provides rapid navigation to My Tasks, Sync Center, and standalone tools (Quick Compass, Site Map Preview).
5. **Recent Activity Feed:**
   * Chronological feed of recorded field actions (e.g., GPS verified, checklist saved, photos captured, inspection submitted, rework started, sync completed).
   * Filterable by categories: **All**, **Tasks**, **Sync**, **Profile**.

---

## 3. Module 3: Tasks & 6-Step Inspection Protocol

### 3.1 Task Lifecycle & Precedence Rules (`tasks_screen.dart`)

Field assignments are stored in PostgreSQL (`field_jobs`) and categorized at the application layer according to verified precedence rules:

| Category | Database State | Description |
|---|---|---|
| **Completed** | `status = 'completed'` | The inspection was submitted or resubmitted. Checked first. |
| **Scheduled** | `is_self_scheduled = true` and `status != 'completed'` | The inspector selected and committed to a specific visit date. |
| **Ongoing** | `status = 'in_progress'` and `is_self_scheduled = false` | The inspector opened and started an unscheduled task. |
| **Pending (Available Anytime)** | `status = 'assigned'` and `is_self_scheduled = false` | New assignment with no committed visit date. |

*Precedence Order:* **Completed → Scheduled → Ongoing → Pending**.  
*Note on `scheduled_date`:* In the database, `scheduled_date` is non-nullable and holds a default/placeholder date. The boolean flag `is_self_scheduled` is the authoritative determinant for the Scheduled group.

### 3.2 Visual Urgency Indicators & Card Theme

The visual design communicates urgency through clean borders, initials badges, and status tags:

* **Blue Indicator / Border:** Normal status for Pending, Scheduled, or Ongoing tasks with ample time remaining before visit or deadline.
* **Orange Border:** Scheduled tasks whose Visit date is **2–3 days away**.
* **Red Border:** Scheduled tasks whose Visit date is **today, tomorrow, or in the past** (Due Today / For Reschedule).
* **Full Red Treatment (Container, Border, Initials Square, Progress Bar):** Any active task whose **admin deadline has passed** (**Overdue**). This overrides normal blue or orange states across all categories.
* **Green Indicator / Border:** Completed inspections. Completed cards do not display historical urgency indicators.
* **Badges:**
  * `Due Today`: The Visit date (Scheduled) or Deadline (Available/Ongoing) is today.
  * `For Reschedule`: A Scheduled Visit date has passed, but the admin Deadline remains valid.
  * `Overdue`: The admin Deadline has passed.
  * `In Progress`: Appears on Scheduled tasks between steps 1/6 and 5/6.
  * `Modified`: Appears on reworked completed tasks where data was altered before resubmission.
* **Contextual Help Trigger (`!`):** Exactly one standalone help button per task card that explains all active badges on that card.

### 3.3 Scheduling & Rescheduling
* Inspectors can set or modify a visit date by tapping the calendar action or long-pressing an active card.
* **Rule:** The selected date must be on or before the administrator-set `deadline_date`.
* **Database Updates:** Updates `scheduled_date`, sets `is_self_scheduled = true`, and stores optional notes in `remarks`.
* *Constraint:* Scheduling requires an active internet connection in the current release.

---

## 5. Inspection Workflow

Opening an active job presents the Task Overview with a six-step protocol. Opening a Scheduled task does not move it to Ongoing; it remains Scheduled and may show the In Progress indicator only while its current step is 1/6 through 5/6. A non-self-scheduled task that starts work is categorized as Ongoing.

1. **Site Verification**: map-based confirmation of the parcel location.
2. **GPS Verification**: on-site position confirmation which records coordinates.
3. **Photographic Evidence**: camera capture with per-photo notes and geotags.
4. **Zoning Checklist**: itemized pass or fail entries with a live counter.
5. **Field Findings**: observations, discrepancy title and details, recommendations.
6. **Review and Submit**: consolidated summary and final submission.

Each step persists progress as the inspector works. Step order is sequential and the overview tracks the highest finished step so work resumes from where the inspector left off, including after app restarts.

### 5.1 Contents of Each Step

* **Step 1, Site Verification screen:** shows a titled header with the task location and a step progress bar. The map displays a red Target Site marker at the parcel coordinates plus a blue "You are here" marker for the device position. The device position updates live during the inspection via continuous GPS streaming, and the authoritative distance to the parcel recalculates in real time. When connectivity is available, the screen additionally draws a road-network route between the two positions (fetched asynchronously after the map is already usable) and shows the road-route distance and estimated travel time beside the authoritative boundary distance. When routing is unavailable, a schematic guide line and the straight-line/boundary distance remain.
* **Step 2, GPS Verification screen:** shows live tracking status, current coordinates, GPS accuracy in meters, straight-line distance to the parcel boundary, and a compass bearing toward the parcel. Verification succeeds when the measured distance is 30 meters or less. Confirmation stores the latitude, longitude, accuracy value, and check-in time.
* **Step 3, Photographic Evidence screen:** opens the device camera. Each capture embeds coordinate and timestamp text into the image file as geotag metadata, accepts an optional inspection note per photo, lists saved photos with thumbnails, note text, and coordinate readouts, and allows photo removal before continuing.
* **Step 4, Zoning Checklist screen:** presents site condition and zoning observation items as tappable rows with check indicators, a running checked count beside the step header, and automatic saving on every toggle.
* **Step 5, Field Findings screen:** provides an Observations text area describing on-site conditions, a Discrepancies section with separate Issue Title and Details inputs left blank when nothing is found, and a Recommendation field for follow-up guidance.
* **Step 6, Review and Submit screen:** consolidates the site answer, checklist score, photo count, findings, and recommendation into summary rows before final submission.

## 5.2 Data Flow of an Inspection

The data moves through four layers in order:

1. **Screen layer.** Each step screen collects answers through forms, camera captures, toggles, or map interactions.
2. **Provider layer.** Answers enter a shared inspection provider that holds them for the active task. Photos are stored locally on the device at capture time. Checklist taps and field edits update memory right away.
3. **Persistence layer.** From the provider, data is written to two destinations:
   * Local device storage keeps drafts, photos, and a queue of pending actions for offline work.
   * Supabase receives the same updates directly when connectivity is available. If a write fails, the action is placed in the offline queue instead of being lost.
4. **Database layer.** Supabase tables store the final record: job fields hold status, dates, progress, findings text, and GPS values; a child table holds each photo record with its URL, note, and geotag; an activity table logs key events such as submission.

Reading follows the reverse path. When the app loads tasks or reopens a completed inspection, it queries Supabase, caches the result locally, maps the records into application models, and renders them on screen. Because every write either reaches the database or waits in the queue, no accepted input is silently discarded.

### 5.3 Route Guidance Subsystem (Step 1)

Checkpoint references:

* Phase A: **374654a — feat(inspection): harden site verification route preview**
* Phase D: controlled dynamic route refresh (implemented after Phase C)

Site Verification includes a road-route preview. The architecture keeps presentation and routing strictly separated: the screen renders markers, polylines, camera state, and distance/ETA text only; all endpoint, HTTP request, header, timeout, JSON parsing, and provider-specific logic lives in a dedicated RouteService. No provider URL, HTTP call, or JSON parsing exists inside the screen.

The routing flow is: current GPS position and target parcel coordinates go to RouteService, which returns a typed route result (polyline points, road distance, duration) or null. A null result never blocks or breaks the screen; the UI falls back to a schematic guide line plus the authoritative straight-line/boundary distance. Route loading is asynchronous and starts only after the map is usable, so opening Step 1 never waits on the network.

Phase D prevents the displayed route from becoming stale during live movement. A refresh is considered only after approximately 50 meters of movement from the latest route-request origin and only when the separate 30-second route-request cooldown has elapsed. Only one route request may run at a time. A successful response replaces the displayed route; a failed response leaves the previous successful route in place. Request-version checks prevent an older asynchronous response from overwriting a newer route. No OSRM request is made while offline.

Provider decisions: OSRM over OpenStreetMap data was selected under a strict zero-cost requirement (no API key, no billing account, no card). The public OSRM demo server is used for development and testing ONLY (community policy of roughly one request per second, an identifying User-Agent, logged requests, no uptime SLA); production deployment should point the service at a controlled, self-hosted OSRM instance. Road coverage was verified around Rosario, Batangas including barangay, rural, and unnamed roads; rural endpoints may snap up to roughly 100 meters from unmapped tracks, so road-route distance is an orientation aid only. Turn-by-turn navigation was evaluated and rejected as unnecessary for this workflow; route preview plus live tracking covers the need at zero cost.

The authoritative Site Verification measurement remains the parcel-boundary distance (server RPC when online, haversine offline). It must never be replaced by the road-route distance.

Offline behavior has four separate concerns that must not be confused: GPS positioning works offline because it comes from the device; target parcel coordinates work offline through the local cache; route geometry could be cached locally in the future but goes stale as the inspector moves; and the map basemap visual is made of tiles fetched from the tile server, which are NOT guaranteed offline. The public OSM tile server does not permit prefetching or building offline tile packs, so a compliant offline basemap strategy (self-hosted tiles or terms-permitting vector-tile provider) is a documented future architectural requirement, not something the current build provides.

### 5.4 Live GPS Tracking Subsystem (Step 1)

Checkpoint reference: **9575103 — feat(inspection): add live GPS tracking to site verification**

Site Verification incorporates continuous device location tracking to guide the inspector in real time while approaching the inspection site.

The architecture enforces strict service layer separation:

```text
UI / Presentation Layer
   site_map_screen.dart (FlutterMap, markers, polylines, camera control)
         |
         +-----------------------+------------------------+
         |                       |                        |
         v                       v                        v
  Location Layer          Proximity Layer          Routing Layer
  LocationService         SupabaseService /        RouteService
  .getPositionStream()    SpatialOfflineService    .fetchDrivingRoute()
         |                       |                        |
         v                       v                        v
  Device GPS Hardware     Supabase RPC /           OSRM Engine (HTTP)
                          Haversine Fallback
```

Key implementation characteristics of the live tracking subsystem:

1. **Shared Location Stream:** Step 1 reuses the shared `LocationService.getPositionStream()` configured with high location accuracy and a 4-meter movement filter, maintaining consistency with Step 2 (GPS Verification).
2. **Immediate UI Responsiveness:** Incoming GPS position ticks immediately update the internal device coordinates and trigger an immediate widget repaint. The "You are here" marker moves across the map without UI stutter or dependency on network latency.
3. **Throttled Authoritative Distance Recalculation:** To prevent flooding Supabase with rapid RPC requests as the inspector moves, distance recalculation is governed by:
   * A minimum recalculation interval (`_minDistanceRecalcInterval` = 4 seconds).
   * A reentrancy guard (`_recomputingDistance` boolean flag).
   * When eligible, the screen requests the authoritative boundary distance from Supabase via RPC when online, or calculates the straight-line Haversine distance via `SpatialOfflineService` when offline.
   * If a transient network failure occurs during recalculation, the screen retains the last known good distance value without throwing an uncaught exception, retrying automatically on the next qualifying tick.
4. **Controlled Route Refresh (Phase D):** The road-route polyline is not regenerated on every GPS tick. After approximately 50 meters of movement from the latest route-request origin and a separate 30-second route-request cooldown, the screen may request a refreshed route through RouteService. Simultaneous requests are prevented, failed refreshes preserve the previous route, and stale responses cannot overwrite a newer route.
5. **Stream Lifecycle and Resource Management:** The location stream subscription is initiated after initial map loading, restored idempotently on `AppLifecycleState.resumed` if disconnected, and explicitly cancelled via `_positionSub?.cancel()` within the screen's `dispose()` lifecycle method, preventing battery drain and memory leaks.

## 6. Data Persistence

Inspection data is stored at two levels:

* Local device storage keeps cached assignments, draft answers, captured photos, and a queue of pending actions taken while offline.
* The online database holds the authoritative record in field_jobs together with child records for photos and activity entries.

Writes performed offline enter the local queue and are applied to the online database in order once connectivity returns. Photo uploads follow the same pattern. Photos are captured locally during the step, then uploaded at defined points in the flow with queued fallback when the network is unavailable.

## 7. Submission

Review and Submit finalizes the inspection. The system records the stored status as completed, saves the submission timestamp, and stores the result classification such as Compliant. The job leaves the active lists and appears under Completed ordered by submission time. Scheduling metadata has no effect on this transition.

## 8. Post-Submission Rework

Any completed step can be reopened through a confirmation dialog. The original step screen loads with previously saved values. Each rework session uses a single save action which returns to the summary and refreshes displayed data automatically.

A Modified marker distinguishes genuine corrections. Opening a step without changes produces no marker. An actual edit sets a rework timestamp shown as the Modified badge together with a Last saved time. Submitting the revised inspection clears the marker. The Last saved time therefore reflects modification state, while the Completed card separately displays the original submission date.

## 9. My Tasks Verification Status

The My Tasks category, scheduling, indicator, contextual-help, completion, and rework behavior passed manual device testing. The category regression test also passes. Verified behavior includes Scheduled/Available Anytime separation, Ongoing without an In Progress tag, Scheduled In Progress only at steps 1/6–5/6, one contextual `!` per card, no duplicate Overdue indicator, and the full red override for active Overdue tasks.

## 10. Known Limitations

* Per-step completion times are now recorded (F1): every Proceed writes the real wall-clock time into step_timestamps on field_jobs when online, mirrored locally and queued for offline sync. Note: the live production column was applied out-of-band; the repository SQL/migration files still need to be synchronized with it.
* Routing preview uses the free public OSRM demo server, which carries no uptime guarantee and is approved for development/testing only; production deployment requires a self-hosted routing endpoint.
* Road-route preview geometry loads asynchronously and may refresh after approximately 50 meters of movement, subject to a separate 30-second route-request cooldown. This is controlled route refresh, not full turn-by-turn navigation.
* Step 1 shows an informational **Arrived at Site** state when the shared 30-meter inspection threshold is reached. It does not automatically advance to Step 2; transitioning remains an explicit inspector action. Online arrival uses the parcel-boundary RPC distance. Offline arrival uses best-effort Haversine distance to cached parcel coordinates.
* Offline behavior consists of four distinct components with differing availability:
  * **GPS Positioning:** Fully functional offline (hardware device sensor).
  * **Target Coordinates:** Fully functional offline (rehydrated from local SQLite cache).
  * **Proximity Distance:** Fully functional offline (falls back to local Haversine computation).
  * **Road Routing:** Unavailable offline (cannot query remote routing engine without network).
  * **Basemap Visual:** Unavailable offline unless tiles were previously cached in memory/disk; OSM tile usage policy forbids prefetching bulk tile packs.
* Scheduling requires connectivity; no offline queue exists for it yet.
* Rescheduling overwrites prior schedule values without history.

## 10. Flow Diagrams

These diagrams show how each screen and function actually behaves, following the same visual style throughout. Each box is a real state or action in the code, and each arrow is a real transition or write.

### 10.1 Site Verification / Route Map Flow

```
SITE VERIFICATION SCREEN
        |
        v
CURRENT GPS + TARGET PARCEL COORDINATES
        |
        +-----------------------------+
        |                             |
        v                             v
AUTHORITATIVE DISTANCE         ROAD-ROUTE PREVIEW
Parcel boundary distance       RouteService / OSRM route
(server RPC when online,       (online only, async after map usable)
Haversine fallback offline)     
        |                             |
        v                             v
VERIFICATION DECISION           NAVIGATION GUIDANCE
30m threshold for pass         route line + ETA + road-route distance
                               refresh after ~50m + ~30s cooldown
        |
        v
user taps Confirm Site Location
        |
        v
STEP 2 GPS VERIFICATION
```

The important distinction is that the route preview is for guidance only; it does not replace the authoritative Site Verification distance.

### 10.2 Full Task Lifecycle (Macro View)

```
ASSIGNMENT CREATED (admin side)
status stored as 'assigned'
        |
        v
PENDING - AVAILABLE ANYTIME
blue card, Deadline shown, no Visit
        |
        |  inspector picks a visit date (optional)
        v
PENDING - SCHEDULED
Visit + Deadline shown; Visit-date urgency color
        |
        |  inspector opens the task
        v
SCHEDULED (still under Pending)
remains Scheduled while work is in progress;
In Progress indicator only at steps 1/6 through 5/6
        |
        |  Steps 1 to 6 finished and submitted
        v
COMPLETED
green card, Completed date shown
never returns to orange or red
```

The entire module answers one question: where is this inspection right now, and what should the inspector do next?

### 10.2 Reschedule Flow (end to end)

```
PENDING - AVAILABLE ANYTIME CARD
blue, Deadline visible, no Visit yet
        |  tap schedule button or long-press card
        v
SCHEDULE DIALOG OPENS
calendar + reminder "must be on or before <deadline>"
+ optional Notes field
        |
        |  pick date, type note, tap confirm
        v
DATE VALIDATION
date must not go past admin deadline_date
        |
        |-- past deadline --> blocked by picker, cannot confirm
        |
        v  valid date
WRITE TO SUPABASE (scheduleJob)
scheduled_date = chosen date
is_self_scheduled = true
remarks = note (if any)
status is NOT touched
        |
        v
TASK LIST RELOADS (onScheduled)
fetchMyJobs -> cache -> TaskItem
        |
        v
CATEGORY RECOMPUTED: SCHEDULED
card moves under Pending, Scheduled header
color becomes orange, Visit row appears
        |
        |  same steps again later = reschedule
        v
NEW DATE OVERWRITES OLD DATE AND NOTE
(no history kept, status still untouched)
        |
        v
...remains Scheduled while started,
then Completed after submission

If an Available Anytime task is started without a self-scheduled Visit date, it follows the separate Ongoing category instead.
```

Known limitation: this whole flow needs internet. Offline, the confirm fails with an error because no queued action exists for it yet.

### 10.3 Per-Step Save Flow (what happens on every Proceed click)

```
ANY STEP SCREEN (1 to 6)
inspector taps Continue / Save / Confirm
        |
        v
markStepComplete(step)
records current step number
AND stamps the real time (now) for that step
        |
        v
PROVIDER HOLDS THE DATA
answers, photos, checklist stay in memory
for the active task
        |
        v
PERSISTENCE (one pass, both destinations)
        |                 |
        v                 v
SQLITE                SUPABASE (if online)
local_inspections     field_jobs
current_step          current_step
step_timestamps       step_timestamps
        |                 |
        |    if offline   |
        +-------> pending_actions queue
                  drains automatically
                  when connection returns
        |
        v
NEXT STEP UNLOCKS
Task Overview shows "Saved on <real time>"
for every finished step, per task
```

Because the timestamp is written together with the step number through the same queued action, an offline proceed is never lost and never lands out of order.

### 10.4 Submission Flow

```
REVIEW AND SUBMIT SCREEN
summary rows built from Steps 1 to 5
        |
        |  inspector taps Submit Inspection
        v
submitInspection WRITE
status = 'completed'
submitted_at = now
rework_started_at = cleared
result recorded (example: Compliant)
        |
        v
TASK LIST RELOADS
leaves Pending and Ongoing buckets
enters Completed bucket ordered by submission time
        |
        v
COMPLETED CARD
green, shows "Completed: <submission date>",
Visit and Deadline rows removed
```

Scheduling metadata plays no role here. A completed task stays completed regardless of any past visit dates or deadlines.

### 10.5 Rework Flow

```
COMPLETED TASK SUMMARY
six collapsible step cards, each with a Saved indicator
        |
        |  tap "Rework this step" on one card
        v
CONFIRMATION DIALOG
explains only that step will be redone
        |  confirm
        v
ORIGINAL STEP SCREEN OPENS
saved answers preloaded, all steps unlocked
        |
        |  edit, then tap the single Save button
        v
DID ANY VALUE ACTUALLY CHANGE?
        |                         |
       yes                       no
        |                         |
        v                         v
rework_started_at set         nothing marked
"Modified" badge appears      badge stays absent
step time refreshed           summary unchanged
        |                         |
        +----------+--------------+
                   v
back on Summary, values refreshed automatically
        |
        |  inspector re-submits later via Review & Submit
        v
Modified badge cleared, new submission time recorded
```

### 10.6 Offline Queue Flow (shared by all writes)

```
ANY SAVE while OFFLINE
(step, checklist, photos, findings, GPS, submit)
        |
        v
pending_actions TABLE (SQLite)
one row per action, deduped per job
FIFO order preserved
        |
        v
CONNECTION RETURNS
        |
        v
SYNC OUTBOX DRAINS THE QUEUE
oldest first, retry on failure,
conflict checks against known good values
        |
        v
SUPABASE UPDATED
same result as if saved while online
```

### 10.7 Site Verification Architecture and Live Tracking Flow

```
STEP 1: SITE VERIFICATION OPENS (site_map_screen.dart)
load parcel coordinates from cache/DB & get initial GPS fix
        |
        v
INITIALIZE MAP & CAMERA
fit bounds to display both Target Site marker and Device marker
        |
        +-------------------------------+-------------------------------+
        |                               |                               |
        v                               v                               v
ROUTE PREVIEW SUBSYSTEM         LIVE LOCATION STREAM            AUTHORITATIVE PROXIMITY
(asynchronous, non-blocking)    LocationService.getPositionStream (initial measurement)
        |                       high accuracy, 4 m filter               |
        v                               |                               v
RouteService.fetchDrivingRoute          v                       Supabase RPC (online) /
        |                       GPS POSITION UPDATE EVENT       Haversine (offline)
        |                       (inspector moves > 4 meters)            |
        v                               |                               v
[Online & OSRM reachable?]              v                       Metric Card displays:
        |               \       UPDATE DEVICE MARKER            "Distance to Site"
       yes               no     _deviceLatLng = newPos                  |
        |                 |     setState() immediately                  |
        v                 v     (smooth, instant visual feedback)       |
Render road       Render schem-         |                               |
polyline layer;   atic fallback         v                               |
display road km   line; distance- IS DISTANCE RECALC ELIGIBLE?          |
and travel time   only readout  (!_recomputingDistance AND              |
(navigation aid)  (zero cost)   >= 4s since last calculation)           |
                                        |                   \           |
                                       yes                   no         |
                                        |                     |         |
                                        v                     v         |
                                EXECUTE RECALCULATION     SKIP RECALC   |
                                (set _recomputingDistance (marker only) |
                                 to true)                               |
                                        |                               |
                                [Device Online?]                        |
                                  /          \                          |
                                yes           no                        |
                                 |             |                        |
                                 v             v                        |
                           Supabase RPC   Haversine                     |
                           Boundary dist  Offline dist                  |
                                 |             |                        |
                                 +------+------+                        |
                                        v                               |
                                REFRESH AUTHORITATIVE <-----------------+
                                DISTANCE METRIC
                                _recomputingDistance = false
```


## Appendix A. Development Notes

### A.1 Canonical Worktree and Safety Rules

The canonical development and testing worktree is C:\Users\Ralph Lauren\imaps_fieldsync_main. All code changes, builds, and device tests happen there. The sibling worktree C:\Users\Ralph Lauren\imaps_fieldsync is protected: it holds historical WIP and agent state and must not be modified. Before any work session, verify branch and sync state first (HEAD should match origin/main; git log --oneline -1 and git status --short --branch). Nothing is staged or committed without an explicitly approved scope, and the three documentation markdown files are deliberately kept untracked unless a documentation commit is approved.

### A.2 Recent Checkpoint History

| Commit | Content |
|---|---|
| 8980cdb | fix(tasks): deadline-driven urgency, border-signal priority model, Scheduled section cleanups |
| 0cc7815 | fix(ui): land completed UI fix cycles F2, GAP-9.5, #3, #4, #5 |
| da3a7e7 | feat(inspection): record real per-step saved times (F1) |
| b52e510 | ui(dashboard): premium glossy Active Assignments folder card |
| 374654a | feat(inspection): harden site verification route preview (Route Map Phase A) |
| 9575103 | feat(inspection): add live GPS tracking to site verification (Route Map Phase B) |

### A.3 Build and Test Methodology Notes

Scoped analysis gate before any commit: flutter analyze on the touched files must report no issues. One environment quirk on this machine: the sqlite3 package native-assets hook fails when paths contain spaces (the user folder name). The no-change workaround is to invoke Flutter and pub through their 8.3 short paths, set PUB_CACHE to the short form of the existing cache, and run from the short project path. Device smoke tests are deployed with adb install -r build/app/outputs/flutter-apk/app-debug.apk, launched via adb shell monkey with applicationId com.example.imaps_fieldsync, and observed through a logcat capture during the manual pass; on-device crash evidence remains available afterwards via dumpsys dropbox and /data/anr even when the live log stream drops.
