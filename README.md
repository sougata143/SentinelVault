# SentinelVault

SentinelVault is a hybrid, offline-first, zero-knowledge password manager and security analysis suite. It runs across Web, iOS, and Android from a unified Flutter codebase, backed by a shared Dart core package for client-side cryptography and data modeling, a native Rust cryptography core, and specialized NestJS backend microservices.

---

## 🛡️ Security Invariants (Non-Negotiable)

1. **Zero-Knowledge Architecture**: The Master Password and decrypted vault items never leave the user''s device. No plaintext vault item, password, card number, or identity data is ever transmitted to the server or any third-party API.
2. **Two-Secret Model**: Authentication and vault decryption are deliberately separate. The **Account Password** authenticates the user''s session (via SRP-6a) and grants no cryptographic access to vault contents. The **Master Password** — a distinct secret, never transmitted to the server in any form — is the only thing that can derive the key needed to decrypt the vault. A valid session alone never unlocks the vault; the Unlock step is always required separately. Successful authentication yields a cryptographically signed JWT (HS256, 24 h expiry) stored on-device in secure storage; every subsequent request to the backend microservices is authenticated via `Authorization: Bearer <token>` — the server verifies the signature before trusting any identity claim.
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
- **Vault Tab**: 3-column layout (sidebar categories, item list with sorting/filtering/search, and a detail pane). Supports **multi-item selection** (long-press or checklist-mode toggle) with batch soft-delete of selected items and a confirmation-guarded Delete All action — both paths use the same soft-delete sync mechanism as single-item deletion (`isDeleted = true`, version-incremented, synced via `VaultSyncManager`). Supports specialized vault item templates for **TOTP / Authenticator**, **SSH Key Pairs** (monospaced formatting), **API Keys & Tokens** (masked secrets), **Crypto Wallet Seed Phrases** (maximally sensitive UI with double-confirmation reveal modal), **Software Licenses**, and **Secure Notes with encrypted file attachments** (10 MB per file limit). Features **Biometric-Gated Vault Unlock Caching** (Face ID, Touch ID, Fingerprint, Windows Hello via `local_auth` and OS secure hardware enclaves) with configurable auto-lock TTL, zero Master Password caching, and instant key purging upon lock or toggle disable.
- **Security Center Tab**: Posture dashboard tracking password health scores, local reused-password detection, a chronological data-breach feed, a weekly AI-generated digest, quick-scan triggers, and a **Zero-Knowledge Security Audit Log Feed** surfacing chronological activity stream events (logins, exports, unlocks, sharing) with status indicators and zero sensitive data leakage.
- **Import/Export Suite**: Local in-memory parsers for 1Password (`.1pux`), Bitwarden (`.json`), LastPass (`.csv`), Chrome/Firefox/Safari native export presets, Dashlane/Keeper/NordPass/RoboForm CSV, Proton Pass JSON, and KeePass `.kdbx` decryption/parsing (with local password/keyfile decryption and strict memory scrubbing). Seamlessly maps imported TOTP keys, SSH keys, API keys, software licenses, and secure notes into native SentinelVault templates. Plaintext exports require Master Password re-verification.

### 2. Shared Core (`core/`)
A platform-agnostic Dart package managing local databases (SQLite), the Dart-side crypto interface (delegating to the native Rust core), data normalization, TOTP code generation (RFC 6238 SHA1/SHA256/SHA512), encrypted file attachment blobs (`VaultItemAttachment`), import parsers, and backend API clients (`AiInsightsClient`, `BackendBreachMonitor`, sync client, `SecurityActivityLog`).

### 3. Native Crypto Core (`native/crypto_core/`)
A single Rust crate providing Argon2id, AES-256-GCM, SRP-6a math, RFC 6238 TOTP code generation, Shamir's Secret Sharing (via `blahaj` — an audited GF(256) SSS implementation that resolves RUSTSEC-2024-0398), and the hybrid PQC (X25519 + ML-KEM-768, Ed25519 + ML-DSA-65) primitives. Compiled natively (`.so`/`.dylib`/`.dll`) for iOS/Android/desktop via `dart:ffi`, and to WebAssembly for both the Flutter Web build and the browser extension via `dart:js_interop`, sharing one build output across both. Native builds additionally get hardware memory protections (page locking, guard pages) where the OS supports it; all platforms get explicit zeroization of key material after use.

