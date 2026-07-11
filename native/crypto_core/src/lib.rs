pub mod secure_mem;
pub mod algorithms;
pub mod shamir;

use num_bigint::BigUint;
use secure_mem::SecureBuffer;

#[cfg(feature = "wasm")]
use wasm_bindgen::prelude::*;

// Helper to copy data into locked/guarded pages (for small secrets)
fn secure_copy(ptr: *const u8, len: usize) -> SecureBuffer {
    let mut sb = SecureBuffer::new(len);
    if len > 0 && !ptr.is_null() {
        unsafe {
            std::ptr::copy_nonoverlapping(ptr, sb.as_mut_slice().as_mut_ptr(), len);
        }
    }
    sb
}

// =========================================================================
// FFI Exports (C-compatible, dynamic and static native libraries)
// =========================================================================

// 1. Argon2id Key Derivation
#[no_mangle]
pub extern "C" fn derive_master_key(
    password_ptr: *const u8,
    password_len: usize,
    salt_ptr: *const u8,
    salt_len: usize,
    output_ptr: *mut u8, // pre-allocated 32 bytes
) -> i32 {
    if password_ptr.is_null() || salt_ptr.is_null() || output_ptr.is_null() {
        return -1;
    }
    
    // Securely lock sensitive input
    let password_sb = secure_copy(password_ptr, password_len);
    let salt = unsafe { std::slice::from_raw_parts(salt_ptr, salt_len) };
    
    // Derived key is a secret, allocate locked buffer
    let mut output_sb = SecureBuffer::new(32);
    
    match algorithms::derive_master_key(password_sb.as_slice(), salt, output_sb.as_mut_slice()) {
        Ok(_) => {
            unsafe {
                std::ptr::copy_nonoverlapping(output_sb.as_slice().as_ptr(), output_ptr, 32);
            }
            0
        }
        Err(_) => -2,
    }
}

// 2. AES-256-GCM Encrypt
#[no_mangle]
pub extern "C" fn encrypt_aes_gcm(
    key_ptr: *const u8,
    key_len: usize,
    nonce_ptr: *const u8,
    nonce_len: usize,
    plaintext_ptr: *const u8,
    plaintext_len: usize,
    output_ptr: *mut u8, // pre-allocated plaintext_len + 16 bytes
) -> i32 {
    if key_ptr.is_null() || nonce_ptr.is_null() || plaintext_ptr.is_null() || output_ptr.is_null() {
        return -1;
    }
    if key_len != 32 || nonce_len != 12 {
        return -2;
    }
    
    // Securely lock the symmetric key (small secret)
    let key_sb = secure_copy(key_ptr, key_len);
    
    // Note: Do NOT lock plaintext as it can be the entire vault payload
    let nonce = unsafe { std::slice::from_raw_parts(nonce_ptr, nonce_len) };
    let plaintext = unsafe { std::slice::from_raw_parts(plaintext_ptr, plaintext_len) };
    
    match algorithms::encrypt_aes_gcm(key_sb.as_slice(), nonce, plaintext) {
        Ok(ciphertext_and_mac) => {
            unsafe {
                std::ptr::copy_nonoverlapping(
                    ciphertext_and_mac.as_ptr(),
                    output_ptr,
                    ciphertext_and_mac.len(),
                );
            }
            0
        }
        Err(_) => -3,
    }
}

// 3. AES-256-GCM Decrypt
#[no_mangle]
pub extern "C" fn decrypt_aes_gcm(
    key_ptr: *const u8,
    key_len: usize,
    nonce_ptr: *const u8,
    nonce_len: usize,
    ciphertext_ptr: *const u8,
    ciphertext_len: usize,
    output_ptr: *mut u8, // pre-allocated ciphertext_len - 16 bytes
) -> i32 {
    if key_ptr.is_null() || nonce_ptr.is_null() || ciphertext_ptr.is_null() || output_ptr.is_null() {
        return -1;
    }
    if key_len != 32 || nonce_len != 12 {
        return -2;
    }
    
    // Securely lock the symmetric key (small secret)
    let key_sb = secure_copy(key_ptr, key_len);
    
    // Note: Do NOT lock ciphertext
    let nonce = unsafe { std::slice::from_raw_parts(nonce_ptr, nonce_len) };
    let ciphertext = unsafe { std::slice::from_raw_parts(ciphertext_ptr, ciphertext_len) };
    
    match algorithms::decrypt_aes_gcm(key_sb.as_slice(), nonce, ciphertext) {
        Ok(plaintext) => {
            unsafe {
                std::ptr::copy_nonoverlapping(plaintext.as_ptr(), output_ptr, plaintext.len());
            }
            0
        }
        Err(_) => -3,
    }
}

