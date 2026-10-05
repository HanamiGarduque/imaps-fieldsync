# MID-FLIGHT HANDOVER PREREQUISITES (Workstream #9, source/local track)

Status: **source/local prerequisites COMPLETE**. Backend authorization remains a
separate decision; nothing in this change mutates the shared Supabase project.

## What this closes

Two prerequisite tracks that must hold before any mid-flight handover or
ownership-transfer behavior can be designed:

- **A. Truthful remote-write results.** A filtered PATCH/UPDATE that matches zero
  rows is no longer treated as success anywhere in the reachable write path.
- **B. Durable original-inspector ownership of local work.** Identity-sensitive
  local inspection state is attributable to the inspector who created it, and is
  preserved rather than transferred when authority is lost.

Full mid-flight transfer, handover UI, and automatic ownership migration are
explicitly out of scope and are not implemented.

## A. Truthful remote-write results

`InspectionAuthorityResult` (`lib/core/services/inspection_authority.dart`) is
the single vocabulary for remote write outcomes, reusing the closed #8 result
set (`InspectionStartResult` is now an alias of it):

| Outcome | Meaning |
|---|---|
| `authorized` | The write demonstrably reached the row and the write predicate holds. |
| `notAssignedOrUnavailable` | The row is not visible/owned under the current inspector. RLS makes reassigned, unassigned and missing indistinguishable, and no such claim is made. |
| `authRequired` | No authenticated session, or the session changed mid-write. |
| `offlineOrUnverifiable` | Transport/read failure, an unexplained zero-row result, or a returned row that does not satisfy the write predicate. |

`SupabaseService._writeWithAuthority` is the single choke point. It:

1. requires an authenticated session before issuing any request;
2. requests the returned representation (`.select()`) so a write is proven by
   the row it changed, not by a non-throwing request;
3. treats a returned row as success only when the post-write state satisfies the
   caller's predicate (`satisfied`);
4. performs one authoritative follow-up read for zero rows, which distinguishes a
   legitimate idempotent/no-op from lost or unverifiable authority.

Converted writers: `markJobOngoing`, `advanceJobInspectionProgress`,
`submitInspection`, `updateJobInspectionProgress`, `confirmGpsOnSite`,
`scheduleJob`, and the GPS-confirm/photos/findings/checklist outbox replays.

Authorized no-op cases are preserved rather than flattened:
already-in-progress start, already-ahead progress, and an already correctly
completed submission under the same current assignee all resolve to
`authorized` without rewriting terminal lifecycle or the original
`submitted_at`. Completed Step 6 is never lowered.

The outbox drains inspector-scoped and refuses to acknowledge an action unless
the owning session is still current. `notAssignedOrUnavailable` marks the action
`conflict` (preserved, needs review); other unproven results mark it `failed`
(retryable). Neither deletes it.

## B. Local original-inspector ownership

SQLite schema **v16 → v17**, additive and data-preserving
(`lib/core/services/inspection_ownership_schema.dart`). One nullable
`inspector_id` on each proven inspection surface:

`local_jobs`, `local_inspections`, `local_photos`, `pending_actions`,
`sync_log_entries`, `inspection_job_retention`.

- **New rows** record the authenticated Supabase Auth UUID captured before
  persistence.
- **Legacy rows** keep `NULL` owner. There is no deterministic row-local proof of
  the original inspector, so nothing is backfilled.
- Owner is never inferred from a current/replacement assignment, a device-wide
  owner preference, display name, email, or a later remote assignee.
- One `idx_<table>_inspector` index per table, justified by the owner-scoped
  selectors below.

Owner-scoped behavior:

- Every read of cached jobs, inspections, photos, queued actions, sync-log
  history, retention, and cache statistics filters on the current inspector.
- Overwriting or re-enqueueing an existing row requires that row's owner to
  match exactly. A `NULL`-owner or foreign row is never consumed, retried,
  altered, or re-attributed.
- Outbox drain executes an action only when the stored owner equals the current
  authenticated UUID, re-checked after every awaited remote step so a session
  switch mid-drain cannot produce a write under the previous account.
- Photo/metadata writers capture the session at entry and re-verify it
  immediately before each remote write.

