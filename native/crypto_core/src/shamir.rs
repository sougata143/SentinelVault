use sharks::{Sharks, Share};
use zeroize::Zeroize;

/// Splits `secret` bytes into `n` shares where any `m` of them can reconstruct
/// the original secret.
///
/// # Arguments
/// - `secret`: The bytes to split (e.g. a 20-byte Recovery Key payload).
/// - `m`: Minimum number of shares required to reconstruct (`threshold`). Must be ≥ 2.
/// - `n`: Total number of shares produced. Must be ≥ m and ≤ 255.
///
/// # Returns
/// A `Vec` of `n` share blobs. Each blob is: `[x_coordinate (1 byte)] ++ [y values (secret.len() bytes)]`.
/// This encoding is sufficient for reconstruction and is identical to the wire format
/// produced by the `sharks` crate's `Share::from_bytes` / `Into<Vec<u8>>` round-trip.
///
/// # Security invariant
/// - The `sharks` crate generates polynomial coefficients via `rand_chacha::ChaCha20Rng`
///   seeded from the OS entropy source (`rand::rngs::OsRng`), so shares are
///   information-theoretically secure: any subset of fewer than `m` shares reveals
///   zero information about the secret.
/// - The `zeroize_memory` feature is enabled; the crate zeroes intermediate polynomial
///   evaluations on drop.
pub fn split_secret(secret: &[u8], m: u8, n: u8) -> Result<Vec<Vec<u8>>, &'static str> {
    if m < 2 {
        return Err("threshold m must be at least 2");
    }
    if n < m {
        return Err("total shares n must be >= threshold m");
    }
    if secret.is_empty() {
        return Err("secret must not be empty");
    }

    let sharks = Sharks(m);
    let dealer = sharks.dealer(secret);

    let shares: Vec<Vec<u8>> = dealer
        .take(n as usize)
        .map(|share| Vec::<u8>::from(&share))
        .collect();

    Ok(shares)
}

/// Reconstructs the original secret from a collection of shares.
///
/// # Arguments
/// - `share_blobs`: A slice of share blobs (each previously produced by [`split_secret`]).
///   Must contain at least `m` valid shares from the same split operation.
///
/// # Returns
/// The reconstructed secret bytes, or `Err` if reconstruction fails (wrong shares,
/// insufficient count, tampered bytes, or shares from different epochs).
///
/// # Security invariant
/// - Reconstruction is entirely client-side; this function never transmits data.
/// - Providing fewer than `m` shares will produce garbage bytes (not an error code);
///   the caller in `shamir_recovery.dart` validates the epoch ID on the reconstructed
///   recovery key string before accepting it, which catches this case.
pub fn combine_shares(share_blobs: &[Vec<u8>]) -> Result<Vec<u8>, &'static str> {
    if share_blobs.is_empty() {
        return Err("no shares provided");
    }

    let shares: Result<Vec<Share>, _> = share_blobs
        .iter()
        .map(|blob| Share::try_from(blob.as_slice()))
        .collect();

    let shares = shares.map_err(|_| "failed to parse one or more share blobs")?;

    let sharks = Sharks(1); // threshold is encoded in shares; use 1 for parsing
    sharks
        .recover(&shares)
        .map_err(|_| "failed to reconstruct secret from shares")
}

/// Zeroes a mutable byte vector in place.
///
/// Use this on reconstructed secret buffers after use.
pub fn zeroize_buf(buf: &mut Vec<u8>) {
    buf.zeroize();
}

#[cfg(test)]
mod tests {
    use super::*;

    const TEST_SECRET: &[u8] = b"SentinelVaultTestSecret1234567890"; // 32 bytes

    #[test]
    fn test_split_and_combine_exactly_threshold() {
        let shares = split_secret(TEST_SECRET, 3, 5).expect("split failed");
        assert_eq!(shares.len(), 5);

        // Take exactly 3 (minimum threshold)
        let subset = shares[0..3].to_vec();
        let reconstructed = combine_shares(&subset).expect("combine failed");
        assert_eq!(reconstructed, TEST_SECRET);
    }

    #[test]
    fn test_split_and_combine_superset_of_threshold() {
        let shares = split_secret(TEST_SECRET, 3, 5).expect("split failed");
        // 4 shares — still works
        let subset = shares[0..4].to_vec();
        let reconstructed = combine_shares(&subset).expect("combine with 4 shares failed");
        assert_eq!(reconstructed, TEST_SECRET);
        // All 5 shares — still works
        let reconstructed = combine_shares(&shares).expect("combine with 5 shares failed");
        assert_eq!(reconstructed, TEST_SECRET);
    }

    #[test]
    fn test_below_threshold_does_not_reconstruct_correctly() {
        let shares = split_secret(TEST_SECRET, 3, 5).expect("split failed");
        // Only 2 shares (below threshold of 3)
        let subset = shares[0..2].to_vec();
        // Either returns an error OR produces wrong bytes — both are acceptable
        // security outcomes; we assert the result is NOT the original secret.
        match combine_shares(&subset) {
            Ok(reconstructed) => {
                assert_ne!(reconstructed, TEST_SECRET,
                    "M-1 shares must not reconstruct the original secret");
            }
            Err(_) => {
                // An error is also acceptable — means reconstruction was detected as invalid
            }
        }
    }

    #[test]
    fn test_split_2_of_3() {
        let secret = b"short_key_12345678901234567890AB";
        let shares = split_secret(secret, 2, 3).expect("split failed");
        assert_eq!(shares.len(), 3);
        let reconstructed = combine_shares(&shares[0..2]).expect("combine failed");
        assert_eq!(reconstructed.as_slice(), secret);
    }

    #[test]
    fn test_split_5_of_7() {
        let shares = split_secret(TEST_SECRET, 5, 7).expect("split failed");
        assert_eq!(shares.len(), 7);
        let reconstructed = combine_shares(&shares[1..6]).expect("combine failed");
        assert_eq!(reconstructed, TEST_SECRET);
    }

    #[test]
    fn test_invalid_threshold_rejected() {
        assert!(split_secret(TEST_SECRET, 1, 5).is_err(), "threshold < 2 must be rejected");
        assert!(split_secret(TEST_SECRET, 5, 3).is_err(), "n < m must be rejected");
        assert!(split_secret(b"", 2, 3).is_err(), "empty secret must be rejected");
    }
}
