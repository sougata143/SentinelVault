import 'dart:typed_data';

/// Abstract class representing the native cryptographic core interface.
/// 
/// Implementing classes bridge calculations to a Rust core library using
/// platform-specific mechanisms (dart:ffi on native, dart:js_interop on Web).
abstract class NativeCryptoBridge {
  /// Derives a 32-byte Master Key from password and salt.
  Future<Uint8List> deriveMasterKey({
    required List<int> password,
    required List<int> salt,
  });

  /// Encrypts plaintext using AES-256-GCM. Returns concatenated ciphertext + MAC.
  Future<Uint8List> encryptAesGcm({
    required List<int> plaintext,
    required List<int> key,
    required List<int> nonce,
  });

  /// Decrypts ciphertextAndMac using AES-256-GCM.
  Future<Uint8List> decryptAesGcm({
    required List<int> ciphertextAndMac,
    required List<int> key,
    required List<int> nonce,
  });

  /// Computes the SRP parameter x.
  Future<Uint8List> srpCalculateX({
    required String username,
    required List<int> masterKey,
    required List<int> salt,
  });

  /// Computes the SRP verifier v.
  Future<Uint8List> srpCalculateVerifier({
    required String username,
    required List<int> masterKey,
    required List<int> salt,
  });

  /// Generates the client ephemeral values secret (a) and public (A).
  ///
  /// Returns a list of two 256-byte Uint8Lists: `[secret, public]`.
  List<Uint8List> srpGenerateClientEphemeral({
    required List<int> secureRandomBytes,
  });

  /// Computes the client session key and client evidence.
  ///
  /// Returns a list of three 32-byte Uint8Lists: `[sessionKey, clientEvidence, expectedServerEvidence]`.
  Future<List<Uint8List>> srpCalculateClientSession({
    required String username,
    required List<int> salt,
    required List<int> a,
    required List<int> A,
    required List<int> B,
    required List<int> masterKey,
  });

  /// Splits [secret] bytes into [n] Shamir shares where any [m] of them reconstruct it.
  ///
  /// Returns a list of [n] share blobs (raw bytes). Each blob contains a
  /// 1-byte x-coordinate plus [secret.length] share bytes in GF(256).
  ///
  /// Security invariant: Each share individually reveals zero information about the
  /// secret (information-theoretically secure for any subset < m shares).
  List<Uint8List> shamirSplit({
    required Uint8List secret,
    required int m,
    required int n,
  });

  /// Reconstructs the original secret from a list of share blobs.
  ///
  /// [shares] must contain at least [m] valid share blobs produced by [shamirSplit]
  /// from the same split operation. Returns the reconstructed bytes.
  ///
  /// Throws [ArgumentError] if reconstruction fails (wrong shares, tampering,
  /// or insufficient share count).
  Uint8List shamirCombine({required List<Uint8List> shares});

  // ─── PQC Hybrid Key-Sharing ───────────────────────────────────────────────

  /// Generates a full classical + post-quantum keypair bundle.
  ///
  /// Returns a [PqcKeyBundle] containing:
  ///  - X25519 key pair (32-byte pub + priv)
  ///  - Ed25519 key pair (32-byte pub + 32-byte seed)
  ///  - ML-KEM-768 encapsulation + decapsulation keys
  ///  - ML-DSA-65 verifying key + 32-byte seed (private)
  ///
  /// Security: private material in the returned bundle must be persisted
  /// only in secure OS key-storage and never transmitted to any server.
  Future<PqcKeyBundle> pqcGenerateKeypairs();

  /// Wraps [folderKey] for [recipient] using the hybrid X25519 + ML-KEM-768
  /// construction (HKDF-SHA256 combined shared-secrets → AES-256-GCM).
  ///
  /// Returns a [PqcWrappedKey] containing all ciphertext components needed
  /// for the recipient to unwrap the key. No plaintext leaves this function.
  Future<PqcWrappedKey> pqcHybridWrap({
    required Uint8List recipientX25519Pub,   // 32 bytes
    required Uint8List recipientMlkemEk,     // 1184 bytes
    required Uint8List folderKey,            // 32 bytes
  });

