---
name: fido2-webauthn-auth
description: Use when implementing passkey/WebAuthn login (Account Password replacement/supplement) or hardware-key vault-unlock factors (Master Password supplement). These are two different features with different risk profiles — read the objective section before starting either.
---

# Skill: FIDO2 / WebAuthn Authentication

## Objective — two separate features, do not conflate them

### Feature A: Passkeys for Account login (clean fit — implement fully)
Standard WebAuthn registration/authentication ceremony, added to
`auth-service` alongside (or replacing) the OPAQUE Account Password flow.
The server stores a public key and verifies signed challenges — this
carries no zero-knowledge risk since the Account Password never touched
vault encryption.

- Server: implement standard WebAuthn relying-party registration
  (`navigator.credentials.create`) and authentication
  (`navigator.credentials.get`) ceremonies. Use a maintained WebAuthn
  library for the backend language in use rather than hand-rolling
  attestation/assertion verification.
- Mobile: use the platform-native passkey APIs (iOS
  `ASAuthorizationPlatformPublicKeyCredentialProvider`, Android Credential
  Manager's passkey support) — check current Flutter plugin coverage for
  these at implementation time rather than assuming a specific package.
- Support both platform passkeys (synced via iCloud Keychain/Google
  Password Manager) and roaming hardware keys (YubiKey via USB/NFC/BLE) as
  Account-login options alongside the existing Account Password.

### Feature B: Hardware key as a vault-unlock factor (needs a design doc first — do not skip this)
A WebAuthn assertion alone does not produce a stable secret usable for key
wrapping. To use a hardware key (e.g. YubiKey) to unlock the vault itself,
the mechanism is the **CTAP2 `hmac-secret` extension**: given a
fixed, app-chosen salt, the authenticator returns a stable, device-bound
pseudorandom value on each use. This can then wrap an additional copy of
the Vault Key, the same way `emergency-kit-recovery`'s Recovery Key does —
**it must be implemented as an additional wrapping layer, never as a
replacement that skips deriving/using a real secret.**

Before writing any code for Feature B:
1. Produce a design doc (`docs/HARDWARE_KEY_UNLOCK_DESIGN.md`) describing
   exactly how the `hmac-secret` output is used to wrap a copy of the
   Vault Key, how the salt is chosen/stored (non-secret, can be public),
   and what happens if the hardware key is lost (this should degrade to
   "that unlock factor stops working," not "vault becomes unrecoverable"
   as long as the Master Password or another registered factor still
   works).
2. Get that design reviewed/approved before implementing Feature B.
3. Confirm the construction doesn't weaken the Master-Password-only path —
   adding a hardware-key unlock factor should never reduce the security of
   unlocking via Master Password alone.

## Rules of engagement
- Never implement Feature B as "WebAuthn assertion succeeded → unlock" —
  that has no cryptographic connection to the actual Vault Key and would
  be security theater.
- Losing all unlock factors (Master Password, any hardware-key factor, any
  Recovery Key) must still mean permanent vault loss — this is expected
  zero-knowledge behavior, not a bug to route around.
- Write tests for Feature A: passkey registration, login success,
  and rejection of a tampered assertion. For Feature B (once its design is
  approved): correct hardware key unwraps the Vault Key copy, a different
  physical key fails, and removing that unlock factor doesn't affect other
  factors' ability to unlock.

## Output location
Feature A: `backend/auth-service/webauthn/`, UI in
`app/lib/features/auth/passkey_login.dart`. Feature B (post-design-approval):
`core/crypto/hardware_key_unlock.dart`, UI in
`app/lib/features/auth/hardware_key_unlock_screen.dart`.
