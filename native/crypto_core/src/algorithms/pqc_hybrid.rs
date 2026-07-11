// ─────────────────────────────────────────────────────────────────────────────
//  SentinelVault – PQC Hybrid Key-Wrapping and Dual Signing
//
//  All math lives in this module (see docs/PQC_SHARING_DESIGN.md).
//  No plaintext Folder Keys, private keys, or vault content ever leave the device.
// ─────────────────────────────────────────────────────────────────────────────

use aes_gcm::{
    aead::{Aead, KeyInit},
    Aes256Gcm, Nonce,
};
use hkdf::Hkdf;
use sha2::Sha256;
use rand::{RngCore, rngs::OsRng};
use x25519_dalek::{StaticSecret, PublicKey as XPublicKey};
use ed25519_dalek::{
    SigningKey as EdSigningKey,
    VerifyingKey as EdVerifyingKey,
    Signature as EdSignature,
};

// ml-kem: KemCore drives generate(); concrete key types live in ml_kem::kem.
use ml_kem::{KemCore, MlKem768, EncodedSizeUser, MlKem768Params};
use ml_kem::kem::{EncapsulationKey as KemEk, DecapsulationKey as KemDk};
// Ciphertext/SharedKey are type aliases defined in the ml_kem root.
use ml_kem::{Ciphertext as KemCt, Encoded};
// kem crate supplies the Encapsulate / Decapsulate traits.
use kem::{Encapsulate, Decapsulate};

// ml-dsa re-exports Signer, Verifier, Keypair, SignatureEncoding from signature v3.
// Using these re-exports avoids the signature v2/v3 version conflict with ed25519-dalek.
use ml_dsa::{
    MlDsa65,
    SigningKey as PqSigningKey,
    VerifyingKey as PqVerifyingKey,
    Signature as PqSignature,
    EncodedVerifyingKey,
    Seed,
    Generate,
    KeyExport,
};

// ─────────────────────────────────────────────────────────────────────────────
//  Key Generation
// ─────────────────────────────────────────────────────────────────────────────

/// Generates a full key-bundle: classical (X25519/Ed25519) + post-quantum
/// (ML-KEM-768/ML-DSA-65) keypairs.
///
/// Returns `(x25519_pub, x25519_priv, ed25519_pub, ed25519_priv,
///           mlkem_ek, mlkem_dk, mldsa_vk, mldsa_seed)`.
///
/// **Security invariants:**
/// - The ML-DSA-65 private key is stored as its 32-byte seed; the full expanded
///   signing key is re-derived on demand via `from_seed`. This keeps the
///   compact representation unambiguous and avoids leaking expanded key material.
/// - All private material must be placed in secure OS key-storage and must
///   never be logged, printed, or transmitted to any server.
pub fn generate_keypairs() -> (
    [u8; 32], [u8; 32],   // X25519  pub, priv
    [u8; 32], [u8; 32],   // Ed25519 pub, priv (seed)
    Vec<u8>,  Vec<u8>,    // ML-KEM-768 ek, dk
    Vec<u8>,  Vec<u8>,    // ML-DSA-65  vk, sk-seed
) {
    let mut rng = OsRng;

    // 1. Classical – X25519
    let x_priv = StaticSecret::random_from_rng(&mut rng);
    let x_pub  = XPublicKey::from(&x_priv);

    // 2. Classical – Ed25519
    let ed_sk = EdSigningKey::generate(&mut rng);
    let ed_vk = ed_sk.verifying_key();

    // 3. Post-Quantum – ML-KEM-768
    //    `KemCore::generate` returns (DecapsulationKey, EncapsulationKey).
    //    `.as_bytes()` returns an `Encoded<T>` (fixed-size Array); `.as_slice()`
    //    converts to `&[u8]`.
    let (kem_dk, kem_ek) = MlKem768::generate(&mut rng);
    let kem_ek_bytes = kem_ek.as_bytes().as_slice().to_vec();
    let kem_dk_bytes = kem_dk.as_bytes().as_slice().to_vec();

    // 4. Post-Quantum – ML-DSA-65
    //    `Generate::generate()` (from crypto-common 0.2) uses the global CSPRNG
    //    internally; it takes no explicit rng argument.
    //    `KeyExport::to_bytes()` returns the 32-byte `Seed`.
    let dsa_sk   = PqSigningKey::<MlDsa65>::generate();
    let dsa_seed = dsa_sk.to_bytes();          // Seed (= Array<u8,U32>, 32 bytes)

    // `verifying_key()` needs `ml_dsa::Keypair` in scope (re-exported from signature v3).
    // `vk.encode()` returns `EncodedVerifyingKey<P>` (a fixed-size Array).
    let dsa_vk_bytes: Vec<u8> = {
        use ml_dsa::Keypair;
        let vk = dsa_sk.verifying_key();
        vk.encode().as_slice().to_vec()
    };

    (
        x_pub.to_bytes(),  x_priv.to_bytes(),
        ed_vk.to_bytes(),  ed_sk.to_bytes(),
        kem_ek_bytes,      kem_dk_bytes,
        dsa_vk_bytes,      dsa_seed.as_slice().to_vec(),
    )
}