### 4. Backend Services (`backend/`)
- **auth-service** (`:3001`): Account authentication via SRP-6a (zero-knowledge), passwordless passkeys (WebAuthn/FIDO2), TOTP MFA, and rate limiting. Uses a Redis-backed store for active SRP-6a login challenges (`srp:challenge:<challengeId>`) featuring 5-minute native key TTL expiration (`EX 300`) and atomic `GETDEL` single-pass challenge consumption for replay protection and horizontal pod scalability. Issues HS256 JWTs with 24 h expiry. TypeORM-backed Postgres persistence for user records — verified to survive service restarts.
- **sync-api** (`:3002`): Stores and serves only encrypted vault blobs, per-item version numbers for conflict detection, and the wrapped Vault Key envelope needed for cross-device Master Password unlock. All endpoints are protected by `JwtAuthGuard`; the acting user ID is extracted from the verified JWT `sub` claim.
- **security-analysis-service** (`:3003`): URL reputation scanning, SPF/DKIM/DMARC email parsing, macro/signature file scanning, scheduled HIBP breach checks, and redacted-signal AI insight generation via Gemini. All identity-gated endpoints verify the JWT before processing.
- **sharing-service** (`:3004`): Key-directory microservice publishing classical + post-quantum public key bundles and managing per-recipient wrapped (ciphertext) Folder Keys for PQC hybrid folder sharing. All key-directory and share-invite endpoints are protected by `JwtAuthGuard`.

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

### 1. Environment Variables
Copy the root `.env.example` to `.env` and fill in the required values:

```bash
cp .env.example .env
```

Key variables:

| Variable | Description |
|---|---|
| `DATABASE_URL` | Postgres DSN, e.g. `postgres://sentinel_admin:sentinel_password_change_me@localhost:5432/sentinelvault` |
| `JWT_SECRET` | HS256 signing key — **must be at least 32 bytes in production** |
| `REDIS_URL` | Redis DSN, e.g. `redis://localhost:6379` |
| `GEMINI_API_KEY` | (Optional) Google Gemini API key for AI Insights; falls back to static placeholders if unset |

### 2. Database and Cache Dependencies
```bash
docker compose up -d
```

This starts:
- **Postgres 16** on port `5432` (database: `sentinelvault`, user: `sentinel_admin`)
- **Redis 7** on port `6379`

### 3. Build the Native Crypto Core
The native crate must be built before running `core/` tests or the Flutter app:
```bash
cd native/crypto_core
cargo build --release
cargo test               # mandatory before any change to crypto code

# Web/browser-extension target:
rustup target add wasm32-unknown-unknown
cargo build --target wasm32-unknown-unknown --features wasm
```

### 4. Backend Services
Each service reads `DATABASE_URL`, `JWT_SECRET`, and `REDIS_URL` from environment variables (or the root `.env` file).

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

### 5. Running the Flutter App

#### Local Development
```bash
cd app
flutter pub get
flutter run -d chrome --web-port=8080
```
> Defaults point to local microservice endpoints (`AUTH_BASE_URL=http://localhost:3001`, `SYNC_BASE_URL=http://localhost:3002`, `SECURITY_BASE_URL=http://localhost:3003`, `SHARING_BASE_URL=http://localhost:3004`). Backend CORS dynamically supports any local dev port (e.g. 8080 or dynamic ports).

#### Production & Custom Base URLs (`--dart-define`)
Backend microservice URLs are configured at build/run time using Dart's compile-time environment variables (`ApiConfig`):

```bash
flutter build web --release \
  --dart-define=AUTH_BASE_URL=https://api-auth.vault.example.com \
  --dart-define=SYNC_BASE_URL=https://api-sync.vault.example.com \
  --dart-define=SECURITY_BASE_URL=https://api-security.vault.example.com \
  --dart-define=SHARING_BASE_URL=https://api-sharing.vault.example.com
```

