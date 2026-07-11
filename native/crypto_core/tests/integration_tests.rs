use crypto_core::algorithms::{derive_master_key, encrypt_aes_gcm, decrypt_aes_gcm};

#[test]
fn test_argon2id_correctness() {
    let password = b"test_password_123";
    let salt = b"salt_of_minimum_length_16";
    let mut key1 = [0u8; 32];
    let mut key2 = [0u8; 32];
    derive_master_key(password, salt, &mut key1).unwrap();
    derive_master_key(password, salt, &mut key2).unwrap();
    
    assert_eq!(key1, key2);
    assert_ne!(key1, [0u8; 32]);
}

#[test]
fn test_aes_gcm_correctness() {
    let key = vec![0xABu8; 32];
    let nonce = vec![0xCDu8; 12];
    let plaintext = b"SentinelVault dynamic FFI memory hardening test vector payload";
    
    let encrypted = encrypt_aes_gcm(&key, &nonce, plaintext).unwrap();
    assert_ne!(encrypted, plaintext);
    
    let decrypted = decrypt_aes_gcm(&key, &nonce, &encrypted).unwrap();
    assert_eq!(decrypted, plaintext);
}
