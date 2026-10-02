# FieldSync — Local SQLite Schema Change Log

Canonical record of **versioned local SQLite schema changes** in FieldSync.

Scope: the on-device SQLCipher database (`imaps_fieldsync.db`, owned by
`lib/core/services/db_helper.dart`). This file records **schema only** — not UI
features, not sync behaviour, not Supabase.

Every version bump and every `onUpgrade` branch must have an entry here.

---

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