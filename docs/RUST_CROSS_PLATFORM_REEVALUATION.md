# SentinelVault — Re-evaluation: Rust & Cross-Platform Scope
### Which Phase 4/5 features actually touch Rust, and what's genuinely platform-limited vs. not

Phase 35 solved the *general pattern* (one crate, `#[cfg]`-gated memory
handling, dual Dart bindings). This document applies that pattern
correctly across every feature that involves native/Rust code, and — more
importantly — separates two categories that were being treated too
similarly:

1. **Pure cryptographic math** (Argon2id, AES-GCM, SRP/OPAQUE, Shamir's
   Secret Sharing, ML-KEM/ML-DSA): platform-agnostic computation. These
   compile identically to `wasm32-unknown-unknown` as to native targets.
   **There is no cross-platform gap here at all** — Phase 35's pattern
   handles all of these the same way, in the same crate.
2. **OS security-hardware integration** (Secure Enclave, Android Keystore/
   StrongBox, `mlock()`/guard pages): genuinely platform-limited. Browsers
   do not expose Secure Enclave/Keystore-equivalent APIs at all — this
   isn't a gap to engineer around, it's a real ceiling. The correct
   response is a documented, graceful no-op on Web, not a workaround.

Conflating these two categories is what led to hedgy language like "prefer
implementing this in the native core if suitable" in a couple of the
Phase 5 skill files — this re-evaluation makes it a firm rule instead.

---

## Corrected scope per feature

| Feature | Category | Cross-platform status |
|---|---|---|
| Argon2id / AES-GCM / SRP-OPAQUE (Phase 35) | Pure math | ✅ Full parity, all 3 platforms — already correctly handled |
| M-of-N Shamir recovery (Phase 36) | Pure math | ✅ Full parity — **belongs in the same crate as Phase 35, not a separate module** |
| Hybrid PQC sharing, ML-KEM/ML-DSA (Phase 38-39) | Pure math | ✅ Full parity — **also belongs in the same crate** |
| Biometric-gated Secure Enclave/Keystore cache (Phase 25) | OS hardware integration | ⚠️ Native (iOS/Android/desktop) only — **no web equivalent exists, and none should be attempted**; Web always requires manual Master Password entry, by design, not as a fallback-of-shame |
| Duress vault's native wipe hook (Phase 37) | OS hardware integration | ⚠️ Native only — on Web there is no biometric cache to invalidate in the first place, so the hook is correctly a no-op there (the Duress Vault's *database-swap* logic itself is pure Dart/math and works identically on Web) |
| Browser extension core (Phase 29-30) | Pure math (crypto) + JS/DOM integration | ✅ Should reuse the **same Wasm build** produced for Flutter Web, not a second, separately-compiled bundle |

---

## Change 1 — Consolidate all pure-math Rust work into one crate

Previously, `shamir-recovery-sharing` and `pqc-hybrid-sharing` each said
"prefer implementing in the native crypto core **if suitable**." That
hedge is removed: Shamir's Secret Sharing and the ML-KEM/ML-DSA hybrid
construction are exactly the same category of platform-agnostic
computation as Argon2id and AES-GCM, so they go in the same
`native/crypto_core/` crate from Phase 35, using the same `#[cfg]` pattern
where relevant (in practice, neither SSS nor the PQC math needs the
`secure_mem` gating at all beyond wrapping their intermediate secrets in
the same `SecureBuffer` type already built).

```
native/crypto_core/
├── src/
│   ├── algorithms/
│   │   ├── argon2id.rs
│   │   ├── aes_gcm.rs
│   │   ├── opaque.rs
│   │   ├── shamir.rs          # new — M-of-N secret sharing
│   │   └── pqc_hybrid.rs      # new — ML-KEM-768/ML-DSA-65 + HKDF combiner
│   └── secure_mem/            # unchanged from Phase 35
```

One crate, one build pipeline (Android `.so`, iOS `.xcframework`, Web
`.wasm` via `wasm-pack`), one shared Dart interface with the same
`dart:ffi` (native) vs. `dart:js_interop` (Web) split already established.
This also means the cross-target test-vector strategy from Phase 35
(bit-identical output across Android/iOS/Wasm builds) extends to Shamir
and PQC operations for free, using the same CI matrix.

## Change 2 — Be explicit that OS-hardware features have no web equivalent, by design

`native-secure-storage` (Phase 25) and the duress vault's wipe hook
(Phase 37) should stop being framed as "does this work on web too?" — they
don't, and that's correct, not a shortcoming to fix. Web's Unlock screen
always uses manual Master Password entry; there is no biometric
quick-unlock option to offer there in the first place, so there's nothing
for a duress trigger to invalidate. State this plainly in-app (e.g. simply
not showing a biometric-unlock toggle in Web Settings at all) rather than
showing a disabled option with an explanation.

## Change 3 — Browser extension reuses the Wasm build, doesn't recompile Dart

`browser-extension-core`'s original instruction to "compile the shared
Dart core to JS/Wasm" is superseded now that Phase 35 already produces a
Wasm build of the actual crypto core for Flutter Web. The browser
extension should link against **that same `wasm-pack` output** — one
compiled artifact serving both Flutter Web and the browser extensions —
rather than maintaining a second, separately-compiled Dart-to-Wasm bundle
that would need to be kept in sync with the Rust one.

---

## What doesn't change
Everything from `docs/FFI_CROSS_PLATFORM_PLAN.md` about the crate layout,
the `#[cfg(unix)]` vs. `#[cfg(target_arch = "wasm32")]` split for
`secure_mem`, and the dual Dart-binding approach stays exactly as
specified — this document extends that pattern to more algorithms, it
doesn't revise it.
