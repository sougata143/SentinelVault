# SentinelVault — Architecture Document
### Hybrid (offline + cloud) password manager with AI-assisted security analysis

---

## 1. Design Principles

1. **Zero-knowledge by default.** The server (and Anthropic/Google/any AI API) must never see a plaintext master password, plaintext vault item, or anything an attacker could use to reconstruct one. Only ciphertext, hashes-of-hashes, and non-sensitive metadata leave the device.
2. **Offline-first.** The vault is fully usable with no network connection. Cloud sync is an eventually-consistent layer on top of a local encrypted store, not a dependency.
3. **Defense in depth.** Encryption, authentication, and transport security are independent layers — breaking one should not break the others.
4. **Least-privilege AI.** The "AI-generated insights" layer only ever receives derived signals (scores, flags, redacted excerpts) — never raw passwords, full email bodies, or full file contents.
5. **Cross-platform from one core.** Cryptography and business logic are written once, shared across web, iOS, and Android, so encryption behavior can't drift between platforms.

---

## 2. High-Level System Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              CLIENT LAYER                                │
│                                                                           │
│   ┌──────────┐        ┌──────────┐        ┌──────────┐                  │
│   │   Web     │        │   iOS    │        │ Android  │                  │
│   │ (Flutter  │        │ (Flutter │        │ (Flutter │                  │
│   │  Web)     │        │  build)  │        │  build)  │                  │
│   └────┬─────┘        └────┬─────┘        └────┬─────┘                  │
│        └───────────────────┼───────────────────┘                        │
│                     ┌───────────────┐                                    │
│                     │  Shared Core   │  (Dart package OR Rust+FFI/WASM)  │
│                     │  - Crypto      │                                    │
│                     │  - Vault model │                                    │
│                     │  - Sync engine │                                    │
│                     │  - Local DB    │  (SQLCipher / Isar encrypted)     │
│                     └───────┬───────┘                                    │
└─────────────────────────────┼─────────────────────────────────────────────┘
                               │  TLS 1.3, only ciphertext + metadata
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                              CLOUD LAYER                                  │
│                                                                           │
│  ┌────────────────┐   ┌───────────────────┐   ┌────────────────────┐    │
│  │ Auth Service     │   │  Sync/Vault API   │   │ Security Analysis   │    │
│  │ (OPAQUE/SRP,     │   │  (encrypted blob  │   │ Service              │    │
│  │  passkeys, MFA)  │   │  store + versions)│   │  - URL scan          │    │
│  └────────────────┘   └───────────────────┘   │  - Email scan        │    │
│                                                 │  - File scan         │    │
│  ┌────────────────┐   ┌───────────────────┐   │  - Breach lookup     │    │
│  │ Postgres         │   │ Object Storage     │   └──────────┬──────────┘    │
│  │ (encrypted        │   │ (encrypted file    │              │             │
│  │  vault blobs,     │   │  attachments)      │              ▼             │
│  │  auth verifiers)  │   └───────────────────┘   ┌──────────────────────┐  │
│  └────────────────┘                             │  AI Insight Layer     │  │
│                                                   │  (LLM API call with  │  │
│                                                   │   redacted signals   │  │
│                                                   │   only)              │  │
│                                                   └──────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
        │                             │                          │
        ▼                             ▼                          ▼
 Have I Been Pwned API      Google Safe Browsing /       VirusTotal / file
 (k-anonymity range query)   PhishTank / URL reputation   hash reputation API
