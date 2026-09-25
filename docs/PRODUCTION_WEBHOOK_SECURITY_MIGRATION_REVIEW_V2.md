# PRODUCTION WEBHOOK SECURITY MIGRATION REVIEW (V2)
**Document Version:** 2.0.0  
**Audit Date:** September 6, 2026  
**Auditor / Agent:** Cline (Security Diagnostic Review)  
**Status:** MANUAL REVIEW ONLY — NO AUTOMATIC EXECUTION  
**Scope:** Supabase Database Webhook Hardening, Vault-Backed Secret Migration, Edge Function Service-to-Service Authentication, and Credential Revocation Preparation.

---

## 1. CURRENT ARCHITECTURE VERIFIED

A comprehensive diagnostic audit of the local repository and Supabase project configuration confirms the following architectural state:

* **Platform / Environment:** PostgreSQL 15+ (Supabase Managed Cloud), Deno Edge Runtime, Flutter Mobile Client.
* **Supabase Project Reference:** `laapipjyprmmaylunxib` (verified via `supabase/.temp/project-ref` and `supabase/.temp/linked-project.json`).
* **Installed Database Extensions (verified via `full.sql`):**
  * `supabase_vault` (installed in schema `vault`) — provides cryptographic key management via `vault.create_secret()`, `vault.update_secret()`, and decrypted view `vault.decrypted_secrets`.
  * `pg_net` (installed in schema `extensions` / `net`) — provides asynchronous non-blocking HTTP client capabilities (`net.http_post()`).
  * `pgcrypto` (installed in schema `extensions`).
  * `postgis` (installed in schema `public`).
  * `pg_stat_statements` (installed in schema `extensions`).
  * `uuid-ossp` (installed in schema `extensions`).
* **Supabase Edge Functions:**
  * Root path: `supabase/functions/`
  * Function file: `supabase/functions/index.ts` (defines the `send-push-notification` push dispatcher).
  * Project Configuration: `supabase/config.toml` is currently **absent** from the local repository tree.
* **Database Tables Linked to Webhooks:**
  * `public.application_status_tracks`: Tracks zoning application lifecycle status changes.
  * `public.field_jobs`: Tracks field inspection assignments and scheduled visits.
  * `public.inspector_device_subscriptions`: Registry mapping inspector UUIDs to OneSignal device push tokens (`device_token`).
* **Current Webhook Trigger Mechanism:**
  * Direct invocation of internal `supabase_functions.http_request()` inside table trigger definitions.
  * Webhook destination: `https://laapipjyprmmaylunxib.supabase.co/functions/v1/send-push-notification` (POST).

---

## 2. EXISTING EDGE FUNCTION AUTH MODEL

### A. Source Code Audit (`supabase/functions/index.ts`)
Inspection of `supabase/functions/index.ts` reveals the following runtime behavior:
```typescript
Deno.serve(async (req) => {
  const payload = await req.json()
  const record = payload.record
  const oldRecord = payload.old_record
  ...
  const secretKeysRaw = Deno.env.get('SUPABASE_SECRET_KEYS')!
  const secretKeys = JSON.parse(secretKeysRaw)
  const serviceRoleKey = secretKeys.default

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    serviceRoleKey
  )
  ...
```

### B. Authentication Model Findings
1. **Application-Level Handler:** `index.ts` currently performs **no application-level authentication check** on incoming request headers. It immediately assumes incoming calls are pre-authenticated and parses `await req.json()`.
2. **Supabase Gateway Level:** By default, all Supabase Edge Functions require an incoming HTTP header containing a valid signed Supabase JWT in the format `Authorization: Bearer <JWT>` unless JWT verification is explicitly disabled via `verify_jwt = false` or the CLI flag `--no-verify-jwt`.
3. **Internal Key Usage:** The Edge Function queries `SUPABASE_SECRET_KEYS` (or legacy `SUPABASE_SERVICE_ROLE_KEY`) from `Deno.env` to instantiate an administrative Supabase client (`serviceRoleKey`) used to bypass RLS when querying `inspector_device_subscriptions`.
4. **Why the New Key Model Breaks the Legacy Gateway Model:**
   * The new Supabase Secret API key format is an opaque token: `sb_secret_...`.
   * It is **not** a signed HS256/RS256 JSON Web Token (JWT).
   * If `Authorization: Bearer <NEW_SUPABASE_SECRET_API_KEY>` is sent to an Edge Function that has gateway JWT verification enabled, the API gateway will attempt to decode the secret as a JWT and fail immediately with `401 Unauthorized` / `Invalid JWT`.
   * Therefore, transitioning to the new Secret API key requires **explicit service-to-service authentication**:
     * Setting `verify_jwt = false` at the gateway level.
     * Passing the secret key in the `apikey: <NEW_SUPABASE_SECRET_API_KEY>` header.
     * Adding explicit secret key validation in the Edge Function TypeScript handler.

