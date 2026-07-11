# SentinelVault — Native FFI Crypto Core: Cross-Platform Implementation Plan
### How Phase 35 stays a single Rust codebase across iOS, Android, and Web

This resolves the gap identified in review: `mlock()`/`mprotect()` have no
meaning inside a Wasm sandbox. The fix is **one Rust crate, two build
outputs, two thin Dart bindings, one unchanged Dart-facing API** — not two
separate crypto implementations.

---

## 1. Crate layout — conditional compilation, not a fork

```
native/crypto_core/
├── Cargo.toml
├── src/
│   ├── lib.rs                 # public crate API — same signatures regardless of target
│   ├── algorithms/             # Argon2id, AES-256-GCM, SRP/OPAQUE math
│   │   └── ...                # pure Rust, no OS syscalls — compiles identically
│   │                           # for aarch64-apple-ios, aarch64-linux-android, AND wasm32
│   ├── secure_mem/
│   │   ├── mod.rs             # public SecureBuffer type, same interface everywhere
│   │   ├── native.rs          # #[cfg(unix)] — real mlock()/mprotect() via `region`
│   │   │                        or direct libc bindings
│   │   └── wasm.rs            # #[cfg(target_arch = "wasm32")] — no-op lock/guard,
│   │                            zeroization only
│   └── zeroize_all.rs         # `zeroize` crate usage — works identically on every
│                                 target, this is the one guarantee that's universal
```

Key point: **the cryptographic algorithms themselves (Argon2id, AES-GCM,
SRP math) are pure computation and compile identically to wasm32 as to
native** — nothing about the actual encryption changes per platform. Only
`secure_mem/` is platform-gated:

```rust
// secure_mem/mod.rs
pub struct SecureBuffer { /* ... */ }

impl SecureBuffer {
    pub fn new(len: usize) -> Self { /* alloc, same everywhere */ }

    #[cfg(unix)]
    pub fn lock(&self) -> Result<(), Error> { native::mlock(self) }
    #[cfg(target_arch = "wasm32")]
    pub fn lock(&self) -> Result<(), Error> { Ok(()) } // no-op, documented

    #[cfg(unix)]
    fn install_guard_pages(&mut self) { native::guard(self) }
    #[cfg(target_arch = "wasm32")]
    fn install_guard_pages(&mut self) { /* not available — no-op */ }
}

impl Drop for SecureBuffer {
    fn drop(&mut self) {
        zeroize_all::zero(self.as_mut_slice()); // universal, every target
    }
}
```

Callers throughout the crate (Argon2id derivation, AES-GCM key handling)
use `SecureBuffer` uniformly — they don't need their own `#[cfg]` branches,
because the guarantee difference is fully contained inside `secure_mem/`.

---

## 2. Build outputs per platform

| Target | Command (representative) | Output | Consumed by |
|---|---|---|---|
| Android | `cargo ndk -t arm64-v8a build --release` | `.so` | Dart FFI (`dart:ffi`) |
| iOS | `cargo build --release --target aarch64-apple-ios` (+ simulator target), packaged as an `.xcframework` | `.a` / `.xcframework` | Dart FFI (`dart:ffi`) |
| Web | `wasm-pack build --target web` | `.wasm` + JS glue | JS interop, **not** `dart:ffi` |

**This is the detail most likely to trip up an agent**: `dart:ffi` itself
does not work on Flutter Web at all — it's an io-platform-only Dart
library. The web build does not "use FFI to call Wasm" the way the mobile
builds use FFI to call a shared library. Instead:

- `wasm-pack`/`wasm-bindgen` generates a `.wasm` file plus a JS glue module
  that exposes plain JS functions wrapping the compiled Rust functions.
- The Flutter web app calls those JS functions via `dart:js_interop`
  (or `package:js` on older Flutter versions) — a completely different
  Dart binding path from the native FFI one.

## 3. Dart-side abstraction — one interface, two implementations, selected by conditional import

```
core/crypto/
├── native_crypto_core.dart        # public interface (abstract class),
│                                     unchanged regardless of platform
├── native_crypto_core_io.dart      # dart:ffi implementation — used on
│                                     Android/iOS/desktop
├── native_crypto_core_web.dart     # dart:js_interop implementation — used
│                                     on Web, calls the wasm-bindgen glue
└── native_crypto_core_selector.dart
```

```dart
// native_crypto_core_selector.dart
export 'native_crypto_core_stub.dart'
    if (dart.library.io) 'native_crypto_core_io.dart'
    if (dart.library.js_interop) 'native_crypto_core_web.dart';
```

Everything above this file (`vault-unlock-flow`, `account-auth-flow`,
`item-type-schema` encryption calls) imports only
`native_crypto_core.dart`'s interface — it never knows or cares whether
it's talking to a `.so`/`.xcframework` via FFI or a `.wasm` module via JS
interop. This is what keeps AGENTS.md rule 12 ("crypto-e2ee-core's public
API stays identical") true across all three platforms.

---

## 4. What's genuinely different on Web, and how to be honest about it

- `SecureBuffer.lock()` is a real `mlock()` call on iOS/Android, a no-op on
  Web. Document this at the point of the `#[cfg]` branch, not just in a
  design doc.
- Guard pages: real on native, unavailable on Web — same treatment.
- Zeroization: **identical guarantee on every platform.** The `zeroize`
  crate's overwrite-on-drop behavior is a language-level operation, not an
  OS syscall, so this protection is not weakened on Web.
- iOS-specific note from the review is also correct and worth carrying
  into the implementation: only lock small fixed-size secrets (a 32-byte
  Vault Key, an Argon2id output) — never attempt to `mlock()` an entire
  decrypted vault payload, since iOS's Jetsam process killer enforces
  strict wired-memory limits per app.

### Recommended (not required) UX addition
Consider a small, honest indicator in the app's security-status view
(e.g. in the Security Center dashboard from Part 2) distinguishing
"Enhanced memory protection: active" (native platforms) from a plainer
state on Web — in the same spirit as the Duress Vault's requirement to
never overstate what a feature guarantees. This is optional but consistent
with how the rest of this project communicates security tradeoffs.

---

## 5. Testing across targets

- **Cross-target correctness**: run the same fixed test vectors (known
  Argon2id/AES-GCM inputs and expected outputs) against the Android build,
  the iOS build, and the Wasm build, asserting bit-identical results. This
  is what actually proves the conditional compilation didn't silently
  change behavior anywhere except `secure_mem/`.
- **Guard-page test**: only runs on the native (unix) build — skip or mark
  as platform-specific for Wasm, since there's nothing to test there.
- **CI matrix**: three build jobs (Android via `cargo-ndk`, iOS via an
  `.xcframework` build, Web via `wasm-pack`), each running the shared test
  vector suite, so a change to `algorithms/` that accidentally breaks one
  target is caught immediately.