## Final-submit safety

`DBHelper.enqueueAction` no longer marks the cached inspection `completed` and no
longer releases retention when a submission is queued. A queued submission is
preserved intent, not proof of completion.

`DBHelper.finalizeAcceptedOnlineInspection(jobId, remoteResult:)` requires
`InspectionAuthorityResult.authorized` and returns `false` for every other
outcome. It is therefore impossible to mark cached work completed or release
retention unless remote completion is actually proven. On authority loss or
unverifiable completion the inspection, photos, checklist, findings, progress,
submission payload, retention and outbox state are all preserved — never
transferred, never silently discarded, and no handover UI was invented.

Account-switch handling no longer performs destructive reconciliation.
`LocalDataGuardService.reconcileLocalDataOwnership` returns `ok` and performs no
wipe; the absence of a pending-action count can no longer authorize destroying
another or unknown inspector's evidence. Row-level ownership does the work.

In-memory field state follows the same rule. `InspectionProvider` is app-scoped
with no logout reset, so both entry paths (`startInspection` and
`hydrateForRework`) clear every field observation before re-populating what the
current session's payload actually carries, and all state getters are gated on
the recorded session owner still being current. A prior inspector's observed
land use, findings, checklist answers and captured photos cannot survive into
another account's report.

## Known consequences of the locked rules

These are accepted by design, not defects, but they are user-visible and must
not be discovered later:

- **A replacement assignee is blocked on that device while preserved evidence
  exists.** Once any row for a job carries a foreign or NULL owner, `requireOwnedJob`
  refuses every later session, and `cacheJobs` will not replace that row. This is
  the "no automatic transfer" rule doing its job: the job is available on another
  device, or after an explicit future handover design. The current
  `notAssignedOrUnavailable` message is generic and does not distinguish this case
  from a genuine unassignment.
- **A pre-v17 queued submission becomes undeliverable and invisible.** Legacy
  NULL-owner outbox rows are never retried, acknowledged, or deleted, and the
  Sync Center is owner-scoped, so after the upgrade the inspector has no in-app
  indication that such a submission still exists. This is the same tradeoff the
  v16 report-queue migration accepted and documented; a count-only "work on this
  device needs recovery" surface is a reasonable follow-up but was not in scope.

## Deployed authorization evidence (read-only inspection)

Catalog reads only, executed against the deployed project. Sanitized results:

**`storage.buckets`** — `inspection-photos`: `public = false`, no MIME or size
restriction configured.

**RLS enabled** on `storage.objects` and `public.field_job_photos`
(`relrowsecurity = true`).

**`storage.objects` policies for the bucket**

| Policy | Cmd | USING | WITH CHECK |
|---|---|---|---|
| `inspectors read own inspection photos` | SELECT | `bucket_id = 'inspection-photos'` AND the job UUID encoded in `storage.foldername(name)[2]` is assigned to `auth.uid()`, OR `profiles.role = 'admin'` | — |
| `inspectors upload own inspection photos` | INSERT | — | `bucket_id = 'inspection-photos'` AND the job UUID in the object path is assigned to `auth.uid()` |

**`public.field_job_photos` policies**

| Policy | Cmd | USING | WITH CHECK |
|---|---|---|---|
| `inspectors view own job photos` | SELECT | `field_job_id` is assigned to `auth.uid()` | — |
| `inspectors insert own job photos` | INSERT | — | `field_job_id` is assigned to `auth.uid()` |
| `r4p1_inspectors_update_assigned_job_photos` | UPDATE | assigned to `auth.uid()` | assigned to `auth.uid()` |

**Referenced helpers** — `auth.uid()` (STABLE, not security-definer) and
`storage.foldername(name text)` (IMMUTABLE, splits the path and returns all
segments except the last).

**Columns** — `field_job_photos`: `id`, `field_job_id`, `photo_url` (both NOT
NULL), `latitude`, `longitude`, `captured_at`, `created_at`. `field_job_id` has a
foreign key to `field_jobs`.

**Classification: INCOMPLETE — a backend authorization delta is required.**

