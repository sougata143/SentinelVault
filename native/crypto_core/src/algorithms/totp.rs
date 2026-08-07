use hmac::{Hmac, Mac};
use sha1::Sha1;
use sha2::Sha256;
use sha2::Sha512;

type HmacSha1 = Hmac<Sha1>;
type HmacSha256 = Hmac<Sha256>;
type HmacSha512 = Hmac<Sha512>;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TotpAlgorithm {
    Sha1,
    Sha256,
    Sha512,
}

impl TotpAlgorithm {
    pub from_str(s: &str) -> Self {
        match s.to_uppercase().as_str() {
            "SHA256" | "SHA-256" => TotpAlgorithm::Sha256,
            "SHA512" | "SHA-512" => TotpAlgorithm::Sha512,
            _ => TotpAlgorithm::Sha1,
        }
    }
}

/// Decodes a Base32 encoded string into raw key bytes.
pub fn decode_base32(input: &str) -> Result<Vec<u8>, &'static str> {
    let clean: String = input
        .chars()
        .filter(|c| !c.is_whitespace() && *c != '-' && *c != '=')
        .collect::<String>()
        .to_uppercase();

    if clean.is_empty() {
        return Err("Empty base32 secret");
    }

    let mut buffer: u32 = 0;
    let mut bits_left = 0;
    let mut out = Vec::new();

    for c in clean.chars() {
        let val = match c {
            'A'..='Z' => (c as u32) - ('A' as u32),
            '2'..='7' => (c as u32) - ('2' as u32) + 26,
            _ => return Err("Invalid base32 character"),
        };

        buffer = (buffer << 5) | val;
        bits_left += 5;

        if bits_left >= 8 {
            bits_left -= 8;
            out.push((buffer >> bits_left) as u8);
        }
    }

    Ok(out)
}

/// Generates a TOTP code for a given timestamp and parameters (RFC 6238).
pub fn generate_totp(
    secret: &str,
    timestamp_sec: u64,
    period: u32,
    digits: u32,
    algorithm: TotpAlgorithm,
) -> Result<String, &'static str> {
    let key_bytes = decode_base32(secret)?;
    let period = if period == 0 { 30 } else { period };
    let digits = if digits == 0 { 6 } else { digits };

    let counter = timestamp_sec / (period as u64);
    let counter_bytes = counter.to_be_bytes();

    let mac_bytes: Vec<u8> = match algorithm {
        TotpAlgorithm::Sha1 => {
            let mut mac = HmacSha1::new_from_slice(&key_bytes).map_err(|_| "HMAC init failed")?;
            mac.update(&counter_bytes);
            mac.finalize().into_bytes().to_vec()
        }
        TotpAlgorithm::Sha256 => {
            let mut mac = HmacSha256::new_from_slice(&key_bytes).map_err(|_| "HMAC init failed")?;
            mac.update(&counter_bytes);
            mac.finalize().into_bytes().to_vec()
        }
        TotpAlgorithm::Sha512 => {
            let mut mac = HmacSha512::new_from_slice(&key_bytes).map_err(|_| "HMAC init failed")?;
            mac.update(&counter_bytes);
            mac.finalize().into_bytes().to_vec()
        }
    };

    let offset = (mac_bytes[mac_bytes.len() - 1] & 0x0f) as usize;
    let binary = ((mac_bytes[offset] & 0x7f) as u32) << 24
        | ((mac_bytes[offset + 1] & 0xff) as u32) << 16
        | ((mac_bytes[offset + 2] & 0xff) as u32) << 8
        | ((mac_bytes[offset + 3] & 0xff) as u32);

    let modulus = 10u32.pow(digits);
    let code_num = binary % modulus;

    Ok(format!("{:0width$}", code_num, width = digits as usize))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_rfc6238_sha1_vectors() {
        // RFC 6238 Appendix B test vectors for SHA1 (20-byte key: 12345678901234567890)
        // Base32 representation of "12345678901234567890" is GEZDGNBVGY3TQOJQGEZDGNBVGY======
        let secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY======";

        let tests = vec![
            (59u64, "287082", "94287082"),
            (1111111109u64, "081804", "07081804"),
            (1111111111u64, "050471", "14050471"),
            (1234567890u64, "005924", "89005924"),
            (2000000000u64, "279037", "69279037"),
        ];

        for (t, exp6, exp8) in tests {
            let code6 = generate_totp(secret, t, 30, 6, TotpAlgorithm::Sha1).unwrap();
            assert_eq!(code6, exp6, "Failed for t={}", t);

            let code8 = generate_totp(secret, t, 30, 8, TotpAlgorithm::Sha1).unwrap();
            assert_eq!(code8, exp8, "Failed for 8-digit t={}", t);
        }
    }
}