---

## 3. EXISTING TRIGGER DEFINITIONS

### A. Trigger Definitions in Source SQL (`full.sql` & `schema.sql`)
The repository contains two triggers configured to call the `send-push-notification` Edge Function:

```sql
-- 1. notify-on-status-change (full.sql: line 623, schema.sql: line 587)
CREATE OR REPLACE TRIGGER "notify-on-status-change" 
AFTER INSERT ON "public"."application_status_tracks" 
FOR EACH ROW 
EXECUTE FUNCTION "supabase_functions"."http_request"(
    'https://laapipjyprmmaylunxib.supabase.co/functions/v1/send-push-notification', 
    'POST', 
    '{"Content-type":"application/json","Authorization":"Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxhYXBpcGp5cHJtbWF5bHVueGliIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3Nzc0OTIxMSwiZXhwIjoyMDkzMzI1MjExfQ.gji-rWjO0waPNKf8kjJJZY6508rK9LNYFelPcvVE_q0"}', 
    '{}', 
    '5000'
);

-- 2. on_assignment_change (full.sql: line 627, schema.sql: line 591)
CREATE OR REPLACE TRIGGER "on_assignment_change" 
AFTER INSERT ON "public"."field_jobs" 
FOR EACH ROW 
EXECUTE FUNCTION "supabase_functions"."http_request"(
    'https://laapipjyprmmaylunxib.supabase.co/functions/v1/send-push-notification', 
    'POST', 
    '{"Content-type":"application/json","Authorization":"Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxhYXBpcGp5cHJtbWF5bHVueGliIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3Nzc0OTIxMSwiZXhwIjoyMDkzMzI1MjExfQ.gji-rWjO0waPNKf8kjJJZY6508rK9LNYFelPcvVE_q0"}', 
    '{}', 
    '5000'
);
```

### B. Payload Structure & Contract Comparison
When invoked by Supabase triggers, `supabase_functions.http_request` generates the standard Supabase webhook payload:
```json
{
  "type": "INSERT",
  "table": "<table_name>",
  "schema": "public",
  "record": { ...NEW row data... },
  "old_record": null
}
```

* **Table 1 (`public.application_status_tracks`):**
  * Columns in `record`: `id`, `reference_number`, `masked_applicant_name`, `status`, `created_at`, `cert_type`, `stage_order`, `note`.
* **Table 2 (`public.field_jobs`):**
  * Columns in `record`: `id`, `local_inspection_id`, `supabase_application_id`, `status`, `scheduled_date`, `assigned_inspector_id`, `supabase_parcel_id`, `findings`, `checklist_data`, etc.
* **Payload Verification:** Both triggers execute on `AFTER INSERT`, use `POST`, send to the identical URL endpoint, and adhere to the standard `{ type, table, schema, record, old_record }` contract. The migration function must construct and preserve this exact schema.

---

## 4. CORRECT NEW-KEY AUTHENTICATION MODEL

### A. Secret API Key Format
The new Supabase credential model uses an opaque Secret API Key:
```text
<NEW_SUPABASE_SECRET_API_KEY> (format: sb_secret_...)
```

### B. Header Specification
* **CORRECT:**
  ```http
  apikey: <NEW_SUPABASE_SECRET_API_KEY>
  Content-Type: application/json
  ```
* **PROHIBITED (DO NOT USE):**
  ```http
  Authorization: Bearer <NEW_SUPABASE_SECRET_API_KEY>
  ```
  *(Secret API keys are not JWTs. Passing them in the `Authorization: Bearer` header causes JWT verification errors at the gateway).*

### C. Target Service-to-Service Architecture
1. **Database Tier:** A hardened PostgreSQL `SECURITY DEFINER` function retrieves `<NEW_SUPABASE_SECRET_API_KEY>` dynamically from `vault.decrypted_secrets` at execution time and issues an asynchronous `net.http_post()` with the `apikey: <NEW_SUPABASE_SECRET_API_KEY>` header.
2. **Gateway Tier:** The Edge Function gateway is configured with `verify_jwt = false` so that non-JWT service calls are permitted through to the Deno runtime.
3. **Edge Function Tier:** The Deno handler validates the incoming `apikey` header against the server-side environment secret before executing application logic.

