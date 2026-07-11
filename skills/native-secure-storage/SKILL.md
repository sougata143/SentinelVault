---
name: native-secure-storage
description: Use when replacing simulated/in-memory platform key wrapping with real OS-backed secure storage (iOS Keychain/Secure Enclave, Android Keystore/StrongBox) — this covers session token storage and the biometric-gated Vault Key cache from vault-unlock-flow.
---

# Skill: Native Secure Storage

## Objective
Move the biometric quick-unlock cache and session token storage from any
simulated/plain local storage onto real platform-backed secure storage,
with the Vault Key cache specifically gated by a non-exportable,
biometric-required hardware key where the platform supports it.

## What to use where
- **Session tokens** (access/refresh from `account-auth-flow`): store via
  `flutter_secure_storage` (Keychain-backed on iOS, Keystore-backed on
  Android) — no biometric gate needed here, just secure-at-rest storage.
- **Biometric-cached Vault Key** (from `vault-unlock-flow`'s biometric
  quick-unlock): needs a stronger guarantee than generic secure storage —
  a key that literally cannot be used without a fresh biometric check at
  the OS level. On iOS this means a Keychain item created with
  `kSecAttrTokenIDSecureEnclave` and an access-control flag requiring
  biometry; on Android, a Keystore key generated with
  `setUserAuthenticationRequired(true)` and, where available,
  `setIsStrongBoxBacked(true)`. If the plugin ecosystem doesn't currently
  expose this level of configuration, implement a small platform-channel
  shim rather than settling for a weaker guarantee.

## Rules of engagement
- Verify current plugin support (e.g. on pub.dev) before assuming a
  specific package covers Secure-Enclave-level access control — this
  moves faster than any static doc, so check at implementation time rather
  than trusting a name in this skill file.
- A change in enrolled biometrics or device passcode must invalidate the
  biometric-cached key automatically (this is standard platform behavior
  for access-control-flagged keys, but write a test/manual QA step
  confirming it falls back to manual Master Password entry, per
  `vault-unlock-flow`'s existing rule).
- Never fall back to a weaker storage mechanism silently if the
  hardware-backed option is unavailable on a given device — detect it and
  disable biometric quick-unlock on that device, falling back to manual
  Master Password entry, rather than caching the key with a lesser
  guarantee.
- This skill only changes *where and how* keys are stored — it does not
  change any of the cryptographic constructions from `crypto-e2ee-core` or
  `vault-unlock-flow`. Do not modify Argon2id parameters, AES-GCM usage, or
  the wrapping hierarchy as part of this work.

## Output location
`core/platform/secure_storage.dart` (shared interface) with platform-
specific implementations under `app/ios/` and `app/android/` for anything
requiring native platform-channel code.
