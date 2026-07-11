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
}