---

## 5. VAULT MIGRATION SQL — MANUAL REVIEW ONLY

> **IMPORTANT:** DO NOT AUTO-EXECUTE. This SQL script must be manually reviewed and executed exclusively inside the **Supabase Dashboard SQL Editor** by an authorized administrator.

```sql
-- =============================================================================
-- STEP 1: STORE NEW SECRET API KEY IN SUPABASE VAULT
-- Target Schema: vault
-- Function: vault.create_secret / vault.update_secret
-- Placeholder: <NEW_SUPABASE_SECRET_API_KEY>
-- =============================================================================

DO $$
DECLARE
    v_secret_name text := 'edge_function_secret_key';
    v_secret_desc text := 'Supabase Secret API Key for send-push-notification webhook';
    v_secret_id uuid;
BEGIN
    -- Check if the secret entry already exists in Supabase Vault
    SELECT id INTO v_secret_id
    FROM vault.decrypted_secrets
    WHERE name = v_secret_name
    LIMIT 1;

    IF v_secret_id IS NULL THEN
        -- Insert new secret into Vault
        PERFORM vault.create_secret(
            '<NEW_SUPABASE_SECRET_API_KEY>',
            v_secret_name,
            v_secret_desc
        );
        RAISE NOTICE 'Vault secret "%" successfully created.', v_secret_name;
    ELSE
        -- Update existing secret in Vault
        PERFORM vault.update_secret(
            v_secret_id,
            '<NEW_SUPABASE_SECRET_API_KEY>',
            v_secret_name,
            v_secret_desc
        );
        RAISE NOTICE 'Vault secret "%" (ID: %) successfully updated.', v_secret_name, v_secret_id;
    END IF;
END $$;
```

---

## 6. DATABASE FUNCTION SQL — MANUAL REVIEW ONLY

```sql
-- =============================================================================
-- STEP 2: CREATE HARDENED SECURITY DEFINER TRIGGER FUNCTION
-- Target Function: public.send_push_notification_webhook()
-- Security Controls: Fixed search_path (pg_temp last), Vault integration,
--                   non-blocking pg_net dispatch, diagnosable error logging.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.send_push_notification_webhook()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, extensions, vault, net, public, pg_temp
AS $$
DECLARE
    v_secret text;
    v_payload jsonb;
    v_url text := 'https://laapipjyprmmaylunxib.supabase.co/functions/v1/send-push-notification';
BEGIN
    -- 1. Retrieve the Secret API key from Supabase Vault
    SELECT decrypted_secret INTO v_secret
    FROM vault.decrypted_secrets
    WHERE name = 'edge_function_secret_key'
    LIMIT 1;

    -- 2. Guard against missing or empty Vault configuration
    IF v_secret IS NULL OR pg_catalog.length(pg_catalog.trim(v_secret)) = 0 THEN
        RAISE WARNING 'send_push_notification_webhook: Vault secret "edge_function_secret_key" not found or empty. Webhook skipped.';
        RETURN NEW;
    END IF;

    -- 3. Construct exact Supabase standard webhook payload preserving TG_OP and table metadata
    v_payload := pg_catalog.jsonb_build_object(
        'type', TG_OP,
        'table', TG_TABLE_NAME,
        'schema', TG_TABLE_SCHEMA,
        'record', pg_catalog.row_to_json(NEW),
        'old_record', CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN pg_catalog.row_to_json(OLD) ELSE NULL END
    );

    -- 4. Dispatch non-blocking HTTP POST via pg_net with Secret API key in "apikey" header
    PERFORM net.http_post(
        url := v_url,
        headers := pg_catalog.jsonb_build_object(
            'Content-Type', 'application/json',
            'apikey', v_secret
        ),
        body := v_payload,
        timeout_milliseconds := 5000
    );

    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        -- Log warning to PostgreSQL server logs without aborting client database transaction
        RAISE WARNING 'send_push_notification_webhook execution failed: % (SQLSTATE: %)', SQLERRM, SQLSTATE;
        RETURN NEW;
END;
$$;

-- Enforce ownership by administrative superuser
ALTER FUNCTION public.send_push_notification_webhook() OWNER TO postgres;
```

