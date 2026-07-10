---
name: crypto-e2ee-core
description: Use when implementing or modifying anything in core/crypto/ — key derivation, vault encryption/decryption, key wrapping, or the zero-knowledge auth handshake. Load this before touching any cryptographic code in this project.
---

# Skill: Crypto / E2EE Core

## Objective
Implement the zero-knowledge key hierarchy exactly as specified — do not
simplify, substitute algorithms, or "temporarily" skip a layer for
convenience.

## Required primitives (do not substitute)
- **KDF**: Argon2id. Parameters: memory ≥ 64 MB, iterations ≥ 3,
  parallelism ≥ 4, unique random salt (16+ bytes) per user, stored alongside
  (not secret) the auth verifier.
- **Symmetric encryption**: AES-256-GCM only. Generate a fresh random 96-bit
  nonce per encryption call. Never reuse a nonce with the same key — if a
  counter-based nonce scheme is used instead of random, it must be proven
  never to repeat across the key's lifetime.
- **Auth handshake**: OPAQUE (preferred) or SRP-6a. The literal password or
  a direct hash of it must never be transmitted or stored server-side.

## Key hierarchy to implement
1. Master Password → Argon2id → Master Key (never persisted, memory-only
   while unlocked).
2. Master Key wraps (AES-256-GCM) a randomly generated Vault Key.
3. Vault Key encrypts each vault item individually (per-item nonce).
4. Master Key is also the input to the OPAQUE/SRP registration and login
   flow — the server ends up with only a verifier it cannot use to derive
   the Master Key or Master Password.

## Rules of engagement
- Any function that touches a key or plaintext vault content must have a
  doc comment stating its security invariant (e.g. "never logs input",
  "caller must zero this buffer after use").
- Write unit tests covering: correct round-trip encrypt/decrypt, nonce
  uniqueness under repeated calls, and that tampering with ciphertext causes
  authentication failure (not silent corruption).
- If the task requires a decision not covered here (e.g. key rotation flow,
  multi-device key sharing), stop and produce a short options doc for human
  review rather than guessing.
- Never write example/test code that prints or logs a real derived key or
  password, even a fake one that looks realistic enough to copy-paste
  elsewhere by accident — use obviously-fake placeholder values.

## Output location
Implementation goes in `core/crypto/`. Tests go alongside in
`core/crypto/test/`. Do not scatter crypto logic into `app/` or backend
services — they should only call the public API exposed by this module.
