# SentinelVault — Phase 4 Advanced Features: Evaluation & Architecture

Evaluates the five proposed features, flags where each does or doesn't fit
the existing zero-knowledge model, and sets a recommended build order.

## Recommended order and why

| # | Feature | Risk to existing model | Effort | Do when |
|---|---|---|---|---|
| 1 | Native Secure Enclave/Keystore | None — hardening only | Low-Med | First |
| 5 | Expanded import parsers | None — additive | Low | Second (parallel-safe with #1) |
| 2 | FIDO2/WebAuthn MFA | Login: none. Vault-unlock: needs a new wrapping layer, same discipline as Recovery Key | Med | Third |
| 4 | Browser extensions | New attack surface (content scripts, extension storage) | High | Fourth |

Note: peer-to-peer/WebRTC syncing was evaluated but is **out of scope** —
descoped at the user's request. Cloud sync (from Phase 4 of the original
build) remains the only sync transport.

---

## 1. Native Secure Enclave & Keystore Integration — straightforward, do first

Your Phase 22 biometric cache was described in terms of "a biometric-gated
platform key" without pinning to specific tooling. This phase makes that
real:

- **`flutter_secure_storage`** is the right choice for storing the
  *wrapped* session tokens and the *wrapped* Vault Key cache — on Android
  it's backed by Keystore (AES, StrongBox where available), on iOS by
  Keychain.
- **Keychain alone is not the same as Secure-Enclave-backed biometric
  gating.** For a key that's genuinely non-exportable and requires Face
  ID/Touch ID or fingerprint at the OS level for every use (not just "the
  app checked a boolean"), you need Keychain items created with
  `kSecAttrTokenIDSecureEnclave` + an access-control flag (iOS) and Android
  Keystore keys generated with `setUserAuthenticationRequired(true)` +
  `setIsStrongBoxBacked(true)` where the device supports it. This typically
  needs a small platform-channel shim (or a plugin purpose-built for it) —
  plain `flutter_secure_storage` alone doesn't expose the Secure Enclave
  access-control-flag configuration on iOS. Check current pub.dev options
  at implementation time (the plugin ecosystem moves faster than this doc
  can stay current) and fall back to a native platform-channel
  implementation if nothing suitable exists.
- This replaces the "simulated" wrapping mentioned in your notes with a
  real hardware-backed key — the actual Vault Key material stored by this
  layer is unchanged (still the AES-256-GCM wrapped blob from
  `vault-unlock-flow`), only *where and how* the wrapping key for the
  biometric cache is generated/stored changes.

## 5. Expanded Import Capabilities — straightforward, do in parallel

Extending `vault-import-export` to cover more sources is low-risk and
purely additive — same parse → preview → encrypt-on-commit pipeline
already built. Two format notes worth flagging:

- **Chrome/Firefox/Safari native exports**: these are just specific CSV
  column layouts (Chrome: `name,url,username,password`; Firefox similar).
  Add them as named presets on top of the generic CSV mapper you already
  have, rather than new parsers from scratch.
- **KeePass (`.kdbx`)**: different from the others — it's an encrypted
  container, not a plaintext export. You'll need a `.kdbx` parsing library
  (KDBX3/KDBX4 format) and the user must supply the KeePass database's own
  password and/or key file *locally* to decrypt it before mapping into
  your schema. This still fits the existing rule (parse in memory, encrypt
  on commit, never persist the intermediate plaintext) — it just has an
  extra "unlock the source file" step first.
- Dashlane, Keeper, NordPass, Proton Pass, RoboForm all export to CSV or
  JSON with their own column/field names — each is a mapping table, not new
  architecture.

## 2. FIDO2/WebAuthn MFA — split this into two genuinely different features

Your two-secret model (Account Password vs. Master Password) means "add
passkeys" isn't one feature — it's two, with different risk profiles:

### 2a. Passkeys/hardware keys for Account login — clean fit, do this fully
Replacing or supplementing the OPAQUE-based Account Password login with
standard WebAuthn/passkey authentication is exactly what that protocol is
for: asymmetric keypair, server verifies a signed challenge, never sees a
shared secret. This is a straightforward addition to `auth-service` and
carries no zero-knowledge concerns since the Account Password never touched
vault encryption anyway.

### 2b. Hardware key as a Master-Password-unlock factor — needs its own design doc, same discipline as the Emergency Kit
"Unlock the vault with a YubiKey" can't just mean "WebAuthn assertion
succeeded, so unlock" — a WebAuthn assertion doesn't produce a stable
secret you can feed into key-wrapping. The mechanism that actually works
(and is what KeePassXC uses for hardware-key unlocking) is the **CTAP2
`hmac-secret` extension**: given a fixed salt, a compatible authenticator
(most YubiKeys) returns a stable, device-bound pseudorandom value. That
value can then be used the same way the Recovery Key was — as an
*additional* wrapping layer on the Vault Key, not a replacement for the
Master Password's cryptographic role.

This must **not** be treated as "type less, same security" — it's
architecturally identical in risk profile to the Emergency Kit feature:
it adds a second cryptographic path to the same Vault Key. Follow the same
pattern — a reviewed design doc before implementation — see the new
`fido2-webauthn-auth` skill below.

## 4. Browser Extensions — biggest new attack surface, plan the boundary carefully

Compiling the Dart core to JS/Wasm is the easy part (`dart2js` for a JS
bundle, or the Dart-to-Wasm toolchain — check current maturity at
implementation time). The architecture decision that matters more:

**Recommended: thin extension, not a standalone vault.** Rather than
giving the browser extension its own copy of the vault and its own unlock
flow (doubling the places a Vault Key can leak from), have the extension
talk to the already-unlocked native/desktop app via a **native messaging
host** (Chrome/Firefox Native Messaging API; Safari Web Extension's
equivalent) — the extension asks "is the vault unlocked, and if so, give me
this one item for autofill," rather than holding vault contents itself.
This mirrors how 1Password's and Bitwarden's desktop-paired extensions
work, and it means there's exactly one place (the main app) that ever holds
the Master Key/Vault Key, not two.

A fallback "standalone extension with its own lock/unlock" mode can be a
later addition for users who only ever use the browser, but it should not
be the first thing built, since it duplicates the highest-risk part of the
whole system (key handling) into a second codebase and a second execution
context (content scripts run in a less-trusted environment than a native
app).

**Content-script boundaries**: autofill/credential-capture content scripts
must only fill credentials into a form whose page origin matches the
stored item's saved origin exactly (no subdomain-wildcard matching by
default, no cross-origin fill), must never fill into a cross-origin
iframe embedded in an otherwise-matching page, and must not expose vault
contents to the page's own JavaScript context (use the isolated content-
script world, communicate with the extension background/service worker
only via extension messaging, never via `window.postMessage` to the page).
