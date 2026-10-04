# FieldSync — Local SQLite Schema Change Log

Canonical record of **versioned local SQLite schema changes** in FieldSync.

Scope: the on-device SQLCipher database (`imaps_fieldsync.db`, owned by
`lib/core/services/db_helper.dart`). This file records **schema only** — not UI
features, not sync behaviour, not Supabase.

Every version bump and every `onUpgrade` branch must have an entry here.

---

## VERSION 14 → 15

**CHANGE:** create `local_report_queue` for offline Reports & Support, and add
two nullable identity columns to `local_jobs`.

### WHY

- A report can exist without an inspection job (a Technical Issue is about the
  app itself, and must not be forced into a job-keyed outbox).
- Inspection SyncOutbox rows (`pending_actions`) carry a NOT NULL `job_id` and
  are drained by `SyncOutboxService` as inspection lifecycle events. Reports
  are not inspection events, and mixing them into `pending_actions` would
  corrupt both. Reports therefore need their own queue table.
- Application Support must travel the exact `field_job_id`,
  `supabase_application_id`, and `bridge_source_id` triple from the task the
  inspector actually selected — never a value inferred from a reference number
  or display text. The cached job rows must carry those exact identities.
- Report drafts must survive offline failure and app restart, and must not be
  reported as submitted until the server confirms an insert.

### TABLE

```
local_report_queue
```

### COLUMNS

```
id                       TEXT PRIMARY KEY
report_type              TEXT NOT NULL
                           CHECK (report_type IN ('technical_issue','application_support'))
payload                  TEXT NOT NULL
local_job_id             TEXT
field_job_id             TEXT
supabase_application_id  TEXT
bridge_source_id         TEXT
remote_report_id         TEXT
reference_code           TEXT
queue_state              TEXT NOT NULL DEFAULT 'pending'
                           CHECK (queue_state IN (
                             'pending','sending','sent',
                             'failed_retryable','delivery_unknown'))
retry_count              INTEGER NOT NULL DEFAULT 0
last_error               TEXT
created_at               TEXT NOT NULL
last_attempt_at          TEXT
updated_at               TEXT NOT NULL
```

Row-level CHECK enforces the locked pairing: a `technical_issue` row has all
`field_job_id`/`supabase_application_id`/`bridge_source_id` NULL, and an
`application_support` row has all three present. A row that disagrees is
rejected at insert time.

### INDEXES

```
idx_local_report_queue_state
idx_local_report_queue_type
idx_local_report_queue_field_job
idx_local_report_queue_remote_report_unique  (UNIQUE, WHERE remote_report_id IS NOT NULL)
```

The unique partial index prevents one confirmed remote report identity from
being attached to two local queue rows.

### local_jobs additions

```
supabase_application_id TEXT
bridge_source_id        TEXT
```

Nullable by design. Existing v14 cached rows upgrade with both NULL: they
remain readable and valid for ordinary task functionality, but an
identity-incomplete row is **not eligible** for Application Support until the
task is refreshed online with the real remote identities. The app never
infers these values.

### QUEUE STATES (local transport, never remote status)

```
pending          -- persisted before any network attempt
sending          -- a send is in progress
sent             -- server confirmed the insert; never retried
failed_retryable -- the report was NOT filed. Whether it retries
                    automatically is DERIVED, not implied by the state:
                      * transient pre-dispatch failure -> auto-retry
                      * auth/RLS refusal              -> never auto
                      * deterministic server rejection -> never auto
                    The three cases are distinguished by a marker on
                    last_error ('auth_error:' / 'rejected:'), so no extra
                    SQLite state is needed.
delivery_unknown -- the request may have reached the server; never
                    auto-retried; inspector is asked to check My Reports
```

These transport states are deliberately distinct from the remote
`diagnostic_reports.status` vocabulary, which stays:
`submitted | in_review | resolved | wont_fix`. A row that becomes
`delivery_unknown` does not claim a report exists in the server.

### MIGRATION

- Fresh install: `onCreate` builds `local_jobs` with the two identity columns
  inline, then creates `local_report_queue` and its indexes. Version **15**.
- Upgrade: `onUpgrade` runs the `oldVersion < 15` branch, which calls
  `ReportQueueSchema.applyV15()`:
  `ALTER TABLE local_jobs ADD COLUMN supabase_application_id TEXT`,
  `ALTER TABLE local_jobs ADD COLUMN bridge_source_id TEXT`, then creates
  `local_report_queue` and its indexes. Existing data is preserved; no table
  is dropped, truncated, or rewritten.
- The queue's `CREATE TABLE`/`CREATE INDEX` SQL lives in
  `lib/core/services/report_queue_schema.dart` rather than in
  `db_helper.dart`. DBHelper still owns the version number and the
  `onUpgrade` branch; the separate file exists because the queue is a separate
  transport, and because the migration suites that rebuild a fixture database
  scrape `CREATE TABLE` statements out of `db_helper.dart` with a pattern that
  stops at the first `)` — which the queue's nested `CHECK` constraints would
  otherwise break.

### VERIFICATION

Executable tests covering this migration:

- `test/sqlite_v15_local_report_queue_test.dart`
  - fresh v15 database contains `local_report_queue` with the full column contract
  - fresh v15 `local_jobs` includes both identity columns
  - all four approved indexes exist
  - v14 → v15 preserves every existing row in `local_jobs`, `local_inspections`,
    `local_photos`, `pending_actions`, `sync_log_entries`,
    `inspection_job_retention`, `local_route_cache`
  - `pending_actions` schema is unchanged downstream of the upgrade
  - the migration creates no report rows
  - CHECK constraints reject an invalid `report_type`, an invalid
    `queue_state`, a Technical Issue carrying identity, and an Application
    Support missing any identity
  - the partial unique index rejects a duplicate `remote_report_id`

### RESUMABILITY (field-device repair)

`ALTER TABLE ... ADD COLUMN` has no `IF NOT EXISTS` form in SQLite, and a real
device can legitimately reach this migration with an identity column already
present — a previous open interrupted between the two ALTERs, or two opens that
raced the version check. Re-running the ALTER then failed with
`duplicate column name: supabase_application_id`.

`ReportQueueSchema.applyV15` therefore reads the real table with
`PRAGMA table_info` before each ALTER and adds a column only when it is absent,
so the migration is idempotent and resumable. This is a read-then-write guard on
the same SQL; **no schema, column, table, index or CHECK constraint changed.**
`DBHelper.database` also now memoises its in-flight open future, so exactly one
`openDatabase`/`onUpgrade` runs per process.

Verified by `test/sqlite_v15_partial_upgrade_test.dart`:
v14 normal; `supabase_application_id` already present; `bridge_source_id`
already present; BOTH already present (the exact state that crashed on
device); `local_report_queue` already present; all four indexes already
present; v15 applied twice; `pending_actions` unchanged; `local_route_cache`
unchanged; and `local_jobs` is never dropped, truncated or recreated — the
original columns keep their order and only the two approved columns are
appended.
- `test/report_queue_test.dart` and `test/report_contract_test.dart` cover the
  queue's behaviour against this schema: persist-before-send, the five transport
  states, restart survival, error classification, retryability derivation,
  concurrency, and the remote payload for each report type.
- `test/inspection_job_retention_test.dart` asserts the DB version literal, so
  its `version: 14` expectation was updated to `version: 15` and an
  `oldVersion < 15` assertion was added alongside the existing ones.

### ROLLBACK

Feature rollback may `DROP TABLE local_report_queue` and remove the feature
code. SQLite does not support cheap `DROP COLUMN` for the two added
`local_jobs` columns, so a full schema downgrade to version 14 would require
table reconstruction or would leave the additive nullable columns inert. Do
not destroy data merely to restore version 14.

---

## VERSION 13 → 14
## VERSION 13 → 14

**CHANGE:** create `local_route_cache`

### TABLE

```
local_route_cache
```

### COLUMNS

```
job_id          TEXT PRIMARY KEY NOT NULL
geometry_json   TEXT NOT NULL
distance_meters REAL
duration_seconds REAL
origin_lat      REAL NOT NULL
origin_lng      REAL NOT NULL
fetched_at      TEXT NOT NULL
```

### PURPOSE

Persist a previously fetched **real OSRM road route** for an exact FieldSync
job, so genuine road geometry remains available for offline map guidance.

`geometry_json` holds the ordered OSRM/GeoJSON coordinate array as
`[longitude, latitude]` pairs — the order OSRM itself returned. The flip to
Flutter's `LatLng(latitude, longitude)` happens in exactly one place,
`RouteService.decodeRoutePoints`.

Destination coordinates are deliberately **not** stored here:
`local_jobs.parcel_lat` / `parcel_lng` remain the authoritative target, so
duplicating them would allow the two to disagree.

### IDENTITY

`job_id` = `field_jobs.id` / `TaskItem.id` — the exact job UUID already used by
`local_jobs`, `local_inspections` and `InspectionProgress`. One cache row per
exact job. Reference numbers are **not** used as an identity, because they can
repeat across different `field_jobs` rows.

### FRESH INSTALL

Table created by `onCreate`.

### UPGRADE

```
if (oldVersion < 14) {
  CREATE TABLE IF NOT EXISTS local_route_cache(...);
}
```

### DATA SAFETY

- additive only
- no existing table dropped
- no existing row rewritten
- no SyncOutbox action type added
- `CREATE TABLE IF NOT EXISTS` makes the branch idempotent

### SYNC CONTRACT

Local-only navigation-support data.

- not uploaded to Supabase
- not an inspection lifecycle state
- never enqueued to `pending_actions`
- disposable: losing it costs a map redraw, never data

### ROLLBACK

`DROP TABLE local_route_cache` only if explicitly rolling back the feature.
Nothing else references it as business state.

### VERIFICATION

Executable tests covering this migration:

- `test/route_cache_db_test.dart`
  - fresh database contains `local_route_cache` with the exact column contract
  - no `dest_lat` / `dest_lng` duplication, no sync or lifecycle columns
  - upgrade preserves existing `local_jobs` / `local_inspections` rows and all
    pre-existing tables
  - migration is idempotent across repeated application
  - write/read round-trip of geometry, distance, duration, origin, `fetched_at`
  - coordinate order is `[lng, lat]` and is not inverted
  - per-job isolation; one job's route is never readable as another's
  - re-saving a job replaces its previous route
  - malformed cached geometry fails safely
  - route cache never touches the SyncOutbox or lifecycle rows
- `test/inspection_job_retention_test.dart`
  - asserts `version: 14,` and the `if (oldVersion < 14)` branch exist

All destructive migration testing runs against **isolated temporary
databases** built from `DBHelper`'s own DDL. The real device database is never
opened or modified by these tests.