What the evidence *does* establish for the old inspector after reassignment:
assignment is re-evaluated server-side on every write, so a reassigned job's
metadata INSERT/UPDATE and Storage INSERT are refused by RLS.

What it does **not** establish, and why client checks cannot substitute:

1. **No canonical path prefix on Storage writes.** The INSERT `WITH CHECK`
   verifies the job UUID found at `foldername(name)[2]`, but never asserts
   `name LIKE 'inspections/<jobId>/%'`. A path whose second segment matches an
   authorized job while carrying a different prefix or extra segments is not
   rejected by that clause.
2. **No metadata/object job coherence.** `field_job_photos.photo_url` is a plain
   text column with no constraint tying it to `field_job_id`'s path namespace, so
   a metadata row can point at an object path belonging to a different job.
3. **`storage.objects` UPDATE is unproven.** No Storage UPDATE policy was
   observed in the deployed catalog, so upsert behavior on an existing object
   inside an authorized namespace cannot be confirmed safe from this evidence.
   Client-side `_requireSession` guards are not server-side enforcement.
4. **Policy composition was not provable from this snapshot.** Postgres ORs
   permissive policies; whether an additional broad policy exists that widens
   these predicates was not conclusively established by catalog reads alone.

Server-side enforcement is the only acceptable boundary here. The client work in
this commit is defense in depth, not a substitute.

## Proposed backend delta — NOT APPLIED

Per the locked instruction, the following is a proposal only. No migration was
created, staged, or applied.

1. Tighten the Storage INSERT/UPDATE `WITH CHECK` to require the canonical
   prefix for the *same* job the row is already assigned to, for both the
   existing row and the newly proposed path on upsert:

   ```sql
   bucket_id = 'inspection-photos'
   AND name LIKE ('inspections/' || <job-uuid> || '/%')
   AND (storage.foldername(name))[2] = <job-uuid>::text
   ```

2. Require a Storage UPDATE policy with both a `USING` (existing row in an
   authorized namespace) and a `WITH CHECK` (new path in an authorized namespace),
   so an object cannot be moved between job namespaces.
3. Preserve the existing DELETE prohibition for evidence; do not add one.
4. Add metadata/path coherence: either a `CHECK` constraint tying `photo_url` to
   `inspections/<field_job_id>/%`, or a trigger, so metadata cannot reference an
   object outside its own job namespace.
5. Review the full deployed policy set for any additional permissive policy that
   ORs wider than these predicates.
6. Keep the narrowed metadata UPDATE policy only if correcting protected
   metadata during rework remains a proven requirement; otherwise revoke it.

**Tests to accompany the delta:** an authenticated non-assignee cannot create,
upsert, or move an object into or within another job's namespace; cannot insert
metadata for another job; cannot update protected metadata for another job;
cannot delete evidence; the assigned inspector's normal upload, resume-repair,
and rework-metadata-correction paths still succeed.

**Rollback:** the delta is expressed as policy replacement plus one optional
constraint/trigger; reverting restores the prior policy definitions and drops the
added object. No data migration is involved.

## Verification

- New focused tests: `test/inspection_authority_test.dart` (11) and
  `test/inspection_provenance_test.dart` (11) — 22 cases covering remote write
  truth, authorized no-ops, authority-loss results, final-submit preservation,
  owner-scoped reads/retries/acknowledgements, legacy NULL-owner preservation,
  account-switch preservation, rework-hydration isolation, in-flight
  session-switch races, and the additive v17 upgrade preserving every v16 row
  with NULL owners.
- Focused regression run: **445 tests passing across 25 suites**,
  `--concurrency=1`, individually. Includes the closed #8 reassignment suite
  (28), completed immutability, R4 recovery (33) and photo loopback (30), the
  rewritten offline-completion/retention suites, and SQLite v15/v16 report
  ownership.
- `flutter analyze --no-pub`: no issues found.
- APK: not built. See the environmental note in the return report.

Test fixtures were updated where they encoded superseded behavior (offline
submission marking the cache completed) or the pre-v17 unowned schema. Two
loopback servers now honor PostgREST's `Accept` distinction so `.maybeSingle()`
reads receive an object while representation requests receive a row list.