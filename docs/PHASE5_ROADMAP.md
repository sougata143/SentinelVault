# SentinelVault — Phase 5 Roadmap: Evaluation & Architecture
### Hybrid PQC sharing, native memory hardening, M-of-N Shamir recovery, duress vault

Source: `SentinelVault_next_features.docx`. All four ideas are sound and
worth building. The build order below differs from the document's — the
FFI/native memory work is foundational and the other three benefit from
sitting on top of it, so it goes first; the sharing feature is the largest
net-new capability (this app has been single-user until now) and has the
most subtle failure mode (server-side key substitution), so it goes last.

| # | Feature | What it changes | Do when |
|---|---|---|---|
| 2 | Native FFI memory hardening | Replaces the Dart-only crypto internals with a Rust/C core | First — foundational |
| 3 | M-of-N Shamir emergency recovery | Extends the existing Emergency Kit (Phase 24) | Second — isolated, moderate complexity |
| 4 | Duress/decoy vault | New parallel vault + native wipe hook | Third |
| 1 | Hybrid PQC sharing (multi-user) | Brand-new capability: PKI, key directory, hybrid KEM | Fourth — largest, most novel attack surface |

---

## 2. Native FFI memory hardening — do first

The core insight in the document is correct: the Dart VM's garbage
collector can leave stale copies of secret-bearing strings/byte arrays in
managed memory, and Dart alone can't `mlock()` pages or guarantee immediate
zeroization the way a systems language can.

- This effectively adopts the "Rust core + FFI" alternative your original
  `docs/ARCHITECTURE.md` §3 flagged but didn't take — you're moving the
  *sensitive* operations (Argon2id, AES-256-GCM, SRP/OPAQUE math) into a
  Rust (recommended over C — memory safety by default, still gives you
  `mlock`/guard-page control via crates like `secrecy` and `region`, or
  direct libsodium bindings) module bound via Dart FFI.
- **Keep the existing public Dart API surface from `crypto-e2ee-core`
  unchanged.** Everything above it (`vault-unlock-flow`,
  `account-auth-flow`, etc.) calls the same function signatures — only the
  implementation underneath moves from pure Dart to an FFI call into the
  native module. This means this phase is a contained swap, not a rewrite
  of everything built so far.
- Required protections inside the native boundary: `mlock()`/equivalent to
  pin secret pages against swap, guard pages before/after secret
  allocations to catch overflows, and explicit zeroization immediately
  after use (not "whenever the GC gets to it").
- This needs to be done per-platform (the FFI boundary differs for iOS,
  Android, and web/Wasm — web can't `mlock()` at all, since browser
  sandboxes don't expose that syscall; document this limitation rather
  than pretending web gets equal protection).

## 3. M-of-N Shamir emergency recovery — extends your existing Emergency Kit

Your current Emergency Kit (Phase 24) is a single printable Recovery Key —
correctly flagged in the document as a single point of loss/compromise.
Splitting that *same* Recovery Key via Shamir's Secret Sharing (SSS) is the
right fix, not a separate mechanism:

- **Use an audited SSS library, never hand-rolled polynomial
  interpolation over GF(2⁸).** This is a classic place for subtle bugs
  (weak randomness for coefficients, timing side channels) — the document
  correctly names the math but the implementation must come from a
  reviewed library (check current Rust/Dart ecosystem options at
  implementation time; several audited implementations exist, including
  ones aligned with the SLIP-0039 approach used by hardware wallets).
- M-of-N (e.g. 3-of-5) means any 1–2 shares leak zero information about the
  key — that's a genuine cryptographic guarantee of SSS, not marketing.
- This sits on top of the existing `emergency-kit-recovery` skill's design
  — the Recovery Key's role in wrapping the Vault Key doesn't change, only
  how that Recovery Key is distributed/reconstructed changes.

## 4. Duress/Decoy Vault — legitimate, but be honest about its limits

This is a real, established pattern (conceptually similar to VeraCrypt's
hidden volumes) and appropriate to build. Two things worth being explicit
about so the feature doesn't overpromise:

- **Perfect plausible deniability is hard to fully guarantee.** A
  sophisticated adversary with forensic access could potentially notice
  two encrypted database files, unusual storage patterns, or app-store
  metadata mentioning a duress feature at all. Document this limitation
  in-app rather than presenting the feature as an absolute guarantee —
  VeraCrypt's own documentation is explicit about equivalent limits for
  hidden volumes, and yours should be too.
- **The "symmetric wipe" must target the biometric cache / Secure Enclave
  hardware-key reference for the real vault only — not delete real vault
  data.** The document's design already does this correctly (zero the
  biometric cache/hardware-key reference, not the vault itself) — this
  is the right scope: it forces a fallback to manual Master Password entry
  for the real vault, which is a reasonable protective step, without
  irreversible data loss if the duress trigger was accidental.
- Must be strictly opt-in, with clear in-app explanation of exactly what
  it does and doesn't protect against.

## 1. Hybrid PQC Sharing — the largest new capability, do last

The cryptographic design in the document is sound and matches how modern
hybrid PQ/classical systems are actually built (this is the same "hybrid
KEM combiner via HKDF" pattern used in things like TLS's hybrid key
exchange proposals): classical (X25519/Ed25519) + post-quantum
(ML-KEM-768/ML-DSA-65) secrets combined via HKDF-SHA256, so the scheme
stays secure even if only one of the two algorithm families holds up.

One important gap to close that the document doesn't mention: **a
malicious or compromised server is now in a position to substitute a
recipient's public keys** (classical or PQ) during the sharing flow,
since User A fetches User B's public keys *from the server*. Without some
out-of-band verification, this is a textbook MITM opportunity — the same
problem Signal solves with "safety numbers." This needs to be part of the
design, not an afterthought:

- Add a **key-fingerprint verification** step (e.g. a short numeric/word
  code derived from both users' public keys) that users can compare
  out-of-band (in person, over a call, via a separate trusted channel)
  before trusting a share — at minimum for first-time sharing between two
  users.
- Consider **key transparency** (a append-only, auditable log of published
  keys) as a stronger, less user-burdensome long-term mitigation, but
  treat that as a further-future enhancement — fingerprint verification is
  the minimum viable protection to ship with the first version.
- Sharing/unsharing needs an explicit key-rotation story: removing a
  recipient's access means rotating the Folder Key and re-wrapping for
  remaining recipients — simply "stopping sending them updates" is not
  revocation.

This is why it's sequenced last: it's a genuinely new trust model (multi-
party, server-mediated key distribution) layered on top of a system that
was single-user by design until now, and it benefits from the Rust FFI
core (PQC libraries are more mature in Rust than in pure Dart) already
being in place from Phase 2 above.

---

## Updated architecture stack (for reference)

```
APPLICATION LAYER:      Flutter UI (+ Duress/Decoy vault switching)
RUNTIME PROTECTION:      Dart FFI -> Rust core (mlock, guard pages, zeroization)
DATA AT REST:            Local AES-256-GCM + Hardware Key (CTAP2 hmac-secret)
IDENTITY & AUTH:         OPAQUE (Account Password) + Argon2id (Master Password)
RECOVERY:                M-of-N Shamir-split Emergency Recovery Key
SHARING (new):           Hybrid PQC (ML-KEM-768 + X25519) + fingerprint verification
```