| Environment Variable | Default Value | Description |
|---|---|---|
| `AUTH_BASE_URL` | `http://localhost:3001` | Base URL for `auth-service` (SRP-6a, login/register, session JWTs) |
| `SYNC_BASE_URL` | `http://localhost:3002` | Base URL for `sync-api` (encrypted vault blobs & key envelopes) |
| `SECURITY_BASE_URL` | `http://localhost:3003` | Base URL for `security-analysis-service` (reputation, breach monitor, AI insights) |
| `SHARING_BASE_URL` | `http://localhost:3004` | Base URL for `sharing-service` (PQC key directory & folder share invites) |

---

## 🧪 Testing

### Core Package
```bash
cd core
dart test
```
> Requires the native crypto core to be built first (see step 3) — `dart:ffi`/`dart:js_interop` have nothing to load otherwise.

### Flutter App
```bash
cd app
flutter test     # 97 widget, navigation, multi-select/delete, Export Auth Gate, and Security Dashboard tests
flutter analyze  # must report "No issues found"
```

### Browser Extension
```bash
cd browser-extension
dart test
node test/autofill_test.js
```

### Backend Services
All services require a running Postgres + Redis instance and a `JWT_SECRET`. The CI pipeline provisions these automatically via service containers; for local runs:

```bash
export DATABASE_URL=postgresql://sentinel_admin:sentinel_password_change_me@localhost:5432/sentinelvault
export JWT_SECRET=test-jwt-secret-at-least-32-bytes-long!!
export REDIS_URL=redis://localhost:6379

for svc in auth-service sync-api security-analysis-service sharing-service; do
  DATABASE_URL=$DATABASE_URL REDIS_URL=$REDIS_URL JWT_SECRET=$JWT_SECRET \
    npm test --prefix backend/$svc -- --forceExit
done
```

### CI Pipeline
GitHub Actions (`.github/workflows/ci.yml`) runs on every push/PR to `main` and `develop`. All matrix jobs use `fail-fast: false` so a single-leg failure does not cancel sibling legs.

| Job | What it does |
|---|---|
| **flutter-checks** | `flutter analyze` + `flutter test` on `app/` and `core/`; runs `osv-scanner` for Dart SCA |
| **rust-crypto-test** | Three matrix legs (`aarch64-apple-ios`, `aarch64-linux-android`, `wasm32-unknown-unknown`): `cargo clippy`, `cargo test`, `cargo build --release`, and `cargo audit` |
| **backend-integration** | Full Jest suites for all NestJS microservices in parallel via matrix; Postgres 15 + Redis 7 service containers provisioned automatically |
| **sonarqube-analysis** | SonarQube Cloud static analysis via `sonarsource/sonarqube-scan-action@v6` |
| **codeql-security** | GitHub CodeQL semantic analysis |

