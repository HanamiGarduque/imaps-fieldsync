# EDGE FUNCTION 401 RUNTIME AUTHENTICATION INVESTIGATION

**Audit Date:** September 6, 2026  
**Auditor / Agent:** Cline (Security Diagnostic Review)  
**Project Ref:** `laapipjyprmmaylunxib`  
**Target Function:** `send-push-notification`  
**Status:** DIAGNOSTIC REPORT ONLY — READ ONLY (NO CODE/DB/VAULT MODIFICATIONS)

---

## 1. CURRENT DEPLOYED AUTHENTICATION CODE

File: `supabase/functions/send-push-notification/index.ts`

```typescript
Deno.serve(async (req) => {
  // -------------------------------------------------------------------
  // 1. Authenticate incoming request via `apikey` header
  // -------------------------------------------------------------------
  const incomingApiKey = req.headers.get('apikey') ?? req.headers.get('x-api-key')

  let expectedSecretKey: string | undefined

  const secretKeysRaw = Deno.env.get('SUPABASE_SECRET_KEYS')
  if (secretKeysRaw) {
    try {
      const secretKeys = JSON.parse(secretKeysRaw)
      expectedSecretKey = secretKeys.Supakey
    } catch {
      // If the env var is not valid JSON, treat the raw value as the key
      expectedSecretKey = secretKeysRaw
    }
  }

  if (!expectedSecretKey || !incomingApiKey || incomingApiKey !== expectedSecretKey) {
    console.error('Unauthorized webhook invocation: missing or invalid apikey header')
    return new Response(
      JSON.stringify({ error: 'Unauthorized' }),
      { status: 401, headers: { 'Content-Type': 'application/json' } },
    )
  }
  // ...
```

### Static Audit of Code:
* `incomingApiKey`: Read via `req.headers.get('apikey') ?? req.headers.get('x-api-key')`.
* `SUPABASE_SECRET_KEYS`: Parsed as JSON; specifically accesses property `secretKeys.Supakey`.
* `Fail-Closed Behavior`: If `expectedSecretKey` is `undefined`, the check `!expectedSecretKey` immediately trips and returns `401`.
* `Legacy Fallbacks`: Completely removed (`SUPABASE_SERVICE_ROLE_KEY` and `SUPABASE_SECRET_KEY` are absent).
* `Authorization Bearer`: Completely absent for incoming webhook authorization.

---

## 2. DATABASE WEBHOOK & VAULT CONFIGURATION

### Database Function: `public.send_push_notification_webhook()`
* **Execution Model:** `SECURITY DEFINER` owned by `postgres`.
* **Vault Lookup:**
  ```sql
  SELECT decrypted_secret INTO v_secret
  FROM vault.decrypted_secrets
  WHERE name = 'push_notification_webhook_key'
  LIMIT 1;
  ```
* **Header Structure:**
  ```sql
  headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', v_secret
  );
  ```
* **pg_net Invocation:**
  ```sql


---

## 3. SUPABASE SECRET API KEY RUNTIME BEHAVIOR & OFFICIAL SPECIFICATIONS

According to official Supabase documentation (`https://supabase.com/docs/guides/getting-started/migrating-to-new-api-keys` and `@supabase/server`):

1. **`SUPABASE_SECRET_KEYS` Format:**
   `SUPABASE_SECRET_KEYS` is injected by the Supabase Edge runtime as a JSON string representing a key-value dictionary:
   ```json
   {
     "default": "<SECRET_KEY_1>",
     "<custom_name>": "<SECRET_KEY_2>"
   }
   ```
2. **Key Naming & Casing:**
   * Keys configured in the Supabase Dashboard / Management API are accessible by their exact configured identifier.
   * Property names are strictly case-sensitive in JavaScript / TypeScript.
3. **Multi-Key & Wildcard Model:**
   * Supabase's standard server library (`@supabase/server`) supports `auth: 'secret:*'` (matching any valid secret key present in `SUPABASE_SECRET_KEYS`) or `auth: 'secret:<name>'`.

---

## 4. ANALYSIS OF THE PERSISTENT 401 FAILURES (10 FRESH FIELD_JOBS)

When 10 fresh inspection jobs (IDs 2011–2020) were inserted, the database trigger fired 10 times, reaching the Edge Function, and all 10 invocations failed with:
`Unauthorized webhook invocation: missing or invalid apikey header` (HTTP 401).

### Why `secretKeys.Supakey` Failed:
In the current code:
```typescript
if (!expectedSecretKey || !incomingApiKey || incomingApiKey !== expectedSecretKey)
```
There are distinct failure modes that produce this identical log:

1. **Failure Mode 1 — `expectedSecretKey` is `undefined` (Key Property Name Mismatch or Missing Env Var):**
   * If `secretKeys` in the deployed runtime contains `default` and lowercase `supakey` (or another identifier, or only `default`), `secretKeys.Supakey` evaluates to `undefined`.
   * When `expectedSecretKey` is `undefined`, `!expectedSecretKey` is `true`, causing an immediate 401 rejection before `incomingApiKey` is even compared.
