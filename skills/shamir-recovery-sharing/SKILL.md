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
  side channels during reconstruction). Verify current audited options at
  implementation time.
- **This is pure platform-agnostic computation — implement it inside the
  same `native/crypto_core/` Rust crate from Phase 35, not as a separate
  module or in Dart.** Shamir's Secret Sharing has no OS-syscall
  dependency, so it compiles identically for Android, iOS, and
  `wasm32-unknown-unknown` with no `#[cfg]` gating needed beyond wrapping
  intermediate secrets in the crate's existing `SecureBuffer` type. See
  `docs/RUST_CROSS_PLATFORM_REEVALUATION.md`.
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
  information, not a corrupted-but-plausible-looking key), regenerating
  shares invalidates the old set, and bit-identical results across the
  Android/iOS/Wasm builds for the same fixed test vectors (same CI matrix
  as Phase 35).

## Output location
`native/crypto_core/src/algorithms/shamir.rs`, exposed through the same
Dart binding split (`native_crypto_core.dart` interface,
`native_crypto_core_io.dart`/`native_crypto_core_web.dart`
implementations) established in Phase 35 — do not create a separate
Dart-only implementation or a second native module. Builds on the existing
Recovery Key logic from `emergency-kit-recovery` — extend it, don't fork a
parallel recovery mechanism. UI: `app/lib/features/auth/
shamir_recovery_setup_screen.dart` and the corresponding reconstruction
flow screen.