Action versions: `actions/checkout@v5`, `actions/setup-java@v5`, `actions/setup-node@v5`, `actions/cache@v5`, `sonarsource/sonarqube-scan-action@v6`.

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
- **Shamir's Secret Sharing Recovery (M-of-N)**: The Emergency Kit recovery key can additionally be split into N shares (threshold M, range 3–10) via the `blahaj` crate — an audited GF(256) Shamir Secret Sharing implementation in the native Rust core that addresses RUSTSEC-2024-0398 (polynomial coefficient bias present in the predecessor `sharks` crate), used for distributed recovery across trusted contacts.
- **FIDO2/WebAuthn Passkey Authentication**: Standard WebAuthn registration/login for the Account Password, supporting platform passkeys (iCloud Keychain/Google Password Manager) and roaming hardware keys (YubiKey via USB/NFC/BLE).
- **Hardware Key Vault-Unlock**: Opt-in additional Vault Key wrapping via the FIDO2 CTAP2 `hmac-secret` extension, with Master Password fallback always available if the key is lost or removed.
- **Duress / Decoy Vault**: Independent Vault Alpha (real) and Vault Beta (decoy) with a visually and timing-indistinguishable unlock flow. Decoy unlock fires a native hook that invalidates the real vault''s biometric cache only — never touching its encrypted data — plus an explicit in-app disclosure of the feature''s actual limitations.
- **PQC Hybrid Folder Sharing (Cross-User Isolation)**: Folder Key sharing via X25519 + ML-KEM-768 envelope wrapping (combined via HKDF-SHA256) and AES-256-GCM, signed with Ed25519 + ML-DSA-65. Mandatory out-of-band key-fingerprint verification defends against server-side public-key substitution; revocation is enforced via Folder Key rotation and re-wrapping. The `fetchWrappedKey` query in `sharing-service` is strictly scoped to the authenticated caller's `userId` and `revokedAt IS NULL` — preventing uninvited third-party users from retrieving wrapped keys shared between other users.
- **Multi-Item Selection & Batch Delete**: Long-press or checklist-mode toggle enables per-item checkboxes in the Vault tab. Delete Selected soft-deletes exactly the chosen items; Delete All is confirmation-guarded and soft-deletes every active vault item. Both paths reuse the existing single-item `softDeleteItem` + `VaultSyncManager.sync()` flow — items remain recoverable from Trash.
- **Thin Browser Extensions (Chrome, Firefox, Safari)**: Paired-mode architecture — the extension holds no Vault Key material itself, instead communicating with the already-unlocked native/desktop app via a native messaging host. Reuses the same Rust-compiled Wasm crypto core built for Flutter Web rather than a separate compiled bundle. Enforces exact-origin autofill matching and blocks cross-origin iframe fills.
- **Security Center Dashboard**: Password health scoring, credential reuse detection, chronological HIBP breach feed, and a weekly redacted AI-generated digest.
- **Import/Export Suite**: See Local Development Setup and the frontend client section above for supported formats.

---

## 🤝 Step-by-Step Guide for PQC Zero-Knowledge Folder Sharing

SentinelVault uses a hybrid classical (X25519) + post-quantum (ML-KEM-768) zero-knowledge architecture for sharing folders between users.

### How PQC Zero-Knowledge Folder Sharing Works
1. **PQC Public Key Bundle Registration**: Each user generates and publishes their X25519, Ed25519, ML-KEM-768, and ML-DSA-65 public key bundle to `sharing-service` (`POST /key-directory/keys`).
2. **Deterministic Folder Key Derivation**: Every folder (e.g. `work-passwords`, `family-vault`, `nvskjndvs`, or **any custom string input by the user**) is automatically converted into a deterministic 36-character PostgreSQL UUID via `getFolderUuid(folderName)`. There are **zero hardcoded values** — users can input any folder string they choose.
3. **PQC Hybrid Key Wrapping**: The sender unwraps/generates a 32-byte Folder Key, wraps it using the recipient's ML-KEM-768 encapsulation key + X25519 ephemeral key, signs it with ML-DSA-65 + Ed25519, and posts the wrapped key record to `sharing-service` (`POST /key-directory/wrapped-keys`).
4. **Shared Item Encryption**: Items created inside or assigned to a shared folder are encrypted on the client using the **Shared Folder Key** (derived via HMAC-SHA256 from the master vault key and cached in `PqcSharingService.unwrappedFolderKeys`).
5. **Recipient Sync & Unwrapping**: Upon recipient login, `PqcSharingService.syncSharedFoldersWithMe()` fetches `GET /key-directory/my-shares`, unwraps the Folder Key using ML-KEM-768 decapsulation key + X25519 private key, and `sync-api` returns all shared folder items for local decryption.

---

### Step-by-Step Manual Testing Procedure (Fresh Database Setup)

#### Step 1: Truncate Database Tables (Optional Fresh Start)
If you want to perform a clean, empty-state test, run the following SQL commands in DBeaver or psql:
```sql
TRUNCATE TABLE wrapped_key_recipients CASCADE;
TRUNCATE TABLE wrapped_key_versions CASCADE;
TRUNCATE TABLE encrypted_vault_items CASCADE;
```