2. **Failure Mode 2 — Secret Value Mismatch between Vault and `Supakey`:**
   * If `push_notification_webhook_key` in Vault contains the `default` Secret API key, but the Edge Function was changed to require `Supakey`.
   * Or conversely, if `Supakey` in `SUPABASE_SECRET_KEYS` does not match the exact string stored in Vault.
3. **Failure Mode 3 — Whitespace / Newline Character in Vault Secret:**
   * If the secret stored in Supabase Vault was inserted with a trailing newline or carriage return (e.g. `sb_secret_...\n` from copy-paste), `req.headers.get('apikey')` receives `sb_secret_...\n`.
   * Strict equality `expectedSecretKey === incomingApiKey` evaluates to `false` due to untrimmed whitespace.
4. **Failure Mode 4 — Diagnostic Masking in Handler:**
   * Because `!expectedSecretKey`, `!incomingApiKey`, and `incomingApiKey !== expectedSecretKey` all log the exact same generic error string, the runtime logs currently do not differentiate between missing property, missing header, or value mismatch.

  PERFORM net.http_post(
      url := 'https://laapipjyprmmaylunxib.supabase.co/functions/v1/send-push-notification',


---

## 5. DIAGNOSTIC CLASSIFICATIONS

| Check / Hypothesis | Status | Classification | Evidence & Reasoning |
|---|---|---|---|
| **`verify_jwt = false` active** | Operational | **CONFIRMED** | `pg_net` requests reach the Edge Function handler and log application errors, proving the gateway did not reject the request. |
| **Database trigger & pg_net dispatch** | Operational | **CONFIRMED** | 10 `field_jobs` inserts reliably triggered 10 Edge Function execution logs. |
| **`apikey` header transmission by pg_net** | Operational | **CONFIRMED** | `net.http_post` sends JSON headers including `apikey`. |
| **Absence of Legacy Service Role JWT** | Hardened | **CONFIRMED** | Live triggers and Vault function do not use `Authorization: Bearer` or legacy JWT. |
| **`secretKeys.Supakey` resolved as `undefined`** | Probable Root Cause | **STRONGLY INDICATED** | If `SUPABASE_SECRET_KEYS` only has `default`, or uses lowercase/different naming, `expectedSecretKey` is `undefined`, immediately triggering 401. |
| **Vault Secret vs Edge Function Key Mismatch** | Probable Root Cause | **STRONGLY INDICATED** | Vault secret value may differ from `secretKeys.Supakey` or may match `secretKeys.default`. |
| **Untrimmed Whitespace in Header/Vault** | Contributing Factor | **UNVERIFIED** | Possible if secret was pasted with trailing newline into Vault. |
| **Incoming Header Missing entirely** | Alternative Cause | **UNVERIFIED** | Cannot be separated from value mismatch without differentiated logging. |

---

## 6. WHAT MUST NOT BE CHANGED

* **Do NOT modify** `public.send_push_notification_webhook()` or database triggers.
* **Do NOT modify** Supabase Vault secrets or extensions.
* **Do NOT reintroduce** `Authorization: Bearer` or legacy service_role JWTs.
* **Do NOT commit or push** any temporary diagnostic files containing secrets.
* **Do NOT print or expose** secret values in logs or repository files.

---

## 7. RECOMMENDED ARCHITECTURAL RESOLUTION (FOR FUTURE ACTION)

Rather than hardcoding a single fragile key property name (`secretKeys.Supakey` vs `secretKeys.default` vs `secretKeys.supakey`), the standard Supabase Edge Function Secret API authentication pattern:

1. **Accept Any Valid Project Secret Key (`auth: 'secret:*'` model):**
   * Parse `SUPABASE_SECRET_KEYS` as JSON.
   * Extract all valid secret key values: `const validKeys = Object.values(secretKeys).map(k => String(k).trim())`.
   * Check if `validKeys.includes(incomingApiKey.trim())`.
   * This guarantees that whether the Vault uses `default`, `Supakey`, or any other authorized Secret API key on the project, authentication succeeds securely without hardcoding key names.
2. **Differentiate Diagnostic Logs (without exposing secrets):**
   * Log distinct non-sensitive debug messages if `SUPABASE_SECRET_KEYS` is missing, if `apikey` header is missing, or if key comparison fails (logging non-sensitive properties like `Object.keys(secretKeys)`).
3. **Trim Whitespace:**
   * Always apply `.trim()` on incoming headers and expected secrets to prevent newline copy-paste mismatches.

---
*End of Investigation Report.*

      headers := headers,
      body := v_payload,
      timeout_milliseconds := 5000
  );
  ```
* **Vault Secret Metadata:**
  * Secret Name: `push_notification_webhook_key`
  * Secret UUID: `372157a1-b754-4b18-8bd5-ce57ae3ed4a4`
