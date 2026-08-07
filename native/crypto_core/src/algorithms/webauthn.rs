use p256::ecdsa::{SigningKey, VerifyingKey, Signature, signature::Signer, signature::Verifier};
use p256::SecretKey;
use sha2::{Sha256, Digest};
use rand::rngs::OsRng;
use zeroize::Zeroize;

/// WebAuthn ES256 (P-256 ECDSA + SHA-256) Credential Keypair.
pub struct WebAuthnKeyPair {
    /// PKCS#8 SEC1 PEM or PKCS#8 DER private key bytes.
    pub private_key_pem: String,
    /// Uncompressed P-256 public key (65 bytes: 0x04 || X || Y).
    pub public_key_raw: Vec<u8>,
    /// COSE-formatted public key map bytes (CBOR map: 1=2 [EC2], 3=-7 [ES256], -1=1 [P-256], -2=X, -3=Y).
    pub cose_public_key: Vec<u8>,
}

impl Zeroize for WebAuthnKeyPair {
    fn zeroize(&mut self) {
        self.private_key_pem.zeroize();
    }
}

impl Drop for WebAuthnKeyPair {
    fn drop(&mut self) {
        self.zeroize();
    }
}

/// Generates a new P-256 (ES256) WebAuthn keypair.
pub fn generate_webauthn_keypair() -> WebAuthnKeyPair {
    let secret_key = SecretKey::random(&mut OsRng);
    let signing_key = SigningKey::from(&secret_key);
    let verifying_key = signing_key.verifying_key();

    let private_key_pem = secret_key.to_sec1_pem(p256::pkcs8::LineEnding::LF)
        .unwrap_or_default()
        .to_string();

    let point = verifying_key.to_encoded_point(false);
    let public_key_raw = point.as_bytes().to_vec();

    let x_bytes = point.x().expect("x coordinate");
    let y_bytes = point.y().expect("y coordinate");

    // Construct CBOR COSE Key map manually for ES256 (COSE Alg -7, P-256):
    // Map with 5 entries:
    //   1: 2  (kty: EC2)
    //   3: -7 (alg: ES256)
    //  -1: 1  (crv: P-256)
    //  -2: X  (x coordinate, 32 bytes)
    //  -3: Y  (y coordinate, 32 bytes)
    let mut cose = Vec::with_capacity(80);
    cose.push(0xa5); // CBOR map with 5 pairs

    // 1 => 2
    cose.push(0x01);
    cose.push(0x02);

    // 3 => -7 (CBOR negative int -7 is encoded as 0x26)
    cose.push(0x03);
    cose.push(0x26);

    // -1 => 1 (CBOR negative int -1 is 0x20)
    cose.push(0x20);
    cose.push(0x01);

    // -2 => X (CBOR negative int -2 is 0x21, byte string 32 bytes 0x58 0x20)
    cose.push(0x21);
    cose.push(0x58);
    cose.push(0x20);
    cose.extend_from_slice(x_bytes.as_slice());

    // -3 => Y (CBOR negative int -3 is 0x22, byte string 32 bytes 0x58 0x20)
    cose.push(0x22);
    cose.push(0x58);
    cose.push(0x20);
    cose.extend_from_slice(y_bytes.as_slice());

    WebAuthnKeyPair {
        private_key_pem,
        public_key_raw,
        cose_public_key: cose,
    }
}

/// Formats standard WebAuthn `authenticatorData` buffer (37+ bytes):
/// - rp_id_hash (32 bytes SHA-256 of rpId, e.g. "github.com")
/// - flags (1 byte: 0x01 User Present, 0x05 UP+UV User Verified)
/// - sign_count (4 bytes big-endian integer)
pub fn build_authenticator_data(rp_id: &str, sign_count: u32, user_verified: bool) -> Vec<u8> {
    let mut hasher = Sha256::new();
    hasher.update(rp_id.as_bytes());
    let rp_id_hash = hasher.finalize();

    let mut auth_data = Vec::with_capacity(37);
    auth_data.extend_from_slice(&rp_id_hash);

    let flags: u8 = if user_verified { 0x05 } else { 0x01 }; // UP (bit 0) | UV (bit 2)
    auth_data.push(flags);

    auth_data.extend_from_slice(&sign_count.to_be_bytes());
    auth_data
}

/// Signs a WebAuthn assertion (authenticatorData + clientDataHash) using P-256 (ES256).
///
/// Returns the ASN.1 DER-encoded ECDSA signature bytes (r and s integers).
pub fn sign_webauthn_assertion(
    private_key_pem: &str,
    auth_data: &[u8],
    client_data_hash: &[u8],
) -> Result<Vec<u8>, String> {
    let secret_key = SecretKey::from_sec1_pem(private_key_pem)
        .map_err(|e| format!("Failed to parse private key: {}", e))?;
    let signing_key = SigningKey::from(&secret_key);

    // Signature payload = authenticatorData || clientDataHash
    let mut signed_data = Vec::with_capacity(auth_data.len() + client_data_hash.len());
    signed_data.extend_from_slice(auth_data);
    signed_data.extend_from_slice(client_data_hash);

    let signature: Signature = signing_key.sign(&signed_data);
    Ok(signature.to_der().as_bytes().to_vec())
}

/// Verifies an ES256 assertion signature against a public key.
pub fn verify_webauthn_assertion(
    public_key_raw: &[u8],
    auth_data: &[u8],
    client_data_hash: &[u8],
    signature_der: &[u8],
) -> bool {
    let point = match p256::EncodedPoint::from_bytes(public_key_raw) {
        Ok(p) => p,
        Err(_) => return false,
    };
    let verifying_key = match VerifyingKey::from_encoded_point(&point) {
        Ok(k) => k,
        Err(_) => return false,
    };
    let signature = match Signature::from_der(signature_der) {
        Ok(s) => s,
        Err(_) => return false,
    };

    let mut signed_data = Vec::with_capacity(auth_data.len() + client_data_hash.len());
    signed_data.extend_from_slice(auth_data);
    signed_data.extend_from_slice(client_data_hash);

    verifying_key.verify(&signed_data, &signature).is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_webauthn_keypair_generation_and_signing() {
        let keypair = generate_webauthn_keypair();
        assert!(!keypair.private_key_pem.is_empty());
        assert_eq!(keypair.public_key_raw.len(), 65);
        assert!(!keypair.cose_public_key.is_empty());

        let auth_data = build_authenticator_data("example.com", 1, true);
        assert_eq!(auth_data.len(), 37);

        let client_data_hash = [0x42u8; 32];
        let sig = sign_webauthn_assertion(&keypair.private_key_pem, &auth_data, &client_data_hash).unwrap();
        assert!(!sig.is_empty());

        let valid = verify_webauthn_assertion(&keypair.public_key_raw, &auth_data, &client_data_hash, &sig);
        assert!(valid);
    }

    #[test]
    fn test_webauthn_keypair_zeroization() {
        let mut keypair = generate_webauthn_keypair();
        assert!(!keypair.private_key_pem.is_empty());
        keypair.zeroize();
        assert!(keypair.private_key_pem.is_empty() || keypair.private_key_pem.chars().all(|c| c == '\0'));
    }
}
