# LOOP 6 SITE INSPECTOR IMAPS ACCESS AUDIT

Audit date: 2026-09-23. Scope: current iMAPS routes, authorization, navigation, login, and the FieldSync identity boundary. No production implementation, database writes, user login attempts, HTTP mutations, staging, or commits performed. Loops 4 and 5 remain closed.

## Current Site Inspector web access

The locked rule is not enforced. An active Site Inspector with valid local credentials can pass the current web login logic. Dashboard, application list/details, technical-review list, map APIs, search, inspection-result lookup, and draft save/delete have no role restriction at their route boundary. Their reachable controller methods do not supply the missing web-role restriction. Draft writes are scoped to the authenticated user's own drafts, but remain unauthorized business capabilities for inspectors.

Evidence is source inspection plus the running Laravel route inventory (`php artisan route:list --json`) and an isolated middleware probe. This audit did not log in as a real inspector or claim successful browser rendering of every page; data, templates, or integrations can fail independently of authorization. A rendering error is not an access-control barrier.

## Route authorization matrix

GET below includes HEAD. `W` = web group (including session/CSRF handling), `A` = auth, `R(x)` = current role middleware, `API` = stateless API group. `AO` = ADMIN ONLY; `PO` = PLANNING OFFICER ONLY; `BOTH` = ADMIN + PLANNING OFFICER. All AO/PO/BOTH routes must have NO SITE INSPECTOR ACCESS. Intended roles below are the minimal proposal, retaining existing explicit business restrictions rather than granting Admin Planning Officer actions. Controller names omit the `Controller` suffix.

