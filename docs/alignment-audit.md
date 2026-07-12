# Alignment Audit: SentinelVault Native & Web Parity

This audit evaluates the platform-parity and architectural alignment of SentinelVault's cryptographic and security-hardware features against the requirements defined in [`docs/RUST_CROSS_PLATFORM_REEVALUATION.md`](file:///Users/sougataroy/Downloads/Kaggle%20Antigravity/SentinelVault/docs/RUST_CROSS_PLATFORM_REEVALUATION.md).

---

## Audit Findings Summary

| # | Audited Area | Risk Level | In Alignment? | Status / Explanation |
|---|---|---|---|---|
| **1** | **Shamir's Secret Sharing (Phase 36)** | 🟢 **No Risk** | **Yes** | Implemented in Rust, compiled to WASM for Web, uses audited `sharks` crate. |
| **2** | **Hybrid PQC wrapping (Phase 38-39)** | 🟢 **No Risk** | **Yes** | Implemented in Rust, compiled to WASM for Web, uses standard `ml-kem` and `ml-dsa` crates. |
| **3** | **Duress Wipe Hook (Phase 37)** | 🟡 **Low Risk** | **Yes (Soft)** | Unconditional call site fails silently on Web due to `try/catch` wrapper in secure storage. |
| **4** | **Settings Biometric Switch on Web** | 🔴 **Medium Risk** | **No** | Toggle is rendered unconditionally on Web, failing only after user interaction. |

---

## Detailed Findings

### 1. Shamir's Secret Sharing (Phase 36)
* **Implementation Location**: Inside the Rust core library ([`native/crypto_core/src/shamir.rs`](file:///Users/sougataroy/Downloads/Kaggle%20Antigravity/SentinelVault/native/crypto_core/src/shamir.rs)) and exposed via FFI / WASM Bindings ([`native/crypto_core/src/lib.rs`](file:///Users/sougataroy/Downloads/Kaggle%20Antigravity/SentinelVault/native/crypto_core/src/lib.rs)).
* **Library Used**: The audited [`sharks`](https://crates.io/crates/sharks) Rust crate (v0.5.0) with the `zeroize_memory` feature enabled.
* **Web Behavior**: Compiles to WASM and is accessed in Flutter Web via JS Interop mapping (`wasmShamirSplit` / `wasmShamirCombine` in [`core/lib/src/crypto/native_crypto_bridge_web.dart`](file:///Users/sougataroy/Downloads/Kaggle%20Antigravity/SentinelVault/core/lib/src/crypto/native_crypto_bridge_web.dart)).
* **Risk Assessment**: **No Risk (Green)**. Full implementation parity and zero hand-rolled crypto primitives.

---

### 2. Hybrid PQC wrap/unwrap (Phase 38-39)
* **Implementation Location**: Inside the Rust core library ([`native/crypto_core/src/algorithms/pqc_hybrid.rs`](file:///Users/sougataroy/Downloads/Kaggle%20Antigravity/SentinelVault/native/crypto_core/src/algorithms/pqc_hybrid.rs)) and exposed via FFI / WASM Bindings ([`native/crypto_core/src/lib.rs`](file:///Users/sougataroy/Downloads/Kaggle%20Antigravity/SentinelVault/native/crypto_core/src/lib.rs)).
* **Libraries Used**: 
  - **`ml-kem`** (v0.2.0) from the official *Rust Crypto* project.
  - **`ml-dsa`** (v0.1.0) from the official *Rust Crypto* project.
* **Web Behavior**: Compiles to WASM and is called via JS Interop (`pqc_hybrid_wrap` / `pqc_hybrid_unwrap`) on Web, reusing the same codebase.
* **Risk Assessment**: **No Risk (Green)**. Maintained, standard, and audited cryptographic libraries from the Rust Crypto project are utilized.

---

### 3. Duress/Decoy Vault Wipe Hook (Phase 37)
* **Call Site**: [`app/lib/features/auth/unlock_screen.dart#L192`](file:///Users/sougataroy/Downloads/Kaggle%20Antigravity/SentinelVault/app/lib/features/auth/unlock_screen.dart#L192):
  ```dart
  await triggerDuressWipeHook();
  ```
* **Guard Status**: The call is **unconditional** (not guarded by any target platform check). It calls into `SecureStorage.instance.deleteBiometricWrappedVaultKey()`.
* **Web Behavior**: Because the production implementation `FlutterPlatformSecureStorage` wraps the native platform MethodChannel call in an error-ignoring `try/catch` block:
  ```dart
  @override
  Future<void> deleteBiometricWrappedVaultKey() async {
    try {
      await _channel.invokeMethod('deleteBiometricWrappedVaultKey');
    } catch (e) {
      // ignore errors on deletion
    }
  }
  ```
  The call fails silently on Web rather than throwing an exception.
* **Risk Assessment**: **Low Risk (Yellow)**. The app does not crash, but relying on silent error-swallowing for MethodChannels on unsupported platforms (Web) is a code smell. It violates the architecture recommendation to make platform-specific OS integration explicitly a guarded no-op.

---

### 4. Settings Biometric Switch on Web
* **Rendering Status**: **Yes**. The switch is rendered unconditionally in [`app/lib/features/settings/settings_screen.dart#L355`](file:///Users/sougataroy/Downloads/Kaggle%20Antigravity/SentinelVault/app/lib/features/settings/settings_screen.dart#L355).
* **Behavior on Click**: When clicked on Web, the app queries `BiometricAuthService.instance.isBiometricsSupported()`, which returns `false` due to the failing platform channel. The app then shows a SnackBar saying:
  > *"Biometrics not supported on this device"*
* **Risk Assessment**: **Medium Risk (Red / Yellow)**. This violates the platform capability guidelines in `docs/RUST_CROSS_PLATFORM_REEVALUATION.md`, which states:
  > *"...OS-hardware features have no web equivalent, by design... State this plainly in-app (e.g. simply not showing a biometric-unlock toggle in Web Settings at all) rather than showing a disabled option with an explanation."*
  Showing an active, togglable UI component that only fails after user interaction leads to poor UX on the Web build.
