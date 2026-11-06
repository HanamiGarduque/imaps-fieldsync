# FieldSync Interactive Guide

The guide offers an optional English/Filipino (Tagalog) walkthrough after an authenticated inspector reaches settled Home. Following the owner's November 5 approval and follow-up removal, the tour has **35 explanations in six stages**. The separate Scheduled / Available Anytime introduction, Quick Actions stage, Profile Edit/Log Out explanations and Help/FAQ replay-instruction stop are removed; their actual app features remain available. G10 advances directly to G12; original IDs of retained stops are unchanged. Full manual replay remains available from **Profile → Help & FAQ → FieldSync Interactive Guide → Start/Replay Tour**, before FAQ search/filtering.

The owner-approved working directory is **`C:/Users/Ralph Lauren/imaps_fieldsync_main`**, on its existing `main` branch. The implementation was initially verified in an isolated worktree; the authorized guide-only transfer and destination verification are recorded in `output/interactive_guide_implementation/TRANSFER.md`. No commit or push is part of that transfer.

## Ownership and safety

- `MainShellScreen` owns one coordinator and `GuideHost`. The existing shell stays mounted. Tutorial tab changes never call the normal Tasks acknowledgement or Sync Center entry paths.
- The tour uses the actual Home, Tasks, Task Overview/completed detail, six inspection screens, Sync Center and Profile widgets. Their optional `walkthrough` input defaults to null for normal entry. There is no separate sample-page composition or guide-owned Quick Actions menu. Completion stays on Profile rather than opening a replay-instruction page.
- An owner-fenced loader reads saved jobs, submissions, draft/findings, photos, GPS, route data and read-only cache statistics. It prefers the current owned task, otherwise the first saved owned assignment. Read failures remain unavailable, never a confirmed-empty account; unknown storage values display `—` rather than initialized zeros.
- Identity, counts, saved records and receipts remain real. Only a missing-data section receives a temporary labelled example. Local saved components also supply completed inspection summaries; provider state belonging to another inspection is never hydrated or borrowed.
- Historical final-submit receipts provide delivery metadata and fallback evidence; current saved components take precedence in the tour. Saved per-step timestamps retain the normal independent-step meaning without changing global progress. Failed inspection reads show unknown/unavailable values rather than invented zero counts, unchecked answers or absent findings.
- Every fictional record/diagram/evidence/stat is labelled `DEMO / SAMPLE — For Tutorial Only`; Tagalog adds `HALIMBAWA LAMANG — Para sa Gabay`. Examples are discarded on interruption/exit, not inserted into business storage.
- The guide is below the app Navigator and existing privacy protection. Non-resumed lifecycle states hide it. Resume requires the same authenticated owner, successful required unlock, settled route and ready protection. An arbitrary lock-route pop is not success.
- Not Now, Skip, Done and Android Back remove guide-owned content only. Replay reconstructs its public Help/guide origin from language/query/category/scroll values while retaining the actual Profile tab. Account loss prevents restoration.

These boundaries are intentional: normal Tasks acknowledges assignments, inspection entry hydrates working state, and normal Sync Center can drain pending work without a tap. Walkthrough initialization, callbacks, pop/lifecycle/disposal and image/map loading are guarded at their owning entry points. No global service/network override is installed by the guide; independent normal background work is not paused. The approved correction is in `docs/superpowers/specs/2026-11-02-fieldsync-guide-live-pages-design.md`.

## Device-local metadata

`GuidePreferences` stores only `{version, language, status}` in SharedPreferences under `fieldsync.guide.<SHA-256 of inspector UUID>`. The digest avoids a raw identifier in the key; it is not encryption or anonymization. No inspection cursor is persisted.

- Current version is 1; statuses are offered, skipped and completed.
- Offered is saved before displaying an automatic invitation. Any existing version/status suppresses automatic re-enrolment, including future versions.
- Replay can update language but never downgrades completed status.
- Corrupt/unreadable metadata suppresses automatic interruption. Manual replay remains ephemeral without overwriting the unreadable record.

## Layout and input

Targets are registered by widget lifetime and measured from attached RenderBoxes, including their real scroll-viewport clipping and the navigation rail. Whole feature cards/containers are registered, not just headings. The guide scrolls actual content vertically, never drags an assignment carousel sideways. Unusually tall sections highlight their actual visible viewport. A clipped 6dp decorative halo is added only after validating the real feature. Android side-gesture insets protect coach controls/background taps, not the painted feature: even under small font/display settings, they must not cut off the fingerprint or either side of a visible card. Strict duplicate-target detection remains enabled; animated assignment updates keep their anchor outside the cross-fade.

Every active stop has a concise English/Tagalog summary. **More details** opens the full explanation and additional information without advancing; its content scrolls while 48dp navigation remains reachable. Narrow/large-text layouts use localized labelled icon controls. A compact white/blue speech bubble stays beside the stationary fingerprint, with a short speech tail and an arrow to the real feature. The guide reserves a bottom/side content lane when needed; its passive Sync header scrolls too. There is no technical “Hindi ligtas…” layout warning and no full-height measurement placeholder. Back/Next stay available during guide-owned scrolling.

Profile has nine explanations: account overview, inspection summary, analytics, security, Help, Support Desk (Technical Issue, Application Support and My Reports), grouped policies, About and a brief completion. Following the November 7 device report, the normal dedicated Guide page uses the same fixed top header as Help/settings. Its language controls, Start/Replay and copy scroll together below that header; short content stays top-aligned rather than vertically centered. The tour no longer teaches the replay procedure.

