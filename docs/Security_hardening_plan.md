# InSight iMAPS FieldSync — Security Testing & Hardening Plan

**Purpose:** Pre-defense security audit, structured around the OWASP Mobile Application Security Top 10 — a recognized standard, worth citing directly in your defense as the methodology. Revised into a disciplined **audit → verify → fix confirmed findings → retest** workflow (per review with GPT) instead of treating every item as something to immediately implement.

**Core rule:** don't fix anything that hasn't been confirmed as an actual problem. A dependency existing (`sqflite_sqlcipher`), a file being an asset (`.env`), or a flag being absent (`usesCleartextTraffic`) is not by itself proof of a vulnerability — each needs verification before being called "confirmed."

---

## Classification System (used throughout this doc)

Every item is tagged one of:
- **A — Confirmed vulnerability** (verified broken, needs a fix)
- **B — Confirmed secure** (verified fine, no action needed)
- **C — Needs Supabase/dashboard verification** (can't be answered from code alone)
- **D — Needs real-device/manual testing** (can't be answered from static reading alone)
- **E — Recommendation only** (defense-in-depth, not evidence of an existing problem)

---

## Phase 1 — Discovery Only (READ ONLY — no code changes, no SQL, no Supabase mutations)

Have your coding agent (Copilot) inspect, and classify each into A-E, **without changing anything**:

- Supabase Storage `inspection-photos` bucket config + usage (public/private, how URLs are generated/used)
- `photo_paths` handling, upload/download/display flow
- RLS policies on `inspections`, `applications`, `parcels`
- Security-definer RPCs (especially the delete RPC) — does it independently check `auth.uid()` ownership?
- `supabase_service.dart`, `.env` loading, `pubspec.yaml`
- `AndroidManifest.xml` (cleartext traffic config)
- `db_helper.dart` — is `sqflite_sqlcipher` actually wired up with a real per-device key, or just installed?
- `SecurePrefsService` and the offline-login implementation (live-session requirement, salted verifier, cooldown)
- `sync_outbox_service.dart`, other network call sites
- Screen protection usage, release build / obfuscation config

Output of this phase: a table of every item above with its A-E tag and 1-line evidence — not fixes.

---

## Phase 2 — Supabase Dashboard Verification (separate from Flutter code — done in the Supabase dashboard/SQL editor directly)

- **`inspection-photos` bucket:** public or private, right now, in the dashboard settings? If public, can an unauthenticated browser open a photo URL directly?
- **RLS on `inspections`/`applications`/`parcels`:** read the actual policy SQL in the dashboard — confirm it scopes by `assigned_inspector_id = auth.uid()` (or equivalent), not just "authenticated users."
- **Delete RPC:** open the actual function definition in the SQL editor, confirm it re-checks ownership internally (since `SECURITY DEFINER` bypasses RLS).

## Phase 3 — Manual Testing (prioritized)

| Priority | Test |
|---|---|
| 🔴 P0 | Public inspection-photo exposure — open a photo URL in an unauthenticated/incognito browser |
| 🔴 P0 | RLS cross-inspector access — see safer method below (no token logging) |
| 🔴 P0 | Delete RPC authorization — attempt deleting another inspector's record |
| 🟠 P1 | Offline-login/session security — live-session requirement, cooldown, no data wipe |
| 🟠 P1 | SQLite encryption — confirm actual encryption key usage, not just the dependency |
| 🟠 P1 | Credential/session storage — no plaintext password/token in `shared_preferences` |
| 🟡 P2 | Large text input (10,000+ chars) in every free-text field |
| 🟡 P2 | Special-character/SQL-meta-character input |
| 🟡 P2 | Photo file/size/type validation on upload |
| 🟡 P2 | HTTPS/cleartext confirmation |
| 🟢 P3 | Obfuscation / screen protection actually applied |
| 🟢 P3 | Dependency audit (`flutter pub outdated`) |

### Safer RLS cross-access test (no JWT logging)

Avoid `debugPrint`-ing a real session token just to test in Postman — that adds its own exposure risk during testing. Two safer options instead:

1. **Simplest — test through the app UI itself:** create 2 real test inspector accounts, log in as each in the app normally, and confirm Inspector A never sees a task assigned to Inspector B anywhere in the UI. No token ever leaves the app.
2. **More rigorous — disposable test script:** a short Dart or Python script that signs in as both test accounts **within the script's own memory** (never printed), then issues a cross-access query as Inspector A for Inspector B's record, and prints only **PASS/FAIL** — never the token or the row data itself. Ask for this script separately if you want it.

## Phase 4 — Implement Only Confirmed (A) Findings, Then Retest

Only items tagged **A** from Phases 1-3 get an actual code/config change. After each fix, re-run the specific test that found it to confirm it's resolved — don't batch-fix everything at once without individual retesting.

---

## Findings So Far (from initial code read — pending Phase 1/2/3 confirmation)

| # | Item | Current tag | Why |
|---|---|---|---|
| 1 | Photo URLs use `/object/public/` path | **C** (needs dashboard check) | Confirms the URL *pattern* used, not yet confirmed the bucket's actual current setting or whether unauthenticated access truly succeeds |
| 2 | `.env` bundled as Flutter asset | **B**, conditionally | Fine as long as it only holds `SUPABASE_URL` + anon key — confirmed via Cline's repo audit already requested separately |
| 3 | RLS policy bug (already fixed per code comments) | **B** (already remediated) | Good defense-day talking point — shows an active review process |
| 4 | Security-definer delete RPC | **C** (needs dashboard check) | Can't confirm ownership-check logic from Flutter code alone — must read the actual SQL function body |
| 5 | No explicit `usesCleartextTraffic="false"` | **E** (recommendation only) | Absence of a hardening flag isn't evidence of insecure traffic — Supabase already enforces HTTPS |
| 6 | `sqflite_sqlcipher` present in `pubspec.yaml` | **D** (needs code verification) | A dependency being installed doesn't confirm it's actually encrypting the local DB with a real key |

---

## Defense Framing

> "We evaluated the mobile application against the OWASP Mobile Application Security Top 10, identified concrete security risks, verified our RLS authorization boundaries against real test accounts, reviewed secure local storage and authentication, and applied only confirmed hardening fixes — following a discovery-first, evidence-based process rather than assuming a fix was needed."