| Method | Path | Controller/action | Current middleware | Intended roles / disposition |
|---|---|---|---|---|
| GET | `/` | Closure → Welcome | W | PUBLIC landing; deny internal entry for existing inspector sessions; see root distinction below |
| GET | `/dashboard` | Dashboard@index | W,A | BOTH |
| GET | `/applications` | Application@index | W,A | BOTH |
| GET | `/applications/{id}` | Application@show | W,A | BOTH |
| GET | `/applications/encode` | Application@create | W,A,R(Planning Officer,Admin) | PO proposed; current source advertises BOTH but middleware actually permits PO only |
| POST | `/applications/encode` | Application@store | W,A,R(Planning Officer) | PO |
| GET | `/applications/drafts` | Application@draftsIndex | W,A,R(Planning Officer) | PO |
| POST | `/applications/drafts/save` | Application@saveDraft | W,A | PO |
| DELETE | `/applications/drafts/{id}` | Application@destroyDraft | W,A | PO, retain ownership predicate |
| POST | `/applications/update-status` | Application@updateStatus | W,A,R(Planning Officer,Admin) | BOTH, as explicitly declared; retain transition rules |
| GET | `/technical-review` | TechnicalReview@index | W,A | BOTH oversight; mutation routes remain PO |
| POST | `/technical-review/update-status` | TechnicalReview@updateStatus | W,A,R(Planning Officer) | PO |
| POST | `/technical-review/submit-batch` | TechnicalReview@submitBatch | W,A,R(Planning Officer) | PO |
| POST | `/technical-review/assign-inspector` | TechnicalReview@assignInspector | W,A,R(Planning Officer) | PO |
| GET | `/api/inspections/{localInspectionId}/supabase-data` | TechnicalReview@getSupabaseInspectionData | W,A | BOTH |
| GET | `/api/map/zoning-lookup` | Map@getZoningByCoordinates | W,A | BOTH |
| GET | `/api/map/zoning-area-lookup` | Map@getZoningByParcelArea | W,A | BOTH |
| GET | `/api/map/{layer}` | Map@getLayer | W,A | BOTH; table whitelist is not role authorization |
| GET | `/api/global-search` | Search@globalSearch | W,A | BOTH; redundant source auth is deduplicated in registered inventory |
| GET | `/api/tax-map/lookup/{pin}` | TaxMapLookup@lookup | API only | BOTH proposed; currently PUBLIC exposure, consumed by application encoding |
| GET | `/api/user` | Closure → request user | API,auth:sanctum | BOTH; current token/session authentication alone does not restrict role |
| GET | `/register-new-account` | Auth/RegisteredUser@create | W,A,R(Admin) | AO |
| POST | `/register-new-account` | Auth/RegisteredUser@store | W,A,R(Admin) | AO; keep Site Inspector provisioning |
| GET | `/analytics` | Analytics@index | W,A,R(Admin) | AO |
| POST | `/analytics/rerun` | Analytics@rerun | W,A,R(Admin) | AO |
| GET | `/audit-log` | AuditTrail@index | W,A,R(Admin) | AO |
| GET | `/settings` | Settings@index | W,A,R(Admin) | AO |
| POST | `/settings/upload-shapefile` | Settings@uploadShapefile | W,A,R(Admin) | AO |
| POST | `/settings/upload-tiles` | Settings@uploadRasterTiles | W,A,R(Admin) | AO |
| GET | `/users` | UserManagement@index | W,A,R(Admin) | AO |
| POST | `/users/sensitive-data` | UserManagement@fetchSensitiveData | W,A,R(Admin) | AO; additional password check |
| POST | `/users/{id}/update` | UserManagement@updateProfile | W,A,R(Admin) | AO |
| GET | `/public-portal` | PublicPortal@index | W | PUBLIC tracking; preserve public access |
| GET | `/login` | Auth/AuthenticatedSession@create | W,guest | PUBLIC guest entry |
| POST | `/login` | Auth/AuthenticatedSession@store | W,guest | PUBLIC credential endpoint; admit only AO/PO to web sessions |
| GET | `/forgot-password` | Auth/PasswordResetLink@create | W,guest | PUBLIC account recovery; no automatic role/account removal |
| POST | `/forgot-password` | Auth/PasswordResetLink@store | W,guest | PUBLIC account recovery |
| GET | `/reset-password/{token}` | Auth/NewPassword@create | W,guest | PUBLIC token recovery |
| POST | `/reset-password` | Auth/NewPassword@store | W,guest | PUBLIC token recovery |
| GET | `/verify-email` | Auth/EmailVerificationPrompt@__invoke | W,A | BOTH web utility |
| GET | `/verify-email/{id}/{hash}` | Auth/VerifyEmail@__invoke | W,A,signed,throttle:6,1 | BOTH web utility; preserve signature/throttle |
| POST | `/email/verification-notification` | Auth/EmailVerificationNotification@store | W,A,throttle:6,1 | BOTH web utility |
| GET | `/confirm-password` | Auth/ConfirmablePassword@show | W,A | BOTH web utility |
| POST | `/confirm-password` | Auth/ConfirmablePassword@store | W,A | BOTH web utility |
| PUT | `/password` | Auth/Password@update | W,A | BOTH web utility |
| POST | `/logout` | Auth/AuthenticatedSession@destroy | W,A | Authenticated-session exit, INCLUDING existing Site Inspector sessions |
| GET | `/sanctum/csrf-cookie` | Sanctum/CsrfCookie@show | W | PUBLIC infrastructure, not internal application data |
| GET | `/up` | Health closure | none | PUBLIC infrastructure |
| GET | `/storage/{path}` | Framework closure → ServeFile | none listed | SYSTEM/capability download; private local disk checks relative URL signature in handler |
| PUT | `/storage/{path}` | Framework closure → ReceiveFile | none listed | SYSTEM/capability upload; requires upload flag and relative URL signature |