The scrim never forwards input to business controls. Only G15's guide-owned task proxy advances; its pointer-down generation, layout revision, size and current rectangle must still match at release. Buttons take priority, system gesture edges are excluded, and focus/normal scroll state are restored on exit. The original shell stays offstage with a separate target registry; the active guide uses a stable inner route.

The official SVG artwork is unchanged. The normal fingerprint is stationary at 48dp inside its 64dp anchor. Welcome/stage pulses run once, not in a loop; reduced motion disables pulses and animated guide scrolling/transitions.

## Verification

Run Flutter commands serially on Windows; concurrent runners can lock `sqlite3.dll`.

```powershell
$guideTests = (Get-ChildItem test/interactive_guide_*_test.dart).FullName
flutter test --no-pub --concurrency=1 $guideTests
flutter test --no-pub --concurrency=1 test/quick_actions_trigger_test.dart test/quick_actions_responsive_test.dart test/quick_actions_landscape_overlay_test.dart
flutter analyze --no-pub
git diff --check
```

Do not repeat blanket host discovery with real credentials: the existing **`test/webhook_test.dart` is live/mutating despite living under `test/`**. It was discovered in the final full run and failed on a missing URL before client initialization or an insert. Inspect and explicitly name offline-safe files for further regression runs. The separately classified `integration_test/live_loop3_completion_e2e_test.dart` was not run and also requires separate live-test authorization. No test exclusion or skip was added.

`test/interactive_guide_integration_test.dart` exercises the real shell, SQLite, SDK session handling and retained navigation with isolated HTTP/platform boundaries. Empty, populated, completed-only and partial-data accounts traverse all 35 stops in both languages, including the six actual inspection screens. It checks unchanged business/security/session snapshots and normal Tasks acknowledgement/Quick Actions after exit. The lock/eligibility tests cover cold-start/resume/idle outcomes, bootstrap/protection failure and owner loss. `interactive_guide_visual_revision_test.dart` also exercises first Help start/replay while native protection acknowledgement is delayed, every retained Next transition in both languages at 16ms intervals, direct G10 ↔ G12 navigation and six-stop My Tasks progress, normal assignment-refresh frames, whole containers, shortened Profile, absence of removed lessons, and saved/unknown cache statistics.

`interactive_guide_reference_layout_test.dart` checks rendered targets, actual viewport clipping, full visible feature width, arrow endpoints, 48dp controls, all-stop details, rotation and ordinary-phone coach height. It covers both languages, empty/saved data, 320/360/390dp phones, landscape, tablet, linear/nonlinear large text and a 720×1600 physical / 432×960 logical small-display case with 0.85× text, non-unit density and Android side-gesture insets. The Guide-page header is checked at small/default/2× text before and after scrolling. Actual-page tests directly invoke callbacks and lifecycle/pop/disposal boundaries with HTTP/hardware checks.

### Reproduce Flutter captures

Use actual Inter, Urbanist and OpenSans font files named `Family-Regular.ttf`, `Family-Medium.ttf`, `Family-SemiBold.ttf`, `Family-Bold.ttf` and `Family-ExtraBold.ttf`. Without this environment variable, the test support deliberately uses SDK fallback fonts for portable host checks; those are not real-font visual proof.

```powershell
$env:IMAPS_GUIDE_FONT_DIR = '<directory containing the font files>'
$env:FS04_EVIDENCE_DIR = (Join-Path (Get-Location) 'output/interactive_guide_live_pages')
flutter test --no-pub --concurrency=1 test/interactive_guide_reference_layout_test.dart test/interactive_guide_integration_test.dart
```

Current small-display PNGs/logs live in `output/interactive_guide_live_pages/small_display/` and `small-display-*.log`; results and limitations are in `output/interactive_guide_live_pages/SHORT_GUIDE_VERIFICATION.md`. The correction ledger remains in `.superpowers/sdd/2026-11-02-fieldsync-guide-live-pages/progress.md`. G11-removal results remain under `g11_removal/`; those and the earlier recordings are history, not fresh small-display proof.

Use **`output/interactive_guide_live_pages/verify_preservation.py`** for current correction checks. The similarly named script under `output/interactive_guide_implementation/` records the historical pre-transfer boundary and must not be rerun after transfer. `TRANSFER.md` and its manifests retain that history.

For a host-rendered video preview, explicitly run `test/interactive_guide_review/visual_revision_recording_test.dart` with the same font/evidence environment, then encode its frame manifests with `output/interactive_guide_live_pages/render_recording.py --ffmpeg <existing Playwright FFmpeg executable>`. These are labelled test-fixture raster sequences with 20fps transition samples and added reading holds, not installed-device recordings.

## Handoff limitations

This is a source-code feature, not a deployment or device installation. A Git commit does not prove native biometrics, installed Android identity, screenshot protection or TalkBack behavior on a device; those require separately authorized device validation.

GPS discrepancy remains separate: the owner reports an approved **10m** requirement; the current implementation and repository manuals use **30m**. This guide revision does not change the production distance, accuracy or freshness rules. See `output/interactive_guide_live_pages/GPS_DISCREPANCY.md`.

Historical V1 gate: **162 passed / 1 optional capture skipped**; historical full host reconciliation: **2384 passed / 143 failed / 2 skipped**, including **87 unclassified failures**. These are not correction results or permission to rediscover live tests. This is not a merge-ready or device-validated release; retain the [historical named failures](../output/interactive_guide_implementation/VERIFICATION.md) alongside the [current correction evidence](../output/interactive_guide_live_pages/VERIFICATION.md).

Original local work and the approved review captures are preserved; no dependency, server/schema or security-policy change is required.
