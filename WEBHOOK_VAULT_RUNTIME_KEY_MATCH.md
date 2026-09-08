# WEBHOOK VAULT VS RUNTIME SECRET KEY MATCH DIAGNOSTIC

**Document Version:** 1.0.0  
**Audit Date:** September 6, 2026  
**Auditor / Agent:** Cline (Security & Runtime Diagnostic Review)  
**Supabase Project Reference:** `laapipjyprmmaylunxib`  
**Investigation Mode:** READ-ONLY (No mutations, no code changes, no deployments, no key exposures)

---

## 1. EXECUTIVE SUMMARY

| Metric / Check | Diagnostic Result |
|---|---|
| **Vault matches runtime key as currently stored?** | **NO** (Literal match fails) |
| **Configured Runtime Secret Keys Count:** | **2** (`default`, `supakey`) |
| **Vault matches runtime key with angle brackets stripped?** | **YES** |
| **Matching Runtime Key Name:** | **`supakey`** (The newly created Secret API key) |
| **Is Vault storing the old exposed legacy key?** | **NO** (Legacy JWT `service_role` does not match) |
| **Is Vault storing the newly created key?** | **YES** (Stored with literal `<` and `>` placeholder wrappers) |
| **Identified Root Cause:** | The Vault secret was populated with literal enclosing angle brackets (`<sb_secret_...>` instead of `sb_secret_...`), causing outbound webhook HTTP headers to send `apikey: <sb_secret_...>` which fails strict string equality against runtime environment secrets. |

---

## 2. CONFIGURED RUNTIME SECRET API KEYS

Inspection via non-sensitive SHA-256 fingerprinting identified the following API keys associated with project `laapipjyprmmaylunxib`:

| Index | Key Name | Key Type | Length | Format / Prefix | SHA-256 Digest |
|---|---|---|---|---|---|
| 0 | `anon` | `legacy` | 208 | JWT (`eyJ...`) | `55db10d2872283241fc40d362bab259b4e806e9a7d3fdab5366a956e7ec6a23a` |
| 1 | `service_role` (old exposed key) | `legacy` | 219 | JWT (`eyJ...`) | `8995b65b5ad4b4607a1c9bcf1f6a2127da016a14e762b3218e5b97e85e9784da` |
| 2 | `default` | `publishable` | 46 | `sb_publishable_...` | `534c83ce50225301a3539a33ccaa6ebd5a9785e91fa3c66fa1bdbdef2d2a8f37` |
| 3 | `default` | `secret` | 41 | `sb_secret_...` | `c8771b02c8a595c483fbeda51ae665feb83e3b428ef6ec3b4baeff7c767a8235` |
| 4 | `supakey` (newly created key) | `secret` | 41 | `sb_secret_...` | `6629b3b1fe2d00d26a43aebc8c423fc8473a6d67e435100da2947cdc8ebe5326` |

*Note: In the Edge Function runtime, `SUPABASE_SECRET_KEYS` receives the dictionary containing both secret keys (`default` and `supakey`).*

---

## 3. POSTGRESQL VAULT SECRET ANALYSIS

Database query against `vault.decrypted_secrets` for `push_notification_webhook_key` (Secret ID: `372157a1-b754-4b18-8bd5-ce57ae3ed4a4`):

| Property | Value | Notes / Significance |
|---|---|---|
| **Secret Name** | `push_notification_webhook_key` | Targeted by `public.send_push_notification_webhook()` |
| **Stored Length** | 43 characters | Discrepancy: Expected length is 41 characters |
| **First Character** | ASCII `60` (`<`) | Literal opening angle bracket |
| **Last Character** | ASCII `62` (`>`) | Literal closing angle bracket |
| **Second Character** | ASCII `115` (`s`) | Prefix starts with `s` |
| **Raw SHA-256 Digest** | `b1840f6503d8064c051ccc32b7b061c543149cfd63cbe5aa7ede95ecc10513df` | Does not match any runtime secret |
| **Stripped Length (`substring(2, 41)`)** | 41 characters | Exact length of Secret API keys |
| **Stripped Starts With** | `sb_secret_` | Valid Secret API key format |
| **Stripped SHA-256 Digest** | `6629b3b1fe2d00d26a43aebc8c423fc8473a6d67e435100da2947cdc8ebe5326` | **EXACT MATCH with `supakey`** |

---

## 4. COMPARISON MATRIX

| Source | Target Secret | Match Status | Details |
|---|---|---|---|
| Vault (Raw) | `service_role` (Legacy JWT) | **NO MATCH** | SHA-256 mismatch (length 43 vs 219) |
| Vault (Raw) | `default` (Secret API Key) | **NO MATCH** | SHA-256 mismatch (length 43 vs 41) |
| Vault (Raw) | `supakey` (Secret API Key) | **NO MATCH** | Mismatch due to enclosing `<` and `>` |
| **Vault (Stripped of `< >`)** | **`supakey` (Secret API Key)** | **MATCH (YES)** | **100% SHA-256 Identical (`6629b3b1...`)** |

---

## 5. ROOT CAUSE EXPLANATION

1. When the secret was initially provisioned into Supabase Vault using SQL (e.g. `vault.create_secret('<sb_secret_...>')`), the placeholder angle brackets `<` and `>` from the template instruction were included literally in the input string.
2. The Vault secret stored was `<sb_secret_...>` (43 characters).
3. At runtime, PostgreSQL trigger function `public.send_push_notification_webhook()` retrieves `decrypted_secret` and passes:
   ```json
   { "apikey": "<sb_secret_...>" }
   ```
4. The Edge Function receives `<sb_secret_...>`, trims whitespace, and compares it against configured runtime secret values:
   * Key 1: `sb_secret_TRCj4...` (`default`)
   * Key 2: `sb_secret_XYSHE...` (`supakey`)
5. Because `<sb_secret_...>` has leading `<` and trailing `>`, string equality fails, triggering the Edge Function's fail-closed guard:
   ```
   "Unauthorized webhook invocation: invalid or mismatched apikey"
   ```

---

## 6. RECOMMENDATION FOR REMEDIATION (NO ACTIONS PERFORMED)

When authorized to update the database Vault secret:
Execute `vault.update_secret` to update `push_notification_webhook_key` (ID: `372157a1-b754-4b18-8bd5-ce57ae3ed4a4`) with the exact 41-character Secret API key without enclosing `<` or `>` angle brackets.
