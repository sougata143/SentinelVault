# SentinelVault — Auth & Vault-Unlock Addendum
### Two-secret model: Account Password (login) vs. Master Password (vault unlock)

---

## 1. Why two secrets, and what changes vs. the original design

The original `docs/ARCHITECTURE.md` §4 assumed one password doing double duty
(feeding both the OPAQUE auth handshake and the Vault Key derivation). That's
still a valid model, but you've chosen the stronger separation most
serious password managers converge on: **compromising the account password
alone must never be enough to decrypt the vault.**

What stays the same:
- `auth-service` (Phase 3, OPAQUE-based) is reused as-is. It now
  authenticates the **Account Password** only.
- The Argon2id → Master Key → Vault Key → per-item AES-256-GCM chain from
  `ARCHITECTURE.md` §4 is unchanged — it now runs on the **Master Password**
  instead.

What's new:
- The Master Password has its own random salt (unrelated to the account
  password's OPAQUE registration) and produces a **wrapped Vault Key blob**
  that gets stored server-side as ciphertext (allowed, per the existing
  "only ciphertext/metadata leaves the device" rule) so it can sync across
  the user's devices.
- There is no server-side verifier for the Master Password at all — the
  wrapping/unwrapping step itself (AES-256-GCM's authentication tag) is the
  only correctness check, and it happens entirely on-device.

```
Account Password ──► OPAQUE handshake ──► session token (JWT access + refresh)
                                            (proves identity, nothing more)

Master Password ──► Argon2id (own salt) ──► Master Key (memory-only)
                                                   │
                                                   ▼ unwraps (AES-256-GCM)
                                        Wrapped Vault Key blob
                                        (synced as ciphertext, from server)
                                                   │
                                                   ▼ success/fail via GCM auth tag
                                              Vault Key ──► decrypts vault items
```

---

## 2. Data stored server-side (still zero-knowledge compliant)

| Field | Secret? | Notes |
|---|---|---|
| Account: email, OPAQUE envelope/verifier | No secret exposure | Standard from Phase 3 |
| `master_kdf_salt` | Not secret | Random per user, needed to re-derive Master Key on any device |
| `wrapped_vault_key` | Ciphertext | AES-256-GCM(Master Key, Vault Key) — useless without Master Password |
| `master_password_hint` (optional, user-supplied) | User's choice | Never store the password itself, even "for hints" — a free-text hint field only |

The server can never verify a Master Password is correct — that's
intentional. It only ever hands back `master_kdf_salt` + `wrapped_vault_key`
for the client to attempt unwrapping locally.

---

## 3. Screens & flow

### 3.1 Sign Up (two steps, don't collapse into one form)
**Step 1 — Create account**: Email, Account Password, Confirm Account
Password → calls `auth-service` register (OPAQUE), creates session.

**Step 2 — Create your Master Password**: separate screen, explicitly
explains: *"This is different from your account password and is never sent
to our servers. If you forget it, we cannot recover your vault."* Fields:
Master Password, Confirm Master Password, live strength meter (reuse
`password-strength-analysis`). On submit, client-side:
1. Generate random `master_kdf_salt`.
2. Derive Master Key = Argon2id(master password, salt).
3. Generate random Vault Key.
4. Wrap: `wrapped_vault_key` = AES-256-GCM(Master Key, Vault Key).
5. Upload only `master_kdf_salt` + `wrapped_vault_key` via `sync-api`.
6. Hold Vault Key in memory → vault is now unlocked for this session.

### 3.2 Login
Email + Account Password → `auth-service` OPAQUE login → session
established → **vault is locked** → redirect to Unlock screen (3.3). Do not
show any vault content or the dashboard shell yet.

### 3.3 Unlock (every new session, or after auto-lock)
Fetch `master_kdf_salt` + `wrapped_vault_key` from `sync-api`. Prompt for
Master Password only. On submit:
1. Derive Master Key = Argon2id(entered password, fetched salt).
2. Attempt to decrypt `wrapped_vault_key` with Master Key.
3. GCM auth tag fails → generic "Incorrect master password" (never
   "incorrect password, try again" phrasing that implies which secret was
   wrong beyond that) + client-side exponential backoff after repeated
   failures.
4. GCM auth tag succeeds → Vault Key now in memory → navigate to the
   Vault/Security Center dashboard shell.

### 3.4 Lock vs. Log out (distinct actions, both need to exist)
- **Lock** (manual button, or automatic after an idle timeout, or on
  app backgrounding on mobile): clears Master Key and Vault Key from
  memory, keeps the account session alive, returns to the Unlock screen
  (3.3) — account password is not required again.
- **Log out**: clears the session token too (requires full Login (3.2) +
  Unlock (3.3) again next time).

### 3.5 Biometric quick-unlock (mobile, optional but expected)
After a successful manual unlock, offer to cache the Vault Key wrapped by a
device-biometric-gated key (iOS Secure Enclave / Android Keystore
StrongBox). Face ID/fingerprint then unlocks by unwrapping *that* local
cache — it never bypasses the Master Password requirement, it just skips
re-typing it on the same trusted device. A device passcode/biometric
change should invalidate this cache and fall back to manual Master
Password entry.

**Restart policy**: the biometric cache is only valid for in-app Lock
events (idle timeout, manual lock, backgrounding). A full app restart
(process killed and relaunched — not just backgrounding) always requires
manual Master Password entry, even if biometric quick-unlock is enabled.
Do not persist the unwrapped or biometric-cached Vault Key across a process
restart in any form (memory-only cache is fine; anything written to disk
for this purpose is not).

---

## 5. Emergency Kit recovery (future phase — not in the initial build)

A true zero-knowledge design has no way for the server to help a user who
forgets their Master Password, since the server never has anything that
can reconstruct it. The common mitigation (used by 1Password's Secret Key,
for example) is a **user-held, offline recovery artifact** generated once
at Master Password creation time — not a server-side reset.

### Design sketch (to be detailed fully when this phase is picked up)
- At Master Password creation, additionally generate a high-entropy random
  **Recovery Key** (independent of the Master Password).
- Use the Recovery Key as an *additional* wrapping layer on the Vault Key
  (i.e. the Vault Key is wrapped once by the Master Key, and the Recovery
  Key independently also wraps a copy, or is combined via a secret-sharing
  scheme) — the specific construction needs a short design doc before
  implementation, since it must not weaken the Master-Password-only path.
- Present the Recovery Key once, as a downloadable/printable PDF, with
  clear instructions to store it offline (printed, in a safe) — never
  emailed, never stored in cloud storage, never displayed again after
  initial creation.
- Losing both the Master Password and the Recovery Key means permanent,
  unrecoverable vault loss — this must remain true; the Recovery Key is a
  user-controlled backup, not a backdoor.
- This phase should not be started until the core auth/unlock flow
  (Phases 17–23) is fully tested, since it adds a second cryptographic path
  to the same Vault Key and needs its own dedicated security review.

## 4. Rules for this feature specifically

- The Master Password field must never be sent over the network in any
  form — not raw, not hashed, not as part of a request body, ever. Only
  `master_kdf_salt` (not secret) and `wrapped_vault_key` (ciphertext) cross
  the network boundary.
- The Account Password and Master Password must use independent salts and
  independent Argon2id calls — never derive one from the other.
- Never let the sign-up flow proceed to vault/dashboard access without
  Step 2 (Master Password creation) completing successfully.
- Never auto-fill or suggest the Master Password using the Account
  Password (no "same as above" shortcut) — that would defeat the entire
  point of separating them.
- Warn clearly, at Master Password creation time, that there is no
  recovery mechanism in this version — this is the correct behavior for a
  true zero-knowledge design, but it must be communicated, not hidden in
  fine print. (An optional future "Emergency Kit" printable recovery sheet,
  similar in spirit to 1Password's, is a reasonable later addition but is
  out of scope here.)
