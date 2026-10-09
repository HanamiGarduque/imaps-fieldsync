# Approved Site Verification UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved map-first Site Verification presentation in Flutter, with the final portrait-control and route/boundary refinements, and produce actual Flutter renders.

**Architecture:** Keep the existing task-bound screen as the owner of GPS, routing, persistence and navigation. Move its presentation into a screen-specific Flutter view; reuse `InspectionStepHeader` unchanged and the real `FlutterMap`. A scoped, opt-in boundary style leaves the Quick Action map's default presentation intact.

**Tech Stack:** Flutter, existing Provider, flutter_map 7, InsightTheme, existing Flutter widget tests; no new dependencies.

**Spec:** Approved sample at `C:/Users/Ralph Lauren/AppData/Local/Temp/opencode/fieldsync-site-verification-proposal-20261009/PROPOSAL.md` and `visuals/site-verification-board.png`, plus the user's implementation approval and final refinements in this conversation.

## Global Constraints

- Retain the existing Site Verification header and separate Step 1–6 container; use the existing component and theme.
- Portrait: two icon-only controls arranged vertically; 40dp visual plates within 48dp accessible hit targets; meaningful tooltips/semantics and distinct fullscreen/fit icons.
- Retain compact Site Details composition, 52dp minimum primary action, complete wrapping text and internal scrolling when needed.
- Use the approved 72% white attribution backing with fully opaque readable text.
- Landscape: map-primary left area, bounded right details pane, preserved automatic device rotation.
- Preserve actual geometry, ≤30m proximity rule, location stream, 50m/30s online route refresh, route cache, offline limitations, navigation, rework and existing callbacks.
- No backend, database, synchronization, auth, shared header or Quick Action screen changes; no new map/navigation features or dependencies.
- Test sequentially with `--no-pub --concurrency=1`; exclude `webhook_test.dart` and `pre_loop3_cleanup_contract_test.dart` from the broad suite.
- Use local/public demonstration fixtures for rendered evidence; never submit a live inspection for this task.

## Review Focus

- Short landscape plus system insets: header, controls and primary action remain reachable without sharing the side pane's hit area.
- 2× text / long location context: details scroll internally; controls keep 48dp targets; text and recovery actions remain readable.
- Fullscreen/collapse followed by rotation: retain map/controller and prior disclosure state; map space is reclaimed smoothly.
- Cached or missing route / missing GPS: truthful labels, no fabricated geometry or route-dependent progression gate.
- Shared boundary: subdued inspection style preserves every point/hole and leaves default Quick Action rendering unchanged.

---

### Task 1: Native screen presentation and responsive interactions

**Files:** Modify `lib/modules/inspection/screens/site_map_screen.dart`; create `lib/modules/inspection/widgets/site_verification_view.dart`; test `test/site_verification_layout_test.dart`.

**Interfaces:** The view consumes the existing map through `Widget Function(EdgeInsets) mapBuilder`, readiness, location/context, real distance/route metrics, proximity/rework values, and existing back/retry/fit/proceed callbacks. It owns only fullscreen/disclosure and measured overlay layout. It produces viewport padding for the existing two-marker camera fit, not automatic following/rerouting.

- [x] Add executable widget acceptance tests against the real screen: portrait control ordering/targets, landscape non-overlap, rotation and disclosure/fullscreen persistence, enlarged text, missing GPS, cached/no route, normal progression and rework return.
- [x] Run the new tests; confirm a meaningful missing-presentation failure before implementation.
- [x] Implement the approved compact view and wire existing screen callbacks; retain service/lifecycle methods and map layer ordering.
- [x] Run the new tests and existing map/inspection layout tests; update only source-wiring assertions superseded by the approved presentation.

### Task 2: Route/boundary hierarchy with shared-screen preservation

**Files:** Modify `lib/modules/inspection/widgets/rosario_boundary_overlay.dart`, the Step 1 map styling, and boundary/map wiring tests.

**Interfaces:** `RosarioBoundaryOverlay(subdued: true)` changes styling only for Step 1; default `false` retains the existing shared-loader/default style. Geometry and `simplificationTolerance: 0` remain intact.

- [x] Add an executable boundary test proving subdued/default styles differ while point/hole lists remain exact and default rendering stays unchanged; watch it fail.
- [x] Use a solid prominent blue route with white casing; a thinner muted dashed municipal outline and matching attribution key. Keep real geometry and independent layers.
- [x] Run boundary, route cache, recovery and initial-tile tests; require no new failures.

### Task 3: Flutter visual acceptance and completion proof

**Files:** Existing/new widget tests and scoped evidence under `C:/Users/Ralph Lauren/AppData/Local/Temp/opencode/fieldsync-site-verification-implementation-20261009/`.

- [x] Render the actual production Flutter screen with explicitly labeled demonstration task/GPS/route inputs and local OSM reference fixtures; save portrait, landscape and disclosure/offline screenshots.
- [ ] Run analyzer and the broad regression suite with the two required exclusions; compare any failures against the independently recorded canonical-main baseline.
- [ ] Build Android arm64 debug APK; review the scoped diff and obtain one independent read-only review.
- [ ] Present Flutter renders and accurate verification results for visual acceptance. Integration/push is a separate operation.

## Execution record

The user explicitly approved the design and authorized implementation. Execute inline without another design approval round. Existing linked workspace is used on `feature/site-verification-approved-ui`; historical worktrees/stashes and ignored files are preserved. Progress/evidence are recorded in the scoped temporary implementation ledger.
