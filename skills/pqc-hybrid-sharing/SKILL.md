---
name: pqc-hybrid-sharing
description: Use when implementing multi-user item/folder sharing via a hybrid post-quantum + classical PKI (X25519/Ed25519 + ML-KEM-768/ML-DSA-65). This is the largest new capability in the app (first multi-user feature) and requires a reviewed design doc before implementation, specifically covering defense against server-side public-key substitution.
---

# Skill: Hybrid PQC Sharing

## Objective
Let User A share a vault folder with User B by wrapping a random Folder
Key using a hybrid construction — classical (X25519) key agreement *and*
post-quantum (ML-KEM-768) encapsulation combined via HKDF-SHA256 — so the
scheme remains secure even if only one of the two algorithm families holds
up over time, while defending against a compromised server substituting
public keys.

## Before writing any implementation code
Produce a design doc (`docs/PQC_SHARING_DESIGN.md`) covering:
1. **Key generation and publication**: each user generates a classical
   keypair (X25519 for encryption, Ed25519 for signatures) and a
   post-quantum keypair (ML-KEM-768 for encapsulation, ML-DSA-65 for
   signatures) at account setup, publishing only public keys to a
   server-hosted directory.
2. **The hybrid wrap flow**: User A generates a random Folder Key
   (AES-256-GCM), fetches User B's public keys, encrypts/encapsulates the
   Folder Key via both X25519 and ML-KEM-768, and combines the two
   resulting shared secrets via HKDF-SHA256 into the final wrapping key.
3. **MITM defense (mandatory — do not skip this in the design doc)**: since
   User A fetches User B's public keys *from the server*, a compromised or
   malicious server could substitute keys during that fetch. Specify a
   key-fingerprint verification mechanism (a short numeric/word code
   derived from both users' public key material) that users can compare
   out-of-band before the app treats a share as fully trusted, at least
   for first-time sharing between any two users.
4. **Revocation/unsharing**: removing a recipient's access must rotate the
   Folder Key and re-wrap it for all remaining recipients — simply
   ceasing to send updates to a removed recipient is not revocation, since
   they'd retain the old key.
5. **Signing**: use Ed25519/ML-DSA-65 to sign share invitations/Folder Key
   updates so a recipient can verify they genuinely came from the claimed
   sender, not just from "whoever the server says is User A."

Get this design doc reviewed and approved before implementation.

## Rules of engagement (apply regardless of design-doc specifics)
- Verify current library maturity for ML-KEM-768/ML-DSA-65 (FIPS 203/204)
  at implementation time — these are newer than the classical primitives
  already in use, and ecosystem support varies by platform. Rust
  implementations are generally more mature than pure-Dart ones; if
  `native-ffi-crypto-core` is already in place, this is a strong candidate
  to implement there rather than in Dart directly.
- The server may only ever see: public keys, wrapped (ciphertext) Folder
  Keys per recipient, and sharing metadata (who has access to what,
  timestamps) — never a private key, an unwrapped Folder Key, or shared
  item plaintext.
- Do not treat a successful key fetch from the server as equivalent to a
  verified identity — that conflation is exactly the gap this skill exists
  to close. Surface the fingerprint-verification step in the UI as a
  genuine trust decision the user makes, not a formality to click through.
- Write tests for: correct hybrid wrap/unwrap round-trip, a tampered
  ciphertext or substituted public key causing a detectable failure (not
  silent acceptance), and that revoking a recipient's access via key
  rotation actually prevents that recipient's old wrapped copy from
  decrypting future Folder Key versions.

## Output location
Design doc: `docs/PQC_SHARING_DESIGN.md` (write first). Key directory
service: `backend/sharing-service/`. Client-side hybrid wrap/unwrap logic:
`core/crypto/pqc_sharing.dart` (or native module). Sharing UI:
`app/lib/features/vault/sharing/`.