No separate registered Site Inspections page, `/profile`, parcel detail, export, download-controller, or bulk draft-sync route exists. `Application::submitTechnicalReview`, `Application::syncAllDrafts`, and `UserManagement::resetPassword` are not registered HTTP actions in this inventory. Application CSV export and printing are client-side operations on already delivered data (`Applications/Index.jsx:925,933`); their security boundary is the list/detail response. Static public storage assets are outside Laravel route authorization. Signed file capabilities must not be mistaken for public unguarded file access just because middleware is empty; role-bound private downloads would be a separately approved contract change if required.

Root distinction: `/` currently renders a public Welcome component, not the authenticated dashboard. No Welcome page file was found in the current page tree, so successful root rendering is not claimed. Preserve guest/public tracking contracts. To meet the explicit negative test for an already-authenticated inspector visiting `/`, add an inspector-session denial/FieldSync explanation at that root entry only; do not turn all public tracking into a restricted route. A person logged out as a guest can still use genuinely public pages.

## Middleware findings

`app/Http/Middleware/RoleMiddleware.php:12` defines `handle(Request, Closure, string $role)`. It compares `Auth::user()->role` strictly to only that one argument and aborts 403. `bootstrap/app.php:26` registers `role`; there is no separate Kernel registration or global web-role boundary. The base controller is empty; no provider authorization policy fills these gaps. HandleInertiaRequests shares the user but does not authorize access.

The no-database probe instantiated unsaved User objects, set the process-local auth user, and called the middleware with a stub response. Results: `role:Admin,Planning Officer` permits Admin (200), denies Planning Officer (403); reversed arguments permit Planning Officer and deny Admin. Site Inspector gets 403 in both cases. Thus fixing argument handling is necessary before using a BOTH group. Current single-role routes work. Missing auth is not safely handled by this middleware because it dereferences a possibly null user; use auth first and a null-safe fail-closed implementation.

## Controller findings

Classification: A = route guard sufficient; B = explicit role check; C = authentication only; D = duplicate/inconsistent authorization; E = conflict with intended contract.

| Reachable controller methods | Classification | Finding |
|---|---|---|
| Dashboard@index | C | Unrestricted application metrics/recent data for authenticated users |
| Application@index, show | C | No role/inspector assignment scope; application detail includes parcels/reviews/inspector selections |
| Application@create | E | Declared two-role route actually permits only PO; Admin creation form is inconsistent with PO-only submit/drafts |
| Application@store | A+B+D | PO route plus PO controller check; existing back-with-errors behavior differs from route 403 |
| Application@draftsIndex | A+B+D | PO route and explicit controller 403; owner-scoped query |
| Application@saveDraft | C+D | Rechecks auth, not role; user-scoped upsert still available to inspectors |
| Application@destroyDraft | C | Owner-scoped deletion, no role restriction |
| Application@updateStatus | E | Route intends PO+Admin, middleware currently denies Admin; controller checks transitions, not roles |
| TechnicalReview@index | C | List is authenticated-only |
| TechnicalReview@updateStatus, submitBatch, assignInspector | A; B/D for assignment helper | PO route protects all; currentPlanningOfficerAssignmentActor also rejects non-PO during assignment capture |
| TechnicalReview@getSupabaseInspectionData | C, high priority | Accepts arbitrary local inspection ID, fetches results/photos using server service credentials; no caller role/ownership check |
| Map@getLayer, getZoningByCoordinates, getZoningByParcelArea | C | Whitelist/input validation are data validation, not authorization |
| Search@globalSearch | C | Searches application/parcel data without role restriction |
| TaxMapLookup@lookup | E | No auth or role middleware/check; exposes parcel owner/title/tax/area/address metadata when query succeeds |
| UserManagement@index, updateProfile | A | Admin route boundary sufficient |
| UserManagement@fetchSensitiveData | A | Admin route plus current user's password check; password alone is not a role check |
| Analytics@index, rerun | A | Admin route boundary sufficient |
| AuditTrail@index | A | Admin route boundary sufficient |
| Settings@index, uploadShapefile, uploadRasterTiles | A | Admin route boundary sufficient |
| Auth/RegisteredUser@create, store | A | Admin provisioning boundary; retain all inspector identity/provisioning behavior |
| Auth/AuthenticatedSession@create, store, destroy | E for store | Active-account/password checks but no role admission rule; logout remains useful for all existing sessions |
| Auth email-verification/password utility actions | C | Auth/signature/throttle/password rules do not express web-role eligibility |
| PublicPortal@index | Public by contract | Keep public tracking; no role-denial test for this route |

