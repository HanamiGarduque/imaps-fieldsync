# SUPABASE WEBHOOK SECURITY MIGRATION: ACTUAL EXECUTION STATE & AUDIT RECORD

**Document Version:** 1.0.0  
**Audit Date:** September 6, 2026  
**Auditor / Agent:** Cline (Security Migration Audit & Execution Log)  
**Supabase Project Reference:** `laapipjyprmmaylunxib`  
**Current Git Branch:** `main`  
**Status:** IN PROGRESS (Authentication Troubleshooting & Hardening)

---

## 1. ORIGINAL VULNERABLE ARCHITECTURE

* **Database Webhook Trigger Mechanism:** Database triggers on `public.application_status_tracks` and `public.field_jobs` invoked internal `supabase_functions.http_request()` directly.
* **Embedded Authentication:** The trigger definitions embedded hardcoded HTTP headers containing:
  `Authorization: Bearer <REDACTED_LEGACY_SERVICE_ROLE>`
* **Edge Function Runtime:** Deployed at `/functions/v1/send-push-notification`. It relied on implicit Supabase API Gateway JWT verification without application-level header authentication checks.
* **Downstream Integration:** Handled push notifications dispatched via OneSignal based on inspector subscription records from `inspector_device_subscriptions`.

---

## 2. SECURITY PROBLEM DISCOVERED

* **Hardcoded Privileged Credentials in Tracked SQL:**
  * `full.sql` (lines 623, 627) and `schema.sql` (lines 587, 591) contained plaintext legacy Supabase `service_role` JWTs embedded directly inside trigger DDL.
* **Remote Git Exposure:**
  * Tracked in Git history across remote branches (`origin/main`, `origin/migration/master-merge`) and tags (`refs/tags/architecture-lock`).
* **Vulnerability Severity:** **Critical**.
  * Anyone with read access to the repository or git history could obtain the `service_role` JWT, allowing full bypass of PostgreSQL Row-Level Security (RLS) policies and complete administrative access to the database.

---

## 3. NEW SECRET API KEY STRATEGY

* **Transition from JWT to Opaque Secret API Key:**
  * Discontinue using `Authorization: Bearer <JWT>` for webhook invocations.
  * Adopt the Supabase Secret API key model (`sb_secret_...`) passed explicitly via the `apikey` HTTP request header.
* **Gateway & Application-Level Authentication:**
  * Disable Supabase API Gateway JWT verification (`verify_jwt = false`) for the Edge Function so pg_net webhooks using opaque API keys are not blocked by the gateway.
  * Implement explicit application-level validation inside the Edge Function against `SUPABASE_SECRET_KEYS`.
* **Database Vault & pg_net:**
  * Decrypt the Secret API key dynamically at runtime from `vault.decrypted_secrets`.
  * Dispatch asynchronous HTTP POST requests using `net.http_post()`.

---

## 4. VAULT SETUP & CONFIGURATION

* **Status:** `[COMPLETED]` / `[VERIFIED]`
* **Database Extensions Verified:**
  * `supabase_vault`: Version `0.3.1` (Schema: `vault`)
  * `pg_net`: Version `0.20.0` (Schema: `net` / `extensions`)
* **Vault Secret Configuration:**
  * **Secret Name:** `push_notification_webhook_key`
  * **Secret UUID:** `372157a1-b754-4b18-8bd5-ce57ae3ed4a4`
  * **Payload:** Stored newly generated Secret API key (`<REDACTED_SECRET_API_KEY>`).
  * **Metadata Verification:** Verified secret entry exists in `vault.secrets` / `vault.decrypted_secrets`.

---

## 5. NEW SECURITY DEFINER WEBHOOK FUNCTION

* **Status:** `[COMPLETED]` / `[VERIFIED]`
* **Function Signature:** `public.send_push_notification_webhook() RETURNS trigger`
* **Verified Properties:**
  * **Execution Context:** `SECURITY DEFINER` (executes with creator privileges to read vault secrets).
  * **Owner:** `postgres`
  * **Search Path Hardening:** Explicitly pinned `search_path = public, vault, net, extensions, pg_temp`.
  * **Secret Decryption:** Queries `vault.decrypted_secrets` where `name = 'push_notification_webhook_key'`.
  * **Header Security:** Transmits `apikey: <REDACTED_SECRET_API_KEY>` (no `Authorization: Bearer` JWT).
  * **Destination URL:** `https://laapipjyprmmaylunxib.supabase.co/functions/v1/send-push-notification`
  * **Payload Contract:** Preserves `{ type, table, schema, record, old_record }`.
  * **Error Handling:** Wrapped in `BEGIN ... EXCEPTION` block; logs `RAISE WARNING` on failure without aborting parent database transactions.



---

## 6. FUNCTION PRIVILEGE HARDENING

* **Status:** `[COMPLETED]` / `[VERIFIED]`
* **Access Control List (ACL) Audit:**
  * Initial state contained broad grants to `anon`, `authenticated`, and `service_role`.
  * Hardened by revoking broad execute permissions.