---

## 7. TRIGGER REPLACEMENT SQL — MANUAL REVIEW ONLY

```sql
-- =============================================================================
-- STEP 3: ATTACH REPLACED TRIGGERS TO APPLICATION TABLES
-- Targets: public.application_status_tracks, public.field_jobs
-- =============================================================================

-- 1. Drop existing triggers containing exposed legacy JWT credentials
DROP TRIGGER IF EXISTS "notify-on-status-change" ON public.application_status_tracks;
DROP TRIGGER IF EXISTS "on_assignment_change" ON public.field_jobs;

-- 2. Create hardened Vault-backed triggers
CREATE TRIGGER "notify-on-status-change"
AFTER INSERT ON public.application_status_tracks
FOR EACH ROW
EXECUTE FUNCTION public.send_push_notification_webhook();

CREATE TRIGGER "on_assignment_change"
AFTER INSERT ON public.field_jobs
FOR EACH ROW
EXECUTE FUNCTION public.send_push_notification_webhook();
```

---

## 8. REQUIRED PRIVILEGES

### A. Principle of Least Privilege Model
| Database Object | Role / Grantee | Privilege | Justification |
|---|---|---|---|
| `public.send_push_notification_webhook()` | `PUBLIC` | **REVOKE ALL** | Closes default PostgreSQL public execution permissions. |
| `public.send_push_notification_webhook()` | `authenticated` | `EXECUTE` | Required so logged-in inspectors updating jobs can trigger the webhook. |
| `public.send_push_notification_webhook()` | `anon` | `EXECUTE` | **Required:** `public.application_status_tracks` has an RLS policy (`Allow public insert access`) allowing `anon` inserts. If `EXECUTE` is revoked from `anon`, public status tracking inserts will fail with a permission error. |
| `public.send_push_notification_webhook()` | `service_role` | `EXECUTE` | Required for administrative backend processes and batch inserts. |
| `vault.decrypted_secrets` | `anon`, `authenticated`, `PUBLIC` | **NO ACCESS (REVOKED)** | Unprivileged roles must **never** read secrets. Access is granted solely to `postgres` (the `SECURITY DEFINER` owner). |
| `net.http_post()` | `anon`, `authenticated`, `PUBLIC` | **NO ACCESS (REVOKED)** | Unprivileged roles cannot make arbitrary outbound network requests directly. |

### B. Privilege Management SQL
```sql
-- Revoke default public execution
REVOKE ALL ON FUNCTION public.send_push_notification_webhook() FROM PUBLIC;

-- Grant execution to roles authorized to perform INSERTs on target tables
GRANT EXECUTE ON FUNCTION public.send_push_notification_webhook() TO authenticated;
GRANT EXECUTE ON FUNCTION public.send_push_notification_webhook() TO anon;
GRANT EXECUTE ON FUNCTION public.send_push_notification_webhook() TO service_role;
```

### C. PostgREST RPC Protection
Because `send_push_notification_webhook()` returns `trigger`, PostgREST **will not expose it** as an RPC endpoint (`/rest/v1/rpc/...`). It cannot be invoked directly via HTTP; it can only fire in response to valid table modifications.

---

## 9. EDGE FUNCTION / config.toml CHANGES REQUIRED

### A. Supabase CLI Configuration (`supabase/config.toml`)
Create or update `supabase/config.toml` to disable gateway-level JWT verification for the webhook function:
```toml
[functions.send-push-notification]
verify_jwt = false
```
*(Alternatively, when deploying via CLI: `supabase functions deploy send-push-notification --no-verify-jwt`)*.

### B. Edge Function Authorization Handler (`supabase/functions/index.ts`)
Update `supabase/functions/index.ts` to implement explicit secret key validation and robust payload handling:

```typescript
import { createClient } from 'jsr:@supabase/supabase-js@2'

Deno.serve(async (req) => {
  // 1. Authorize caller via 'apikey' header (Service-to-Service Authentication)
  const incomingApiKey = req.headers.get('apikey') || req.headers.get('x-api-key')
  const secretKeysRaw = Deno.env.get('SUPABASE_SECRET_KEYS')
  let expectedSecretKey: string | undefined

  if (secretKeysRaw) {
    try {
      const secretKeys = JSON.parse(secretKeysRaw)
      expectedSecretKey = secretKeys.default
    } catch {
      expectedSecretKey = secretKeysRaw
    }
  } else {
    expectedSecretKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || Deno.env.get('SUPABASE_SECRET_KEY')
  }

  if (!incomingApiKey || incomingApiKey !== expectedSecretKey) {
    console.error('Unauthorized webhook invocation: invalid or missing apikey header')
    return new Response(JSON.stringify({ error: 'Unauthorized: Invalid API key' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  // 2. Parse Webhook Payload
  const payload = await req.json()
  const record = payload.record
  const oldRecord = payload.old_record
  console.log('Webhook triggered. Event:', payload.type, 'Table:', payload.table, 'Record:', JSON.stringify(record))

  // 3. Initialize Supabase Administrative Client
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    expectedSecretKey
  )

  // 4. Resolve Inspector ID (handles field_jobs 'assigned_inspector_id' and inspection_assignments 'inspector_id')
  const inspectorId = record.assigned_inspector_id || record.inspector_id
  if (!inspectorId) {
    console.log('Skipping push notification: no inspector_id/assigned_inspector_id present in record')
    return new Response(
      JSON.stringify({ skipped: true, reason: 'no inspector id in record' }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    )
  }

  // 5. Query Device Subscriptions
  const { data: devices, error } = await supabase
    .from('inspector_device_subscriptions')
    .select('device_token')
    .eq('inspector_id', inspectorId)

  console.log('Devices found:', JSON.stringify(devices))
  console.log('Query error:', JSON.stringify(error))

  if (error || !devices?.length) {
    console.log('Skipping: no devices found or query error')
    return new Response(
      JSON.stringify({ skipped: true, reason: error?.message ?? 'no devices found' }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    )
  }

  // 6. Build Notification Message
  const isNewAssignment = !oldRecord
  const applicantName = record.applicant_name ?? 'Inspection Task'
  const barangay = record.barangay ? ` - ${record.barangay}` : ''
  const message = isNewAssignment
    ? `New inspection assignment: ${applicantName}${barangay}`
    : `Assignment update: ${applicantName} is now ${record.status}`

  const restApiKey = Deno.env.get('ONESIGNAL_REST_API_KEY')!
  const appId = Deno.env.get('ONESIGNAL_APP_ID')!

  // 7. Dispatch to OneSignal API
  const oneSignalRes = await fetch('https://onesignal.com/api/v1/notifications', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Key ${restApiKey}`,
    },
    body: JSON.stringify({
      app_id: appId,
      include_subscription_ids: devices.map((d: { device_token: string }) => d.device_token),
      contents: { en: message },
      headings: { en: 'iMAPS FieldSync' },
    }),
  })

  const result = await oneSignalRes.json()
  console.log('OneSignal response status:', oneSignalRes.status)
  return new Response(JSON.stringify(result), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  })
})
```

---

## 10. VERIFICATION SQL

Run these read-only queries in the Supabase Dashboard SQL Editor to verify the migration state:

```sql
-- 1. Verify Secret Presence in Vault (Masked output)
SELECT 
    id,
    name,
    description,
    created_at,
    updated_at,
    (length(decrypted_secret) > 0) AS secret_is_populated,
    substring(decrypted_secret from 1 for 10) || '...' AS secret_prefix
FROM vault.decrypted_secrets
WHERE name = 'edge_function_secret_key';

-- 2. Verify Function Definition, Owner, and search_path
SELECT 
    p.proname AS function_name,
    pg_catalog.pg_get_userbyid(p.proowner) AS owner_name,
    p.prosecdef AS is_security_definer,
    p.proconfig AS search_path_configuration
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' 
  AND p.proname = 'send_push_notification_webhook';

-- 3. Verify Trigger Attachments
SELECT 
    t.tgname AS trigger_name,
    c.relname AS table_name,
    pg_catalog.pg_get_triggerdef(t.oid) AS trigger_definition
FROM pg_catalog.pg_trigger t
JOIN pg_catalog.pg_class c ON c.oid = t.tgrelid
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND t.tgname IN ('notify-on-status-change', 'on_assignment_change')
  AND NOT t.tgisinternal;

-- 4. Monitor Asynchronous HTTP Webhook Activity (pg_net response queue)
SELECT 
    id,
    status_code,
    error_msg,
    created