## Frontend/navigation findings

`Sidebar.jsx:16,123` distinguishes only Admin versus everyone else. Site Inspectors therefore see Dashboard (including GIS) and Applications; Analytics, Audit Trail, Users and Settings are hidden in this sidebar. There is no separate Site Inspections/GIS menu item. `Header.jsx:524` exposes Account & Settings to every role even though its backend is Admin-only. Global search is part of the shared header and resolves application links.

`AuthenticatedLayout.jsx` exposes Dashboard/Analytics without role checks in both desktop and mobile menus, plus an unregistered `/profile` link. Its only page import found is `Pages/Parcels/Show.jsx`, which has no registered route; this is latent navigation inconsistency, not evidence of a currently reachable inspector page. Active Dashboard/Applications pages use Header/Sidebar. Application Index limits New Application and Drafts links to Planning Officer, but already accessible records can still be viewed and exported. Frontend hiding cannot repair the backend holes.

## Login/post-login behavior

`AuthenticatedSessionController::store` (`:28–79`) looks up the local user, rejects inactive accounts, calls Auth::attempt, regenerates the session, writes last_login, then redirects to the intended URL or `/dashboard`. There is no Site Inspector admission check. Correct credentials can therefore establish a web session; a saved direct URL can bypass a dashboard-only redirect fix. `LoginRequest::authenticate()` is not called by this controller, so adding a restriction only there would not fix the live login path.

Option A (recommended): reject Site Inspector web admission with a clear “Use FieldSync for inspections” validation response, without establishing a lasting web session, deactivating the account, changing credentials/handshake, or treating a valid-role denial as a failed-password attempt. Validate credentials before revealing role-specific guidance. Also enforce the backend allowlist for existing sessions and direct URLs; login-only blocking is insufficient.

Option B (authenticate then dedicated Use FieldSync page) is workable but adds a protected page, redirect rules and loop handling. Option C (allow login then 403 everywhere) closes data access with route guards but creates a confusing successful-login experience. A plus backend guards is the smallest coherent change with the existing login form/error handling. No new UI page or broad controller authorization duplication is needed.

## FieldSync independence check

Source trace confirms FieldSync's `lib/core/services/auth_service.dart:31` calls the Supabase client's signInWithPassword; it does not authenticate through iMAPS `/login`. SupabaseService initializes its own client. Local web role middleware does not wrap these calls.

Local Site Inspector users and handshake_key must remain. Admin RegisteredUserController provisions inspector Supabase Auth/profile identity; PushInspectionToSupabase resolves local inspector → profiles.handshake_key → assigned_inspector_id (`:238–270`). Planning Officer controller queries continue selecting Site Inspector records; no role deletion, renaming, is_active change or query filtering is proposed. The field_jobs INSERT notification function targets the assigned inspector through its existing OneSignal path. PullCompletedInspections is an Artisan/Supabase service operation, scheduled every five minutes in routes/console.php; it does not require an inspector web session. None of these paths need modification for Loop 6. This is architectural/source verification, not a new live notification/auth/sync test.

## Exact security/access defects

Highest priority is the authenticated-only result proxy using server credentials, alongside unrestricted application/detail/search/GIS reads. Another direct exposure is unauthenticated tax-map lookup. Authenticated draft save/delete is a missing business-role restriction, even with owner scoping. Login admits inspectors and preserves intended internal destinations. The middleware's single-argument implementation silently denies the second allowed role and prevents a correct BOTH guard. Navigation presents internal capabilities to non-admin users without a PO allowlist.

