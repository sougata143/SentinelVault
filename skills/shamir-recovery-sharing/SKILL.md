---
name: shamir-recovery-sharing
description: Use when upgrading the existing Emergency Kit (from emergency-kit-recovery) to M-of-N distributed recovery via Shamir's Secret Sharing, splitting the Recovery Key across multiple trusted contacts. Load emergency-kit-recovery's SKILL.md alongside this one — this extends that feature, it doesn't replace its core design.
---

# Skill: Shamir Recovery Sharing (M-of-N)

## Objective
Split the existing single-envelope Recovery Key (from `emergency-kit-
recovery`) into N cryptographic shares via Shamir's Secret Sharing (SSS),
such that any M of them (e.g. 3-of-5) can reconstruct the Recovery Key,
while any fewer yield zero information about it.

## Rules of engagement
- **Use an audited SSS library — never a hand-rolled polynomial
  interpolation implementation.** This is a well-known area for subtle
  bugs (weak/predictable randomness for polynomial coefficients, timing
  side channels during reconstruction). Verify current audited options
  (Rust crates are generally more mature here than Dart-native ones — this
  is a good candidate to implement in the `native-ffi-crypto-core` module
  if that phase is already in place) at implementation time.
- The thing being split is the **existing Recovery Key** from
  `emergency-kit-recovery` — do not invent a second, separate secret. This
  keeps the underlying Vault Key-wrapping construction unchanged; only the
  Recovery Key's distribution/reconstruction mechanism changes.
- Let the user choose M and N within reasonable bounds (e.g. N from 3–10,
  M from 2 up to N) at setup time, with a sensible default (e.g. 3-of-5)
  and a clear explanation of the tradeoff (higher M = more resistant to a
  single compromised/colluding share-holder, but requires coordinating
  more people to recover).
- Each share must be presented as an independent, distributable artifact
  (e.g. a distinct printable card or file), with no labeling that reveals
  which other people hold the remaining shares — a compromised or coerced
  share-holder should not be able to identify targets for collecting
  additional shares.
- Reconstruction happens **entirely client-side** — collected shares are
  combined locally to reconstruct the Recovery Key, never uploaded to any
  server for combination.
- Regenerating the share set (e.g. suspected compromise of a share, or
  changing M/N) must invalidate the previous share set entirely.
- Write tests for: correct reconstruction from exactly M valid shares,
  failed reconstruction from M-1 shares (should yield no partial
  information, not a corrupted-but-plausible-looking key), and that
  regenerating shares invalidates the old set.

## Output location
`core/crypto/shamir_recovery.dart` (or native module if built into
`native-ffi-crypto-core`), building on the existing Recovery Key logic in
`core/crypto/recovery_key.dart` from `emergency-kit-recovery` — extend it,
don't fork a parallel recovery mechanism. UI: `app/lib/features/auth/
shamir_recovery_setup_screen.dart` and the corresponding reconstruction
flow screen.
