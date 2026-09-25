# Security Audit Report

## Overview

This document provides an overview of the findings from the security audit conducted on the iMAPS FieldSync application, aligning with OWASP standards.
# Repository & Secrets Exposure Audit

**Date performed:** September 6, 2026  
**Performed by:** Cline (VS Code AI agent), on behalf of iMAPS FieldSync Development Team  
**Scope:** Local repository, Git history, tracked source assets, and GitHub remote for `HanamiGarduque/imaps-fieldsync`

---

## Methodology

A comprehensive nine-step discovery and exposure audit was performed on the repository to verify secret isolation, Git ignore integrity, historical commits, source code patterns, binary objects, GitHub remote refs, and Android signing assets.

Each check targeted specific potential vulnerability vectors:
1. **Environment Variable Inspection (`.env`):** Verified active configuration variable names without dumping sensitive values to confirm no privileged backend keys are bundled in client configuration.
2. **Git Ignore Configuration:** Verified that `.env` and local environment files are properly ignored and excluded by Git rules.
3. **Historical Commit Traversal:** Scanned all Git commit history across branches and tags for historical leakage of `.env`, keystores, private keys, certificates, or credentials.
4. **Tracked File Inventory:** Inspected currently tracked files to detect misplaced configuration files, database dumps, and credential artifacts.
5. **Static Pattern & Regex Secret Scan:** Searched all tracked code, configuration, JSON, SQL, YAML, and Dart source files for API key patterns, JWTs, AWS credentials, private keys, and hardcoded `service_role` tokens.
6. **Git Object & Binary Analysis:** Identified the top 20 largest objects in the Git object database to uncover hidden binaries, archives, database dumps, or keystore files.
7. **GitHub Remote Surface Audit:** Inspected remote heads and tags on `origin` (`https://github.com/HanamiGarduque/imaps-fieldsync.git`) to evaluate public/remote exposure of repository assets.
8. **Android Signing Configuration:** Inspected Android build scripts, keystore references, and signing properties for exposed private signing keys.
9. **Working Tree Cross-Check:** Verified the working tree status to ensure untracked, ignored, and staged assets adhere to security boundaries.

---

## Findings

### Step 1 — Current `.env` Contents

**What was checked:**
Inspected `.env` variable names using a value-safe parsing routine:
```bash
(Get-Content .env) -replace '=.*', ''
```

**Result:**
Found `.env` file containing client-safe variables only.