FROM net._http_response
ORDER BY created DESC
LIMIT 10;
```

---

## 11. WEBHOOK TEST PLAN

### A. Pre-Test Verification
1. Ensure the secret is populated in Supabase Vault (`name = 'edge_function_secret_key'`).
2. Ensure Edge Function `send-push-notification` is deployed with `verify_jwt = false`.

### B. Execution Step 1: Controlled Database Trigger Test
Execute a test insert inside the SQL Editor:
```sql
-- Insert a test status track entry (will be cleaned up)
INSERT INTO public.application_status_tracks (
    reference_number,
    masked_applicant_name,
    status,
    cert_type,
    stage_order,
    note
) VALUES (
    'TEST-AUDIT-2026',
    'J*** D**',
    'Under Review',
    'Zoning Certificate',
    1,
    'Security Migration Webhook Test'
);
```

### C. Execution Step 2: Query pg_net Response Queue
Within 5 seconds of the insert, execute:
```sql
SELECT 
    id,
    status_code,
    headers,
    body,
    error_msg,
    created
FROM net._http_response
ORDER BY created DESC
LIMIT 1;
```
* **Success Criteria:** `status_code = 200`.

### D. Execution Step 3: Edge Function & Push Logs Verification
1. Open **Supabase Dashboard → Edge Functions → send-push-notification → Logs**.
2. Confirm the webhook request log appears with `Event: INSERT`, `Table: application_status_tracks`.
3. Verify OneSignal log status (or expected skip if no test inspector device is registered).

### E. Execution Step 4: Test Cleanup
```sql
DELETE FROM public.application_status_tracks WHERE reference_number = 'TEST-AUDIT-2026';
```

---

## 12. SAFE ROLLBACK PLAN

If an unexpected issue arises during migration, execute this rollback plan.  
> **SECURITY MANDATE:** Rollback must **NEVER** re-introduce hardcoded credentials into repository SQL files.

### A. Immediate Webhook Disablement (Safe SQL)
```sql
-- Drop the Vault-backed triggers to halt automated webhook calls immediately
DROP TRIGGER IF EXISTS "notify-on-status-change" ON public.application_status_tracks;
DROP TRIGGER IF EXISTS "on_assignment_change" ON public.field_jobs;

