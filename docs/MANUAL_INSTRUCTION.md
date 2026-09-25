# iMAPS:FieldSync — Manual Instruction

A simple step-by-step practical guide for MPDO field inspectors on how to use the app.

---

## 1. Login & App Access
1. Open the app on your device.
2. Enter your assigned email and passcode.
3. If logging in for the first time or after a policy update, read and tap **Acknowledge & Accept** on the Terms of Use and Privacy Policy.
4. If Biometric Login is enabled, simply tap the fingerprint/face unlock icon or scan your fingerprint to sign in quickly without typing your passcode.
5. If offline, the app uses your locally saved passcode verifier to let you in seamlessly.

## 2. Home Dashboard
- View your greeting, live time, and connectivity status at the top.
- The **Active Assignments** carousel shows your current tasks. Tap any card to open the inspection overview.
- Check the **Calendar Strip** for dates with scheduled inspections (marked with blue dots).
- Review the **Recent Activity** feed to see a history of your verified steps, saved checklists, and submissions.



## Security Measures

### Authentication Security
- Ensure that users are authenticated and authorized to access sensitive data.
- Biometric and offline login capabilities should only be available to verified users.

### Data Security
- Sensitive data must be secured via encryption (e.g., SQLite with SQLCipher).
- Ensure security measures against unauthorized access to stored data are thoroughly documented.
## 3. Tasks & Organization
Tap the **Tasks** icon in the bottom navigation bar to view all assignments.

### 3.1 Task Categories
* **Pending**: New or scheduled inspections that need attention.
  * *Scheduled*: Inspections where you picked a committed visit date.
  * *Available Anytime*: New assignments you can conduct whenever available.
* **Ongoing**: Inspections you have already opened and started working on.
* **Completed**: Submitted inspections.

### 3.2 What Task Colors Mean
* **Blue**: Normal task with plenty of time.
* **Orange**: Scheduled visit date is 2–3 days away.
* **Red Border / Due Today**: Scheduled visit date is today, tomorrow, or in the past (For Reschedule).
* **Full Red Card (Overdue)**: Admin deadline has passed. Complete immediately!
* **Green**: Completed and submitted inspection.

### 3.3 Scheduling a Visit
1. Find an unstarted task under Pending (Available Anytime).
2. Tap the calendar button or long-press the card.
3. Pick a visit date on or before the admin deadline, add an optional note, and tap confirm.
4. The task moves to the Scheduled section. (Note: Requires internet connection).


Indicator meanings:

* **Due Today**: the applicable Visit date (Scheduled) or Deadline (Available Anytime/Ongoing) is today.
* **For Reschedule**: a Scheduled Visit date has passed, but the admin Deadline has not. Reschedule the visit before the Deadline passes.
* **Overdue**: the admin Deadline has passed. The active card becomes fully red, including its container and applicant icon.
* **In Progress**: only Scheduled tasks at steps 1/6 through 5/6. Ongoing already communicates that work has started, so it has no In Progress tag.

Tap the single `!` beside the applicant name for card-level help. The popup may explain several current indicators together, but it does not repeat tags or show historical urgency on a Completed task.

### 3.4 Scheduling a Visit (Reschedule Inspection Date)

1. Find your task under Pending, Available Anytime.
2. Tap the schedule button on the card. You can also press and hold the card.
3. A modal will appear with a calendar for picking a date, a reminder like "Must be on or before 2026-08-31 (deadline set by admin)", and an optional Notes field.
4. Pick your visit date. Dates after the admin deadline are not selectable.
5. Type a short note if needed (example: "Visit in the morning").
6. Tap the confirm button.
7. The task will move to Pending, Scheduled and show both Visit and Deadline.
8. The card will now show your **Visit** date beside the **Deadline**.

You can reschedule again anytime before finishing. Just repeat the same steps. The new date replaces the old one, so always double check before confirming.

### 3.5 Starting an Inspection

1. Open the task you want to work on (Scheduled or Available Anytime).
2. The Task Overview screen appears.
3. It shows the step counter starting at **0 of 6**, plus these parts:
   * **Inspection Protocols**: the six inspection steps.
   * **Photos**: photo evidence collected so far.
   * **Application Details**: applicant info, classification, land use focus, and contact buttons.
4. Opening an Available Anytime task and saving progress moves it to Ongoing. Opening a Scheduled task keeps it in Scheduled.
5. A Scheduled task may show **In Progress** only from step 1/6 through step 5/6. It does not show that tag at 6/6, and Ongoing tasks never show it.

### 3.6 The Six Inspection Steps

Do the steps in order. Each step saves your progress, so you can close the app and continue later.

