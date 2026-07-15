# SentinelVault

SentinelVault is a hybrid, offline-first, zero-knowledge password manager and security analysis suite. It runs across Web, iOS, and Android from a unified Flutter codebase, backed by a shared Dart core package for client-side cryptography and data modeling, a native Rust cryptography core, and specialized NestJS backend microservices.

---

## 🛡️ Security Invariants (Non-Negotiable)

1. **Zero-Knowledge Architecture**: The Master Password and decrypted vault items never leave the user's device. No plaintext vault item, password, card number, or identity data is ever transmitted to the server or any third-party API.
2. **Two-Secret Model**: Authentication and vault decryption are deliberately separate. The **Account Password** authenticates the user's session (via SRP-6a) and grants no cryptographic access to vault contents. The **Master Password** — a distinct secret, never transmitted to the server in any form — is the only thing that can derive the key needed to decrypt the vault. A valid session alone never unlocks the vault; the Unlock step is always required separately. Successful authentication yields a cryptographically signed JWT (HS256, 24 h expiry) stored on-device in secure storage; every subsequent request to the backend microservices is authenticated via `Authorization: Bearer <token>` — the server verifies the signature before trusting any identity claim.
3. **Local Cryptography**: All symmetric encryption uses AES-256-GCM. Keys are derived using Argon2id with a unique local salt per user. Cryptographic key material is held only in volatile memory while the vault is unlocked and is explicitly zeroized afterward.
4. **Privacy-Preserving Breach Monitoring**: Password breach checks use k-anonymity (only the first 5 characters of the SHA-1 password hash are sent to Have I Been Pwned). Email breach checks are opt-in only, with explicit disclosure before any email address is sent to a third party.
5. **Least-Privilege AI Insights**: The AI Insights layer (Gemini) receives only redacted, non-sensitive structural signals (e.g. password strength scores, file extensions, signature-mismatch flags) — never raw passwords, emails, files, or vault content.

---

## 🏗️ System Architecture

```
                          ┌────────────────────────────────────────────────────────┐
                          │                      CLIENT LAYER                      │
                          │                                                        │
                          │    ┌──────────┐        ┌──────────┐        ┌──────────┐│
                          │    │   Web    │        │   iOS    │        │ Android  ││
                          │    │ (Flutter)│        │ (Flutter)│        │ (Flutter)││
                          │    └────┬─────┘        └────┬─────┘        └────┬─────┘│
                          │         └───────────────────┼───────────────────┘      │
                          │                      ┌───────────────┐                 │
                          │                      │  Shared Core  │                 │
                          │                      │ (Dart Package)│                 │
                          │                      └───────┬───────┘                 │
                          │                      ┌───────────────┐                 │
                          │                      │ Native Crypto │                 │
                          │                      │ Core (Rust)   │                 │
                          │                      └───────────────┘                 │
                          └──────────────────────────────┼─────────────────────────┘
                                                         │
                                                         │ TLS 1.3
                                                         ▼
                          ┌────────────────────────────────────────────────────────┐
                          │                      CLOUD LAYER                       │
                          │                                                        │
                          │  ┌────────────────┐  ┌────────────────┐               │
                          │  │ Auth Service   │  │ Sync API        │               │
                          │  │ (SRP-6a / MFA/ │  │ (Encrypted vault│               │
                          │  │  Passkeys)     │  │  blob sync)     │               │
                          │  └───────┬────────┘  └────────┬────────┘               │
                          │          │                    │                        │
                          │  ┌───────────────────┐ ┌────────────────────────┐      │
                          │  │ Security Analysis  │ │ Sharing Service        │      │
                          │  │ Service (NestJS)   │ │ (PQC Key Directory /   │      │
                          │  └────────────────────┘ │  Share Invites / REST) │      │
                          │            │             └────────────────────────┘     │
                          │            ▼                                            │
                          │       ┌──────────┐        ┌──────────┐                  │
                          │       │ Postgres │        │  Redis   │                  │
                          │       └──────────┘        └──────────┘                  │
                          └────────────────────────────────────────────────────────┘
```

