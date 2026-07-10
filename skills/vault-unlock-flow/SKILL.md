---
name: vault-unlock-flow
description: Use when implementing or modifying Master Password creation (sign-up step 2), the vault Unlock screen shown after login, Lock vs. Log out behavior, or biometric quick-unlock. Load docs/AUTH_AND_UNLOCK_FLOW.md fully before starting — this is the highest-risk new surface in the app alongside the original crypto core.
---

# Skill: Vault Unlock Flow

## Objective
Implement the Master Password as a fully separate secret from the Account
Password: created once during sign-up, never transmitted in any form, and
used solely to unwrap a Vault Key blob that gates access to the
Vault/Security Center dashboard.

## Master Password creation (sign-up step 2)
- Runs immediately after successful account registration
  (`account-auth-flow`), before any dashboard access.
- Explicitly explain in the UI: this password is different from the
  account password, is never sent to our servers, and there is no recovery
  if forgotten.
- On submit: generate a random `master_kdf_salt`, derive the Master Key via
  Argon2id (same parameters as `crypto-e2ee-core`), generate a random Vault
  Key, wrap it with the Master Key (AES-256-GCM), and upload only
  `master_kdf_salt` + the wrapped ciphertext via the sync API. Never upload
  the Master Password or the unwrapped Vault Key.
- Do not offer a "same as account password" shortcut or pre-fill anything
  from the account password field.

## Unlock screen (after every login, or after auto-lock)
- Fetch `master_kdf_salt` + wrapped Vault Key blob from the sync API.
- Prompt for Master Password only (no account password field here).
- Derive Master Key locally, attempt to unwrap. Success/failure is
  determined by the AES-GCM authentication tag — do not implement a
  separate "verifier" that could leak more information than the wrap
  itself already provides.
- On failure: generic error message, and client-side exponential backoff
  after repeated attempts (e.g. increasing delay after 3, 5, 8 failed
  tries). Do not distinguish "wrong password" from other failure modes in
  the UI copy.
- On success: hold the Vault Key in memory for this session only, navigate
  to the dashboard shell.

## Lock vs. Log out
- **Lock**: clears Master Key and Vault Key from memory, keeps the account
  session token valid, returns to the Unlock screen. Trigger on manual
  action, an idle timeout (configurable in settings), and app
  backgrounding on mobile.
- **Log out**: clears the session token (delegates to `account-auth-flow`)
  AND performs a Lock. Next access requires full Login + Unlock again.
- These must be implemented as genuinely separate functions, not "log out"
  calling a partial version of "lock" or vice versa.

## Biometric quick-unlock (mobile)
- Only offered after at least one successful manual Master Password
  unlock. Caches the Vault Key wrapped by a biometric-gated platform key
  (iOS Secure Enclave / Android Keystore with `setUserAuthenticationRequired`).
- A change in enrolled biometrics or device passcode must invalidate this
  cache, falling back to manual Master Password entry — do not silently
  keep the old cached key valid.
- The biometric cache only satisfies Lock events (idle timeout, manual
  lock, backgrounding). A full app/process restart always requires manual
  Master Password entry regardless of whether biometric unlock is enabled
  — never persist an unwrapped or biometric-cached Vault Key across a
  process restart.

## Emergency Kit recovery — not in scope for this skill yet
A future skill (`emergency-kit-recovery`) will cover a user-held offline
recovery artifact for forgotten Master Passwords. Do not attempt to
improvise a recovery mechanism as part of this skill's work — if asked to
add "password recovery," point back to `docs/AUTH_AND_UNLOCK_FLOW.md`
section 5 and treat it as a separate, later phase requiring its own design
review.

## Rules of engagement
- Grep for any place the Master Password value might be passed into a
  network call, logger, analytics event, or crash report — this is the
  single most important thing to verify by hand after this skill's code is
  generated, not just by test coverage.
- Write tests: correct Master Password unwraps successfully; incorrect
  Master Password fails via the GCM auth tag (not a separate check);
  repeated failures trigger increasing backoff; Lock clears memory but
  preserves session; Log out clears both.

## Output location
UI: `app/lib/features/auth/master_password_setup_screen.dart`,
`app/lib/features/auth/unlock_screen.dart`. Core logic:
`core/crypto/vault_key_wrapping.dart` (builds on `crypto-e2ee-core`'s
primitives — don't reimplement AES-GCM/Argon2id calls here, reuse them).
Session/lock state: `core/auth/vault_lock_manager.dart`.
