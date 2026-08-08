# SentinelVault

SentinelVault is a hybrid, offline-first, zero-knowledge password manager and security analysis suite. It runs across Web, iOS, and Android from a unified Flutter codebase, backed by a shared Dart core package for client-side cryptography and data modeling, a native Rust cryptography core, and specialized NestJS backend microservices.

---

## 🛡️ Security Invariants (Non-Negotiable)

1. **Zero-Knowledge Architecture**: The Master Password and decrypted vault items never leave the user's device. No plaintext vault item, password, card number, or identity data is ever transmitted to the server or any third-party API.
2. **Two-Secret Model**: Authentication and vault decryption are deliberately separate. The **Account Password** authenticates the user's session (via SRP-6a or OIDC SSO) and grants no cryptographic access to vault contents. The **Master Password** — a distinct secret, never transmitted to the server in any form — is the only thing that can derive the key needed to decrypt the vault. A valid session alone never unlocks the vault; the Unlock step is always required separately. Successful authentication yields a cryptographically signed JWT (HS256, 24 h expiry) stored on-device in secure storage; every subsequent request to the backend microservices is authenticated via `Authorization: Bearer <token>` — the server verifies the signature before trusting any identity claim.
3. **Local Cryptography**: All symmetric encryption uses AES-256-GCM. Keys are derived using Argon2id with a unique local salt per user/vault. Cryptographic key material is held only in volatile memory while the vault is unlocked and is explicitly zeroized afterward.
4. **URL Fragment Security Invariant for Share Links**: Ephemeral decryption keys for unauthenticated one-time share links travel **exclusively in the URL fragment** (`#<keyHex>`). Per RFC 3986, URL fragments are processed strictly client-side by the browser and are **never sent over the wire** in HTTP request lines or logged in server access logs.
5. **Privacy-Preserving Breach Monitoring**: Password breach checks use k-anonymity (only the first 5 characters of the SHA-1 password hash are sent to Have I Been Pwned). Email breach checks are opt-in only, with explicit disclosure before any email address is sent to a third party.
6. **Least-Privilege AI Insights**: The AI Insights layer (Gemini) receives only redacted, non-sensitive structural signals (e.g. password strength scores, file extensions, signature-mismatch flags) — never raw passwords, emails, files, or vault content.

---

## 🏗️ System Architecture

```
                          ┌────────────────────────────────────────────────────────┐
                          │                      CLIENT LAYER                      │
                          │                                                        │
                          │ ┌──────────┐  ┌──────────┐  ┌──────────┐ ┌──────────┐ │
                          │ │   Web    │  │   iOS    │  │ Android  │ │ Desktop  │ │
                          │ │ (Flutter)│  │ (Flutter)│  │ (Flutter)│ │ (Windows/│ │
                          │ └────┬─────┘  └────┬─────┘  └────┬─────┘ │ mac/Lnx) │ │
                          │      │             │             │       └────┬─────┘ │
                          │      │    ┌────────┴────────┐    │            │       │
                          │      │    │ iOS AutoFill /  │    │            │       │
                          │      │    │ WidgetKit Ext   │    │            │       │
                          │      │    └────────┬────────┘    │            │       │
                          │      │             │             │            │       │
                          │ ┌────┴─────────────┴─────────────┴────────────┴─────┐ │
                          │ │            Shared Core (Dart Package)             │ │
                          │ └──────────────────────────┬────────────────────────┘ │
                          │ ┌──────────────────────────┴────────────────────────┐ │
                          │ │           Native Crypto Core (Rust / FFI)         │ │
                          │ └───────────────────────────────────────────────────┘ │
                          │                                                       │
                          │ ┌────────────────────────┐   ┌──────────────────────┐ │
                          │ │   Thin Extension       │   │  Developer CLI       │ │
                          │ │ (Chrome/Firefox/Safari)│   │  (svault / PAT API)  │ │
                          │ └───────────┬────────────┘   └──────────┬───────────┘ │
                          └─────────────┼───────────────────────────┼─────────────┘
                                        │ Native Messaging          │
                                        ▼                           ▼ TLS 1.3
                          ┌────────────────────────────────────────────────────────┐
                          │                      CLOUD LAYER                       │
                          │                                                        │
                          │  ┌────────────────┐  ┌────────────────┐               │
                          │  │ Auth Service   │  │ Sync API        │               │
                          │  │ (SRP-6a / OIDC │  │ (Multi-Vault    │               │
                          │  │  SSO / PATs)   │  │  blob sync)     │               │
                          │  └───────┬────────┘  └────────┬────────┘               │
                          │          │                    │                        │
                          │  ┌───────────────────┐ ┌────────────────────────┐      │
                          │  │ Security Analysis  │ │ Sharing Service        │      │
                          │  │ Service (NestJS)   │ │ (PQC Key Directory /   │      │
                          │  └────────────────────┘ │  One-Time Share Links /│      │
                          │            │             │  Emergency Access)     │      │
                          │            ▼             └────────────────────────┘     │
                          │       ┌──────────┐        ┌──────────┐                  │
                          │       │ Postgres │        │  Redis   │                  │
                          │       └──────────┘        └──────────┘                  │
                          └────────────────────────────────────────────────────────┘
```