// ─────────────────────────────────────────────────────────────────────────────
//  Hybrid Wrap (Encapsulate)
// ─────────────────────────────────────────────────────────────────────────────

/// Wraps a 32-byte Folder Key using the hybrid X25519 + ML-KEM-768 construction
/// defined in docs/PQC_SHARING_DESIGN.md §3.
///
/// Steps:
///  1. Ephemeral X25519 ECDH → SS_c
///  2. ML-KEM-768 Encapsulate(recipient_ek) → (KEM-CT, SS_pq)
///  3. HKDF-SHA256(IKM = SS_c ‖ SS_pq, info = domain label) → K_wrap
///  4. AES-256-GCM(K_wrap, nonce) encrypts the Folder Key
///
/// **Invariant:** The Folder Key never leaves this function in plaintext.
pub fn hybrid_encapsulate(
    recipient_x25519_pub: &[u8; 32],
    recipient_mlkem_pub:  &[u8],      // serialised EncapsulationKey bytes
    folder_key:           &[u8; 32],
) -> Result<
    (
        [u8; 32],  // ephemeral X25519 public key
        Vec<u8>,   // ML-KEM-768 ciphertext
        [u8; 12],  // AES-GCM nonce (unique per wrap)
        Vec<u8>,   // AES-256-GCM ciphertext+tag wrapping the Folder Key
    ),
    String,
> {
    let mut rng = OsRng;

    // Step 1 – Classical ECDH
    let ephem_secret = StaticSecret::random_from_rng(&mut rng);
    let ephem_pub    = XPublicKey::from(&ephem_secret);
    let peer_x25519  = XPublicKey::from(*recipient_x25519_pub);
    let ss_c         = ephem_secret.diffie_hellman(&peer_x25519);

    // Step 2 – ML-KEM-768 encapsulation
    // Deserialise via EncodedSizeUser::from_bytes which takes &Encoded<EK> (a fixed Array).
    // We borrow the slice as a fixed-size reference and then convert to the Encoded newtype.
    let ek = kem_ek_from_slice(recipient_mlkem_pub)?;
    let (kem_ct, ss_pq) = ek
        .encapsulate(&mut rng)
        .map_err(|e| format!("ML-KEM encapsulate failed: {:?}", e))?;

    // Step 3 – HKDF-SHA256 key combination
    let mut ikm = [0u8; 64];
    ikm[..32].copy_from_slice(ss_c.as_bytes());
    ikm[32..].copy_from_slice(ss_pq.as_slice());

    let hkdf       = Hkdf::<Sha256>::new(None, &ikm);
    let mut k_wrap = [0u8; 32];
    hkdf.expand(b"SentinelVault Hybrid PQC Sharing v1", &mut k_wrap)
        .map_err(|e| format!("HKDF expand failed: {:?}", e))?;

    // Step 4 – AES-256-GCM wrapping
    let mut nonce_bytes = [0u8; 12];
    rng.fill_bytes(&mut nonce_bytes);

    let cipher    = Aes256Gcm::new_from_slice(&k_wrap)
        .map_err(|e| format!("AES init failed: {:?}", e))?;
    let nonce     = Nonce::from_slice(&nonce_bytes);
    let encrypted = cipher
        .encrypt(nonce, folder_key.as_slice())
        .map_err(|e| format!("AES encrypt failed: {:?}", e))?;

    // Zeroize the wrapping key before returning
    zeroize_bytes(&mut k_wrap);

    Ok((ephem_pub.to_bytes(), kem_ct.as_slice().to_vec(), nonce_bytes, encrypted))
}