// 4. SRP Calculate X
#[no_mangle]
pub extern "C" fn srp_calculate_x(
    username_ptr: *const u8,
    username_len: usize,
    master_key_ptr: *const u8,
    master_key_len: usize,
    salt_ptr: *const u8,
    salt_len: usize,
    output_ptr: *mut u8, // pre-allocated 32 bytes
) -> i32 {
    if username_ptr.is_null() || master_key_ptr.is_null() || salt_ptr.is_null() || output_ptr.is_null() {
        return -1;
    }
    
    let username_bytes = unsafe { std::slice::from_raw_parts(username_ptr, username_len) };
    let username = match std::str::from_utf8(username_bytes) {
        Ok(s) => s,
        Err(_) => return -2,
    };
    
    // Lock master key
    let master_key_sb = secure_copy(master_key_ptr, master_key_len);
    let salt = unsafe { std::slice::from_raw_parts(salt_ptr, salt_len) };
    
    let x = algorithms::calculate_x(username, master_key_sb.as_slice(), salt);
    let x_bytes = algorithms::biguint_to_bytes_padded(&x, 32);
    
    unsafe {
        std::ptr::copy_nonoverlapping(x_bytes.as_ptr(), output_ptr, 32);
    }
    0
}

// 5. SRP Calculate Verifier
#[no_mangle]
pub extern "C" fn srp_calculate_verifier(
    username_ptr: *const u8,
    username_len: usize,
    master_key_ptr: *const u8,
    master_key_len: usize,
    salt_ptr: *const u8,
    salt_len: usize,
    output_ptr: *mut u8, // pre-allocated 256 bytes
) -> i32 {
    if username_ptr.is_null() || master_key_ptr.is_null() || salt_ptr.is_null() || output_ptr.is_null() {
        return -1;
    }
    
    let username_bytes = unsafe { std::slice::from_raw_parts(username_ptr, username_len) };
    let username = match std::str::from_utf8(username_bytes) {
        Ok(s) => s,
        Err(_) => return -2,
    };
    
    // Lock master key
    let master_key_sb = secure_copy(master_key_ptr, master_key_len);
    let salt = unsafe { std::slice::from_raw_parts(salt_ptr, salt_len) };
    
    let v = algorithms::calculate_verifier(username, master_key_sb.as_slice(), salt);
    let v_bytes = algorithms::biguint_to_bytes_padded(&v, 256);
    
    unsafe {
        std::ptr::copy_nonoverlapping(v_bytes.as_ptr(), output_ptr, 256);
    }
    0
}

// 6. SRP Generate Ephemeral (A)
#[no_mangle]
pub extern "C" fn srp_generate_client_ephemeral(
    a_bytes_ptr: *const u8,
    a_bytes_len: usize,
    secret_output_ptr: *mut u8, // pre-allocated 256 bytes
    public_output_ptr: *mut u8, // pre-allocated 256 bytes
) -> i32 {
    if a_bytes_ptr.is_null() || secret_output_ptr.is_null() || public_output_ptr.is_null() {
        return -1;
    }
    
    // Lock random bytes (private exponent seed)
    let a_bytes_sb = secure_copy(a_bytes_ptr, a_bytes_len);
    
    let (a, a_pub) = algorithms::generate_client_ephemeral(a_bytes_sb.as_slice());
    
    let a_bytes_out = algorithms::biguint_to_bytes_padded(&a, 256);
    let a_pub_bytes = algorithms::biguint_to_bytes_padded(&a_pub, 256);
    
    unsafe {
        std::ptr::copy_nonoverlapping(a_bytes_out.as_ptr(), secret_output_ptr, 256);
        std::ptr::copy_nonoverlapping(a_pub_bytes.as_ptr(), public_output_ptr, 256);
    }
    0
}

