# FieldSync Bridge & Outbox Recovery Architecture

## 1. Executive Summary & Active Loop Status

**Current Active Loop:** Loop 1D Final Lifecycle Closure  
**Loop 1D-R4 Status:** COMPLETED (R4-V3 Verification Finalized)

This document establishes the canonical specification for the FieldSync offline outbox bridge, local SQLite persistence layer, Supabase remote synchronization protocol, and the interrupted outbox recovery subsystem (Loop 1D-R4).

---

## 2. Core Architectural Principles

1. **Deterministic Outbox & Durable Identity:**
   - Every offline-capable operational change is converted to a durable outbox record (`pending_actions` in SQLite) before or atomically with local state changes.
   - Enqueueing uses deterministic IDs for single-card items (`gps_confirm_{job_id}`, `mark_ongoing_{job_id}`, `checklist_update_{job_id}`, `findings_update_{job_id}`, `current_step_update_{job_id}`) and unique UUIDs for multi-event submissions (`submit_inspection`).
   - SQLite table schema strictly enforces non-null metadata: `id`, `type`, `job_id`, `payload`, `status`, `retry_count`, `created_at`, `updated_at`.

2. **Conditional Ownership & Enqueue-vs-ACK Safety (R4-V3):**
   - When an outbox action is in-flight during a drain pass (`status = 'syncing'`), user edits enqueue a newer payload that replaces the row in SQLite with `status = 'pending'`.
   - All completion and error transitions (`DBHelper.markActionSynced`, `DBHelper.markActionFailed`, `DBHelper.markActionConflict`) strictly require `WHERE id = ? AND status = 'syncing'`.
   - If an in-flight drain pass finishes after a replacement action was enqueued, the zero-row conditional update safely preserves the new replacement payload in `pending` status for the subsequent drain pass.

3. **Startup Interrupted Claim Recovery:**
   - A single startup recovery pass (`DBHelper.recoverAbandonedClaims()`) identifies any actions left in `syncing` state across process boundaries or unexpected restarts.
   - Interrupted actions are converted to `status = 'failed'` with the diagnostic marker `r4RecoveryRequired: true` injected into their JSON payload.
   - The outbox drain routes actions with `r4RecoveryRequired: true` strictly through `_reconcileInterruptedAction`, which performs read-before-write validation against remote Supabase state before applying conditional updates.

4. **Remote Reconciliation & Timestamp Durability:**
   - **Pre-flight Status Checks:** Reconciles against remote job status (`assigned`, `approved`, `in_progress`, `completed`). Stale operations on already `completed` remote jobs are recognized as satisfied or safely rejected with conflict without regressing remote state.
   - **Timestamp Preservation:** `submit_inspection` actions preserve the exact original `submittedAt` from the payload; if absent, they fall back durably to the action's `created_at`. Empty or missing timestamps reject with conflict.
   - **Conditional Business Updates:** Recovery updates use optimistic concurrency control (`updated_at` / `cachedUpdatedAtSnapshot` verification). Zero rows affected immediately transitions the action to `status = 'conflict'`, avoiding infinite retry loops.
   - **Cross-Job Isolation:** Recovery failures or conflicts on Job A never block Job B from draining or syncing.

5. **Local Projection and Cache Retention (Loop 1D-R2A/R2B):**
   - Unacknowledged `submit_inspection` actions protect the local `completed` status and cache retention until remote acknowledgement is received.
   - Acknowledgement cleanly retires retention and local projection without leaving orphaned markers.

---

## 3. Lifecycle State Machine Matrix

| Remote Status | Action Type | Pre-condition / Evidence Match | Outcome Status | Remote Mutation |
|---|---|---|---|---|
| `in_progress` / `completed` | `mark_ongoing` | `started_at != null` | `synced` | None (Satisfied/Superseded) |
| `assigned` | `mark_ongoing` | `version == snapshot` | `synced` | Guarded `in_progress` write |
| `completed` | `gps_confirm` | Matching coordinates & timestamp | `synced` | None (Satisfied) |
| `completed` | `gps_confirm` | Differing coordinates / absent evidence | `conflict` | None (Lifecycle protected) |
| `in_progress` | `current_step_update` | `desired_step < remote_step` | `conflict` | None (Progress never regresses) |
| `in_progress` | `checklist_update` | Base timestamp mismatch | `conflict` | None (Stale base trapped) |
| `completed` | `submit_inspection` | Matching payload & `submitted_at` | `synced` | None (Satisfied) |
| `completed` | `submit_inspection` | Differing `submitted_at` / rework revision | `conflict` | None (Conflict preserved) |

---

## 4. Verification and Automated Test Coverage

The recovery architecture is backed by an automated test suite:

1. `test/r4_recovery_test.dart` (Loop 1D-R4 Comprehensive Matrix):
   - Exact `submittedAt` preservation and durable `created_at` fallback.
   - Missing timestamp conflict trap.
   - Zero-row conditional update conflict detection.
   - Same-job historical supersession and evidence immutability.
   - Cross-job isolation.
   - Enqueue-vs-ACK ownership and in-flight replace safety.
   - Single startup recovery deduplication.
   - Diagnostic payload preservation and inertness after sync.

2. `test/r4_photo_loopback_test.dart` (Photo Subroutine & Storage Recovery):
   - Storage upload and metadata write parity.
   - Deterministic UUID v5 photo identity and URL extraction.
   - Fault injection passes (FI-1 metadata fail, FI-2 patch fail, FI-3 storage fail, FI-4 persisted reopen).

3. `test/interrupted_drain_verification_test.dart` (Database Reopen & Recovery Flow).

4. `test/offline_completion_persistence_test.dart` (R2A/R2B Retention & Projection).

5. `test/offline_start_atomicity_test.dart` & `test/offline_start_verification_test.dart` (Offline Start Atomicity).
