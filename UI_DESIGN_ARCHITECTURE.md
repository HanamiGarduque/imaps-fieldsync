# UI DESIGN ARCHITECTURE STANDARD (UDAS)
### InSight / iMAPS FieldSync — Frontend UI/UX Governing Document
**Version:** 1.1 — user-directed composition update, 2026-10-09
**Owner / Master:** rlo.tot
**Status:** ACTIVE
**Applies to:** All UI/UX enhancement work across all screens and modules of the Flutter application.

---

## 0. PURPOSE

This document is the single source of truth for how UI/UX work is done on InSight / iMAPS FieldSync. It is **tool-agnostic** — it applies identically whether the working agent is a chat-based AI (Claude, ChatGPT) or an IDE-embedded coding agent with direct filesystem/git access (Cursor, Antigravity, GitHub Copilot, or any other). Multiple different tools and accounts may be used interchangeably across sessions depending on availability; this document must never need to be re-explained to whichever one is used. Every AI agent assigned to a UI task must read this document in full before writing a roadmap, before touching any file, and before generating any code.

**Note on heuristics vs. rules:** most of the guidance below is a strong default, not an absolute technical prohibition. When a heuristic in this document would conflict with actual usability, accessibility, or an already-established pattern in this specific app, the existing app's real behavior wins — flag the conflict in the roadmap/report rather than forcing the heuristic. The exceptions are rules explicitly marked as hard/non-negotiable (theme lock, UI-only scope, confirmation on destructive actions, empty-state requirement) — those apply without exception.

This document does NOT replace the existing migration governance (MAS → MMS → MMP → Migration Execution → Verification Report). It is a **parallel standard specific to UI/UX enhancement work**, and it inherits the same discipline: no unilateral decisions, roadmap before code, evidence before claims.

---

## 1. NATURE OF THIS WORK: ENHANCEMENT, NOT NEW BUILD

This is critical and overrides any instinct to redesign from scratch:

- The app **already has a working UI/frontend design.** This work is **enhancement and cleanup**, not a rebuild.
- A **theme already exists in the repo** (colors, typography, spacing — wherever it's defined, e.g. `ThemeData`, a `theme/` or `constants/` directory, or similar). **Every agent must locate and reuse the existing theme.** Do not invent new colors, new type scales, or new spacing values. If a needed token doesn't exist in the current theme, flag it to Master — do not silently add a one-off value.
- **Audit before you touch anything.** Every agent's roadmap must start with a short audit of the assigned screen: what theme tokens it currently uses (or fails to use — e.g. hardcoded colors that should reference the theme), what widgets it reuses vs. duplicates, and what's already consistent with other screens vs. what's drifted.
- **Consistency over novelty.** If another screen in the app has already established a pattern (e.g. how empty states look, how a status timeline is built, how a bottom sheet is styled), **reuse that pattern.** Do not invent a new visual treatment for the same type of problem just because it's a different screen. When no existing pattern is found for a given problem, propose one in the roadmap and flag it as a new pattern for Master's approval — new patterns are decisions, not defaults.
- **Guiding philosophy: clean and low cognitive load.** When more than one valid approach exists, prefer the one with fewer elements, clearer hierarchy, and less simultaneous information on screen. This applies to every section below — it is the tiebreaker whenever a rule doesn't fully resolve a design decision.

---

## 2. TARGET USER & DEVICE PROFILE

This section exists because it directly overrides generic "modern minimal UI" trends when they conflict with real usability for this specific audience. Every design decision in this document is filtered through this profile.

### 2.1 Who uses this app
- **Field inspectors, roughly age 35–45.** Not a young, highly tech-fluent demographic by default — don't assume comfort with subtle gestures, hidden menus, or trend-driven micro-interactions that require discovery.
- **Used on-site**, not in an office — inspectors are walking a site, possibly under time pressure, possibly distracted, possibly outdoors in direct sunlight, possibly wearing gloves or otherwise not making precise taps.
- **Presbyopia consideration:** in the 35–45 range, near-vision sharpness is already starting to decline for a meaningful portion of users. Combined with outdoor glare, this means text and tap targets need real headroom above typical "modern app" minimums — not just the bare 44px floor.

### 2.2 What device they're likely using
- **Device ownership is unknown/mixed** — could be a company-provided phone or the inspector's own personal phone. Do not assume a recent flagship device.
- **Assume mid-range or lower-mid-range Android as the baseline**, not the newest hardware. This means:
  - Avoid heavy shader-based effects, large particle animations, or anything that could visibly stutter on modest hardware.
  - Keep image assets optimized (compressed, appropriately sized) rather than shipping large hi-res source images.
  - Avoid depending on the newest OS-level features that may not exist on older Android versions still in use.
  - Test/design assumptions should target "acceptable performance on a modest device," not "looks best on the newest phone."
- **Network conditions on-site may be inconsistent.** Field inspection sites are not guaranteed to have reliable signal. Any UI that implies real-time/always-online behavior must also gracefully communicate offline/syncing/pending states — this is a UX requirement, not just a technical one (see §5.7-equivalent empty/status states, and sync indicators specifically).

### 2.3 Concrete design consequences (binding, not optional)
- **Type size:** favor the larger end of any reasonable range; don't default to trendy small/light body text. Prioritize legibility over visual minimalism.
- **Contrast:** favor high-contrast color/text combinations over subtle low-contrast "modern" gray-on-white or gray-on-gray patterns — outdoor sunlight glare and age-related contrast sensitivity both push in the same direction.
- **Touch targets:** treat 44px as the absolute floor, not the target — primary/frequent actions should lean larger where layout allows, accounting for imprecise taps (gloves, sun glare, walking/standing).
- **Never gesture-only for anything important.** Swipe, long-press, and similar gestures may supplement an action but must never be the *only* way to perform it — always provide a visible, labeled button/tap alternative. This audience should never need to "discover" a hidden gesture to complete a task.
- **Offline/sync status must be visible and unambiguous.** If a screen's data depends on connectivity, show a clear state (syncing / synced / offline — pending) rather than letting the user guess whether their work was saved.
- **Icons always paired with text labels** (already a rule in §8/§9 — reinforced here specifically because icon-only nav assumes a level of app fluency this audience may not have).
- **Avoid clutter and cleverness for its own sake.** When choosing between a "cleaner/trendier" pattern and a "more obvious/more explicit" pattern, prefer the more obvious one for this app, even if it looks slightly less cutting-edge. This directly reinforces the cognitive-load principle in §1 — for this audience, obvious beats clever.

---

## 3. GOVERNANCE HIERARCHY (UI TRACK)

```
UDAS (this document, fixed)
   ↓
UI Enhancement Prompt (per screen/module — issued by Master)
   ↓
Agent Roadmap (produced by agent, must be approved before code)
   ↓
Implementation (UI layer only)
   ↓
Verification Report (back to Master)
```

- rlo.tot ("Master") is the sole authority on architectural and design-direction decisions.
- Any agent working on UI must produce a **roadmap before writing code** — this is a confirmed working practice inherited from the module audit phase.
- Cross-screen or cross-module design decisions (e.g., a shared navigation shell, a global design token change) are **never decided unilaterally** by an agent. These are deferred back to Master, same principle as cross-module import paths in the backend migration.
- Agents report back using the same four-label discipline already established: **PASS / REGRESSION / PRE-EXISTING ISSUE / IMPROVEMENT OPPORTUNITY** — applied here to UI/UX findings (e.g., a screen that was already inconsistent before the agent touched it is a PRE-EXISTING ISSUE, not something the agent broke).

---

## 4. SCOPE BOUNDARIES

- **UI-layer only.** Agents working under this document do not modify business logic, service classes, Supabase calls, or state logic beyond what's needed to wire a widget to existing Provider state. If a screen's problem is actually a data/logic problem, STOP and flag it — do not silently "fix" it.
- **Shared core widgets are read-only** unless a specific prompt explicitly scopes them for editing. Don't refactor a shared button/card component because one screen would look better with a tweaked version — flag it as a proposal instead.
- **Grep before fully reading.** For large screen files that mix UI and logic, use targeted reads before opening the whole file.
- **No unauthorized structural renames.** Folder/file placement follows whatever the current layered-architecture naming convention is (see project memory — this is still being finalized). If unsure, ask; don't invent a new folder pattern.

---

## 5. MOBILE UI FOUNDATIONS
*(Source: mobile-first design fundamentals — applies to every screen in the app)*

### 3.1 Navigation
- Bottom navigation bar with **3–4 items ideally, 5 as a hard ceiling**.
- All tappable targets maintain a **minimum 44px touch target** (fat-finger rule).
- If there are too many top-level destinations to fit a bottom bar, convert the "extra" links into a dedicated home/hub screen instead of cramming the bar.
- Navigation/actions are **contextual** — they can and should change depending on what screen the user is in. Don't force one static action set everywhere.

### 3.2 Scale & Type
- Mobile does **not** mean shrink everything. Type size and spacing on mobile are often equal to or *larger* than desktop equivalents (reference: iOS base font ~17px vs macOS ~13px).
- When adapting a desktop/dashboard-style layout, resist the urge to cram every panel onto one mobile screen. Pick the single most important piece of content per screen.

### 3.3 Content Layout
- **Default heuristic:** on mobile, a content *section* typically extends in one direction only — either vertical stack or horizontal scroll — rather than a two-axis desktop dashboard grid. This is a strong default, not an absolute rule: a vertically scrolling page legitimately containing a horizontally scrolling subsection (e.g. a horizontal chip/filter row inside a vertical list) is fine. What to avoid is recreating true two-axis desktop grid density on a single mobile screen.
- The four building blocks of any screen: **cards, text/links, images, inputs.** Everything else is a composition of these four.
- **Avoid double-nested cards** (card inside a card). It compounds padding and cramps content. Prefer whitespace-based grouping over nested containers when possible.

### 3.4 One Screen, One Job
- Every screen (except an intentional dashboard/home screen) does exactly **one thing**. A settings screen is only settings. An inspection form is only the inspection form. Don't bolt on "recent items" or "suggested actions" to a focused task screen.
- When a secondary action is needed without breaking context (e.g., picking a template while editing), use a **bottom sheet**, not a full page navigation.

### 3.5 Gestures
- Swipe-right-to-go-back should feel physically connected (background shifts ~35% and animates back in) — not an abrupt cut.
- Swipe-down should dismiss bottom sheets with a matching zoom/scale motion on the background.
- Long-press is the mobile equivalent of right-click — use it for contextual actions, paired with a subtle zoom/blur treatment.
- Every gesture must be discoverable or hinted — never rely on a gesture the user has no way of learning.

### 3.6 Dynamic, Contextual Actions
- Top bars and action sets are not static — they change based on what the user is doing (e.g., entering an inspection detail screen should hide the main nav and reveal task-specific actions like save/submit/sync).
- Reduce action clutter to only what's relevant to the current context (e.g., a bottom sheet for template/photo selection should only show a confirm and a close — nothing else).

### 3.7 Empty States (Mandatory for every list/data screen)
- **First-use empty state:** full-screen, guides the user toward the primary action (e.g., "Start your first inspection" pointing at the FAB), not a wall of instructional cards.
- **No-results empty state** (e.g., search/filter with zero matches): acknowledge the empty result, show light imagery, and offer a recovery action (clear filters, check spelling, browse all).
- Every screen that can show zero items must have both states designed — this is not optional polish, it's a required state.

---

## 6. BEHAVIORAL & PSYCHOLOGICAL PRINCIPLES

Apply these where the interaction genuinely benefits from them — not decoration for its own sake, and never at the expense of clarity, accessibility, or an already-established pattern elsewhere in the app.

| Principle | Application in FieldSync |
|---|---|
| **Personalization by user stage** | New field inspector → onboarding-first UI. Repeat user → routine/shortcut-first UI (recent sites, recent forms). Power user (senior inspector/supervisor) → stats, batch actions, optimization tools. Don't show the same home screen to all three. |
| **Smart search** | Never a blank search bar. Pre-populate with recent searches (recent site/report lookups), frequent items, and role-relevant suggestions. |
| **Visual status tracking** | For inspection/report status (draft → submitted → reviewed → approved), use a visual timeline/stepper instead of a raw status label or table row. Reduces "is my report actually submitted?" anxiety. |
| **Consistent categorized screens** | Inspection types, site categories, etc. use a unified color-coded system with consistent icon style — not a mismatched icon grab-bag. |
| **Input matched to frequency** | One-time/low-frequency setup fields (e.g., profile height, one-time config) → slider or picker. Frequent/precise/repetitive fields (e.g., logging readings, entering measurements) → text field with stepper, not a slider. |
| **Smart defaults** | Pre-fill forms with the most common/likely choice (last used site, current date, logged-in inspector) to cut decision fatigue. |
| **Goal Gradient Effect** | Never show a progress indicator starting at 0%. If a multi-step form has any known context (e.g., site pre-selected), start the progress bar reflecting that. |
| **Reciprocity** | Give the user something useful before asking for input/signup — e.g., show a preview of what a completed inspection report looks like before requiring full registration. |
| **IKEA Effect** | Where relevant, let users customize/build (e.g., custom checklist ordering, saved templates) — user-built structures feel more "theirs" and get used more. |
| **Loss Aversion** | Frame risky/destructive actions in terms of what's lost ("This will discard your unsaved photos") rather than neutral phrasing. |
| **Contrast Effect** | When presenting tiers/options (e.g., sync frequency, storage plan if applicable), the ordering and anchor value shown first influences how the rest are perceived — sequence deliberately. |

---

## 7. CRAFT & DELIGHT DETAILS

- **Animation:** Break complex transitions into smaller steps rather than one big animated jump — this reads as more premium and is easier for the agent to actually implement correctly.
- **Illustrations for empty/error states:** Prefer a custom illustration or simple mascot over plain text for empty states, where feasible within existing asset budget. Flag to Master if new illustration assets are needed — do not fabricate/hotlink external art.
- **Haptic feedback:** Use subtle haptics to confirm key actions (submit, sync success, delete confirm) where the platform/package already supports it. Do not add a new haptics dependency without flagging it.
- **Icon consistency:** Use one consistent icon family/style throughout. Distinguish active/inactive states with weight (thin vs. filled) rather than introducing a second icon set.

---

## 8. MICRO-UI RULES (Component-Level)
*(Full checklist — source: uidesign.tips/ui-tips. Every applicable item must be checked per screen. If an item genuinely doesn't apply to a given screen, that's fine — just don't skip the check.)*

### Buttons & CTAs
- One primary CTA per screen/section. Don't mix multiple button styles for equivalent-weight actions.
- Use consistent button styling and copy throughout — especially avoid inconsistent buttons within the same header/top area of a screen.
- Prefer an actual button over a bare text link when the action isn't inside a header, footer, or article body — links alone are easy to miss and low-affordance.
- Button copy should be actionable and specific ("Save Inspection", not "Submit" or "OK").
- Never let the user guess what happens next — a vague action label (e.g. a bare "Reserve"/"Confirm") creates hesitation. State clearly what the action does.

### Dangerous / Destructive Actions
- Visually de-emphasize dangerous actions (delete, discard, logout-everywhere) relative to the safe/default action, using more than one differentiator (color + size + placement) — never rely on color alone (accessibility).
- Deletion always requires confirmation — inline or modal — with a specific action-labeled button ("Delete Report", never a bare "Yes"/"No").
- Where feasible, offer an undo instead of (or in addition to) a confirmation dialog.
- Frame the risk in terms of what's lost ("This will discard your unsaved photos") — loss aversion applies here too (see §6).

### Layout, Alignment & Hierarchy
- Alignment of uneven-size elements: normalize to the width of the largest element instead of leaving ragged edges.
- Visual hierarchy hacks to use deliberately: reduce opacity of secondary info, bold weight for emphasis, a fixed type-scale ratio for headers (e.g. ×1.25) rather than arbitrary sizes, left-alignment for LTR readability, and grouping related elements physically closer together.
- A good header/title block: strong weight on the title, a consistent scale ratio down to the subtitle, lower contrast for the subtitle, proper line-height on body copy, left-aligned.
- Prefer whitespace over dividers to separate related groups; use dividers only between clearly distinct sections, not everywhere — too many dividers reads as visual noise.
- Cap paragraph/body text width for readability (roughly 500–700px equivalent / limited character count per line) — don't let body copy run full-bleed edge to edge.
- Users' eyes travel top-left to bottom-right in a Z-pattern (Gutenberg principle) — place the primary action at the natural end of that path, not buried mid-layout.

### Cards
- Tappable cards must look tappable — don't rely purely on the user's assumption; use a visible affordance (chevron, "View" label, subtle elevation), not just a hover/press state.
- Avoid double-nested cards/containers — compounds padding and cramps content (see §5.3).
- Padding on rounded cards: when one edge of the card content is non-round (icon, text) and another is round (image), the non-round edge typically needs roughly double the padding for visual balance.
- Border-radius consistency: for nested rounded elements (image inside card), outer radius ≈ 2× inner radius as a rule of thumb.

### Composition, Proportion & Information Density

**User-directed FieldSync standard, 2026-10-09:** premium UI means purposeful composition, not oversized surfaces. The requested result is the minimum target, not the ceiling; creative freedom must improve usability rather than add decoration.

- Establish the screen's primary working area first. Maps, evidence, and editable content must not be dominated by supporting cards without a functional reason.
- Size surfaces to their content and purpose. A maximum-height constraint is a safety cap, not an invitation to fill the viewport. Avoid fixed heights, stretch, repeated padding and large empty regions when the content does not need them.
- Group related information closely and align it deliberately. Use readable horizontal arrangements when width and text scaling permit; stack when actual content needs it, not merely because the device is a phone.
- Separate primary values, secondary labels and supporting descriptions by appropriate type role, weight and contrast. Remove redundant captions before reducing readability; retain FieldSync's existing minimum type sizes and outdoor contrast.
- Allocate whitespace by relationship: smaller within a group, larger between distinct groups. Every gap, divider, border, radius and shadow should explain structure or interaction.
- Keep comfortable interaction areas even when visual plates are compact: 48dp Android control targets and the existing 52dp inspection primary action. Shrink ornament, not accessibility.
- Respect actual font metrics, including Android's nonlinear text scaling. Scale font sizes, measure wrapped content, and verify the complete action fits inside its scroll viewport; do not pass layout widths/heights to `TextScaler.scale()` as though they were font sizes.
- Use existing disclosure for optional supporting detail. Keep recovery actions, important limitations and truthful data states discoverable; do not hide errors or invent unsupported capabilities to make a panel smaller.
- Judge the complete screen at actual phone widths, landscape, enlarged text and realistic content states. Check usable working area, scan order, clipped targets, internal scrolling and empty space—not only individual attractive components.
- Apply refinements in audited, manageable screen groups with rendered visual review and functionality checks between groups. Calendar/lanyard appearance and motion require sample approval before production implementation.
- Preserve Provider/state interfaces, actual data, callbacks, backend contracts and inspection workflows. These composition rules authorize visual judgment, not application-logic changes.

### Forms & Inputs
- Placeholder text should guide the user, not just repeat the field's label.
- Constrain input type to the expected data wherever possible (numeric keyboard for numbers, predefined values/dropdowns for known sets like country codes) rather than trusting free text.
- Pick the right input control for the job: a number stepper (−/+) for small integer counts, a slider/picker for one-time low-frequency setup values, a text field for frequent/precise/repetitive entries (see §6 table).
- Pre-fill forms with the most likely/common value (smart defaults) to reduce decision fatigue.
- Never start a multi-step form's progress indicator at 0% if there's already known context — reflect real progress (goal gradient effect, §6).

### Icons, Avatars & Visuals
- Use one consistent icon family/style throughout; distinguish active/inactive states via weight (thin vs. filled), not a second icon set.
- Pair icons with text labels wherever the icon alone could be ambiguous — especially in bottom nav, settings, and anywhere without hover affordance (mobile has no hover).
- Avatars/images with transparency: apply a background/border fallback consistent with the app background to avoid inconsistent transparent-PNG artifacts.
- Distinguish selected/active items clearly (e.g. background color change) — never rely on a subtle border alone.
- Visually distinguish different element types using more than one attribute at once (color + icon + shape), not color alone — protects against color-blind accessibility issues.

### Tooltips, Labels & Charts
- Hover-based tooltips don't work on mobile touch — use a tappable info icon that reveals the tooltip content instead.
- Use labels cleverly: where a value benefits from a visual preview (e.g. a text-transform option showing how it will actually look), show that preview instead of a plain label.
- Match chart type to the data's actual granularity — don't use a line chart implying continuous/daily data when the underlying data is monthly/discrete; use bar charts for discrete categorical comparisons.

### Color & Branding
- Apply the app's brand/primary color sparingly — reserve it for the most important elements. For everything else, use tints/shades of the existing theme palette rather than repeating the brand color everywhere it loses impact.
- All color usage must pull from the existing theme (see §1) — no new hex values introduced ad hoc.

### Onboarding, Empty States & Guidance
- Upgrade empty states with actionable starting points (e.g. pre-made checklist templates) rather than just redirecting the user to build from scratch — see also §5.7.
- Surface useful shortcuts near the action they relate to (Fitts's law — proximity reduces the effort to use them), especially for power users.
- Keep the full app experience oriented toward **not surprising the user** — any ambiguous action (e.g. "does this auto-submit or let me review first?") is a friction point; UX copy should remove that doubt before the user has to test it.

---

## 9. TECHNICAL CONSTRAINTS (Flutter/FieldSync-Specific)

- **State management:** all UI must wire through the existing **Provider** pattern already in use — no introducing a second state management approach for a single screen.
- **Design tokens — THEME LOCK:** the app already has a theme defined in the repo (colors, typography, spacing constants). All UI work must **reference the existing theme** — no new hex values, no new arbitrary spacing numbers, no new font sizes invented per screen. If a screen currently hardcodes values instead of using the theme, that's an **IMPROVEMENT OPPORTUNITY** to fix during this enhancement — replace the hardcoded value with the matching theme token, don't just leave it or add another hardcoded value next to it. If a value truly doesn't exist in the current theme and is genuinely needed, flag it to Master rather than adding it unilaterally.
- **Reuse before create:** check existing shared widgets before building a new one that duplicates functionality (e.g., don't create a second custom button widget when one already exists).
- **Biometric / security / screen-protection UI** (from the Authentication & Security module) is subject to the existing module's governing docs (MMS, `AUTHENTICATION_ROADMAP.md`) — UI enhancement here must not weaken existing security screen behavior (e.g., screen protection, app resume lock) even for visual polish.
- **No backend/service logic changes** — if a UI fix seems to require a logic/service-layer change, stop and escalate rather than reaching into `lib/backend/services/`.

---

## 10. WHAT EVERY AGENT MUST DO BEFORE WRITING CODE

1. Read this document in full.
2. Read the specific UI Enhancement Prompt for the assigned screen/module (issued separately by Master).
3. Grep/inspect the target screen file(s) and any directly related shared widgets.
4. Produce a **roadmap** covering: current-state assessment, proposed changes mapped to the relevant sections of this document (§5–§9), any assumptions, and any items that need Master's decision before proceeding.
5. Wait for roadmap approval (or proceed only if the prompt explicitly authorizes direct execution).
6. Implement UI-layer changes only, scoped to the assigned files.
7. Report back using PASS / REGRESSION / PRE-EXISTING ISSUE / IMPROVEMENT OPPORTUNITY labeling for anything discovered outside the original scope.

---

## 11. DEFINITION OF DONE — PER-SCREEN SELF-CHECK

Before reporting a screen as complete, the agent must be able to answer **yes** (or "N/A — not applicable to this screen") to each of the following:

- [ ] All colors, type sizes, and spacing values trace back to the existing theme — none invented.
- [ ] Screen does one job; no unrelated content bolted on (§5.4).
- [ ] If this is a list/data screen: both first-use and no-results empty states exist (§5.7).
- [ ] Navigation/touch targets meet the 44px minimum (§5.1).
- [ ] No double-nested cards/containers (§5.3, §8).
- [ ] Any destructive action is de-emphasized and requires confirmation with a specific label (§8).
- [ ] Icons are paired with labels wherever ambiguity is possible; consistent icon family used (§8).
- [ ] Any pattern reused from elsewhere in the app matches that existing pattern — no unnecessary new visual treatment invented (§1).
- [ ] Cognitive load check: could any element be removed or simplified without losing function? If yes, it should have been (§1).
- [ ] Legibility/contrast check: text size and contrast are appropriate for outdoor use and a 35–45 audience — not just "looks fine on a lab monitor" (§2.3).
- [ ] No critical action depends on a gesture alone — a visible button/tap alternative exists (§2.3).
- [ ] If the screen has connectivity-dependent data, sync/offline status is visible and unambiguous (§2.2, §2.3).
- [ ] Accessibility: no information conveyed by color alone; sufficient contrast maintained within the existing theme's palette.
- [ ] Nothing outside the assigned file scope was modified.

---

*This document is fixed and authoritative. It does not get modified by individual agents. Only Master (rlo.tot) issues updates to this document.*
