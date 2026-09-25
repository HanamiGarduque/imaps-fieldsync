# My Tasks — Status, Color, Tag & Filter Design Spec

**Purpose:** Reference doc for manual testing and implementation of the "My Tasks" screen (site inspection task tracking). This is the finalized logic from the design review — use it as a checklist against the current implementation.

---

## 1. Top-Level Categories

3 mutually exclusive categories: **Pending → Ongoing → Completed**

### Pending has 2 subgroups:
- **Available Anytime** — default landing spot for a new task. Has only a **Deadline** (admin-set), no Visit date.
- **Scheduled** — has both a **Visit date** (inspector-set) AND a **Deadline** (admin-set).

---

## 2. Flow (2 paths to Completed)

```
Available Anytime
  ├─ (set/resched Visit date) → SCHEDULED
  │                                └─ stays here until Completed
  │                                └─ even once started (gets "In Progress" tag),
  │                                   it does NOT move to the Ongoing category
  │
  └─ (start steps 1-2, no schedule set) → ONGOING → Completed
```

⚠️ **Ongoing tasks never have a Visit date** — they only ever come from an Available Anytime task that was started directly.

**Calendar rule:** a Visit date already taken by another task should be blocked/warned against — no double-booking.

---

## 3. Border & Tag Logic per Section

### 📌 Scheduled (under Pending)
| Element | Based on | Trigger |
|---|---|---|
| Border **Red** | **Visit** date | 1 day left, or the visit day itself |
| Border **Orange** | **Visit** date | 2–3 days out |
| Border **Blue** | Visit date | still far off (default/normal) |
| Tag **Due Today** | Visit date | visit == today |
| Tag **For Reschedule** *(new)* | Visit date vs Deadline | Visit date has passed, but Deadline hasn't yet |
| Tag **Overdue** | **Deadline** date | deadline < today, not yet completed |
| Tag **In Progress** | manual status | task has been started |

**Key rule:** once the Visit date passes without action, the border **stays Red** — it does not fall back to Orange/Blue — all the way until the task becomes Overdue. Purpose: keep the urgency visible as a reminder to reschedule.

**Reset rule:** rescheduling a task (new Visit date) resets the border back to **Blue** — a fresh window, with no carry-over from the previous miss.

**"For Reschedule" tag:** appears between Due Today and Overdue. Comes with an alert/notice on the card with a Reschedule action button — e.g.: *"The visit date you set has passed. Reschedule now to avoid this becoming overdue."*

### 📌 Available Anytime (under Pending)
| Element | Based on |
|---|---|
| Border **Blue** | default/normal |
| Tag **Overdue / Due Today** | directly on the **Deadline** date (no Visit date exists yet) |

### 📌 Ongoing
| Element | Based on |
|---|---|
| Border **Blue** | normal |
| Tags | **Overdue, Due Today only** — no "In Progress" or "Ongoing"  (redundant, since the category itself already signals that) |

**Overdue override:** when any active task has an **Overdue** tag, the entire task card uses the red overdue container treatment, including a red border and red applicant initials/icon. This full red container rule overrides the normal blue Ongoing border and any scheduled visit-border color. The blue border rule applies only while the task is not overdue.

### 📌 Completed
| Element | Based on |
|---|---|
| Border **Green** | completed |
| Tag **Completed** | default |
| Tag **Modified** (orange) | if edited after being marked complete |

---

## 4. Dashboard Widget: "Task Completion Flow"

This is a **tally/count only**, not a pipeline. 4 buckets, mutually exclusive, should sum to the total:

```
Scheduled + Pending + Ongoing + Completed = Total Tasks
```

⚠️ **In this widget only**, "Pending" refers to the **Available Anytime subgroup only**. The Scheduled subgroup gets its own bucket here — this avoids double-counting. In the task list view itself, Scheduled still stays nested under the Pending category.