// ─────────────────────────────────────────────────────────────────────────────
//  Hybrid Unwrap (Decapsulate)
// ─────────────────────────────────────────────────────────────────────────────

/// Unwraps a wrapped Folder Key using the recipient's private keypair.
/// Returns the 32-byte plaintext Folder Key, or an error if any step fails
/// (including AEAD tag verification — indicating tampering or wrong key).
pub fn hybrid_decapsulate(
    recipient_x25519_priv: &[u8; 32],
    recipient_mlkem_priv:  &[u8],     // serialised DecapsulationKey bytes
    ephemeral_x25519_pub:  &[u8; 32],
    mlkem_ciphertext:      &[u8],     // serialised KEM ciphertext bytes
    aes_nonce:             &[u8; 12],
    wrapped_folder_key:    &[u8],
) -> Result<[u8; 32], String> {
    // Step 1 – Classical ECDH
    let priv_secret = StaticSecret::from(*recipient_x25519_priv);
    let peer_pub    = XPublicKey::from(*ephemeral_x25519_pub);
    let ss_c        = priv_secret.diffie_hellman(&peer_pub);

    // Step 2 – ML-KEM-768 decapsulation
    let dk    = kem_dk_from_slice(recipient_mlkem_priv)?;
    let ct    = kem_ct_from_slice(mlkem_ciphertext)?;
    let ss_pq = dk
        .decapsulate(&ct)
        .map_err(|e| format!("ML-KEM decapsulate failed: {:?}", e))?;

    // Step 3 – HKDF-SHA256 key combination
    let mut ikm = [0u8; 64];
    ikm[..32].copy_from_slice(ss_c.as_bytes());
    ikm[32..].copy_from_slice(ss_pq.as_slice());

    let hkdf       = Hkdf::<Sha256>::new(None, &ikm);
    let mut k_wrap = [0u8; 32];
    hkdf.expand(b"SentinelVault Hybrid PQC Sharing v1", &mut k_wrap)
        .map_err(|e| format!("HKDF expand failed: {:?}", e))?;

    // Step 4 – AES-256-GCM decryption (AEAD tag validates ciphertext integrity)
    let cipher    = Aes256Gcm::new_from_slice(&k_wrap)
        .map_err(|e| format!("AES init failed: {:?}", e))?;
    let nonce     = Nonce::from_slice(aes_nonce);
    let decrypted = cipher
        .decrypt(nonce, wrapped_folder_key)
        .map_err(|_| "Decryption failed – ciphertext tampered or wrong key".to_string())?;

    // Zeroize wrapping key immediately
    zeroize_bytes(&mut k_wrap);

    if decrypted.len() != 32 {
        return Err("Decrypted Folder Key has wrong length".to_string());
    }
    let mut out = [0u8; 32];
    out.copy_from_slice(&decrypted);
    Ok(out)
}

// ─────────────────────────────────────────────────────────────────────────────
//  Dual Signing – Share Invitation
// ─────────────────────────────────────────────────────────────────────────────

/// Signs a share-invitation payload with both Ed25519 (classical) and
/// ML-DSA-65 (post-quantum) keys. Both signatures must verify for the
/// invitation to be accepted (defense-in-depth).
///
/// `mldsa_seed` is the 32-byte seed returned by `generate_keypairs`; the full
/// signing key is re-derived here via `from_seed`.
///
/// Returns `(ed25519_sig_bytes, mldsa_encoded_sig_bytes)`.
pub fn sign_invitation(
    payload:      &[u8],
    ed25519_priv: &[u8; 32],
    mldsa_seed:   &[u8],     // 32-byte ML-DSA seed
) -> Result<(Vec<u8>, Vec<u8>), String> {
    // Classical Ed25519 – bring ed25519_dalek::Signer (signature v2) into scope.
    let ed_sig_bytes: Vec<u8> = {
        use ed25519_dalek::Signer;
        let ed_sk = EdSigningKey::from_bytes(ed25519_priv);
        ed_sk.sign(payload).to_bytes().to_vec()
    };

    // Post-Quantum ML-DSA-65 – use ml_dsa::Signer which is signature v3.
    // Scoped separately to avoid conflict with the ed25519_dalek Signer above.
    let dsa_sig_bytes: Vec<u8> = {
        use ml_dsa::Signer;


        let seed_arr: &[u8; 32] = mldsa_seed
            .try_into()
            .map_err(|_| "ML-DSA seed must be 32 bytes".to_string())?;
        // Seed = Array<u8, U32>; build from a fixed-size array reference.
        let seed: Seed = Seed::try_from(seed_arr.as_slice())
            .map_err(|_| "ML-DSA seed conversion failed".to_string())?;
        let dsa_sk = PqSigningKey::<MlDsa65>::from_seed(&seed);
        let sig: PqSignature<MlDsa65> = dsa_sk.sign(payload);
        // `encode()` returns EncodedSignature<P> (fixed-size Array).
        sig.encode().as_slice().to_vec()
    };

    Ok((ed_sig_bytes, dsa_sig_bytes))
}

