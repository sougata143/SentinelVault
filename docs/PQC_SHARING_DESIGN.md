# Hybrid PQC Folder Sharing Design

This document details the architecture and cryptographic specifications for secure multi-user sharing in SentinelVault. It combines classical cryptography with post-quantum cryptography (PQC) in a hybrid scheme to defend against harvest-now-decrypt-later attacks and malicious server-side key substitutions.

---

## 1. Cryptographic Primitives

To ensure security even if one algorithmic family is broken (classical or quantum), SentinelVault uses a dual-wrapping hybrid architecture combining:

| Scheme Class | Algorithm | Standard / Spec | Purpose |
| :--- | :--- | :--- | :--- |
| **Classical Encryption** | X25519 | RFC 7748 | Classical ECDH shared secret generation |
| **Post-Quantum Encryption** | ML-KEM-768 | FIPS 203 | Post-Quantum key encapsulation (128-bit quantum security) |
| **Classical Signatures** | Ed25519 | RFC 8032 | Classical authenticity and signing |
| **Post-Quantum Signatures** | ML-DSA-65 | FIPS 204 | Post-Quantum authenticity and signing |
| **Key Derivation** | HKDF-SHA256 | RFC 5869 | Hybrid shared secret combination |
| **Symmetric Encryption** | AES-256-GCM | NIST SP 800-38D | Folder Key wrapping & item payload encryption |

---

## 2. Key Generation and Publication

Every user generates four distinct keypairs at account creation or sharing activation.

### Key Composition
$$\text{User Keys} = \{ (\text{pub}_{\text{X25519}}, \text{priv}_{\text{X25519}}), (\text{pub}_{\text{Ed25519}}, \text{priv}_{\text{Ed25519}}), (\text{pub}_{\text{ML-KEM}}, \text{priv}_{\text{ML-KEM}}), (\text{pub}_{\text{ML-DSA}}, \text{priv}_{\text{ML-DSA}}) \}$$

### Setup Flow
1. **Client-Side Generation**: All keypairs are generated inside the native Rust crypto core.
2. **Private Key Storage**: The private keys are concatenated and wrapped using the user's Master Key (Argon2id derived) and cached locally via the biometric hardware key in `SecureStorage`. They never leave the device.
3. **Public Key Publication**: The public keys are exported as raw byte arrays, serialized into a JSON bundle, and published to the server-hosted directory service (`auth-service`/`sharing-service`):
   ```json
   {
     "userId": "user-uuid-1234",
     "publicKeyBundle": {
       "x25519": "base64...",
       "ed25519": "base64...",
       "mlKem768": "base64...",
       "mlDsa65": "base64..."
     }
   }
   ```

---

## 3. The Hybrid Wrap Flow

When User A wants to share a folder with User B:

```
                  ┌──────────────────────┐
                  │  Generate FolderKey  │
                  └──────────┬───────────┘
                             │
              ┌──────────────┴──────────────┐
              ▼                             ▼
       [Classical ECDH]              [Post-Quantum KEM]
    X25519 Ephemeral key          ML-KEM-768 Encapsulate
    against User B's pubkey       against User B's pubkey
              │                             │
              ▼                             ▼
       Shared Secret (SS_c)          Shared Secret (SS_pq)
       Size: 32 bytes                Size: 32 bytes
              │                             │
              └──────────────┬──────────────┘
                             ▼
                    ┌─────────────────┐
                    │   HKDF-SHA256   │ <-- Combine SS_c and SS_pq
                    └────────┬────────┘
                             ▼
                    Derived Wrapping Key (K_wrap)
                             │
                             ▼
                    ┌─────────────────┐
                    │   AES-256-GCM   │ <-- Encrypt FolderKey
                    └────────┬────────┘
                             ▼
                    [Wrapped Folder Key Envelope]
```

### Protocol Steps
1. **Generate Folder Key**: User A generates a cryptographically secure random 256-bit key: $K_{\text{folder}} \leftarrow \text{Random}(32)$.
2. **Classical Agreement**: User A generates an ephemeral X25519 keypair and performs Diffie-Hellman against User B's $\text{pub}_{\text{X25519}}$ to obtain the classical shared secret $SS_c$.
3. **Post-Quantum Encapsulation**: User A runs `ml_kem_768::encapsulate` against User B's $\text{pub}_{\text{ML-KEM}}$ to obtain ciphertext $C_{\text{pq}}$ and the post-quantum shared secret $SS_{pq}$.
4. **Hybrid Key Derivation**: The two shared secrets and ephemeral inputs are combined via HKDF-Extract and HKDF-Expand:
   $$\text{PRK} = \text{HKDF-Extract}(\text{salt} = 0, \text{IKM} = SS_c \mathbin{\Vert} SS_{pq})$$
   $$K_{\text{wrap}} = \text{HKDF-Expand}(\text{PRK}, \text{info} = \text{"SentinelVault Hybrid PQC Sharing v1"}, \text{L} = 32)$$
5. **Encrypt Folder Key**: User A encrypts $K_{\text{folder}}$ using $K_{\text{wrap}}$ via AES-256-GCM with a unique 12-byte nonce, producing ciphertext $C_{\text{folder}}$ and a 16-byte authentication tag $T$.
6. **Encapsulated Invitation Packet**: User A sends the following wrapped key material to the server for User B:
   ```json
   {
     "senderUserId": "user-a-uuid",
     "recipientUserId": "user-b-uuid",
     "folderId": "folder-uuid",
     "x25519EphemeralPub": "base64...",
     "mlKemCiphertext": "base64...",
     "wrappedFolderKey": "base64...", // C_folder + T
     "nonce": "base64..."
   }
   ```