### 1. Unified Frontend Client (`app/`)
A cross-platform Flutter application providing:
- **Vault Tab**: 3-column layout (sidebar categories, item list with sorting/filtering/search, and a detail pane).
- **Security Center Tab**: Posture dashboard tracking password health scores, local reused-password detection, a chronological data-breach feed, a weekly AI-generated digest, and quick-scan triggers.
- **Import/Export Suite**: Local in-memory parsers for 1Password (`.1pux`), Bitwarden (`.json`), LastPass (`.csv`), Chrome/Firefox/Safari native export presets, Dashlane/Keeper/NordPass/RoboForm CSV, Proton Pass JSON, and KeePass `.kdbx` decryption/parsing (with local password/keyfile decryption and strict memory scrubbing). Plaintext exports require Master Password re-verification.

### 2. Shared Core (`core/`)
A platform-agnostic Dart package managing local databases (SQLite), the Dart-side crypto interface (delegating to the native Rust core), data normalization, import parsers, and backend API clients (`AiInsightsClient`, `BackendBreachMonitor`, sync client).

### 3. Native Crypto Core (`native/crypto_core/`)
A single Rust crate providing Argon2id, AES-256-GCM, SRP-6a math, Shamir's Secret Sharing, and the hybrid PQC (X25519 + ML-KEM-768, Ed25519 + ML-DSA-65) primitives. Compiled natively (`.so`/`.dylib`/`.dll`) for iOS/Android/desktop via `dart:ffi`, and to WebAssembly for both the Flutter Web build and the browser extension via `dart:js_interop`, sharing one build output across both. Native builds additionally get hardware memory protections (page locking, guard pages) where the OS supports it; all platforms get explicit zeroization of key material after use.

### 4. Backend Services (`backend/`)
- **auth-service**: Account authentication via SRP-6a (zero-knowledge — the Account Password is never transmitted in a crackable form), passwordless passkeys (WebAuthn/FIDO2), TOTP MFA, and rate limiting. Issues cryptographically signed JWTs (`@nestjs/jwt`, HS256) containing the server-assigned user UUID as `sub`; token expiry is 24 h.
- **sync-api**: Stores and serves only encrypted vault blobs, per-item version numbers for conflict detection, and the wrapped Vault Key envelope needed for cross-device Master Password unlock — never anything the server could decrypt. All endpoints are protected by a custom `JwtAuthGuard`; the acting user ID is extracted from the verified JWT `sub` claim, never from a client-supplied header.
- **security-analysis-service**: URL reputation scanning, SPF/DKIM/DMARC email parsing, macro/signature file scanning, scheduled HIBP breach checks, and redacted-signal AI insight generation via Gemini. All identity-gated endpoints verify the JWT before processing.
- **sharing-service**: Key-directory microservice publishing classical + post-quantum public key bundles and managing per-recipient wrapped (ciphertext) Folder Keys for PQC hybrid folder sharing. All key-directory and share-invite endpoints are protected by `JwtAuthGuard`.

---

## 📂 Project Directory Structure

