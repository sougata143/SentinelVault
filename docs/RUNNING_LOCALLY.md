# SentinelVault — Local Development Guide

> **Security reminder:** The master password never leaves the device. Never log it, print it, or pass it to any API — even during local testing.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Clone & Initial Setup](#2-clone--initial-setup)
3. [Environment Variables](#3-environment-variables)
4. [Start Infrastructure (PostgreSQL + Redis)](#4-start-infrastructure-postgresql--redis)
5. [Build the Native Crypto Core (Rust)](#5-build-the-native-crypto-core-rust)
6. [Run Backend Services](#6-run-backend-services)
7. [Run the Flutter App](#7-run-the-flutter-app)
8. [Run Tests](#8-run-tests)
9. [VS Code IDE Setup](#9-vs-code-ide-setup)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. Prerequisites

Install the following tools before starting. Versions listed are the minimum tested.

| Tool | Version | Install |
|---|---|---|
| **Node.js** | ≥ 20 LTS | [nodejs.org](https://nodejs.org) or `brew install node` |
| **npm** | ≥ 10 | Comes with Node.js |
| **Rust + Cargo** | ≥ 1.77 | `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \| sh` |
| **Flutter SDK** | ≥ 3.22 (Dart ≥ 3.12) | [flutter.dev](https://flutter.dev/docs/get-started/install) |
| **Docker + Docker Compose** | ≥ 24 | [docker.com](https://www.docker.com/get-started/) |
| **Git** | ≥ 2.40 | `brew install git` |

Verify everything is installed:

```bash
node --version        # v20.x.x
cargo --version       # cargo 1.77.x
flutter --version     # Flutter 3.22.x
docker --version      # Docker 24.x.x
docker compose version
```

---

## 2. Clone & Initial Setup

```bash
git clone git@github.com:sougata143/SentinelVault.git
cd SentinelVault
```

Install Node.js dependencies for each backend service:

```bash
cd backend/auth-service             && npm install && cd ../..
cd backend/sync-api                 && npm install && cd ../..
cd backend/security-analysis-service && npm install && cd ../..
cd backend/sharing-service          && npm install && cd ../..
```

Install Flutter dependencies:

```bash
cd app && flutter pub get && cd ..
```

> **Note:** If any service was previously installed with `sudo npm install`, fix permissions:
> ```bash
> sudo chown -R $(whoami) backend/sharing-service/node_modules
> ```

---

## 3. Environment Variables

```bash
cp .env.example .env
```

Edit `.env` and fill in:

| Variable | Required | Description |
|---|---|---|
| `DATABASE_URL` | ✅ | PostgreSQL connection string |
| `REDIS_URL` | ✅ | Redis connection string |
| `JWT_SECRET` | ✅ | Strong random string (≥ 64 chars) |
| `AUTH_PORT` | ✅ | Auth service port (default `3001`) |
| `SYNC_PORT` | ✅ | Sync API port (default `3002`) |
| `SECURITY_ANALYSIS_PORT` | ✅ | Security analysis port (default `3003`) |
| `GEMINI_API_KEY` | optional | AI Insights summaries |
| `HIBP_API_KEY` | optional | Email breach monitoring |
| `VIRUSTOTAL_API_KEY` | optional | File-hash reputation checks |

> ⚠️ **Never commit `.env` to git.** It is already in `.gitignore`.

---

## 4. Start Infrastructure (PostgreSQL + Redis)

```bash
docker compose up -d
```

Verify both containers are healthy:

```bash
docker compose ps
# sentinelvault-db      running   0.0.0.0:5432->5432/tcp
# sentinelvault-cache   running   0.0.0.0:6379->6379/tcp
```

| Command | Effect |
|---|---|
| `docker compose up -d` | Start in background |
| `docker compose stop` | Stop without deleting data |
| `docker compose down -v` | Stop and **wipe all data volumes** |

---

## 5. Build the Native Crypto Core (Rust)

The `native/crypto_core/` Rust crate provides AES-256-GCM, Argon2id, X25519, Ed25519, ML-KEM-768, and ML-DSA-65. It must be compiled before the Flutter app can run.

```bash
cd native/crypto_core

# Debug build (fast, for development)
cargo build

# Release build (optimised)
cargo build --release

# Run crypto unit tests (MANDATORY before any change to crypto code)
cargo test

cd ../..
```

**Wasm build** (required for the web target):

```bash
rustup target add wasm32-unknown-unknown
cd native/crypto_core
cargo build --target wasm32-unknown-unknown --features wasm
```

---

## 6. Run Backend Services

Open **four separate terminal tabs** — one per service. All run with hot-reload.

### 6.1 Auth Service — port 3001

```bash
cd backend/auth-service
npm run start:dev
```

Handles account registration, OPAQUE-based login, JWT issuance, FIDO2/WebAuthn hardware-key vault unlock.

```bash
curl http://localhost:3001/health   # {"status":"ok"}
```

---

### 6.2 Sync API — port 3002

```bash
cd backend/sync-api
npm run start:dev
```

Handles encrypted vault sync between devices. Only ciphertext blobs are accepted.

```bash
curl http://localhost:3002/health
```

---

### 6.3 Security Analysis Service — port 3003

```bash
cd backend/security-analysis-service
npm run start:dev
```

Provides: password strength scoring, phishing detection, dark-web breach monitoring (HIBP k-anonymity), file-hash reputation (VirusTotal), AI Insights (Gemini).

> The service starts without optional API keys but returns static fallback responses.

```bash
curl http://localhost:3003/health
```

---

### 6.4 Sharing Service (PQC Key Directory) — port 3004

```bash
cd backend/sharing-service
SHARING_PORT=3004 npm run start:dev
```

Provides PQC hybrid (X25519 + ML-KEM-768 + Ed25519 + ML-DSA-65) key-bundle registration and Folder Key wrapping/unwrapping.

```bash
curl http://localhost:3004/health
```

---

## 7. Run the Flutter App

Ensure backend services and Docker infrastructure are running first.

```bash
cd app

# List available devices
flutter devices

# iOS Simulator
flutter run -d "iPhone 16"

# Android Emulator
flutter run -d emulator-5554

# Web (Chrome)
flutter run -d chrome

# macOS Desktop
flutter run -d macos
```

> **First launch:** Successful account login does **not** unlock the vault. The Master Password unlock step is always required separately (see `docs/AUTH_AND_UNLOCK_FLOW.md`).

**Release builds:**

```bash
flutter build apk --release    # Android APK
flutter build ipa --release    # iOS IPA
flutter build web --release    # Web bundle
flutter build macos --release  # macOS app
```

---

## 8. Run Tests

### Rust crypto core

```bash
cd native/crypto_core
cargo test
cargo test -- --nocapture    # verbose
```

### Backend services

```bash
cd backend/auth-service                && npm test && cd ../..
cd backend/sync-api                    && npm test && cd ../..
cd backend/security-analysis-service   && npm test && cd ../..
cd backend/sharing-service             && npm test && cd ../..
```

### Flutter app

```bash
cd app
flutter test                   # unit + widget tests
flutter test integration_test  # integration tests (requires device)
```

### Browser Extension

```bash
cd browser-extension
flutter test
```

---

## 9. VS Code IDE Setup

The `.vscode/settings.json` is gitignored (team members use different editors). Create it manually if needed:

```bash
mkdir -p .vscode
cat > .vscode/settings.json << 'EOF'
{
  "typescript.tsdk": "backend/sharing-service/node_modules/typescript/lib",
  "typescript.enablePromptUseWorkspaceTsdk": true,
  "[typescript]": {
    "editor.defaultFormatter": "vscode.typescript-language-features"
  }
}
EOF
```

After opening the project:

1. Click the blue notification: **"Use Workspace Version (5.x.x)"**
2. Or: `Cmd+Shift+P` → **TypeScript: Select TypeScript Version** → **Use Workspace Version**
3. `Cmd+Shift+P` → **TypeScript: Restart TS Server**

This resolves `class-validator` / `class-transformer` "Cannot find module" errors in the sharing-service.

---

## 10. Troubleshooting

### `Cannot find module 'class-validator'` or `'class-transformer'`

The TS language server walked up past `sharing-service/` to the monorepo root which has no `node_modules/`.

**Fix:**
1. `backend/sharing-service/tsconfig.json` must have `"moduleResolution": "node"` and `"paths"` for both packages (already committed — `git pull`).
2. Select the workspace TypeScript SDK in VS Code (§9).
3. Restart TS Server.

---

### `error TS2304: Cannot find name 'Reflect'`

`reflect-metadata` is missing or not imported first.

**Fix:** Ensure `main.ts` starts with:
```typescript
import 'reflect-metadata';
```
And `tsconfig.json` has `"emitDecoratorMetadata": true` and `"experimentalDecorators": true`.

---

### `cargo` or `rustup` not found

```bash
source "$HOME/.cargo/env"
# Or add to ~/.zshrc:
export PATH="$HOME/.cargo/bin:$PATH"
```

---

### Docker port conflict (5432 or 6379 already in use)

```bash
lsof -i :5432   # find the conflicting process
```

Either stop the conflicting service, or change the host port in `docker-compose.yml`:
```yaml
ports:
  - "5433:5432"   # maps host 5433 → container 5432
```

---

### Flutter: `No supported devices found`

```bash
flutter doctor          # diagnose missing toolchain
open -a Simulator       # open iOS Simulator on macOS
```

For Android, start an emulator from Android Studio's AVD Manager.

---

### `node_modules` owned by root

```bash
sudo chown -R $(whoami) backend/auth-service/node_modules
sudo chown -R $(whoami) backend/sync-api/node_modules
sudo chown -R $(whoami) backend/security-analysis-service/node_modules
sudo chown -R $(whoami) backend/sharing-service/node_modules
```

---

## Architecture Overview

```
SentinelVault/
├── app/                             # Flutter app (iOS, Android, Web, macOS)
├── browser-extension/               # Browser extension (Dart/Flutter)
├── core/                            # Shared Dart package (crypto API, models)
├── native/crypto_core/              # Rust: AES-GCM, Argon2id, PQC
├── backend/
│   ├── auth-service/       :3001    # OPAQUE login, FIDO2, JWT
│   ├── sync-api/           :3002    # Encrypted vault sync
│   ├── security-analysis-service/ :3003  # HIBP, VirusTotal, AI
│   └── sharing-service/    :3004    # PQC hybrid key directory
├── docs/                            # Architecture & design documents
├── infra/                           # Deployment configs
├── docker-compose.yml               # PostgreSQL 15 + Redis 7
└── .env.example                     # Environment variable template
```

For deeper architecture details see [`docs/ARCHITECTURE.md`](./ARCHITECTURE.md).