**Overdue** is **not** one of the 4 main buckets (it's cross-cutting across Pending/Ongoing, so it would double-count). Instead, show it as a **separate badge/reminder inside the widget container**, not next to the 4 main labels — e.g. a small "⚠️ 4 overdue" strip.

---

## 5. Urgency Filter

| Filter | Based on | Where it shows |
|---|---|---|
| **Urgent** | Due Today tag | Scheduled, Available Anytime, Ongoing |
| **Overdue** | Overdue tag | Scheduled, Available Anytime, Ongoing |
| **Scheduled** | Has a Visit date set | Pending (Scheduled subgroup) + Completed (not Ongoing, since Ongoing tasks never have a Visit date) |

Note: "For Reschedule" tasks are already covered by the "Scheduled" filter (still Scheduled, just with a passed Visit date) — no separate filter chip needed.

---

## 6. Final Verified UI Behavior

Manual device testing passed for the current My Tasks behavior:
- Ongoing = **Blue** border, no "In Progress" or "Ongoing" tag.
- Scheduled = visit-driven border, and may show "In Progress" only at steps 1/6 through 5/6.
- Active overdue tasks use the full red treatment: container, border, applicant initials/icon, and progress indicator.
- Completed tasks remain green and do not inherit historical urgency details.
- Each card has one standalone `!` trigger whose popup lists only indicators currently present on that card.
- Each card renders one `Overdue` tag when applicable; the popup does not render duplicate tags.

---

## 7. Implementation Record

The implementation decisions below are complete and verified against manual device testing:

### Fix 1 — Scheduled tasks still appear in the Ongoing tab (line 801–848)
An existing `ScheduledActive` bucket in `_categorizeAndFilter()` deliberately shows a started Scheduled task in **both** the Pending→Scheduled section AND the Ongoing tab (comment says "validated: show in both" — a prior design decision, predating this new spec).
**Verified result:** Scheduled tasks stay only in Pending→Scheduled, never appearing in the Ongoing tab even once started. A started Scheduled task may show the "In Progress" tag inside its Scheduled card.

### Fix 2 — Border urgency (Red/Orange) is Deadline-based, should be Visit-based (line 254–265, used at line 1647)
`isUrgentDeadline` reads `deadlineDate` to determine urgency (≤1 day away).
**Verified result:** scheduled border urgency uses `scheduledDate` (Visit date): Red when 1 day remains, on the visit day, or after it; Orange when 2–3 days out; Blue otherwise.

### Fix 3 — "Overdue" tag is Visit-based, should be Deadline-based (line 214–227)
`scheduleUrgency` uses `scheduledDate` (Visit) for BOTH "Due today" and "Overdue".
**Verified result:** "Due Today" stays Visit-based; "Overdue" is Deadline-based (`deadlineDate` < today).

### Fix 4 — No "For Reschedule" tag/state exists
There's no logic yet for the new 4th tag that appears once the Visit date has passed but the Deadline hasn't.
**Verified result:** `For Reschedule` appears when the Visit date has passed but the Deadline has not, with the reschedule action available.

### Fix 5 — `_getStatusColor()` Scheduled is always Orange, not variable (line 1408–1413)
The avatar/step-bar color doesn't change based on proximity to the Visit date.
**Verified result:** the Scheduled avatar and progress color follow the Visit-date urgency: Blue, Orange, or Red.

---

## 7b. Resolved Category Regression

The earlier regression in which non-completed tasks were all classified as Scheduled is resolved and was verified with the category regression test and manual device testing.

Because `scheduled_date` is non-nullable in the database, it is not used to determine category membership. `is_self_scheduled` is the category switch.

**Verified category derivation:**
- `status == 'completed'` → Completed
- `is_self_scheduled == true` → Scheduled (regardless of status)
- `is_self_scheduled == false && status == 'in_progress'` → Ongoing
- `is_self_scheduled == false && status == 'assigned'` → Pending (Available Anytime)

---

## 8. Readability Consideration (35+ inspectors)
- Consistent phrasing/wording — don't swap terms for the same concept

---

## 9. Info Icon (Contextual Help)

To directly address the readability concern in Section 8, add a small tappable **"!" circle icon** next to button of the profile icon or beside of the applicant name. Tapping it opens a small popup/card with a short (1–2 sentence) plain-language explanation of what that specific indicator means — no need to search for a separate legend.

**Placement:** ⚠️ **Do NOT place the "!" icon directly beside a tag** (e.g. next to "Overdue") — confirmed via testing that this visually reads as a second, duplicate tag (looks like two "Overdue" badges stacked together), which is more confusing, not less. Instead, place it near the inspector's avatar/initials box, or beside the assignment name/title — close enough to the card to feel attached to it, but visually separate from the tag row itself.

**Contextual-state rule:** the popup lists only indicators currently present on the card. Completed tasks must not show Due Today, For Reschedule, or Overdue explanations, even if historical date fields are past. An active Overdue task shows the **Container: Red** and Overdue explanations; no urgency explanation is shown for a completed task without that tag.

INTENDED BEHAVIOR

The ! icon is a contextual explanation mechanism for the entire task card.

For example, if a task currently has:

Red border
Overdue tag
In Progress tag

there should still be ONLY ONE ! icon on that task card.

When the user taps it, open a small popup/card containing only the explanations relevant to the indicators currently present on that specific task.

Example:

!
────────────────────────
Overdue
The deadline given by admin has passed.
This needs immediate attention.

In Progress
You've already started working on this task.

Red
Your visit date is today, tomorrow, or has
already passed.
────────────────────────

Do NOT show explanations for indicators that are not currently present.

IMPORTANT PLACEMENT

Follow the latest Section 9 rule:

Do NOT place the ! directly beside any tag.

It should be positioned near:

the inspector/profile avatar or initials box, OR
the assignment name/title

It should visually belong to the task card while remaining clearly separate from the tag row.

There must be one info icon per task card, regardless of how many tags/indicators the task has.

CONTEXTUAL CONTENT

Use the existing approved explanations exactly:

Indicator	Explanation
Available Anytime	"This task has no set visit date yet. You can do it anytime before the deadline."
Scheduled	"You've set a visit date for this task. It will stay here until completed."
Border: Blue	"Normal — no urgent action needed yet."
Border: Orange	"Your visit date is coming up in 2–3 days."
Border: Red	"Your visit date is today, tomorrow, or has already passed."
Due Today	"Your visit date is today."
For Reschedule	"You missed your visit date. Reschedule now before this becomes overdue."
Overdue	"The deadline given by admin has passed. This needs immediate attention."
In Progress	"You've already started working on this task."
Ongoing	"This task is currently being worked on, without a fixed visit date."
Completed	"This task has been finished and submitted."
Modified	"This completed task was edited after submission."
HOW TO BUILD THE POPUP CONTENT

Do not hard-code one generic explanation for every card.

The popup must be generated from the actual state of the task card.

For each task, determine which applicable indicators are currently present and build the explanation list dynamically.

For example:

Example A

Task:

Scheduled
Red border
Due Today

Popup should contain explanations for:

Scheduled
Red
Due Today

Nothing else.

Example B

Task:

Ongoing
Blue border

Popup should contain:

Ongoing
Blue

Nothing else.

Example C

Task:

Scheduled
Orange border
In Progress

Popup should contain:

Scheduled
Orange
In Progress
Example D

Task:

Completed
Modified

Popup should contain:

Completed
Modified
PRIORITY / DUPLICATION RULE

Avoid redundant explanations where the same underlying condition is already represented.

However, preserve the existing approved indicator semantics.

The goal is:

one icon → one contextual explanation panel → multiple relevant explanations

NOT:

one tag → one icon

UI REQUIREMENTS

Keep the existing task card design.

Do not redesign the card.

Do not add a separate legend.

Do not add another button.

Do not add another ! for each tag.

Do not move or remove existing tags.

Do not change the status/category semantics.

Do not change the border/color logic.

Only change the info/help mechanism so that it becomes a single contextual info icon per task card.

Use the existing app theme/tokens and existing popup/modal patterns where possible. Do not introduce arbitrary new colors or design tokens.
---

## 10. Naming Map (for the implementing AI)

**Rule: reuse existing identifiers below. Do not create new/duplicate fields for concepts that already exist in the code — only "For Reschedule" is genuinely new.**

| Spec Term | Existing Code Identifier | Action |
|---|---|---|
| Visit date | `TaskItem.scheduledDate` | Reuse as-is |
| Deadline | `TaskItem.deadlineDate` | Reuse as-is |
| Pending category | `category == 'Pending'` (getter, `tasks_screen.dart` line 185) | Reuse as-is |
| Scheduled category | `category == 'Scheduled'` | Reuse as-is |
| Ongoing category | `category == 'Ongoing'` | Reuse as-is |
| Completed category | `category == 'Completed'` | Reuse as-is |
| Red/Orange border trigger | `TaskItem.isUrgentDeadline` | Verified: Scheduled visit-date urgency drives the Scheduled border; active Overdue overrides the card with the full red treatment |
| Due Today / Overdue tag | `TaskItem.scheduleUrgency` | Verified: Due Today is Visit-based and Overdue is Deadline-based inside this same getter |
| "In Progress" tag | task-card badge condition | Verified: only `category == 'Scheduled'` with `currentStep` 1 through 5; absent from Ongoing |
| Scheduled shown in Ongoing tab | `_categorizeAndFilter()` | Verified: Scheduled tasks are not duplicated into the Ongoing tab |
| Dashboard widget counts | `_completionCounts` in `home_dashboard_screen.dart` | Four mutually exclusive buckets: Scheduled, Pending, Ongoing, and Completed; Overdue is a separate reminder |
| "For Reschedule" tag | none | Genuinely new — add as a new computed property, following the existing `scheduleUrgency` pattern |


---

## 11. Real Database Schema (ground truth, from Supabase `inspections` table)

Confirmed against the actual table structure and a real data sample:

| Field | Type | Notes |
|---|---|---|
| `status` | varchar, non-nullable | Only 3 raw values exist in practice: `assigned`, `in_progress`, `completed`. There is no raw "Scheduled" or "Pending" status in the database — those are **derived/computed at the app layer**, not stored directly. |
| `scheduled_date` | date, **non-nullable** | Always has a value for every task — this is NOT what determines "Scheduled" category membership. Corresponds to the app's "Visit" date. |
| `is_self_scheduled` | bool, non-nullable | **This is the true switch for Scheduled category membership** — true means the inspector deliberately picked/committed to this date; false means it's just a default/placeholder value, not a real commitment. |
| `deadline_date` | date, nullable | Corresponds to "Deadline" in the app. |
| `current_step` / `started_at` | int4 / timestamptz | Used to derive "In Progress" state and step progress (Step X/6). |
| `rework_started_at` | timestamptz, nullable | A completed task can be reopened for rework — relevant to the "Modified" tag on Completed cards (Section 3). |

**Final verified category derivation:** a task's app-level category is derived as:
- `status == 'completed'` → **Completed**
- `is_self_scheduled == true` → **Scheduled** (regardless of `status`, per the Fix 1 decision in Section 7 — Scheduled always wins over In Progress)
- `is_self_scheduled == false && status == 'in_progress'` → **Ongoing**
- `is_self_scheduled == false && status == 'assigned'` → **Pending (Available Anytime)**

**Verification result:** the real sample records with `is_self_scheduled: false` and `status: in_progress` (including local inspection IDs 503, 501, 604, 23, 502, 803, 22, and 509) are classified as **Ongoing**, not Scheduled.