The tax-map route is public in code but consumed by the internal encoder; the proposed classification is protected BOTH, not public tracking. Team Leader must explicitly approve that tightening. No public tracking route should be denied. Generic auth utilities and `/api/user` also need explicit web-role treatment so an auth-only side path is not forgotten.

## Minimal proposed implementation

Fix RoleMiddleware to accept variadic roles, perform strict membership checking and fail closed for absent/unknown roles. Place internal web routes under auth then BOTH, retaining nested AO and PO restrictions. Add PO guards to both draft mutations. Keep registration/analytics/audit/settings/users Admin-only, and all technical-review mutations/application submission PO-only. Make encode GET PO-only to match existing submit/draft behavior; if Admin form viewing is desired, obtain an explicit separate decision rather than broadening writes.

Move the same `/api/tax-map/lookup/{pin}` URL declaration from the stateless API file into the guarded session-backed web group, avoiding duplicate registration and preserving the encoder's same-origin session fetch. Keep `/api/user` on Sanctum and add the BOTH role rule. Restrict authenticated web account-utility routes to BOTH, with logout outside that restriction. Public login/recovery/tracking/health/CSRF and existing signed-storage capability contracts remain separately scoped.

After approval only, change AuthenticatedSessionController::store to deny Site Inspector web admission cleanly. Handle an existing inspector session visiting the public root explicitly as described above. Add frontend role allowlists to shared navigation, with Settings visible only to Admin. Do not change ApplicationController or TechnicalReviewController: their holes can be closed at route boundaries, and their existing business/immutability logic stays intact.

## Files that would change

| Category | Exact proposed files |
|---|---|
| Route/middleware | `routes/web.php`, `routes/api.php`, `routes/auth.php`, `app/Http/Middleware/RoleMiddleware.php` |
| Frontend visibility | `resources/js/Components/Sidebar.jsx`, `resources/js/Components/Header.jsx`, `resources/js/Layouts/AuthenticatedLayout.jsx` (latent layout consistency) |
| Controller + login | `app/Http/Controllers/Auth/AuthenticatedSessionController.php` — store only; no other controller changes proposed |
| New middleware registration/page | None needed for this minimal proposal; bootstrap role alias already exists |
| Tests | New `tests/Unit/RoleMiddlewareTest.php`, new `tests/Feature/SiteInspectorWebAccessTest.php`, update `tests/Feature/Auth/AuthenticationTest.php`; extend `tests/Feature/Auth/RegistrationTest.php` for current Admin-only provisioning contract |
| Identity/bridge/DB | No changes to models, jobs, FieldSync source, migrations, schema, Supabase policies or users |

## Negative-access test plan

Prepare a role/method data provider covering every AO/PO/BOTH row above. Use isolated test users, an array session/cache and a verified disposable database; never the live loop fixtures. Existing phpunit.xml specifies SQLite :memory:, but verify effective runtime configuration before any RefreshDatabase test. No such mutation tests ran in this audit.

For a Site Inspector session, assert 403 before controller/service execution for dashboard, applications/list/detail, encode GET/POST, draft GET/save/delete, all technical-review routes, inspection data proxy, map lookups/layers, search, users/provisioning, analytics/rerun, audit, settings/uploads and web account utilities. Test real registered middleware, not controllers in isolation. POST tests must use valid CSRF/test middleware handling and distinguish role denial from 419/422; use valid existing isolated IDs to distinguish role denial from incidental 404. Assert no DB/file/queue/HTTP side effects with fake services and before/after checks. Token-authenticate a Site Inspector for `/api/user` and assert role denial separately from unauthenticated 401. Test tax-map for guest, inspector session and missing credentials; never count a missing parcel 404 as authorization.