### 1. Unified Frontend Client (`app/`)
A cross-platform Flutter application providing:
- **Vault Tab & Multi-Vault Switcher**: 3-column layout (sidebar categories, item list with sorting/filtering/search, and a detail pane). Supports **Multi-Vault Switching** (`VaultSwitcher`), allowing users to manage distinct vaults (Personal, Work, Finances) with independent Master Passwords and 256-bit Vault Keys. Supports **multi-item selection** (long-press or checklist-mode toggle) with batch soft-delete of selected items. Features **Home-Screen TOTP Widget Integration** (`isAvailableInWidget`), FIDO2/WebAuthn Passkeys, SSH keys, API tokens, crypto wallet seed phrases, and secure notes with encrypted file attachments (10 MB limit).
- **Security Center Tab**: Posture dashboard tracking password health scores, local reused-password detection, a chronological data-breach feed, a weekly AI-generated digest, quick-scan triggers, and a **Zero-Knowledge Security Audit Log Feed**.
- **Import/Export & Developer Tools**: Local in-memory parsers for 1Password, Bitwarden, LastPass, Dashlane, Keeper, NordPass, RoboForm, Proton Pass, and KeePass `.kdbx`. Integrates **Developer Personal Access Tokens (PATs)** management screen (`PatManagementScreen`) for generating, viewing, and revoking API tokens.
- **Manage Devices & SSO Integration**: Interactive Settings screen (`ManageDevicesScreen`) for device session management, **Duress / Decoy Vault Setup** (`DuressSetupScreen`), and **Team SSO Configuration** (`SsoConfigDialog`).

### 2. Shared Core (`core/`)
A platform-agnostic Dart package managing local SQLite databases (scoped by `vault_id`), the Dart-side crypto interface, data normalization, WebAuthn passkey credentials, TOTP code generation (RFC 6238), **Client-Side One-Time Share Link Helpers** (`SecureShareHelper`), **PKCE SSO Helpers** (`SsoAuthHelper`), **PAT Helper Utilities** (`PatHelper`), and backend API clients (`AiInsightsClient`, `BackendBreachMonitor`, sync client, `SecurityActivityLog`).

### 3. Native Crypto Core (`native/crypto_core/`)
A single Rust crate providing Argon2id, AES-256-GCM, SRP-6a math, WebAuthn FIDO2 P-256 (ES256) keypair generation, RFC 6238 TOTP code generation, Shamir's Secret Sharing (via `blahaj`), and hybrid PQC (X25519 + ML-KEM-768, Ed25519 + ML-DSA-65) primitives. Compiled natively (`.so`/`.dylib`/`.dll`) for iOS/Android/desktop via `dart:ffi`, and to WebAssembly for Web and browser extensions via `dart:js_interop`.

### 4. Backend Microservices (`backend/`)
- **auth-service** (`:3001`): Account authentication via SRP-6a, OIDC Enterprise Single Sign-On (`SsoService`), Personal Access Tokens (`PatService`), MFA, rate limiting, and **Active Session Management**. Issues signed JWTs containing unique `jti` session claims, enforces instant Redis-backed token revocation, and handles PAT SHA-256 token hashing and scope verification.
- **sync-api** (`:3002`): Stores and serves encrypted vault blobs, per-vault scoping (`UserVault` / `vaultId`), per-item version numbers for conflict detection, and wrapped Vault Key envelopes. Protected by `JwtAuthGuard` and PAT scopes.
- **security-analysis-service** (`:3003`): URL reputation scanning, SPF/DKIM/DMARC email parsing, macro/signature file scanning, scheduled HIBP breach checks, and redacted-signal AI insight generation via Gemini.
- **sharing-service** (`:3004`): Key-directory microservice publishing classical + PQC public key bundles, **Time-Limited One-Time-View Share Links** (`ShareLinkService`), and Emergency Access management.

---

## 📂 Project Directory Structure