#### Step 2: Launch Application
- Ensure Docker containers are running (`sentinelvault-db`, `sentinelvault-sharing`, `sentinelvault-sync`, `sentinelvault-auth`).
- Start Flutter web (using `web-server` to avoid debug timeouts):
  ```bash
  cd app
  flutter run -d web-server --web-port=8080
  ```

#### Step 3: Register / Login as Sender (`test-a@sentinelvault.local`)
1. Open `http://localhost:8080` in Chrome.
2. Log in (or register) as **`test-a@sentinelvault.local`** (Password: `TestAccountPassword123!`).
3. Unlock the vault using Master Password **`TestMasterPassword456!`**.
4. The client automatically generates and publishes `test-a@sentinelvault.local`'s PQC public key bundle to `sharing-service`.

#### Step 4: Create a Shared Item & Assign to Folder
1. Click **`+` (Add Item)** button in the vault screen.
2. Enter item details:
   - **Title**: `Personal Shared Credentials`
   - **Username**: `sougata_shared`
   - **Password**: `SecretPqcPass123!`
3. Scroll down to **Organization & Notes**.
4. In **Folder / Shared Section Name or ID**, enter **ANY custom folder name** (e.g. `work-passwords`, `my-shared-folder`, `nvskjndvs`, etc.).
5. Click **Save Item** (`✓`).
   *(The item is encrypted under the shared folder key derived for that folder name).*

#### Step 5: Invite Recipient (`test-b@sentinelvault.local`)
1. Open **Sharing** for that item or folder.
2. Under **Invite user by email**, type **`test-b@sentinelvault.local`** and click **Add Recipient**.
3. Verify and confirm the Safety Number / Key Fingerprint dialog.
   *(The PQC wrapped Folder Key is published to `sharing-service` under the folder's deterministic UUID).*

#### Step 6: Log Out
1. Click **Logout** in the left sidebar to clear memory keys and session token.

#### Step 7: Log In as Recipient (`test-b@sentinelvault.local`)
1. Log in as **`test-b@sentinelvault.local`** (Password: `TestAccountPassword123!`).
2. Unlock the vault using Master Password **`TestMasterPassword456!`**.
3. The app automatically runs `PqcSharingService.syncSharedFoldersWithMe()`, retrieves the wrapped key from `sharing-service`, and unwraps the folder key using ML-KEM-768.
4. `VaultSyncManager.sync()` pulls the encrypted item from `sync-api`.

#### Step 8: Verification
1. Click **All Items** or **Shared With Me** in the sidebar.
2. **`Personal Shared Credentials`** appears in the list pane!
3. Click the item to view decrypted credentials (`sougata_shared` / `SecretPqcPass123!`).

#### Step 9: Test Recipient Revocation (Optional)
1. Log out of `test-b@sentinelvault.local` and log back in as **`test-a@sentinelvault.local`**.
2. Open Sharing for **`nvskjndvs`**.
3. Click the red **`-`** (Revoke) icon next to `test-b@sentinelvault.local` and confirm.
   *(The backend sets `revokedAt = NOW()` for `test-b@sentinelvault.local` and rotates the Folder Key).*
4. In DBeaver, query `SELECT "recipientUserId", "folderId", "revokedAt" FROM wrapped_key_recipients;` to confirm `revokedAt` is populated.
5. Log back in as **`test-b@sentinelvault.local`** — `test-b@sentinelvault.local` can no longer access new items or future updates in that folder.

---

## 🔮 Future Scope

- **Post-Quantum Account Auth Hardening**: SRP-6a and WebAuthn/passkey signatures are asymmetric/discrete-log-based and theoretically vulnerable to a future quantum computer, unlike the vault''s symmetric-only encryption chain. Bounded in severity today (compromise would grant account-level access only, never vault contents) but worth revisiting once post-quantum variants of these protocols mature.
- **Emergency Kit printable artifact refinements**: further hardening of the offline recovery-kit UX.

> Peer-to-peer/local-network syncing was evaluated and intentionally descoped — cloud sync via `sync-api` remains the only sync transport.
