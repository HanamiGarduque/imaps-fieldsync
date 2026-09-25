# WEBHOOK VAULT VS RUNTIME SECRET KEY MATCH (AFTER FIX VERIFICATION)

**Document Version:** 1.0.0  
**Audit Date:** September 6, 2026  
**Auditor / Agent:** Cline (Security & Post-Fix Diagnostic Verification)  
**Supabase Project Reference:** `laapipjyprmmaylunxib`  
**Investigation Mode:** READ-ONLY (No mutations, no code changes, no deployments, no key exposures)

---

## 1. EXECUTIVE SUMMARY & VERIFICATION RESULTS

| Metric / Check | Post-Fix Result | Status |
|---|---|---|
| **Vault matches runtime key?** | **YES** | **VERIFIED** |
| **Matching Runtime Key Name:** | **`supakey`** | **VERIFIED** |
| **Vault Raw Length:** | **41 characters** | **VERIFIED** |
| **Is the previous `< >` mismatch gone?** | **YES** (Zero angle brackets present) | **RESOLVED** |
| **Prefix Validation:** | Starts with `sb_secret_` | **VALID** |
| **Fail-Closed Auth Status:** | Ready for 200 OK webhook dispatch | **ALIGNED** |

---

## 2. POSTGRESQL VAULT SECRET VERIFICATION

Database verification query against `vault.decrypted_secrets` for `push_notification_webhook_key` (Secret ID: `372157a1-b754-4b18-8bd5-ce57ae3ed4a4`):

* **Secret Name:** `push_notification_webhook_key`
* **Raw Length:** `41` (Correct Secret API key character length)
* **First Character ASCII:** `115` (`s`)
* **Last Character ASCII:** `79` (`O`)
* **Angle Bracket Presence (`<` or `>`):** `false`
* **Format:** Valid `sb_secret_...` format
* **Raw SHA-256 Digest:** `6629b3b1fe2d00d26a43aebc8c423fc8473a6d67e435100da2947cdc8ebe5326`
* **Trimmed SHA-256 Digest:** `6629b3b1fe2d00d26a43aebc8c423fc8473a6d67e435100da2947cdc8ebe5326`

---

## 3. RUNTIME API KEYS COMPARISON MATRIX

| Key Index | Key Name | Key Type | Length | Format | SHA-256 Digest | Matches Vault Secret? |
|---|---|---|---|---|---|---|
| 0 | `anon` | `legacy` | 208 | JWT | `55db10d2872283241fc40d362bab259b4e806e9a7d3fdab5366a956e7ec6a23a` | **NO** |
| 1 | `service_role` | `legacy` | 219 | JWT | `8995b65b5ad4b4607a1c9bcf1f6a2127da016a14e762b3218e5b97e85e9784da` | **NO** |
| 2 | `default` | `publishable` | 46 | `sb_publishable_...` | `534c83ce50225301a3539a33ccaa6ebd5a9785e91fa3c66fa1bdbdef2d2a8f37` | **NO** |
| 3 | `default` | `secret` | 41 | `sb_secret_...` | `c8771b02c8a595c483fbeda51ae665feb83e3b428ef6ec3b4baeff7c767a8235` | **NO** |
| **4** | **`supakey`** | **`secret`** | **41** | **`sb_secret_...`** | **`6629b3b1fe2d00d26a43aebc8c423fc8473a6d67e435100da2947cdc8ebe5326`** | **YES (100% Match)** |

---

## 4. CONCLUSION

The manual correction to Supabase Vault successfully removed the literal `<` and `>` wrapper characters.
The stored value in `push_notification_webhook_key` is now an exact byte-for-byte match with the runtime Secret API key named **`supakey`**.
Outbound webhook invocations dispatched by `public.send_push_notification_webhook()` will now present the exact matching Secret API key header (`apikey: sb_secret_...`), satisfying the Edge Function authentication check.
