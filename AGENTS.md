# AGENTS.md — SentinelVault

Standing instructions for every agent spawned in this workspace. Read this
before starting any task. Full architecture lives at `docs/ARCHITECTURE.md` —
consult it before making structural decisions.

## What this project is
A hybrid (offline-first + cloud-sync) zero-knowledge password manager with
extra security-analysis features: password strength, URL/email phishing
detection, dark-web breach monitoring, and basic file security checks, all
summarized via an AI insights layer. Cross-platform: web, iOS, Android from
one Flutter codebase, with a shared `core/` package for crypto and data
models.

## Non-negotiable security rules (never violate these, even if asked to
"simplify for now")
1. The master password never leaves the device and is never logged, ever —
   not in debug prints, not in crash reports, not in analytics.
2. No plaintext vault item, password, or file content is ever sent to the
   backend or to any third-party API (including the AI insights LLM call).
   Only ciphertext, hashes used for k-anonymity lookups, or redacted
   structured signals may leave the device.
3. All new cryptographic code must use vetted libraries (e.g. `cryptography`,
   `pointycastle`, libsodium bindings) — never hand-rolled crypto primitives.
4. AES-256-GCM only for symmetric encryption (never ECB, never CBC without
   HMAC). Argon2id only for password-based key derivation. Unique nonce per
   encryption operation — never reuse a nonce with the same key.
5. Any change touching `core/crypto/` or `backend/auth-service/` requires
   writing/updating unit tests in the same task and must not be marked done
   until those tests pass.
6. Never commit real API keys, secrets, or `.env` files. Use `.env.example`
   with placeholder values.
7. Vault import/export is a high-risk area: imported plaintext must be
   encrypted immediately and never written to a temp file, cache, or log;
   plaintext export requires master-password re-entry and an explicit
   warning before it's produced. See the `vault-import-export` skill before
   touching any of this code.
8. There are two entirely separate secrets: the **Account Password**
   (identity/session, handled by `auth-service`'s OPAQUE flow) and the
   **Master Password** (vault unlock, feeds Argon2id → Master Key → Vault
   Key, never transmitted to the server in any form). Never derive one
   from the other, never let a UI flow substitute one for the other, and
   never let a successful account login alone unlock the vault dashboard —
   the Unlock step (Master Password) is always required separately. See
   `docs/AUTH_AND_UNLOCK_FLOW.md` before touching auth or unlock code.
9. Any new *additional* unlock factor (hardware-key `hmac-secret`, a future
   Recovery Key, etc.) must be implemented as an extra wrapping layer on
   the Vault Key, never as a shortcut that bypasses deriving/using a real
   secret. Each such factor requires its own reviewed design doc before
   implementation — see `fido2-webauthn-auth` and `emergency-kit-recovery`
   skills for the pattern to follow.
10. The browser extension must not hold an independent copy of the Vault
    Key by default — it operates paired to the native/desktop app via
    native messaging (see `browser-extension-core` skill) unless a
    standalone mode is explicitly scoped and reviewed separately.

## Coding standards
- Dart: follow `effective_dart` lint rules; run `dart analyze` and
  `flutter test` before considering a task complete.
- Backend (Node/NestJS): strict TypeScript (`strict: true`), no `any` in
  code touching crypto, auth, or vault data.
- Every public function in `core/` needs a doc comment explaining inputs,
  outputs, and any security invariant it relies on or enforces.
- Prefer small, reviewable diffs. For anything touching encryption, auth, or
  the sync protocol: stop and produce an `implementation_plan.md` artifact
  for human review before writing code.

## Workspace boundaries
- Agents working on `app/` (Flutter UI) should not modify `core/crypto/`
  without flagging it — UI agents consume the crypto core's public API, they
  don't change its internals.
- Agents working on `backend/security-analysis-service/` must not add code
  paths that forward raw vault data to third-party APIs (see rule 2).
- Treat `skills/` directory as read/append-only reference material, not a
  place for application code.

## When in doubt
Pause and ask the human rather than guessing on anything related to: key
derivation parameters, what data is allowed to cross the network boundary,
or third-party API credential handling.