```

---

## 3. Cross-Platform Strategy

**Recommendation: Flutter** for web + iOS + Android from a single Dart codebase.

Why over React Native or three native apps:
- One cryptography implementation (via `cryptography` / `pointycastle` packages or a compiled libsodium binding) — no risk of the AES-GCM/Argon2id behavior diverging between an iOS Swift build and an Android Kotlin build.
- Genuinely compiles to native ARM on mobile (not a JS bridge) and to real Wasm/JS for web, so performance for KDF operations is acceptable.
- Single UI codebase cuts the surface area an agentic IDE has to keep consistent across three platforms.

**Alternative (higher security ceiling, more effort): Rust core + platform shells.**
This is closer to what 1Password actually ships: a Rust crate does 100% of the cryptography and data model, compiled to:
- WebAssembly for the web client
- a static library via FFI for iOS (Swift wrapper)
- a static library via JNI for Android (Kotlin wrapper)

This is worth doing if you later want independent security audits of a single crypto core, or plan to add a CLI/desktop app. It's more setup work for the agentic IDE to scaffold correctly, so the guide below defaults to the Flutter path and calls out where you'd swap in Rust instead.

---

## 4. Encryption & Key Architecture (Zero-Knowledge)

### 4.1 Key hierarchy (envelope encryption)

```
Master Password (never leaves device, never stored anywhere)
        │
        ▼  Argon2id (KDF: memory=64MB+, iterations=3+, parallelism=4, unique salt per user)
        │
Master Key (256-bit, kept only in memory / secure enclave while unlocked)
        │
        ├──► Auth: fed into OPAQUE or SRP protocol → server stores only a
        │     password-independent verifier, never a crackable hash
        │
        └──► Vault Key wrapping: Master Key encrypts (AES-256-GCM) a
              randomly generated 256-bit Vault Key
                    │
                    ▼
              Vault Key encrypts every individual vault item (per-item
              nonce, AES-256-GCM, authenticated)