```
.
├── app/                           # Flutter client application
│   ├── lib/
│   │   ├── features/              # Feature UI screens (vault, security_center, auth, settings, etc.)
│   │   └── theme/                 # Global theme configuration
│   └── test/                      # Widget, UI, and navigation tests
├── core/                          # Shared cryptography & data package
│   ├── lib/
│   │   └── src/                   # Crypto interface, DB, models, security, import/export, sync
│   └── test/                      # Core unit and crypto round-trip tests
├── native/                        # Native Crypto Core (Rust)
│   └── crypto_core/
│       ├── src/algorithms/        # Argon2id, AES-GCM, SRP, Shamir, pqc_hybrid.rs
│       └── Cargo.toml
├── browser-extension/             # Browser extension (Chrome, Firefox, Safari)
│   ├── src/                       # Extension popup, content scripts, native messaging host
│   └── test/                      # Native messaging host + content-script integration tests
├── backend/                       # NestJS cloud microservices
│   ├── auth-service/              # Account authentication, MFA, passkeys        (:3001)
│   ├── sync-api/                  # Encrypted vault sync                         (:3002)
│   ├── security-analysis-service/ # Reputation, breach, and AI insight service   (:3003)
│   └── sharing-service/           # PQC key directory & folder sharing           (:3004)
├── infra/                         # Cloud Run, Postgres, Redis Terraform templates
└── docs/                          # Architecture, schemas, and UX definitions
```

---

## 🛠️ Local Development Setup

### Prerequisites
- Flutter SDK (v3.22+, Dart ≥ 3.12)
- Node.js (v20 LTS+)
- Rust + Cargo (v1.77+) — required to build the native crypto core
- Docker & Docker Compose

### 1. Database and Cache Dependencies
```bash
docker compose up -d
```

### 2. Build the Native Crypto Core
The native crate must be built before running `core/` tests or the Flutter app:
```bash
cd native/crypto_core
cargo build --release
cargo test               # mandatory before any change to crypto code

# Web/browser-extension target:
rustup target add wasm32-unknown-unknown
cargo build --target wasm32-unknown-unknown --features wasm
```

### 3. Backend Services
Each service reads a shared root `.env` at startup. Copy `.env.example` to `.env` and set a strong `JWT_SECRET` before running in any environment beyond local dev.

```bash
# Auth Service — :3001
cd backend/auth-service && npm install && npm run start

# Sync API — :3002
cd backend/sync-api && npm install && npm run start

# Security Analysis Service — :3003
cd backend/security-analysis-service && npm install && npm run start

# Sharing Service (PQC Key Directory) — :3004
cd backend/sharing-service && npm install --legacy-peer-deps && SHARING_PORT=3004 npm run start
```

### 4. Running the Flutter App
```bash
cd app
flutter pub get
flutter run
```

Build for web distribution:
```bash
flutter build web --release
```

---

## 🧪 Testing

### Core Package
```bash
cd core
dart test
```
> Requires the native crypto core to be built first (see setup step 2) — `dart:ffi`/`dart:js_interop` have nothing to load otherwise.

### Flutter App
```bash
cd app
flutter test   # widget, navigation, Export Auth Gate, and Security Dashboard tests
```

### Browser Extension
```bash
cd browser-extension
dart test
node test/autofill_test.js
```

### Backend Services
All services require a running Postgres + Redis and a `JWT_SECRET` for the integration test suites:
```bash
export DB=postgresql://sentinel_admin:sentinel_password_change_me@localhost:5432/sentinelvault
export JWT_SECRET=test-jwt-secret-at-least-32-bytes-long!!

for svc in auth-service sync-api security-analysis-service sharing-service; do
  DATABASE_URL=$DB REDIS_URL=redis://localhost:6379 JWT_SECRET=$JWT_SECRET \
    npm test --prefix backend/$svc -- --forceExit
done
```

---

## 🚀 Key Features