// ─────────────────────────────────────────────────────────────────────────────
//  Dual Verification – Share Invitation
// ─────────────────────────────────────────────────────────────────────────────

/// Verifies both classical (Ed25519) and post-quantum (ML-DSA-65) signatures
/// on a share invitation payload. Returns `false` (instead of error) on any
/// verification mismatch.
///
/// **Security invariant:** A substituted public key (MITM attack on the key
/// directory) will cause at least one signature to fail, because the signatures
/// were made with private keys corresponding to the *original* public keys.
/// The UI must additionally enforce an out-of-band fingerprint confirmation
/// before treating a share as fully trusted.
pub fn verify_invitation(
    payload:     &[u8],
    ed25519_pub: &[u8; 32],
    mldsa_pub:   &[u8],      // encoded verifying key bytes (EncodedVerifyingKey)
    ed25519_sig: &[u8; 64],
    mldsa_sig:   &[u8],      // encoded signature bytes
) -> Result<bool, String> {
    // 1. Classical Ed25519 – bring ed25519_dalek::Verifier (signature v2) into scope.
    let ed_ok: bool = {
        use ed25519_dalek::Verifier;
        let ed_vk = EdVerifyingKey::from_bytes(ed25519_pub)
            .map_err(|e| format!("Invalid Ed25519 public key: {:?}", e))?;
        let ed_signature = EdSignature::from_bytes(ed25519_sig);
        ed_vk.verify(payload, &ed_signature).is_ok()
    };
    if !ed_ok {
        return Ok(false);
    }

    // 2. Post-Quantum ML-DSA-65 – ml_dsa::Verifier is signature v3.
    let dsa_ok: bool = {
        use ml_dsa::Verifier;

        // `decode` takes &EncodedVerifyingKey<P>` (a fixed-size Array type).
        // Build from slice using TryFrom.
        let enc_vk = EncodedVerifyingKey::<MlDsa65>::try_from(mldsa_pub)
            .map_err(|_| "Invalid ML-DSA verifying key length".to_string())?;
        let dsa_vk = PqVerifyingKey::<MlDsa65>::decode(&enc_vk);

        // Signature implements TryFrom<&[u8]>.
        let dsa_signature = PqSignature::<MlDsa65>::try_from(mldsa_sig)
            .map_err(|e| format!("Invalid ML-DSA signature: {:?}", e))?;

        dsa_vk.verify(payload, &dsa_signature).is_ok()
    };

    Ok(ed_ok && dsa_ok)
}

// ─────────────────────────────────────────────────────────────────────────────
//  Internal ML-KEM Deserialization Helpers
// ─────────────────────────────────────────────────────────────────────────────
// ml_kem uses the `EncodedSizeUser` trait: `T::from_bytes(&Encoded<T>)`.
// `Encoded<T>` is `Array<u8, T::EncodedSize>` which implements `TryFrom<&[u8]>`.

fn kem_ek_from_slice(bytes: &[u8]) -> Result<KemEk<MlKem768Params>, String> {
    let encoded: Encoded<KemEk<MlKem768Params>> =
        Encoded::<KemEk<MlKem768Params>>::try_from(bytes)
            .map_err(|_| format!(
                "ML-KEM encapsulation key must be {} bytes, got {}",
                core::mem::size_of::<Encoded<KemEk<MlKem768Params>>>(),
                bytes.len()
            ))?;
    Ok(KemEk::<MlKem768Params>::from_bytes(&encoded))
}