-- Drop the trigger function
DROP FUNCTION IF EXISTS public.send_push_notification_webhook();
```

### B. Manual Restoration of Previous Trigger Function (If Required)
If you must restore the legacy webhook behavior temporarily before debugging:
1. Do **not** commit credentials to Git.
2. Manually execute the trigger creation in the **Supabase Dashboard SQL Editor only**, passing the required API key manually at prompt time.

---

## 13. LEGACY SERVICE_ROLE USAGE AUDIT

A repository-wide regex search was performed across all 106 tracked files for `SUPABASE_SERVICE_ROLE_KEY`, `service_role`, `SERVICE_ROLE`, `Authorization: Bearer`, and hardcoded Supabase JWTs:

| Category | Location | Usage Description | Status / Action |
|---|---|---|---|
| **Confirmed Repository Exposure** | `full.sql` (lines 623, 627) | Exposed legacy `service_role` JWT in trigger DDL | **Critical** — Subject of this remediation. Key must be revoked in Supabase Dashboard. |
| **Confirmed Repository Exposure** | `schema.sql` (lines 587, 591) | Exposed legacy `service_role` JWT in trigger DDL | **Critical** — Subject of this remediation. Key must be revoked in Supabase Dashboard. |
| **Confirmed Edge Function Variable** | `supabase/functions/index.ts` (line 10) | `Deno.env.get('SUPABASE_SECRET_KEYS')` | Valid server-side environment access; safe when secrets are injected via Supabase Secrets engine. |
| **Confirmed Client Non-Usage** | `lib/**` (Flutter Dart files) | Sourced via `dotenv.env['SUPABASE_PUBLISHABLE_KEY']` | **Clean** — Flutter client exclusively uses publishable/anon key. No `service_role` reference. |
| **Confirmed Config Non-Usage** | `.env` | Sourced via `.gitignore` (line 54) | **Clean** — `.env` is properly ignored and contains no service_role keys. |
| **Live Project External Usage** | Supabase Dashboard / External Services | Third-party integrations, manual DBA scripts, or external cron jobs | **Manual Verification Required** — Administrator must verify that no external automation depends on the old service_role key prior to revocation. |

---

## 14. GIT EXPOSURE / HISTORY IMPACT

* **Affected Branches Containing Leaked Key:**
  * `main`
  * `migration/master-merge`
  * `agents/audit-enhancement-roadmap-tracker`
  * `agents/core-migration-script-v2-fixes`
  * `agents/final-list-map-string-dynamic-checklistdata-lib`
  * `agents/google-oauth-signin-integration`
  * `chore/insight-widgets-token-unify`
  * `feature/route-map`
  * `step-7-entrypoint`
  * `temp-main-update`
* **Affected Git Tags:**
  * `architecture-lock` (commit `84f8540c8aebb1f7f695caea7fb476b81ec31b97`)
* **First Introducing Commit:**
  * Commit `cb59fc73e3f33af934eb258b5969b9e69e3f569c` (Date: Sat Jul 11 2026)
* **Exposure Risk Analysis:**
  Because the repository was pushed to remote origins (`origin/main`, `origin/migration/master-merge`), the legacy `service_role` key must be treated as **permanently compromised**.
* **Zero New Exposure Guarantee:**
  The proposed migration SQL in this document contains **only placeholders** (`<NEW_SUPABASE_SECRET_API_KEY>`) and uses dynamic database Vault decryption. Applying this migration introduces zero secrets into Git history.

---

## 15. MANUAL STEPS THAT REQUIRE MY APPROVAL

The following steps must be executed manually by the Supabase project administrator in the exact order specified:

1. [ ] **Step 1: Generate New Secret API Key** in Supabase Dashboard (`Project Settings` → `API Keys` / `Secret Keys`).
2. [ ] **Step 2: Store Key in Supabase Vault** by running Section 5 SQL in the Supabase Dashboard SQL Editor, replacing `<NEW_SUPABASE_SECRET_API_KEY>` with the real `sb_secret_...` key.
3. [ ] **Step 3: Create Hardened Trigger Function** by running Section 6 SQL and Section 8 Privilege SQL in the SQL Editor.
4. [ ] **Step 4: Re-attach Webhook Triggers** by running Section 7 SQL in the SQL Editor.
5. [ ] **Step 5: Deploy Edge Function & Config** with `verify_jwt = false` and update `supabase/functions/index.ts` with the secret validation handler.
6. [ ] **Step 6: Execute Verification Queries & Test Plan** (Sections 10 & 11) to confirm successful `200 OK` webhook execution.
7. [ ] **Step 7: Revoke Leaked Legacy Service Role Key** in the Supabase Dashboard (`Project Settings` → `API` → Delete/Revoke legacy key).
8. [ ] **Step 8: Sanitize SQL Files in Repository** by replacing exposed JWT strings in `full.sql` and `schema.sql` with safe placeholders.

---

## 16. SECURITY RISKS STILL REMAINING

1. **Active Exposure Window:** The leaked legacy `service_role` key remains capable of bypassing all RLS policies until Step 7 (manual revocation in Supabase Dashboard) is completed.
2. **Gateway JWT vs Secret Key Desynchronization:** If database triggers are updated to send `apikey: <NEW_SUPABASE_SECRET_API_KEY>` before `send-push-notification` is deployed with `verify_jwt = false`, webhook calls will fail at the gateway with `401 Unauthorized`. Step 5 must precede or accompany Step 4.
3. **Historical Commit History:** Even after sanitizing `full.sql` and `schema.sql` in working branches, historical commits retain the exposed credential. Revocation of the key renders historical git exposures completely benign.

---

## 17. FINAL GO / NO-GO

### Criteria Checklist
* [x] Correct Secret API key format (`sb_secret_...`) and header (`apikey: ...`) adopted.
* [x] Plaintext credentials completely eliminated from all migration SQL and replaced with Vault decryption (`vault.decrypted_secrets`).
* [x] Trigger payload contract `{ type, table, schema, record, old_record }` verified and preserved.
* [x] `SECURITY DEFINER` function hardened with explicit `search_path` and `pg_temp` placed last.
* [x] Non-blocking `RAISE WARNING` error handling implemented to prevent transaction breakage.
* [x] PostgreSQL execution privileges verified (including necessary `anon` privilege for public status inserts).
* [x] Service-to-service Edge Function authorization model defined.
* [x] Safe, secret-free rollback strategy documented.

### **DECISION: GO FOR MANUAL REVIEW AND EXECUTION**
The migration SQL package in Sections 5, 6, 7, and 8 is **fully approved for manual execution** in the Supabase Dashboard SQL Editor by the system administrator. All security issues identified in V1 have been corrected.

---
*End of Review Document.*