* **Verified Final Permissions:**
  * `postgres`: `EXECUTE` (Allowed)
  * `anon`: `REVOKED` (No direct execute)
  * `authenticated`: `REVOKED` (No direct execute)
  * `service_role`: `REVOKED` (No direct execute)

---

## 7. LIVE DATABASE TRIGGER MIGRATION

* **Status:** `[COMPLETED]` / `[VERIFIED]`
* **Migration Strategy:** Atomically replaced existing triggers inside transactional blocks (`BEGIN; DROP TRIGGER ...; CREATE TRIGGER ...; COMMIT;`).
* **Migrated Triggers:**
  1. **Trigger:** `notify-on-status-change`
     * **Table:** `public.application_status_tracks`
     * **Timing/Event:** `AFTER INSERT ON public.application_status_tracks FOR EACH ROW`
     * **Action:** `EXECUTE FUNCTION public.send_push_notification_webhook()`
  2. **Trigger:** `on_assignment_change`
     * **Table:** `public.field_jobs`
     * **Timing/Event:** `AFTER INSERT ON public.field_jobs FOR EACH ROW`
     * **Action:** `EXECUTE FUNCTION public.send_push_notification_webhook()`
* **Verification:** Confirmed that neither live trigger references `supabase_functions.http_request` or contains legacy JWT credentials.

---

## 8. EDGE FUNCTION RESTRUCTURING & DEPLOYMENT

* **Status:** `[COMPLETED]` / `[VERIFIED]`
* **CLI Setup & Project Link:**
  * Installed Supabase CLI `2.116.0`.
  * Linked successfully to remote project `laapipjyprmmaylunxib`.
* **Directory Restructuring:**
  * Moved entrypoint from `supabase/functions/index.ts` to `supabase/functions/send-push-notification/index.ts` to comply with Supabase CLI deploy conventions.
* **Configuration:**
  * Created `supabase/config.toml` configuring:
    ```toml
    [functions.send-push-notification]
    verify_jwt = false
    ```
* **Remote Deployment:**
  * Executed `supabase functions deploy send-push-notification --no-verify-jwt`.
  * Successfully deployed as version `12`.

---

## 9. CONTROLLED WEBHOOK TEST

* **Status:** `[VERIFIED]`
* **Test Execution:**
  * Inserted controlled test record into `public.application_status_tracks`:
    * Reference: `WEBHOOK-SECURITY-TEST-20260905`
    * Resulting Record ID: `20`
* **Observed Pipeline Path:**
  * Database `INSERT` succeeded.
  * Trigger `notify-on-status-change` fired.
  * `public.send_push_notification_webhook()` executed and read secret from Vault.
  * `pg_net` successfully sent HTTP POST request to `/functions/v1/send-push-notification`.
  * Request arrived at deployed Edge Function instance.

---

## 10. RUNTIME 401 FAILURE & OBSERVATIONS

* **Status:** `[FAILED]` (Edge Function Authentication Stage)
* **Observed Response:**
  * HTTP Status: `401 Unauthorized`
  * Edge Function Log:
    ```text
    Unauthorized webhook invocation: missing or invalid apikey header
    ```
* **Implication:**
  * Connectivity from `Database Trigger → pg_net → Edge Function` is operational.
  * The Edge Function rejected the incoming request during internal API key validation.


---

## 11. SUSPECTED AUTHENTICATION ROOT CAUSE

* **Status:** `[STRONGLY INDICATED]` (Pending local/remote environment variable confirmation)
* **Diagnostic Breakdown:**
  1. **Dashboard Key Hierarchy:** The Supabase Dashboard holds multiple Secret API keys:
     * A default key (`default`).
     * A newly generated key named `Supakey`.
  2. **Vault Secret Generation:** Vault secret `push_notification_webhook_key` was populated with the new `Supakey` secret.
  3. **Edge Function Parsing Logic:** The deployed Edge Function extracts the secret via:
     ```typescript
     const secretKeys = JSON.parse(secretKeysRaw);
     expectedSecretKey = secretKeys.default;
     ```
  4. **Key Mismatch:** The Edge Function strictly compared incoming `apikey` against `secretKeys.default`, whereas `pg_net` was transmitting the key corresponding to `Supakey`.
  5. **Legacy Fallback Debt:** The function code currently retains fallback checks against `SUPABASE_SERVICE_ROLE_KEY` / `SUPABASE_SECRET_KEY`, which contradicts the objective of eliminating legacy service role dependencies.

---

## 12. COMPLETED VS. PENDING MIGRATION ITEMS

