---
name: emergency-kit-recovery
description: Use only when implementing the optional Emergency Kit / Recovery Key feature — a user-held offline backup for a forgotten Master Password. Do not start this without a reviewed design doc in place first; the construction must not weaken the Master-Password-only unlock path.
---

# Skill: Emergency Kit Recovery

## Objective
Give users a way to recover their vault if they forget their Master
Password, without introducing any server-side backdoor and without
weakening the existing Master-Password-only cryptographic path.

## Before writing any code
1. Produce a written design doc (`implementation_plan.md` or a dedicated
   `docs/RECOVERY_KEY_DESIGN.md`) proposing the exact construction — e.g.
   whether the Recovery Key independently wraps a second copy of the Vault
   Key, or whether a secret-sharing scheme (e.g. Shamir) splits it. Get
   this reviewed/approved before implementation. This skill intentionally
   does not prescribe the exact primitive so it gets deliberate human
   review rather than an agent's default choice.
2. Confirm the chosen construction cannot be used to reconstruct the Vault
   Key from server-held data alone — the Recovery Key material itself must
   never be uploaded or stored server-side in usable form.

## Required properties regardless of construction chosen
- The Recovery Key is generated once, client-side, at Master Password
  creation time (or when the user opts in later).
- It is displayed to the user exactly once, as a downloadable/printable
  artifact, with instructions to store it offline (printed, physical safe)
  — never emailed, never saved to cloud storage by the app itself, never
  re-displayable after initial creation.
- Losing both the Master Password and the Recovery Key must still result
  in permanent vault loss — this is a feature of the design, not a gap to
  "fix."
- Using the Recovery Key to regain access must still require deriving/
  entering it locally — it does not grant any server-side reset capability.
- If the user regenerates a Recovery Key (e.g. suspected compromise of the
  old one), the old one must be invalidated for future use.

## Rules of engagement
- Do not implement this feature as "email the user a reset link" or any
  variant that involves the server being able to grant vault access — that
  defeats the zero-knowledge model entirely.
- Write tests for: successful recovery via a valid Recovery Key, rejection
  of an invalidated/regenerated old Recovery Key, and that no network
  request ever includes the Recovery Key's raw value (only whatever
  minimal wrapped/derived artifact the approved design calls for, if any).
- For M-of-N distributed recovery (splitting this Recovery Key across
  multiple trusted contacts via Shamir's Secret Sharing), see the
  `shamir-recovery-sharing` skill — that's an extension of this feature,
  not a separate mechanism.

## Output location
Design doc: `docs/RECOVERY_KEY_DESIGN.md` (write this first). Implementation:
`core/crypto/recovery_key.dart` and `app/lib/features/auth/recovery_kit_screen.dart`,
following whatever locations the approved design doc specifies.