---

## 4. Key-Fingerprint Verification (MITM Defense)

Since the public keys of User B are retrieved from the server, a compromised server could substitute User B's public keys with keys controlled by the adversary.

### Verification Design
To detect key substitution, clients calculate a deterministic, order-independent **Key Fingerprint** of the active sharing session:
1. **Fingerprint Computation**:
   $$\text{HashInput} = \text{Sorted}(\text{UserId}_A, \text{UserId}_B) \mathbin{\Vert} \text{pub}_{\text{X25519}}^A \mathbin{\Vert} \text{pub}_{\text{X25519}}^B \mathbin{\Vert} \text{pub}_{\text{ML-KEM}}^A \mathbin{\Vert} \text{pub}_{\text{ML-KEM}}^B$$
   $$\text{FingerprintBytes} = \text{SHA256}(\text{HashInput})$$
2. **Visual Presentation**: Convert the first 8 bytes of the fingerprint into a visual verification representation:
   * **Visual Pattern**: A Base32 string formatted as two blocks: `XXXX-XXXX`.
   * **BIP39 Words**: Alternatively, mapped to 4 distinct words from the BIP39 wordlist.
3. **Trust Flow**: 
   * When establishing a shared folder for the first time, both users see a "Verify Sharing Fingerprint" prompt in the app.
   * Users verify this fingerprint out-of-band (e.g., via signal call, physically showing QR code).
   * Once verified, User A clicks "Trust Recipient" which stores the peer's public key fingerprint locally in a trusted peer directory database. Subsequent invites bypass manual verification unless public keys change.

---

## 5. Folder Key Rotation (Revocation and Unsharing)

If User A revokes User B's access to the shared folder, simply omitting User B from future communications is insufficient since User B still retains the old folder key.

### Rotation Protocol
1. **Generate New Folder Key**: User A generates a new random key: $K_{\text{folder}}^{\text{new}} \leftarrow \text{Random}(32)$.
2. **Re-encrypt Payload**: The client retrieves all items belonging to the folder, decrypts them using $K_{\text{folder}}^{\text{old}}$, re-encrypts them using $K_{\text{folder}}^{\text{new}}$, and updates the database records.
3. **Re-wrap for Active Users**: User A wraps $K_{\text{folder}}^{\text{new}}$ using the hybrid wrap flow for all remaining active recipients (including User A's other devices).
4. **Publish and Delete**: The newly wrapped keys are sent to the sharing-service, and the old invitations/envelopes (wrapped with the old key) are deleted from the server. User B's client can no longer retrieve or decrypt the folder key.

---

## 6. Invitation & Update Signing (Authenticity)

Every sharing packet or folder key rotation payload published by a user must be signed using both classical and post-quantum keys:

1. **Signing**: User A concatenates the sharing envelope parameters and signs them:
   $$\text{ClassicalSig} = \text{Ed25519-Sign}(\text{priv}_{\text{Ed25519}}^A, \text{Payload})$$
   $$\text{PQSig} = \text{ML-DSA-65-Sign}(\text{priv}_{\text{ML-DSA}}^A, \text{Payload})$$
2. **Verification**: When User B downloads a shared folder invitation, they fetch User A's public keys. Before decrypting, the client verifies both classical and post-quantum signatures:
   $$\text{Valid} = \text{Ed25519-Verify}(\text{pub}_{\text{Ed25519}}^A, \text{ClassicalSig}) \land \text{ML-DSA-65-Verify}(\text{pub}_{\text{ML-DSA}}^A, \text{PQSig})$$
   If verification fails, the invitation is discarded with a high-priority warning to the user.

---

## 7. Crate Architecture and Module Integration

To comply with workspace security boundaries and cross-platform consistency, all mathematical and cryptographic components of the hybrid PQC sharing feature will be implemented in the existing Rust native crypto core:

### Crate Path
`native/crypto_core/src/algorithms/pqc_hybrid.rs`

### Rust Module Structure
```rust
pub mod pqc_hybrid {
    // Uses the standard `ml-kem` crate (FIPS 203)
    // Uses the standard `ml-dsa` crate (FIPS 204)
    // Uses `x25519-dalek` and `ed25519-dalek`
    
    pub fn pqc_generate_keypairs() -> PqcKeyPairBundle { ... }
    
    pub fn pqc_hybrid_encapsulate(
        recipient_x25519_pub: &[u8],
        recipient_mlkem_pub: &[u8],
        plaintext_key: &[u8],
    ) -> Result<HybridEnvelope, CryptoError> { ... }
    
    pub fn pqc_hybrid_decapsulate(
        recipient_x25519_priv: &[u8],
        recipient_mlkem_priv: &[u8],
        ephemeral_x25519_pub: &[u8],
        mlkem_ciphertext: &[u8],
        wrapped_key: &[u8],
    ) -> Result<Vec<u8>, CryptoError> { ... }
}
```

### FFI Exports in `native/crypto_core/src/lib.rs`
The FFI layer will expose length-prefixed flat buffers to Dart:
* `pqc_generate_keypairs_ffi`
* `pqc_hybrid_encapsulate_ffi`
* `pqc_hybrid_decapsulate_ffi`
* `pqc_sign_payload_ffi`
* `pqc_verify_payload_ffi`