  /// Unwraps a wrapped Folder Key using the caller's private keypair.
  ///
  /// Returns the 32-byte plaintext Folder Key on success.
  /// Throws [ArgumentError] if AEAD tag verification fails (tampered ciphertext
  /// or wrong private key — both are treated identically to prevent oracle attacks).
  Future<Uint8List> pqcHybridUnwrap({
    required Uint8List recipientX25519Priv,  // 32 bytes
    required Uint8List recipientMlkemDk,     // 2400 bytes
    required PqcWrappedKey wrappedKey,
  });

  /// Dual-signs [payload] with Ed25519 + ML-DSA-65.
  ///
  /// [mldsaSeed] is the 32-byte ML-DSA seed (not the expanded key).
  /// Returns a [PqcSignatureBundle] holding both signature blobs.
  Future<PqcSignatureBundle> pqcSignInvitation({
    required Uint8List payload,
    required Uint8List ed25519Priv,   // 32-byte seed
    required Uint8List mldsaSeed,     // 32-byte ML-DSA seed
  });

  /// Verifies a [PqcSignatureBundle] against [payload] using the provided
  /// public keys. Returns true only when BOTH signatures verify.
  ///
  /// Security invariant: a server-substituted public key will cause at least
  /// one signature to fail because the signatures bind to the original keys.
  Future<bool> pqcVerifyInvitation({
    required Uint8List payload,
    required Uint8List ed25519Pub,    // 32 bytes
    required Uint8List mldsaVk,       // 1952 bytes
    required PqcSignatureBundle signatures,
  });
}

// ─── PQC Data Structures ─────────────────────────────────────────────────────

/// Immutable bundle of classical + post-quantum public/private keys.
/// Private fields are named with a `priv` suffix to make accidental logging
/// easier to audit.
class PqcKeyBundle {
  final Uint8List x25519Pub;
  final Uint8List x25519Priv;     // 32 bytes — treat as secret
  final Uint8List ed25519Pub;
  final Uint8List ed25519Priv;    // 32-byte seed — treat as secret
  final Uint8List mlkemEk;        // 1184 bytes — public
  final Uint8List mlkemDk;        // 2400 bytes — treat as secret
  final Uint8List mldsaVk;        // 1952 bytes — public
  final Uint8List mldsaSeed;      // 32 bytes — treat as secret

  const PqcKeyBundle({
    required this.x25519Pub,
    required this.x25519Priv,
    required this.ed25519Pub,
    required this.ed25519Priv,
    required this.mlkemEk,
    required this.mlkemDk,
    required this.mldsaVk,
    required this.mldsaSeed,
  });

  /// Concatenated public components for hashing/fingerprinting.
  Uint8List get publicBytes => Uint8List.fromList([
    ...x25519Pub, ...ed25519Pub, ...mlkemEk, ...mldsaVk,
  ]);
}

/// All ciphertext components produced by [pqcHybridWrap].
/// Safe to store on the server — contains only ciphertext, never plaintext.
class PqcWrappedKey {
  final Uint8List ephemeralX25519Pub;  // 32 bytes
  final Uint8List mlkemCiphertext;     // 1088 bytes
  final Uint8List aesNonce;            // 12 bytes
  final Uint8List wrappedFolderKey;    // 48 bytes (32 + 16 GCM tag)

  const PqcWrappedKey({
    required this.ephemeralX25519Pub,
    required this.mlkemCiphertext,
    required this.aesNonce,
    required this.wrappedFolderKey,
  });
}

/// Ed25519 + ML-DSA-65 dual signature pair.
class PqcSignatureBundle {
  final Uint8List ed25519Signature;  // 64 bytes
  final Uint8List mldsaSignature;    // 3309 bytes

  const PqcSignatureBundle({
    required this.ed25519Signature,
    required this.mldsaSignature,
  });
}
