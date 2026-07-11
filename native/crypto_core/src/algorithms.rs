use aes_gcm::{
    aead::{Aead, KeyInit, Error as AeadError},
    Aes256Gcm, Nonce
};
use argon2::{Argon2, Algorithm, Version, Params};
use num_bigint::BigUint;
use num_traits::Num;
use sha2::{Sha256, Digest};

// --- Argon2id Key Derivation ---

pub fn derive_master_key(
    password: &[u8],
    salt: &[u8],
    output: &mut [u8],
) -> Result<(), argon2::Error> {
    let params = Params::new(
        64 * 1024, // 64 MB (65,536 KB)
        3,         // iterations
        4,         // parallelism
        Some(32),  // output length
    )?;
    let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, params);
    argon2.hash_password_into(password, salt, output)?;
    Ok(())
}

// --- AES-256-GCM symmetric encryption ---

pub fn encrypt_aes_gcm(
    key: &[u8],
    nonce: &[u8],
    plaintext: &[u8],
) -> Result<Vec<u8>, AeadError> {
    let cipher = Aes256Gcm::new_from_slice(key).map_err(|_| AeadError)?;
    let nonce_val = Nonce::from_slice(nonce);
    let ciphertext = cipher.encrypt(nonce_val, plaintext)?;
    Ok(ciphertext)
}

pub fn decrypt_aes_gcm(
    key: &[u8],
    nonce: &[u8],
    ciphertext_and_mac: &[u8],
) -> Result<Vec<u8>, AeadError> {
    let cipher = Aes256Gcm::new_from_slice(key).map_err(|_| AeadError)?;
    let nonce_val = Nonce::from_slice(nonce);
    let decrypted = cipher.decrypt(nonce_val, ciphertext_and_mac)?;
    Ok(decrypted)
}

// --- SRP-6a Client Math (RFC 5054 2048-bit prime group) ---

pub fn get_n() -> BigUint {
    BigUint::from_str_radix(
        "AC6BDB41324A9A9BF166DE5E1389582FAF72B6651987EE07FC332F683B94471B\
         A25CEB5F15DE38B4341168461CCBA0140F00D0160AFFA93DD2C85E247E674003\
         79E0957D0502438DF02B22B647CA55F2A3841D39634992644265EEBEC4D20A16\
         C5F3528A6D15E4407B18E06A53ED9027D9B420C21C313E1B2749591A9B65438A\
         2566CCC4465B2035F121210850D6955DFEB4CD0EE5460E58F69646FA5E4B4957\
         B733B9B47E53B026BE6395EE1B24E7985474D5409605553E4774B819EF66E2E1\
         9C898394EAEEDC4C7E9C4CC295F8CCE8CC991666CB29A51F2231BC7FF2FB81C7\
         89FE2CA0B83EAD80A3A059B51E13D667793B9F2EA2F29A58814D7964E94EA25D",
        16
    ).unwrap()
}

pub fn get_g() -> BigUint {
    BigUint::from(2u32)
}

pub fn biguint_to_bytes_padded(val: &BigUint, length: usize) -> Vec<u8> {
    let bytes = val.to_bytes_be();
    if bytes.len() == length {
        bytes
    } else if bytes.len() > length {
        bytes[bytes.len() - length..].to_vec()
    } else {
        let mut padded = vec![0u8; length];
        padded[length - bytes.len()..].copy_from_slice(&bytes);
        padded
    }
}

pub fn get_multiplier_k() -> BigUint {
    let n_bytes = biguint_to_bytes_padded(&get_n(), 256);
    let g_bytes = biguint_to_bytes_padded(&get_g(), 256);
    let mut hasher = Sha256::new();
    hasher.update(&n_bytes);
    hasher.update(&g_bytes);
    let hash = hasher.finalize();
    BigUint::from_bytes_be(&hash)
}