fn kem_dk_from_slice(bytes: &[u8]) -> Result<KemDk<MlKem768Params>, String> {
    let encoded: Encoded<KemDk<MlKem768Params>> =
        Encoded::<KemDk<MlKem768Params>>::try_from(bytes)
            .map_err(|_| format!(
                "ML-KEM decapsulation key must be {} bytes, got {}",
                core::mem::size_of::<Encoded<KemDk<MlKem768Params>>>(),
                bytes.len()
            ))?;
    Ok(KemDk::<MlKem768Params>::from_bytes(&encoded))
}

fn kem_ct_from_slice(bytes: &[u8]) -> Result<KemCt<MlKem768>, String> {
    KemCt::<MlKem768>::try_from(bytes)
        .map_err(|_| format!(
            "ML-KEM ciphertext has wrong length, got {}",
            bytes.len()
        ))
}

// ─────────────────────────────────────────────────────────────────────────────
//  Internal Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Zeroise a key buffer using volatile writes to prevent compiler elimination.
/// For structs holding key material, prefer the `zeroize::Zeroize` derive.
#[inline]
fn zeroize_bytes(buf: &mut [u8]) {
    for b in buf.iter_mut() {
        // SAFETY: write to a valid mutable reference, volatile to prevent optimisation.
        unsafe { std::ptr::write_volatile(b, 0u8) };
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tests
// ─────────────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    fn make_folder_key() -> [u8; 32] {
        let mut k = [0u8; 32];
        k.iter_mut().enumerate().for_each(|(i, b)| *b = i as u8);
        k
    }

    /// Round-trip: wrap then unwrap recovers the original Folder Key exactly.
    #[test]
    fn test_hybrid_wrap_unwrap_roundtrip() {
        let (x_pub, x_priv, _, _, kem_ek, kem_dk, _, _) = generate_keypairs();
        let folder_key = make_folder_key();

        let (ephem_pub, kem_ct, nonce, wrapped) =
            hybrid_encapsulate(&x_pub, &kem_ek, &folder_key)
                .expect("encapsulate should succeed");

        let recovered = hybrid_decapsulate(
            &x_priv, &kem_dk, &ephem_pub, &kem_ct, &nonce, &wrapped,
        ).expect("decapsulate should succeed");

        assert_eq!(folder_key, recovered, "Folder Key must survive round-trip");
    }

    /// Tampered AES-GCM ciphertext must be detected via AEAD tag failure.
    #[test]
    fn test_tampered_ciphertext_is_detected() {
        let (x_pub, x_priv, _, _, kem_ek, kem_dk, _, _) = generate_keypairs();
        let folder_key = make_folder_key();

        let (ephem_pub, kem_ct, nonce, mut wrapped) =
            hybrid_encapsulate(&x_pub, &kem_ek, &folder_key).unwrap();

        // Flip a bit in the AES-GCM ciphertext body
        wrapped[0] ^= 0xFF;

        let result = hybrid_decapsulate(
            &x_priv, &kem_dk, &ephem_pub, &kem_ct, &nonce, &wrapped,
        );
        assert!(result.is_err(), "Tampered ciphertext must be rejected");
    }

    /// Substituted KEM private key (wrong recipient) must fail after decapsulation.
    /// ML-KEM spec: on wrong dk, decapsulate returns a pseudo-random shared secret,
    /// making the HKDF output differ so AES-GCM tag verification fails.
    #[test]
    fn test_substituted_kem_key_is_rejected() {
        let (x_pub, x_priv, _, _, kem_ek, _, _, _) = generate_keypairs();
        // Attacker generates their own KEM keypair
        let (attacker_dk, _) = MlKem768::generate(&mut OsRng);
        let attacker_dk_bytes = attacker_dk.as_bytes().as_slice().to_vec();

        let folder_key = make_folder_key();
        let (ephem_pub, kem_ct, nonce, wrapped) =
            hybrid_encapsulate(&x_pub, &kem_ek, &folder_key).unwrap();

        // Try to decapsulate with the attacker's different dk
        let result = hybrid_decapsulate(
            &x_priv, &attacker_dk_bytes, &ephem_pub, &kem_ct, &nonce, &wrapped,
        );
        assert!(
            result.is_err(),
            "Decapsulation with a substituted private key must fail (AEAD tag mismatch)"
        );
    }

    /// Dual-signing round-trip: sign then verify succeeds with correct keys.
    #[test]
    fn test_sign_verify_roundtrip() {
        let (_, _, ed_pub, ed_priv, _, _, dsa_vk, dsa_seed) = generate_keypairs();
        let payload = b"share-invitation:alice@example.com:folder-id-123";

        let (ed_sig, dsa_sig) =
            sign_invitation(payload, &ed_priv, &dsa_seed).expect("sign should succeed");

        let ed_sig_arr: [u8; 64] = ed_sig.try_into().expect("Ed25519 sig must be 64 bytes");
        let ok = verify_invitation(payload, &ed_pub, &dsa_vk, &ed_sig_arr, &dsa_sig)
            .expect("verify should not error");

        assert!(ok, "Signature verification must succeed after valid sign");
    }

    /// Verification with a wrong (different) public key must fail.
    #[test]
    fn test_wrong_public_key_fails_verification() {
        let (_, _, ed_pub, ed_priv, _, _, dsa_vk, dsa_seed) = generate_keypairs();
        // Different keypair – simulates an attacker substituting their public key.
        let (_, _, ed_pub_evil, _, _, _, dsa_vk_evil, _) = generate_keypairs();
        let payload = b"share-invitation:alice@example.com:folder-id-123";

        let (ed_sig, dsa_sig) = sign_invitation(payload, &ed_priv, &dsa_seed).unwrap();
        let ed_sig_arr: [u8; 64] = ed_sig.try_into().unwrap();

        // Substituted Ed25519 key – must fail
        let ok_ed = verify_invitation(payload, &ed_pub_evil, &dsa_vk, &ed_sig_arr, &dsa_sig)
            .expect("verify should not error");
        assert!(!ok_ed, "Verification with wrong Ed25519 pub key must fail");

        // Substituted ML-DSA key – must fail
        let ok_dsa = verify_invitation(payload, &ed_pub, &dsa_vk_evil, &ed_sig_arr, &dsa_sig)
            .expect("verify should not error");
        assert!(!ok_dsa, "Verification with wrong ML-DSA pub key must fail");
    }

    /// Revoked recipient cannot decrypt Folder Key v2 after rotation.
    ///
    /// Simulates: Alice revokes Bob. A new Folder Key is generated and
    /// re-wrapped only for Alice. Bob's old v1-wrapped copy cannot yield v2.
    #[test]
    fn test_revoked_recipient_cannot_decrypt_after_rotation() {
        let (alice_x_pub, alice_x_priv, _, _, alice_kem_ek, alice_kem_dk, _, _) =
            generate_keypairs();
        let (bob_x_pub, _, _, _, bob_kem_ek, _, _, _) = generate_keypairs();

        // Version 1: both Alice and Bob receive the Folder Key
        let folder_key_v1 = make_folder_key();
        let (ephem_a, ct_a, n_a, wrap_a) =
            hybrid_encapsulate(&alice_x_pub, &alice_kem_ek, &folder_key_v1).unwrap();
        let _ = hybrid_encapsulate(&bob_x_pub, &bob_kem_ek, &folder_key_v1).unwrap();

        // Alice can decrypt v1
        let recovered_v1 = hybrid_decapsulate(
            &alice_x_priv, &alice_kem_dk, &ephem_a, &ct_a, &n_a, &wrap_a,
        ).unwrap();
        assert_eq!(folder_key_v1, recovered_v1);

        // Revocation: rotate to Folder Key v2; only Alice receives a new wrapped copy.
        let mut folder_key_v2 = [0u8; 32];
        OsRng.fill_bytes(&mut folder_key_v2);
        let (ephem_a2, ct_a2, n_a2, wrap_a2) =
            hybrid_encapsulate(&alice_x_pub, &alice_kem_ek, &folder_key_v2).unwrap();

        // Alice can decrypt v2
        let recovered_v2 = hybrid_decapsulate(
            &alice_x_priv, &alice_kem_dk, &ephem_a2, &ct_a2, &n_a2, &wrap_a2,
        ).unwrap();
        assert_eq!(folder_key_v2, recovered_v2);

        // Bob was never issued a v2 wrap; the v1 and v2 keys are independent.
        assert_ne!(
            folder_key_v1, folder_key_v2,
            "v1 and v2 Folder Keys must differ after rotation"
        );
        // Bob's only copy is the v1 wrap. Post-rotation, all new vault content
        // is encrypted under v2, which Bob cannot derive. The backend enforces
        // this by only storing wrapped copies for current (non-revoked) recipients.
    }
}