```
.
├── .github/                       # GitHub Actions CI/CD workflows & security policies
│   └── workflows/                 # ci.yml, checkmarx-one.yml
├── app/                           # Cross-platform Flutter client application
│   ├── android/                   # Android native app, CredentialProviderService & SentinelVaultWidgetProvider
│   ├── ios/                       # iOS native app, ASCredentialProviderViewController & SentinelVaultWidget
│   ├── lib/
│   │   ├── features/              # Feature UI screens (vault, security_center, passkey, auth, sharing, duress)
│   │   └── theme/                 # Global theme configuration
│   └── test/                      # Widget, UI, and native service interop tests
├── core/                          # Shared cryptography & data package (Dart)
│   ├── lib/
│   │   └── src/                   # Crypto interface, DB, models, security, import/export, sync, auth, sso, pat
│   └── test/                      # Core unit, crypto round-trip, SSO boundary, and PAT tests
├── native/                        # Native Crypto Core (Rust)
│   └── crypto_core/
│       ├── src/algorithms/        # Argon2id, AES-GCM, SRP, Shamir, webauthn.rs, pqc_hybrid.rs
│       └── Cargo.toml
├── cli/                           # SentinelVault Developer CLI (`svault` in Rust)
│   ├── src/                       # Login, unlock, vault list, env injection commands
│   └── Cargo.toml
├── browser-extension/             # Thin Browser Extension (Chrome, Firefox, Safari)
│   ├── src/                       # Content scripts, background worker, native messaging host
│   └── test/                      # WebAuthn interceptor & host integration tests
├── backend/                       # NestJS cloud microservices
│   ├── auth-service/              # Account auth, OIDC SSO, PATs, session management  (:3001)
│   ├── sync-api/                  # Multi-vault encrypted blob sync                    (:3002)
│   ├── security-analysis-service/ # Reputation, breach, and AI insight service          (:3003)
│   └── sharing-service/           # PQC key directory, One-Time Share Links, Emergency (:3004)
├── infra/                         # Cloud Run, Postgres, Redis Terraform templates
└── docs/                          # Architecture, schemas, OpenAPI 3.0 spec, and security definitions
```

---

## 🚀 Key Features & Architectural Capabilities

### 🔒 Core Security & Zero-Knowledge Architecture
- **Zero-Knowledge Cryptography**: Local AES-256-GCM encryption for all vault items, Argon2id key derivation with a unique local salt per vault, and a native Rust crypto core shared across native and Wasm builds.
- **Two-Secret Auth Model**: Account Password (session/identity, SRP-6a / OIDC SSO) and Master Password (vault unlock) are fully independent — compromising one never grants access via the other.
- **Multi-Vault Support**: Allows a single account to hold multiple independent vaults (Personal, Work, Finances) with separate Master Passwords and independent 256-bit Vault Keys. Zero shared cryptographic material across vaults. Integrated `VaultSwitcher` UI component in mobile/web navigation shells.
- **Home-Screen TOTP Widget Access**: Native Android App Widgets (`SentinelVaultWidgetProvider`) and iOS WidgetKit Extensions (`SentinelVaultWidget.swift`) for one-tap live TOTP verification codes. Strictly gated by per-item opt-in (`isAvailableInWidget: true`) and automatically purged on vault lock or logout.

### 🌐 Sharing & External Integrations
- **Time-Limited, One-Time-View Secure Share Links**: Allows vault owners to share individual credentials with unauthenticated recipients who don't have a SentinelVault account. The 32-byte ephemeral AES-256 decryption key travels **exclusively in the URL fragment** (`#<keyHex>`) per RFC 3986 — never sent to or logged by the server. Supports configurable expiry (1h to 7d) and automatic one-time-view destruction (`HTTP 410 Gone`).
- **SAML / OIDC Single Sign-On (SSO) for Team Vaults**: Enterprise OpenID Connect (OIDC) Authorization Code flow with PKCE ($S256$). SSO authenticates account identity, while vault decryption **strictly requires entering the Master Password on-device**. Dynamic email domain auto-detection (`GET /auth/sso/config/:domain`), `SsoLoginButton`, and `SsoConfigDialog` for team admins.
- **Public API & Scoped Personal Access Tokens (PATs)**: Personal Access Tokens (`pat_sv_live_<32_hex_chars>`) for CLI, CI/CD, and developer integrations. Plaintext token is displayed ONCE upon creation; the server stores only `SHA-256(raw_token)` hashes. Supports granular scopes (`vault:read`, `vault:write`, `sharing:read`), OpenAPI 3.0 spec (`docs/openapi.yaml`), audit logging (`pat_created`, `pat_used`, `pat_revoked`), and instant revocation via Settings.

### 🛡️ Advanced Protection & Recovery
- **Duress / Decoy Vault**: Entering an alternate Duress Password unlocks a separate, non-real Decoy Vault (Vault Beta) pre-populated with plausible fake items. Decoy unlock fires a native hook (`triggerDuressWipeHook`) that purges Vault Alpha's biometric quick-unlock key from platform Keychain/Keystore — never touching real encrypted storage (AGENTS.md Rule 14 compliant).
- **PQC Hybrid Folder Sharing**: Cross-user folder key sharing via X25519 + ML-KEM-768 envelope wrapping signed with Ed25519 + ML-DSA-65. Mandatory out-of-band key-fingerprint verification defends against server-side public-key substitution.
- **Emergency Kit & Shamir's Secret Sharing (SSS)**: Offline-first recovery via dual key-wrapping and M-of-N secret splitting using the audited `blahaj` Rust crate (resolving RUSTSEC-2024-0398).

---

## 🧪 Testing & Quality Assurance

```bash
# Core package unit & crypto tests (including SSO, PAT, Multi-Vault, and Secure Share Links)
cd core
cargo build --manifest-path ../native/crypto_core/Cargo.toml --release
dart test

# Flutter app widget & UI tests
cd app
flutter test
flutter analyze

# Backend NestJS microservice tests
for svc in auth-service sync-api security-analysis-service sharing-service; do
  npm test --prefix backend/$svc -- --forceExit
done
```