**Step 1: Site Verification**
A map screen opens with the title "Site Verification" and the task location.
* **Markers on the Map:** You will see a red pin labeled **Target Site** marking the parcel boundary, and a blue marker for your current location ("You are here").
* **Live GPS Tracking:** As you walk or drive toward the site, the blue location marker moves with you on the map in real time, and the distance shown in the summary card automatically refreshes.
* **Road Route (Online):** When your phone has an active internet connection, a blue route line along actual roads appears between your location and the target site after the map has already become usable. The card can also show the road distance and estimated driving time, but this is only a route-guidance view.
* **Route Refresh While Moving:** As you move far enough from the position used for the current route, the app may refresh the road route. Refreshing is controlled so it does not request a new route for every GPS update. The route may remain unchanged briefly while the refresh movement and cooldown conditions are met.
* **Authoritative Distance vs Route Distance:** The app keeps two separate measurements. The **authoritative Site Verification distance** is the direct distance between your location and the parcel boundary. This is the number used to decide whether the site has been verified. The **road-route distance** is only for route guidance and navigation context, not the verification result.
* **Offline Guidance:** Without an internet connection, your live GPS marker still moves and shows your direct distance to the site, along with a straight schematic guideline. Fresh road routes cannot be drawn offline, and map tiles may remain blank unless they were already loaded previously.
* **Arrival Indicator:** When the displayed distance reaches 30 meters or less, the app shows **Arrived at Site**. This is an informational proximity state; the app does not automatically advance to Step 2. Tap **Confirm Site Location** yourself to continue.
* **Offline Arrival:** With GPS available, the arrival indicator can still work without internet using a best-effort local distance estimate. This estimate is not identical to the online spatial-distance measurement.
* **Next Action:** Use this screen to confirm you have arrived near the designated parcel, then tap **Confirm Site Location** to proceed to Step 2.

**Step 2: GPS Verification**
This screen checks that you are physically at the site.
* It shows your live position, your distance to the parcel, and a compass bearing pointing to it (example: NE 45).
* A badge shows "LIVE TRACKING" while your location updates in real time.
* The app measures how far you are from the parcel boundary. You are verified when you are within **30 meters** or closer.
* Once verified, confirm your check-in. Your coordinates and accuracy are recorded. If there is no signal, the check-in is saved offline and synced later.

**Step 3: Photographic Evidence**
1. Tap to open the camera.
2. Take a photo of the site. The app automatically embeds geotag details (coordinates and time) into the photo file itself.
3. Add an optional inspection note for the photo.
4. Tap Save. The photo appears in the step with its note and coordinates shown as text (like "14.123456, 121.654321").
5. You can remove a photo before continuing if needed.
6. Saved photos also appear in the Photos section of the Task Overview.

**Step 4: Zoning Checklist**
Tick each checklist item that passes. A live counter shows how many items are checked, like "3 of 5 checked". Every tap saves automatically.

**Step 5: Field Findings**
Fill in the following text boxes:
* Observations: describe what you saw on site, such as structure condition, land use, or notable features.
* Discrepancies: add an issue title (leave blank if none found) plus a short detail line about the location or problem.
* Recommendation: suggest next actions, like required permits or follow-up visits.

**Step 6: Review and Submit**
Check the summary of all your answers from Steps 1 to 5. If everything is correct, tap Submit Inspection. A success message appears and the inspection is recorded with its result, such as Compliant.


### 3.7 After Submission

1. The task leaves Pending and Ongoing.
2. It appears under the **Completed** tab.
3. The card turns green and shows the completion date.
4. You can open it anytime to review the full inspection record.
5. **Ordering (newest-first / LIFO):** the Completed list always shows your most recently finished inspection as the FIRST card. The longer ago you submitted a task, the farther down the list it sits.

### 3.8 Reworking a Completed Step

Sometimes you need to correct one step after submission. You do not need to redo everything.

1. Open the completed task.
2. Expand the step card you want to fix.
3. Tap **Rework this step**.
4. A confirmation message appears explaining that only that step needs to be done again. Confirm it.
5. The original screen for that step opens with your saved answers loaded.
6. Make your correction and tap Save.
7. You return to the summary and the updated values appear right away.

About the **Modified** tag:

* It appears only when you actually changed something during rework.
* Opening a step and backing out without edits will not trigger it.
* While the Modified tag is showing, a **Last saved** time tells you when the latest change was stored.
* Submitting the reworked inspection clears the Modified tag.

### 3.9 Filtering Tasks

Tap the filter icon beside the search bar to open Filter and Sort. Under **Filter by Urgency** you can choose:

* **All**: no urgency filter.
* **Urgent**: active tasks due today or tomorrow according to their applicable date.
* **Scheduled**: tasks with a saved visit date.
* **Overdue**: active tasks whose admin deadline has already passed.

Urgent and Overdue do not overlap — a task counted in one is never counted in the other.

You can also filter by date range and barangay, and search by name, location, or inspection number.

The **Completed** tab contains submitted inspections. Open one to review the saved inspection. If a correction is needed, choose **Rework this step**, edit the step, and save. The **Modified** indicator appears only after a real change and disappears after the revised inspection is submitted.

---

## Planned Improvements

These are noted for future development:

* Offline scheduling support.
* Real per-step saved times are now implemented: every finished step records its real save time.
* Offline map view: the map picture itself currently needs internet; showing the roads without a connection requires a separate offline map solution.
* Turn-by-turn navigation, voice guidance, maneuver instructions, map matching, navigation sessions, route caching, offline road routing, offline basemap tile packs, self-hosted OSRM, additional providers, and camera auto-follow are outside the current Site Verification scope.
