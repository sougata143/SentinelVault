# SentinelVault

SentinelVault is a hybrid, offline-first, zero-knowledge password manager and security analysis suite. It is designed to run securely across Web, iOS, and Android platforms from a unified Flutter codebase, powered by a shared core package for client-side cryptography and data modeling, and specialized NestJS backend microservices.

---

## 🛡️ Security Invariants (Non-Negotiable)

1. **Zero-Knowledge Architecture**: The master password and decrypted vault items never leave the user's device. No plaintext vault item, password, card number, or identity data is ever transmitted to the server or any third-party APIs.
2. **Local Cryptography**: All symmetric encryption uses AES-256-GCM. Passwords are derived using the Argon2id key derivation function with a unique local salt per user. Cryptographic keys are held purely in volatile memory while the vault is unlocked.
3. **Privacy-Preserving Breach Monitoring**: Password breach checks use k-anonymity (transmitting only the first 5 characters of the SHA-1 password hash to Have I Been Pwned). Email breach checks are opt-in only with explicit user disclosure before sending.
4. **Least-Privilege AI Insights**: The AI Insights generation layer (Gemini 1.5 Flash) receives strictly redacted, non-sensitive structural signals (e.g., password zxcvbn scores, file extensions, signature mismatch flags) — never raw passwords or vault content.

---

## 🏗️ System Architecture

SentinelVault is organized into three primary components:

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
                          └──────────────────────────────┼─────────────────────────┘
                                                         │
                                                         │ TLS 1.3
                                                         ▼
                          ┌────────────────────────────────────────────────────────┐
                          │                      CLOUD LAYER                       │
                          │                                                        │
                          │    ┌────────────────┐   ┌────────────────────────┐     │
                          │    │ Auth Service   │   │ Security Analysis      │     │
                          │    │ ( SRP / MFA /  │   │ Service (NestJS)       │     │
                          │    │  Passkeys)     │   │ - URL Scanner          │     │
                          │    └───────┬────────┘   │ - Email Scanner        │     │
                          │            │            │ - File Security        │     │
                          │            ▼            │ - Breach Monitor       │     │
                          │       ┌──────────┐      │ - AI Insights (Gemini) │     │
                          │       │ Postgres │      └────────────────────────┘     │
                          │       └──────────┘                                     │
                          └────────────────────────────────────────────────────────┘