**Evidence:**
Variable names present:
- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`
- `SUPABASE_ANON_KEY`
- `ONESIGNAL_APP_ID`

No privileged variable names (e.g., `SERVICE_ROLE`, `SECRET`, `PRIVATE_KEY`, `ADMIN`, `DB_PASSWORD`, `DATABASE_URL`) exist in `.env`.

**Risk:**
None / Low (Client publishable keys are intended for client-side mobile distribution).

**Remediation status:**
Not needed (Client `.env` is well-scoped).

---

### Step 2 — `.env` Git Ignore Status

**What was checked:**
Evaluated `.gitignore` rules and active Git ignore matching via:
```bash
git check-ignore -v .env
git status --ignored --short .env
```

**Result:**
`.env` is actively and correctly ignored.

**Evidence:**
- `.gitignore` line 54 matches: `.gitignore:54:.env .env`
- `git status` reports: `!! .env` (ignored, untracked).

**Risk:**
None.

**Remediation status:**
Already properly configured.

---

### Step 3 — Git History Exposure

**What was checked:**
Full history traversal across all commits for environment files and credential extensions:
```bash
git log --all --full-history --oneline --diff-filter=A -- "*.env" "*.jks" "*.keystore" "*key.properties*" "*google-services.json*" "*.pem" "*.p12" "*.p8"
```

**Result:**
No `.env`, keystore, certificate, or `key.properties` files were ever committed to Git history. However, SQL dumps containing hardcoded service role tokens were committed under `.sql` extensions (see Step 4 & 5).

**Evidence:**
Zero matches for `.env` or keystore additions across all Git commits.

**Risk:**
Critical (due to historical SQL dump commits; see Step 4/5).

**Remediation status:**
Pending action (credential rotation required).

---

### Step 4 — Currently Tracked Sensitive Files

**What was checked:**
Tracked file scan across repository trees:
```bash
git ls-files | Select-String -Pattern "(\.env|keystore|\.jks|key\.properties|google-services\.json|\.pem|\.p12|\.p8|secret|credential|password|\.sql)"
```

**Result:**
Critical findings in tracked SQL files.

**Evidence:**
Tracked files identified:
- `full.sql` (346 KB) — Contains hardcoded Supabase `service_role` JWT in HTTP triggers.
- `schema.sql` (41 KB) — Contains hardcoded Supabase `service_role` JWT in HTTP triggers.
- `supabase/migrations/001_inspection_assignments.sql` — Clean DDL schema.
- `supabase/migrations/002_core_tables.sql` — Clean DDL schema.
- `lib/screens/reset_password_screen.dart.bak` — Non-sensitive UI backup code.

**Risk:**
Critical (due to `full.sql` and `schema.sql`).

**Remediation status:**
Pending action (credential rotation and SQL sanitization).

---

### Step 5 — Hardcoded Secret Scan

**What was checked:**
Static code and asset scan across all source directories (`lib/`, `supabase/`, `android/`, root) for private key headers, AWS tokens, Google API keys, and JWT authorization headers:
```bash
Select-String -Pattern "eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"
```

**Result:**
Critical hardcoded secret detected in database schema dumps.

**Evidence:**
1. **`full.sql` (Lines 623 & 627):**
   Database triggers `notify-on-status-change` and `on_assignment_change` define HTTP requests to Supabase Edge Functions with a hardcoded `Authorization` header containing an active Supabase `service_role` JWT:
   ```text
   Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxhYXBpcGp5cHJtbWF5bHVueGliIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3Nzc0OTIxMSwiZXhwIjoyMDkzMzI1MjExfQ.gji...redacted
   ```
2. **`schema.sql` (Lines 587 & 591):**
   Identical hardcoded `service_role` JWT present in HTTP request triggers.
3. **Dart Source Code (`lib/**`):**
   No hardcoded secrets found. All Supabase connections properly source keys from `dotenv.env`.
4. **Edge Functions (`supabase/functions/index.ts`):**
   Properly uses `Deno.env.get(...)`. No hardcoded secrets.

**Risk:**
Critical (The `service_role` key bypasses Supabase Row-Level Security and grants administrative access to the database).

**Remediation status:**
Urgent rotation required.

---

### Step 6 — Large/Binary Git Objects

**What was checked:**
Top 20 largest objects in the Git database sorted by size:
```bash
git rev-list --objects --all | git cat-file --batch-check="%(objecttype) %(objectname) %(objectsize) %(rest)" | sort
```

**Result:**
Found large archive blobs and schema dumps in history.

**Evidence:**
Top objects:
- `android.zip` (2.45 MB) — Archived Android project directory.
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png` (1.48 MB) — App icon.
- `assets/icon/app_icon.png` (1.48 MB) — App icon.
- `analysis_fresh_current.json` (879 KB) — Dart analyzer diagnostic output.
- `analysis_post_patch.json` (874 KB) — Dart analyzer diagnostic output.
- `logcat_errors.txt` (770 KB) — Android logcat output.
- `analysis.json` (696 KB) — Diagnostic output.
- `lib.zip` (693 KB) — Archived source directory.
- `full.sql` (346 KB) — Database dump containing the `service_role` JWT.

**Risk:**
Critical (specifically regarding `full.sql`).

**Remediation status:**
Pending action (SQL sanitization and history remediation).

---

### Step 7 — GitHub Remote Exposure

**What was checked:**
Remote repository configuration and remote ref tree listings:
```bash
git remote -v
git ls-remote --heads --tags origin
git ls-tree -r origin/main full.sql schema.sql
```

**Result:**
`full.sql` and `schema.sql` containing the `service_role` token are pushed to the GitHub remote repository.

**Evidence:**
- Remote URL: `https://github.com/HanamiGarduque/imaps-fieldsync.git`
- Remote branches/tags containing the files:
  - `refs/heads/main`
  - `refs/heads/migration/master-merge`
  - `refs/tags/architecture-lock`

**Risk:**
Critical.

**Remediation status:**
Urgent rotation required on the Supabase Dashboard.

---

### Step 8 — Android Signing Key Exposure

**What was checked:**
Inspected repository for keystores, key properties, and Gradle signing configuration:
```bash
find . -iname "*.jks" -o -iname "*.keystore"
test -f android/key.properties
```

**Result:**
No private signing keystores or passwords exist in the repository.

**Evidence:**
- No `*.jks` or `*.keystore` files exist in the repository or Git history.
- `android/key.properties` does not exist.
- `android/app/build.gradle.kts` uses default local debug signing:
  `signingConfig = signingConfigs.getByName("debug")`.

**Risk:**
None.

**Remediation status:**
No action needed.

---

### Step 9 — Working Tree Cross-Check

**What was checked:**
Inspected working tree status:
```bash
git status --short
git branch --show-current
```

**Result:**
Local working tree is on branch `main`. No modified tracked files exist.

**Evidence:**
Untracked artifacts are documentation/spec files and test reports. `.env` is properly ignored by Git.

**Risk:**
None.

**Remediation status:**
No action needed for local tree.

---

## Summary Table

| Finding | Location | Evidence | Risk | Status |
|---|---|---|---|---|
| **Client `.env` Variables** | `.env` | `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_ANON_KEY`, `ONESIGNAL_APP_ID` | Low | Expected client config; no action needed |
| **`.env` Git Ignore** | `.gitignore` (line 54) | Ignored via rule `.env` (`git check-ignore` verified) | None | Already properly configured |
| **Historical `.env` / Keystore Commits** | Git history | 0 occurrences across all historical commits | None | Clean history for `.env` and `.jks` |
| **Tracked `service_role` JWT in SQL Triggers** | `full.sql` (623, 627), `schema.sql` (587, 591) | Trigger DDL embeds `Authorization: Bearer eyJhbGci...` with `role: "service_role"` | **Critical** | **Urgent credential rotation required** |
| **Dart Source Code Hardcoded Secrets** | `lib/**` | All Supabase clients source credentials via `dotenv.env` | None | Clean client code |
| **Edge Function Secrets** | `supabase/functions/index.ts` | All secrets sourced via `Deno.env.get` | None | Clean edge function code |
| **GitHub Remote Exposure** | `origin/main`, `origin/migration/master-merge`, tag `architecture-lock` | `full.sql` and `schema.sql` exist on remote branches/tags | **Critical** | **Urgent credential rotation required** |
| **Android Signing Keystore** | `android/` | Debug config only; no release keystore or `key.properties` present | None | Clean signing posture |

---

## Conclusion

The repository maintains strong client-side security hygiene: `.env` is properly ignored, Dart source files do not contain hardcoded keys, and Android release keystores are not exposed. However, a **Critical secret exposure** was identified in `full.sql` and `schema.sql`, where an active Supabase `service_role` JWT token was embedded in database trigger DDL definitions calling edge functions via `supabase_functions.http_request` and pushed to the GitHub remote repository (`refs/heads/main`, `refs/heads/migration/master-merge`, and `refs/tags/architecture-lock`).

Because this privileged key bypasses Row-Level Security (RLS) and grants administrative database access, **immediate rotation of the Supabase Service Role Key via the Supabase Dashboard is required**, followed by sanitization of the repository SQL files and migration of database webhooks to vault/secret references.