pub fn calculate_x(username: &str, master_key: &[u8], salt: &[u8]) -> BigUint {
    let master_key_hex: String = master_key.iter().map(|b| format!("{:02x}", b)).collect();
    let identity = format!("{}:{}", username, master_key_hex);
    let mut hasher = Sha256::new();
    hasher.update(identity.as_bytes());
    let inner_hash = hasher.finalize();

    let mut hasher = Sha256::new();
    hasher.update(salt);
    hasher.update(&inner_hash);
    let outer_hash = hasher.finalize();
    BigUint::from_bytes_be(&outer_hash)
}

pub fn calculate_verifier(username: &str, master_key: &[u8], salt: &[u8]) -> BigUint {
    let x = calculate_x(username, master_key, salt);
    let g = get_g();
    let n = get_n();
    g.modpow(&x, &n)
}

pub fn generate_client_ephemeral(a_bytes: &[u8]) -> (BigUint, BigUint) {
    let a_raw = BigUint::from_bytes_be(a_bytes);
    let n = get_n();
    let a = a_raw % &n;
    let g = get_g();
    let a_pub = g.modpow(&a, &n);
    (a, a_pub)
}

pub fn calculate_client_session(
    username: &str,
    salt: &[u8],
    a: &BigUint,
    a_pub: &BigUint,
    b_pub: &BigUint,
    master_key: &[u8],
) -> Result<(Vec<u8>, Vec<u8>, Vec<u8>), &'static str> {
    let n = get_n();
    if b_pub % &n == BigUint::from(0u32) {
        return Err("Server ephemeral B cannot be 0 mod N");
    }

    let k = get_multiplier_k();
    let x = calculate_x(username, master_key, salt);

    let a_bytes = biguint_to_bytes_padded(a_pub, 256);
    let b_bytes = biguint_to_bytes_padded(b_pub, 256);

    let mut hasher = Sha256::new();
    hasher.update(&a_bytes);
    hasher.update(&b_bytes);
    let u_hash = hasher.finalize();
    let u = BigUint::from_bytes_be(&u_hash);

    if u == BigUint::from(0u32) {
        return Err("Scrambling parameter u cannot be 0");
    }

    // S = (B - k * g^x) ^ (a + u * x) mod N
    let exp = a + &u * &x;
    let g_x = get_g().modpow(&x, &n);
    let term = (&k * &g_x) % &n;
    
    // safe subtraction mod N: (B - term) mod N
    let base = if b_pub >= &term {
        (b_pub - &term) % &n
    } else {
        (&n - (&term - b_pub) % &n) % &n
    };

    let s = base.modpow(&exp, &n);
    let s_bytes = biguint_to_bytes_padded(&s, 256);

    let mut hasher = Sha256::new();
    hasher.update(&s_bytes);
    let session_key = hasher.finalize().to_vec();

    // M1 = H(H(N) ^ H(g), H(username), salt, A, B, sessionKey)
    let mut hasher = Sha256::new();
    hasher.update(&biguint_to_bytes_padded(&n, 256));
    let hn = hasher.finalize();

    let mut hasher = Sha256::new();
    hasher.update(&biguint_to_bytes_padded(&get_g(), 256));
    let hg = hasher.finalize();

    let mut h_xor = vec![0u8; 32];
    for i in 0..32 {
        h_xor[i] = hn[i] ^ hg[i];
    }

    let mut hasher = Sha256::new();
    hasher.update(username.as_bytes());
    let hu = hasher.finalize();

    let mut hasher = Sha256::new();
    hasher.update(&h_xor);
    hasher.update(&hu);
    hasher.update(salt);
    hasher.update(&a_bytes);
    hasher.update(&b_bytes);
    hasher.update(&session_key);
    let m1 = hasher.finalize().to_vec();

    // M2 = H(A, M1, sessionKey)
    let mut hasher = Sha256::new();
    hasher.update(&a_bytes);
    hasher.update(&m1);
    hasher.update(&session_key);
    let m2 = hasher.finalize().to_vec();

    Ok((session_key, m1, m2))
}
