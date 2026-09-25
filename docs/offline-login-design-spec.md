# Offline Email + Passcode Login — Design Spec

**Purpose:** Reference doc for enabling offline login via email + passcode, for inspector devices without biometric hardware or enrollment. Finalized logic from design review — use as implementation checklist.

---

## 1. Root Cause (confirmed from code)

- `AuthService.signIn()` calls Supabase's `signInWithPassword()` directly — a real network call. The passcode is never checked locally, only server-side. Password login inherently requires connectivity today.
- Biometric login works offline because it never re-verifies a credential — it only unlocks an already-live cached Supabase session (`AuthService.hasLiveUnderlyingSession`) and falls back to a locally-cached profile (`getCurrentProfileOfflineAware`). No network call needed.
- Devices without biometric hardware/enrollment currently have **no offline login path at all** — this spec closes that gap.

---

## 2. Solution: Local Passcode Verifier

A securely-hashed, on-device copy of the passcode, checked locally when offline — conceptually the same "unlock an already-live cached session" pattern biometric already uses, but using a knowledge factor (passcode) instead of a biometric factor. No new UI concept for the inspector — they still just type the same email + passcode they already know.

### Enrollment
- On every **successful online** password login (`_handleLogin` in `splash_screen.dart`), hash the passcode (salted) and store it via `SecurePrefsService` (FlutterSecureStorage / Android Keystore / iOS Secure Enclave — same backing store already used for biometric data).
- Refreshed on **every** successful online login, not just first-time enrollment — so it always reflects the current real passcode.

### Offline verification
- When offline and the inspector submits email + passcode: skip the Supabase network call, hash the entered passcode with the same method, and compare against the stored local hash.
- **Precondition:** only works if there's already a live cached session on the device for that user (same precondition biometric login already checks). A device that has never logged in online has no local hash to check against — it genuinely needs connectivity for the first login, same as today.
- On match: same success path as biometric login — clear soft-logout, load cached profile via `getCurrentProfileOfflineAware()`, proceed to `MainShellScreen`.

### Invalidation
- Clear the stored local hash wherever biometric data is already cleared today: `SecurePrefsService.clearAuthPrefs()` / `clearAll()` (real sign-out, revoked session, password reset flows).
- No separate "did the passcode change" detection needed — since it's refreshed on every successful online login, it's always current by construction.

---

## 3. Retry / Cooldown Logic

Single-user device (only the assigned inspector uses it) — escalating cooldown instead of a hard lockout or data wipe, so a struggling inspector (gloves, heat, stress) is never locked out or loses cached field data, while still deterring rapid brute-force guessing:

| Failed attempt # | Cooldown before next try |
|---|---|
| 1–2 | None — retry immediately |
| 3 | 30 seconds |
| 5 | 2 minutes |
| 8+ | 5 minutes, repeating until a correct entry |

- Never wipes data, never force-signs-out, never deletes the local hash due to failed attempts alone — only cooldown delay increases.
- Cooldown state can be simple in-memory + a timestamp in local storage (survives app restart, since someone could otherwise bypass the cooldown by force-closing the app).

---

## 4. UI: Offline Mode Indicator

- Show a visible **offline mode banner/indicator** on the Login screen and/or after login when this fallback path was used, so the inspector knows they're in offline mode (not just silently succeeding as if online).
- Exact placement/copy TBD at implementation — keep consistent with any existing offline indicators already used elsewhere in the app (check `sync_progress_banner.dart` / `updates_screen.dart` for existing offline-state UI patterns before designing a new one from scratch).

---

## 5. Naming Map (for the implementing AI)

| Concept | Existing identifier | Action |
|---|---|---|
| Secure on-device storage | `SecurePrefsService` (FlutterSecureStorage, `secure_prefs_service.dart`) | Reuse — add new key(s) for the local passcode hash + salt, following the existing `_k...` key-constant pattern |
| Unused hook found | `getBioSecret()` / `setBioSecret()` (`secure_prefs_service.dart` line 44–51) | Currently dead code — not called anywhere. Flag to the implementing AI: confirm before reusing this for the new local-passcode-hash storage vs. adding a distinct new key. Do not assume its original intended purpose without checking. |
| Online login success hook | `_handleLogin()` in `splash_screen.dart` (line 390) | Add local-hash-store call here, alongside the existing `SecurePrefsService.setSavedEmail(...)` call (line 455) |
| Offline session unlock pattern | `_handleBiometricLogin()` in `splash_screen.dart` (line 280) | Model the new offline-passcode-login function on this same structure (`hasLiveUnderlyingSession` check → `clearSoftLogout()` → `getCurrentProfileOfflineAware()` → navigate) |
| Connectivity check | `AuthService.hasConnectivity()` (`auth_service.dart` line 173) | Reuse as-is to decide whether to attempt the network path or the new local-verify path |
| Clear on logout/reset | `SecurePrefsService.clearAuthPrefs()` / `clearAll()` (`secure_prefs_service.dart` line 204, 220) | Add the new local-passcode-hash key(s) to these existing clear methods |

**Rule:** reuse the identifiers above. Do not create a parallel/duplicate storage service or a second connectivity-check helper.

---

## 5b. Hashing Approach (confirmed)

Use the `crypto` package — **confirmed already a direct dependency** in `pubspec.yaml` (`crypto: ^3.0.3`), so zero new dependencies needed. Manual PBKDF2-style scheme:
- Generate a random per-device salt (e.g. 16 bytes via `Random.secure()`) once, stored alongside the hash.
- Derive the verifier via repeated `Hmac(sha256, key: passcode+salt)` iterations (e.g. 10,000) — slow enough to blunt brute-force attempts even if the encrypted storage were somehow extracted, on top of the OS-level Keystore/Secure Enclave protection `SecurePrefsService` already provides.
- Store both the salt and the resulting hash (not the raw passcode) via `SecurePrefsService`.
- Rationale: avoids adding a new dependency (`bcrypt` was the alternative considered), and the extra hashing work is layered on top of hardware-backed storage that's already in place for biometric data — reasonable defense in depth without over-engineering.

## 5c. Offline-Mode Indicator (confirmed placement/style)

Reuse the existing visual pattern already established in `updates_screen.dart` (Sync Center) rather than inventing a new one — a small colored status dot + label:
- 6×6 circle, `InsightTheme.red` when offline / `InsightTheme.green` when online, next to a text label.
- On the Login screen: show this dot + "Offline — you can still sign in if you've logged in before on this device" when connectivity drops, so the inspector understands why the screen looks the same but works differently.
- After a successful offline-passcode login: carry a small persistent "Offline mode" dot + label into the main app shell (same visual treatment), so it's clear throughout the session, not just at the login moment.

## 6. Open Items to Confirm at Implementation Time

- Whether cooldown timing (Section 3) needs tuning once tested in the field.
- Exact offline-banner copy and placement (Section 4) — see confirmed defaults in Section 5c; adjust only if it doesn't fit once seen in the actual app shell.