```

### 1. Unified Frontend Client (`app/`)
A cross-platform Flutter application providing:
- **Vault Tab**: 3-column layout (sidebar categories, item list with sorting/filtering/search, and a detail pane).
- **Security Center Tab**: Posture dashboard tracking password health scores, local reused-password detection, a chronological data breach feed, a weekly AI-generated digest, and quick-scan triggers.
- **Import/Export Suite**: Local in-memory parsers for 1Password (`.1pux`), Bitwarden (`.json`), LastPass (`.csv`), Chrome/Firefox/Safari native export presets, Dashlane/Keeper/NordPass/RoboForm CSV, Proton Pass JSON, and KeePass `.kdbx` decryption/parsing (with local password/keyfile decryption and strict memory scrubbing). Plaintext exports require master-password verification.

### 2. Shared Core (`core/`)
A platform-agnostic Dart package managing local databases (SQLite), cryptography engines (Argon2id and AES-256-GCM), data normalization, import parsers, and backend API clients (`AiInsightsClient`, `BackendBreachMonitor`).

### 3. Backend Services (`backend/`)
- **auth-service**: Restricts authentication using passwordless passkeys (WebAuthn/FIDO2), secure SRP, rate-limiting, and TOTP MFA.
- **security-analysis-service**: Handles URL reputation scanning, SPF/DKIM/DMARC email parsing, macro/signature file scanning, HIBP cron synchronizations, and allow-listed AI insights generation using Gemini.

---

## 📂 Project Directory Structure

```
.
├── app/                          # Flutter client application
│   ├── lib/
│   │   ├── features/             # Feature UI screens (vault, security_center, etc.)
│   │   └── theme/                # Global theme configuration
│   └── test/                     # Widget, UI, and navigation tests
├── core/                         # Shared cryptography & data package
│   ├── lib/
│   │   └── src/                  # Crypto, DB, Models, Security, Import/Export
│   └── test/                     # Core units and crypto round-trip tests
├── backend/                      # NestJS cloud microservices
│   ├── auth-service/             # Authentication & user directory microservice
│   └── security-analysis-service/ # Security reputation, breach, and AI service
├── infra/                        # Cloud Run, Postgres, Redis Terraform templates
└── docs/                         # Architecture, schemas, and UX definitions
```

---

## 🛠️ Local Development Setup

### Prerequisites
- Flutter SDK (v3.12+)
- Node.js (v18+)
- Docker & Docker Compose

### 1. Database and Cache Dependencies
Spin up PostgreSQL and Redis using Docker:
```bash
docker-compose up -d
```

### 2. Security Analysis Backend
Create a `.env` file inside `backend/security-analysis-service/` matching `.env.example`, then run:
```bash
cd backend/security-analysis-service
npm install
npm run start
```
*Note: Service runs on port `3003`.*

### 3. Authentication Backend
Create a `.env` file inside `backend/auth-service/`, then run:
```bash
cd backend/auth-service
npm install
npm run start
```

### 4. Running the Flutter App
Run the client application:
```bash
cd app
flutter pub get
flutter run
```

To build the client for web distribution:
```bash
flutter build web --release
```

---

## 🧪 Testing

### Running Client and Core Tests
Run all core package tests:
```bash
cd core
dart test
```

Run all Flutter widget and integration tests (including the Export Auth Gate and Security Dashboard tests):
```bash
cd app
flutter test
```

### Running Backend Tests
Run NestJS unit and integration test suites:
```bash
cd backend/security-analysis-service
npm run test
```

---

## 🚀 Key Features

- **Zero-Knowledge Cryptography**: Local AES-256-GCM symmetric encryption for all vault items, and Argon2id key derivation with a local unique salt.
- **Secure Remote Password (SRP-6a)**: Zero-knowledge client-server login handshakes preventing plaintext password transmission over the network.
- **Local Unlock & Brute-Force Lockouts**: Screen-lock client protecting the master key in memory with client-side exponential backoff delays on repeated failed attempts.
- **Independent Lock vs. Logout**: Separates memory key zero-out (Lock) from token session invalidation (Logout) for maximum security and usability.
- **Biometric Quick-Unlock & OS-Backed Secure Storage**: Uses `flutter_secure_storage` for session tokens. The biometric-cached Vault Key is protected via a non-exportable, biometric-required hardware key (Secure Enclave on iOS with `kSecAccessControlBiometryCurrentSet`, and Android Keystore with `setUserAuthenticationRequired(true)` and StrongBox where available). Automatically detects devices/emulators lacking hardware-backed secure storage to disable insecure quick-unlock. Any new biometric enrollment invalidates the cached key and falls back to manual Master Password entry.
- **Emergency Kit Recovery Key**: Offline-first recovery system using Dual Key-Wrapping (Candidate 1). Generates a 32-character Base32 recovery key client-side, derives a KDF key via Argon2id, wraps the active Vault Key using AES-256-GCM, and persists it via sync API envelopes. Past recovery keys are invalidated on regeneration.
- **Security Center Dashboard**: Password health score tracking, credential re-use checks, Have I Been Pwned chronological breach feed, and weekly redacted AI digests.
- **Import/Export Suite**: Local in-memory parsers for 1Password (`.1pux`), Bitwarden (`.json`), LastPass (`.csv`), Chrome/Firefox/Safari native export presets, Dashlane/Keeper/NordPass/RoboForm CSV, Proton Pass JSON, and KeePass `.kdbx` decryption/parsing (with local password/keyfile decryption and strict memory scrubbing). Plaintext exports require master-password verification.
- **FIDO2/WebAuthn Passkey Authentication (Feature A)**: Standard WebAuthn primary registration and login ceremonies. Supports both platform passkeys (iCloud Keychain/Google Password Manager) and roaming hardware keys (e.g. YubiKeys via USB/NFC/BLE) alongside OPAQUE Account Password flow, including username-less/discoverable credentials.
- **Hardware Key Vault-Unlock (Feature B)**: Secure local vault-unlock option using the FIDO2 CTAP2 `hmac-secret` extension to wrap an additional copy of the Vault Key. Operates as an opt-in additional envelope, ensuring Master Password fallback if the key is lost or removed.

---

## 🔮 Future Scope

1. **Browser Extensions**: Export core dart libraries to Javascript/Wasm to share the same cryptographic engine in Chrome, Firefox, and Safari extensions.