| Area | Item / Task | Status | Environment |
|---|---|---|---|
| **CLI** | CLI installation (2.116.0) & project link (`laapipjyprmmaylunxib`) | `COMPLETED` | Local / Tooling |
| **Edge Function** | Directory restructure to `send-push-notification/index.ts` | `COMPLETED` | Local Repo |
| **Edge Function** | Creation of `supabase/config.toml` (`verify_jwt = false`) | `COMPLETED` | Local Repo |
| **Edge Function** | Remote function deployment (v12) | `COMPLETED` | Remote Cloud |
| **Vault** | Extensions verification (`supabase_vault` 0.3.1, `pg_net` 0.20.0) | `COMPLETED` | Live DB |
| **Vault** | Secret creation (`push_notification_webhook_key`, ID: `372157a1-...`) | `COMPLETED` | Live DB |
| **Database** | `public.send_push_notification_webhook()` creation | `COMPLETED` | Live DB |
| **Database** | Execution permissions tightened to `postgres` only | `COMPLETED` | Live DB |
| **Database** | Atomic migration of `notify-on-status-change` trigger | `COMPLETED` | Live DB |
| **Database** | Atomic migration of `on_assignment_change` trigger | `COMPLETED` | Live DB |
| **Testing** | Controlled invocation of `application_status_tracks` | `VERIFIED` | Live DB / Gateway |
| **Edge Function** | Resolution of `SUPABASE_SECRET_KEYS.Supakey` auth parsing | `PENDING` | Local / Remote |
| **Edge Function** | Removal of legacy `SUPABASE_SERVICE_ROLE_KEY` fallbacks | `PENDING` | Local Repo |
| **Edge Function** | Function redeployment with authentication correction | `PENDING` | Remote Cloud |
| **Testing** | End-to-end webhook validation with `200 OK` HTTP response | `PENDING` | Live Integration |
| **Testing** | Verification of `field_jobs` assignment notification trigger | `PENDING` | Live Integration |
| **Mobile Integration**| Verification of push delivery to OneSignal registered devices | `PENDING` | Mobile Client |
| **Credential Rotation**| Dashboard revocation of leaked legacy `service_role` JWT | `PENDING` | Supabase Dashboard |
| **Repo Sanitization** | Replacement of exposed JWT tokens in `full.sql` & `schema.sql` | `PENDING` | Local Repo / Git |
| **Repo Sanitization** | Git history purging / remote push of cleaned branches | `PENDING` | Remote GitHub |

---

## 13. REMAINING PRODUCTION STEPS BEFORE ROTATION & CLOSURE

The migration cannot be marked complete until the following sequence is executed:

1. **Edge Function Authentication Correction:**
   * Update `supabase/functions/send-push-notification/index.ts` to parse `secretKeys.Supakey ?? secretKeys.default`.
   * Strip legacy environment variable fallbacks (`SUPABASE_SERVICE_ROLE_KEY`).
2. **Edge Function Redeployment:**
   * Deploy the updated handler using `supabase functions deploy send-push-notification --no-verify-jwt`.
3. **End-to-End Verification (application_status_tracks):**
   * Perform test insertion into `public.application_status_tracks`.
   * Confirm `net._http_response` records `status_code = 200`.
   * Confirm Edge Function runtime logs report successful webhook execution.
4. **End-to-End Verification (field_jobs):**
   * Perform controlled insertion into `public.field_jobs`.
   * Verify notification dispatch log and OneSignal receipt.
5. **Sanitize Repository SQL Files:**
   * Scrub hardcoded JWT strings from `full.sql` and `schema.sql`, replacing them with migration-hardened SQL using Vault placeholders.
6. **Revoke Compromised Legacy Service Role Key:**
   * In Supabase Dashboard (`Project Settings` → `API`), delete/revoke the compromised legacy service role key.
   * Verify Flutter client and background operations remain unaffected.

---

## 14. CURRENT SECURITY IMPLICATIONS

* **Active Window of Exposure:** The leaked legacy `service_role` key remains valid and capable of bypassing Row-Level Security until step 6 of the remaining steps is completed.
* **Non-Impacting Mobile App Delivery:** The failure of mobile push notifications upon task assignment is currently isolated to the Edge Function `401 Unauthorized` response and does not indicate a Flutter client bug.
* **Safe State of Database Webhooks:** The live database triggers are already fully detached from the compromised JWT and are safely using Vault encryption and `apikey` transport.

---

## 15. EVIDENCE & VERIFICATION QUERIES

### Verification Query 1: Confirm Triggers Detached from Legacy Functions
```sql
SELECT 
    event_object_table AS table_name,
    trigger_name,
    action_timing,
    event_manipulation AS event,
    action_statement
FROM information_schema.triggers
WHERE trigger_name IN ('notify-on-status-change', 'on_assignment_change');
```
*Expected Result:* `action_statement` must reference `EXECUTE FUNCTION public.send_push_notification_webhook()`.

### Verification Query 2: Inspect HTTP Response Queue in pg_net
```sql
SELECT 
    id,
    status_code,
    error_msg,
    created
FROM net._http_response
ORDER BY created DESC
LIMIT 5;
```
*Target Result after Auth Fix:* `status_code` = `200`.

---
*End of Actual Execution State Document.*