// 7. SRP Calculate Session
#[no_mangle]
pub extern "C" fn srp_calculate_client_session(
    username_ptr: *const u8,
    username_len: usize,
    salt_ptr: *const u8,
    salt_len: usize,
    a_ptr: *const u8,             // 256 bytes
    a_pub_ptr: *const u8,         // 256 bytes
    b_pub_ptr: *const u8,         // 256 bytes
    master_key_ptr: *const u8,
    master_key_len: usize,
    session_key_out: *mut u8,     // 32 bytes
    client_evidence_out: *mut u8, // 32 bytes
    server_evidence_out: *mut u8, // 32 bytes
) -> i32 {
    if username_ptr.is_null() || salt_ptr.is_null() || a_ptr.is_null() || a_pub_ptr.is_null()
        || b_pub_ptr.is_null() || master_key_ptr.is_null() || session_key_out.is_null()
        || client_evidence_out.is_null() || server_evidence_out.is_null()
    {
        return -1;
    }
    
    let username_bytes = unsafe { std::slice::from_raw_parts(username_ptr, username_len) };
    let username = match std::str::from_utf8(username_bytes) {
        Ok(s) => s,
        Err(_) => return -2,
    };
    
    let salt = unsafe { std::slice::from_raw_parts(salt_ptr, salt_len) };
    
    // Lock private secret a and master key
    let a_sb = secure_copy(a_ptr, 256);
    let master_key_sb = secure_copy(master_key_ptr, master_key_len);
    
    let a = BigUint::from_bytes_be(a_sb.as_slice());
    
    let a_pub_bytes = unsafe { std::slice::from_raw_parts(a_pub_ptr, 256) };
    let a_pub = BigUint::from_bytes_be(a_pub_bytes);
    
    let b_pub_bytes = unsafe { std::slice::from_raw_parts(b_pub_ptr, 256) };
    let b_pub = BigUint::from_bytes_be(b_pub_bytes);
    
    match algorithms::calculate_client_session(
        username,
        salt,
        &a,
        &a_pub,
        &b_pub,
        master_key_sb.as_slice(),
    ) {
        Ok((session_key, m1, m2)) => {
            unsafe {
                std::ptr::copy_nonoverlapping(session_key.as_ptr(), session_key_out, 32);
                std::ptr::copy_nonoverlapping(m1.as_ptr(), client_evidence_out, 32);
                std::ptr::copy_nonoverlapping(m2.as_ptr(), server_evidence_out, 32);
            }
            0
        }
        Err(_) => -3,
    }
}

// =========================================================================
// WebAssembly Exports (via wasm-bindgen for Web targets)
// =========================================================================

#[cfg(feature = "wasm")]
#[wasm_bindgen]
pub fn wasm_derive_master_key(password: &[u8], salt: &[u8]) -> Result<Vec<u8>, JsValue> {
    let mut output = vec![0u8; 32];
    algorithms::derive_master_key(password, salt, &mut output)
        .map_err(|e| JsValue::from_str(&e.to_string()))?;
    Ok(output)
}

#[cfg(feature = "wasm")]
#[wasm_bindgen]
pub fn wasm_encrypt_aes_gcm(key: &[u8], nonce: &[u8], plaintext: &[u8]) -> Result<Vec<u8>, JsValue> {
    algorithms::encrypt_aes_gcm(key, nonce, plaintext)
        .map_err(|e| JsValue::from_str(&e.to_string()))
}

#[cfg(feature = "wasm")]
#[wasm_bindgen]
pub fn wasm_decrypt_aes_gcm(key: &[u8], nonce: &[u8], ciphertext: &[u8]) -> Result<Vec<u8>, JsValue> {
    algorithms::decrypt_aes_gcm(key, nonce, ciphertext)
        .map_err(|e| JsValue::from_str(&e.to_string()))
}

#[cfg(feature = "wasm")]
#[wasm_bindgen]
pub fn wasm_srp_calculate_x(username: &str, master_key: &[u8], salt: &[u8]) -> Vec<u8> {
    let x = algorithms::calculate_x(username, master_key, salt);
    algorithms::biguint_to_bytes_padded(&x, 32)
}

#[cfg(feature = "wasm")]
#[wasm_bindgen]
pub fn wasm_srp_calculate_verifier(username: &str, master_key: &[u8], salt: &[u8]) -> Vec<u8> {
    let v = algorithms::calculate_verifier(username, master_key, salt);
    algorithms::biguint_to_bytes_padded(&v, 256)
}

#[cfg(feature = "wasm")]
#[wasm_bindgen]
pub fn wasm_srp_generate_client_ephemeral(a_bytes: &[u8]) -> Vec<u8> {
    let (a, a_pub) = algorithms::generate_client_ephemeral(a_bytes);
    let mut out = Vec::with_capacity(512);
    out.extend_from_slice(&algorithms::biguint_to_bytes_padded(&a, 256));
    out.extend_from_slice(&algorithms::biguint_to_bytes_padded(&a_pub, 256));
    out
}