```

Why this shape:
- **Argon2id**, not PBKDF2/bcrypt, for KDF — memory-hard, resists GPU/ASIC cracking.
- **Vault Key indirection** means a master password change only re-wraps one small key, not the entire vault.
- **OPAQUE (preferred) or SRP** for authentication means the server never even transiently sees a value derived directly from the password that could be brute-forced offline if the DB leaks. Plain "hash the password and send it" schemes (even salted) don't give this property.
- **Per-item nonces** with AES-256-GCM (authenticated encryption) — never reuse a nonce with the same key.

### 4.2 Local storage

- Mobile: SQLCipher-backed SQLite (or Isar with its encrypted storage) — vault stored encrypted at rest even before considering cloud sync.
- Vault Key itself, once unwrapped, held only in memory; on mobile, optionally cached behind biometric unlock using **iOS Keychain (Secure Enclave)** / **Android Keystore (StrongBox where available)** — never written to disk unencrypted.
- Auto-lock timers, clear-clipboard-after-N-seconds, and screen-recording/screenshot blocking on sensitive screens (mobile).

### 4.3 Sync protocol

- Client encrypts locally, uploads ciphertext blob + monotonic version number.
- Server does last-write-wins per-item with version check, returns 409 on conflict; client resolves conflicts locally (never server-side, since server can't decrypt).
- All transport over TLS 1.3, with certificate pinning on mobile clients.

### 4.4 What the server is allowed to know

Allowed: user's public identifier, auth verifier, encrypted blobs, blob version numbers, timestamps, item count.
Never allowed: master password, vault key, plaintext item content, plaintext file contents.

---

## 5. Security Analysis Modules

Each module below is designed so the **heavy analysis happens locally or via reputation APIs first**, and the **AI call only ever receives a small, redacted, structured summary** — never the raw secret/email/file.

### 5.1 Password strength analysis
- Local-only, no network call needed.
- Use entropy + pattern-based estimation (the `zxcvbn` algorithm or a Dart/Rust port) rather than naive length/character-class rules — it catches "Password123!" as weak despite satisfying charset rules.
- Output: a 0–4 score, estimated crack time, and *which pattern* triggered a low score (e.g., "keyboard sequence," "common substitution") — this structured output, not the password, is what's optionally sent to the AI layer for a plain-English explanation.

### 5.2 URL phishing detection
- Layer 1 (local, instant): heuristics — punycode/homoglyph domains, suspicious TLDs, IP-literal URLs, excessive subdomains, mismatched display-vs-actual link text, urgency keywords.
- Layer 2 (reputation): query Google Safe Browsing API and/or PhishTank/URLhaus for known-bad status.
- Layer 3 (AI insight): send only `{domain, heuristic flags, reputation verdict}` to the LLM to generate a plain-English "here's why this looks risky" explanation — never send the user's personal browsing context.

### 5.3 Email phishing detection
- Parse headers only (not necessarily full body) for SPF/DKIM/DMARC pass/fail, sender domain vs. reply-to mismatch, display-name spoofing.
- Extract URLs from the body and run them through the URL module above.
- Redact the body (strip anything matching PII/credential patterns) before any snippet is sent to the AI layer for summarization — or better, only send the *extracted signals*, not the body text at all.

### 5.4 Dark-web / breach monitoring
- Use **Have I Been Pwned's** k-anonymity range API for both passwords (SHA-1 prefix, never the plaintext password) and email breach checks — this is the same privacy-preserving pattern HIBP documents publicly, and it's how you avoid ever sending a full password hash or email to a third party unnecessarily.
- Poll periodically (e.g., daily) for saved emails; surface new breaches with an AI-generated summary of what data type was exposed and what the recommended action is (rotate password, enable MFA, etc.).

### 5.5 File security checks
- Compute file hash (SHA-256) locally, check against VirusTotal's hash-reputation endpoint before ever uploading file bytes anywhere.
- Static checks: flag macro-enabled Office documents, double extensions (`invoice.pdf.exe`), mismatched file signature vs. extension.
- Only escalate to full upload-and-scan (VirusTotal file upload) with explicit user consent, since that does leave the device.

### 5.6 AI insights layer
- One thin service that takes structured findings from 5.1–5.5 and calls an LLM (Claude or Gemini via API) with a system prompt constraining it to: explain risk in plain language, suggest concrete next steps, and never request or repeat back the sensitive input.
- Log only the structured findings sent (for debugging), never full prompts/responses containing user data, and set a short retention window.

---

## 6. Backend Stack

| Layer | Choice | Why |
|---|---|---|
| API | Node.js + NestJS (or Go + Fiber) | Strong typing, good crypto libs, easy to scaffold with an agent |
| Auth | OPAQUE (e.g. `opaque-ke` via WASM binding) or SRP-6a | Zero-knowledge auth |
| Primary DB | PostgreSQL | Encrypted blob storage, row-level versioning |
| Object storage | S3-compatible (or GCS) | Encrypted file attachments |
| Cache/queue | Redis | Rate limiting, breach-check job queue |
| Background jobs | BullMQ (Node) or a Go worker | Scheduled dark-web re-checks |
| Hosting | Cloud Run / Fly.io / ECS | Container-based, scales to zero when idle |

---

## 7. Repository Layout

```
sentinelvault/
├── AGENTS.md                     # Antigravity standing instructions (project root)
├── skills/                       # Antigravity skills directory
│   ├── crypto-e2ee-core/SKILL.md
│   ├── password-strength-analysis/SKILL.md
│   ├── phishing-url-detection/SKILL.md
│   ├── phishing-email-detection/SKILL.md
│   ├── dark-web-monitor/SKILL.md
│   ├── file-security-scan/SKILL.md
│   └── ai-insights-generator/SKILL.md
├── core/                         # Shared Dart package: crypto, models, sync engine
├── app/                          # Flutter app (web + iOS + Android targets)
├── backend/
│   ├── auth-service/
│   ├── sync-api/
│   └── security-analysis-service/
├── infra/                        # IaC (Terraform), Docker, CI configs
└── docs/
    └── ARCHITECTURE.md           # this file
```

**Where the `.md` files live:**
- `AGENTS.md` → the **project root** (`sentinelvault/AGENTS.md`). Antigravity reads this automatically for every agent spawned in the workspace.
- Each `SKILL.md` → its **own subfolder** under `skills/` at the project root (e.g., `skills/password-strength-analysis/SKILL.md`). Antigravity only loads the metadata header until a task needs that specific skill, then loads full instructions — keeping context usage low.

---

## 8. Compliance & Hardening Checklist

- Independent penetration test + cryptography review before public launch (this class of product is exactly the kind attackers target first).
- Bug bounty program once stable.
- No analytics SDKs on vault-unlocked screens.
- Rate-limit and lock out auth attempts; support hardware security keys (WebAuthn/FIDO2) and TOTP as MFA.
- Key rotation plan for the Vault Key (re-encrypt vault, don't just rotate the wrapping key, on suspected compromise).
- Full data export (encrypted and, with explicit action, decrypted) so users are never locked in.