Root test: an existing inspector session must not receive the landing/internal entry payload; apply the approved 403/FieldSync explanation behavior. Guest root and public-portal tracking remain public. Invalid application IDs or nonexistent Site Inspection URLs are not substitutes for tests of real inspection endpoints. There is no separate registered Site Inspection page to exercise; protect the actual technical-review/details/result paths. Existing signed file routes require capability-specific tests, not invented role assertions.

Login tests: valid inspector credentials show FieldSync guidance and leave no authenticated web session; no last_login/is_active/handshake/password changes or lockout counter increment caused by role denial. Test remember-me and intended internal URLs; pre-existing inspector sessions must still be denied by routes. Verify logout works. Unknown/null roles fail closed. Middleware tests cover both role argument orders and single-role routes.

Existing AuthenticationTest lacks role cases and expects logout `/` even though the controller returns `/login`. RegistrationTest still tests public `/register`, while actual provisioning is Admin-only `/register-new-account`. These tests need contract alignment; do not claim they currently prove access safety.

## Positive-access regression plan

Admin: dashboard/list/detail/map/search/result oversight plus users, registration, analytics, audit and settings; standard status transition route as explicitly declared. Planning Officer: dashboard/list/detail, encoding/submission, own draft lifecycle, technical reviews/assignment and map/result access. Admin remains denied PO-only submit, drafts and technical-review mutations; Planning Officer remains denied Admin-only pages/actions. Preserve draft ownership isolation. Verify both role orders in BOTH middleware.

Use mocked HTTP/queues to verify Admin can still provision Site Inspector identity, Planning Officer selections include inspectors and retain handshake mapping, assignment push targets the same inspector, and the background completed-result command is independent of the web guard. Do not rerun live assignments, notifications or completed inspections. Reuse existing Loop 2–5 bridge/immutability contract tests only when implementation changes justify them.

## Database/Supabase impact

No schema, PostgreSQL user data, Supabase RLS, Auth identity, notification or bridge mutation is needed or proposed. Moving the internal tax-map URL behind the web guard is a route-security change, not a database change. Separate public signed-file and public recovery contracts remain intact unless separately approved.

## Team Leader approval message

Draft only — not sent:

> Requesting approval for Loop 6: restrict iMAPS web access to Admin and Planning Officer while keeping FieldSync as the Site Inspector operational app. Current gaps allow authenticated inspectors into application/GIS/result reads and draft writes; tax-map lookup is public, and multi-role middleware honors only the first role. Proposed fix: correct role middleware, guard internal routes while retaining PO-only business actions, protect internal tax-map lookup, and align navigation. The only proposed controller change is AuthenticatedSessionController::store: reject inspector web login with “Use FieldSync” guidance without deactivating users or changing credentials/handshake identity. Existing inspector sessions will also be blocked at route level. Inspector provisioning, assignment selection, Supabase authentication, notification and reverse sync remain intact. Please approve that controller behavior and the matrix decisions: PO-only encode form, Admin+PO standard status updates, protected tax-map lookup, and inspector-session denial at `/` while public tracking remains public.

Approval boundary: the user's Loop-6 request explicitly forbids implementation in this pass. The canonical roadmap also states, “Before **any Controller modification**, the Team Leader must be notified and approval must be received.” Source: `C:/Users/Ralph Lauren/iMAPS/docs/FIELDSYNC_BRIDGE_ARCHITECTURE.md:674` (also :1049; Loop 6 :1105). This report is the concrete proposal for review, not an implementation or an approval request sent to anyone.

## Git status

iMAPS started with only unrelated untracked `is_nullable`; no source changes were made. FieldSync's pre-existing build report/Supabase temporary or deleted files/untracked documents remain untouched. This audit adds only this report under `output/loop6/` in the writable FieldSync workspace. No commits, staging, resets, stashes, history rewrites, pushes, DB mutations or mobile tests.

LOOP 6 AUDIT COMPLETE — TEAM LEADER APPROVAL REQUIRED