#[cfg(feature = "wasm")]
#[wasm_bindgen]
pub fn wasm_srp_calculate_client_session(
    username: &str,
    salt: &[u8],
    a_bytes: &[u8],
    a_pub_bytes: &[u8],
    b_pub_bytes: &[u8],
    master_key: &[u8],
) -> Result<Vec<u8>, JsValue> {
    let a = BigUint::from_bytes_be(a_bytes);
    let a_pub = BigUint::from_bytes_be(a_pub_bytes);
    let b_pub = BigUint::from_bytes_be(b_pub_bytes);
    
    let (session_key, m1, m2) = algorithms::calculate_client_session(
        username,
        salt,
        &a,
        &a_pub,
        &b_pub,
        master_key,
    ).map_err(|e| JsValue::from_str(e))?;
    
    let mut out = Vec::with_capacity(96);
    out.extend_from_slice(&session_key);
    out.extend_from_slice(&m1);
    out.extend_from_slice(&m2);
    Ok(out)
}

// ==========================================================================
// 7. Shamir's Secret Sharing — Split
// ==========================================================================
//
// Output wire format (flat buffer written to output_ptr):
//   [4 bytes LE u32: share_0_len] [share_0_len bytes: share_0]
//   [4 bytes LE u32: share_1_len] [share_1_len bytes: share_1]
//   ... × n
//
// Caller (Dart) pre-allocates `n * (4 + secret_len + 1)` bytes to be safe.
//
// Returns 0 on success, negative error code on failure:
//  -1  null pointer
//  -2  invalid m/n parameters or output too small
//  -3  internal split error
#[no_mangle]
pub extern "C" fn shamir_split(
    secret_ptr: *const u8,
    secret_len: usize,
    m: u8,
    n: u8,
    output_ptr: *mut u8,
    output_capacity: usize,
    written_ptr: *mut usize, // out-parameter: actual bytes written
) -> i32 {
    if secret_ptr.is_null() || output_ptr.is_null() || written_ptr.is_null() {
        return -1;
    }

    // Securely copy secret into locked/guarded pages (small secret — vault key, RK bytes)
    let secret_sb = secure_copy(secret_ptr, secret_len);

    let shares = match shamir::split_secret(secret_sb.as_slice(), m, n) {
        Ok(s) => s,
        Err(_) => return -2,
    };

    // Flatten into length-prefixed wire format
    let mut buf: Vec<u8> = Vec::new();
    for share_blob in &shares {
        let share_len = share_blob.len() as u32;
        buf.extend_from_slice(&share_len.to_le_bytes());
        buf.extend_from_slice(share_blob);
    }

    if buf.len() > output_capacity {
        return -2;
    }

    unsafe {
        std::ptr::copy_nonoverlapping(buf.as_ptr(), output_ptr, buf.len());
        *written_ptr = buf.len();
    }
    0
}

// ==========================================================================
// 8. Shamir's Secret Sharing — Combine
// ==========================================================================
//
// Input wire format matches the output of shamir_split exactly:
//   [4 bytes LE u32: share_0_len] [share_0_len bytes: share_0] ...
//
// Output: reconstructed secret written to output_ptr.
//
// Returns 0 on success:
//  -1  null pointer
//  -2  malformed input buffer
//  -3  reconstruction failed (wrong shares / tampered)
#[no_mangle]
pub extern "C" fn shamir_combine(
    shares_ptr: *const u8,
    shares_total_len: usize,
    output_ptr: *mut u8,
    output_capacity: usize,
    written_ptr: *mut usize,
) -> i32 {
    if shares_ptr.is_null() || output_ptr.is_null() || written_ptr.is_null() {
        return -1;
    }

    let flat = unsafe { std::slice::from_raw_parts(shares_ptr, shares_total_len) };

    // Parse length-prefixed share blobs
    let mut share_blobs: Vec<Vec<u8>> = Vec::new();
    let mut cursor = 0usize;
    while cursor + 4 <= flat.len() {
        let len = u32::from_le_bytes([flat[cursor], flat[cursor+1], flat[cursor+2], flat[cursor+3]]) as usize;
        cursor += 4;
        if cursor + len > flat.len() {
            return -2;
        }
        share_blobs.push(flat[cursor..cursor + len].to_vec());
        cursor += len;
    }
    if share_blobs.is_empty() {
        return -2;
    }

    // Reconstruct secret
    match shamir::combine_shares(&share_blobs) {
        Ok(mut secret) => {
            if secret.len() > output_capacity {
                shamir::zeroize_buf(&mut secret);
                return -3;
            }
            unsafe {
                std::ptr::copy_nonoverlapping(secret.as_ptr(), output_ptr, secret.len());
                *written_ptr = secret.len();
            }
            shamir::zeroize_buf(&mut secret);
            0
        }
        Err(_) => -3,
    }
}