- **Zero-Knowledge Cryptography**: Local AES-256-GCM encryption for all vault items, Argon2id key derivation with a unique local salt, and a native Rust crypto core shared across native and Wasm builds.
- **Two-Secret Auth Model**: Account Password (session/identity, SRP-6a) and Master Password (vault unlock) are fully independent — compromising one never grants access via the other.
- **Secure Remote Password (SRP-6a)**: Zero-knowledge client-server login handshake; the Account Password is never transmitted in a crackable form. Successful login yields a signed JWT stored on-device; all subsequent API requests carry it as `Authorization: Bearer <token>`.
- **Server-Side JWT Verification**: Every backend endpoint that modifies or reads user-scoped data validates the `Authorization: Bearer <token>` header via a shared `JwtAuthGuard` before the controller method runs. The acting user identity is derived entirely from the verified JWT `sub` claim — the server never trusts a client-supplied user ID header.
- **Local Unlock & Brute-Force Lockouts**: Client-side exponential backoff on repeated failed Master Password attempts.
- **Independent Lock vs. Logout**: Lock clears key material from memory but preserves the session; Logout clears both.
- **Biometric Quick-Unlock & OS-Backed Secure Storage**: `flutter_secure_storage` for session tokens; the biometric-cached Vault Key is protected via a non-exportable, biometric-required hardware key (Secure Enclave on iOS via `kSecAccessControlBiometryCurrentSet`, Android Keystore with `setUserAuthenticationRequired(true)` and StrongBox where available). Devices lacking hardware-backed secure storage have quick-unlock disabled automatically; new biometric enrollment invalidates the cache and falls back to manual Master Password entry. Not offered on Web, which has no equivalent hardware to back it.
- **Emergency Kit Recovery Key**: Offline-first recovery via dual key-wrapping — a client-side-generated recovery key derives a second wrapping key for the Vault Key, persisted as ciphertext via the sync API. Regenerating invalidates prior recovery keys.
- **Shamir's Secret Sharing Recovery (M-of-N)**: The Emergency Kit recovery key can additionally be split into N shares (threshold M, range 3–10) via an audited GF(256) SSS implementation in the native Rust core, for distributed recovery across trusted contacts.
- **FIDO2/WebAuthn Passkey Authentication**: Standard WebAuthn registration/login for the Account Password, supporting platform passkeys (iCloud Keychain/Google Password Manager) and roaming hardware keys (YubiKey via USB/NFC/BLE).
- **Hardware Key Vault-Unlock**: Opt-in additional Vault Key wrapping via the FIDO2 CTAP2 `hmac-secret` extension, with Master Password fallback always available if the key is lost or removed.
- **Duress / Decoy Vault**: Independent Vault Alpha (real) and Vault Beta (decoy) with a visually and timing-indistinguishable unlock flow. Decoy unlock fires a native hook that invalidates the real vault's biometric cache only — never touching its encrypted data — plus an explicit in-app disclosure of the feature's actual limitations.
- **PQC Hybrid Folder Sharing**: Folder Key sharing via X25519 + ML-KEM-768 envelope wrapping (combined via HKDF-SHA256) and AES-256-GCM, signed with Ed25519 + ML-DSA-65. Mandatory out-of-band key-fingerprint verification defends against server-side public-key substitution; revocation is enforced via Folder Key rotation and re-wrapping.
- **Thin Browser Extensions (Chrome, Firefox, Safari)**: Paired-mode architecture — the extension holds no Vault Key material itself, instead communicating with the already-unlocked native/desktop app via a native messaging host. Reuses the same Rust-compiled Wasm crypto core built for Flutter Web rather than a separate compiled bundle. Enforces exact-origin autofill matching and blocks cross-origin iframe fills.
- **Security Center Dashboard**: Password health scoring, credential reuse detection, chronological HIBP breach feed, and a weekly redacted AI-generated digest.
- **Import/Export Suite**: See Local Development Setup and the frontend client section above for supported formats.

---

## 🔮 Future Scope

- **Post-Quantum Account Auth Hardening**: SRP-6a and WebAuthn/passkey signatures are asymmetric/discrete-log-based and theoretically vulnerable to a future quantum computer, unlike the vault's symmetric-only encryption chain. Bounded in severity today (compromise would grant account-level access only, never vault contents) but worth revisiting once post-quantum variants of these protocols mature.
- **Emergency Kit printable artifact refinements**: further hardening of the offline recovery-kit UX.

> Peer-to-peer/local-network syncing was evaluated and intentionally descoped — cloud sync via `sync-api` remains the only sync transport.
