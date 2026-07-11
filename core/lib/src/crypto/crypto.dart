/// Cryptographic operations for SentinelVault.
///
/// Implements Argon2id key derivation, AES-256-GCM vault item encryption, and
/// the key wrapping hierarchy (Master Key wraps Vault Key, Vault Key encrypts items).
library core.crypto;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'native_crypto_bridge.dart';
import 'native_crypto_bridge_selector.dart';

/// Cryptographic services for SentinelVault key management and encryption.
class VaultCrypto {
  /// The platform-specific native/wasm cryptographic bridge.
  final NativeCryptoBridge _bridge;
  /// The secure random number generator.
  final Random _secureRandom;

  /// Creates a new instance of [VaultCrypto] with standard security parameters.
  VaultCrypto()
      : _bridge = NativeCryptoBridgeImpl(),
        _secureRandom = Random.secure();

  /// Generates a list of cryptographically secure random bytes of [length].
  ///
  /// Security invariant: Uses [Random.secure] to ensure unpredictability.
  /// Caller must zero the returned buffer after use when handling sensitive data.
  Uint8List generateRandomBytes(int length) {
    if (length <= 0) {
      throw ArgumentError('Length must be greater than 0');
    }
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _secureRandom.nextInt(256);
    }
    return bytes;
  }

  /// Derives a 32-byte (256-bit) Master Key from the master password and a user-specific salt.
  ///
  /// Security invariant: The master password is never stored or logged in plaintext.
  /// The salt must be unique per user and at least 16 bytes long.
  Future<List<int>> deriveMasterKey({
    required String masterPassword,
    required List<int> salt,
  }) async {
    if (masterPassword.isEmpty) {
      throw ArgumentError('Master password cannot be empty');
    }
    if (salt.length < 16) {
      throw ArgumentError('Salt must be at least 16 bytes long');
    }

    final passwordBytes = utf8.encode(masterPassword);
    try {
      return await _bridge.deriveMasterKey(
        password: passwordBytes,
        salt: salt,
      );
    } finally {
      // Clear sensitive password bytes from memory immediately after derivation
      _zeroOut(passwordBytes);
    }
  }

  /// Encrypts plaintext bytes using AES-256-GCM.
  ///
  /// Security invariant: Key and plaintext are held only in memory.
  /// The [nonce] must be exactly 12 bytes (96-bit) and never reused with the same key.
  /// Returns a concatenated list of bytes: `ciphertext + MAC (16 bytes)`.
  Future<List<int>> encryptAesGcm({
    required List<int> plaintext,
    required List<int> key,
    required List<int> nonce,
  }) async {
    if (key.length != 32) {
      throw ArgumentError('Key must be exactly 32 bytes (256-bit)');
    }
    if (nonce.length != 12) {
      throw ArgumentError('Nonce must be exactly 12 bytes (96-bit)');
    }

    return await _bridge.encryptAesGcm(
      plaintext: plaintext,
      key: key,
      nonce: nonce,
    );
  }

  /// Decrypts AES-256-GCM encrypted bytes.
  ///
  /// Security invariant: Authenticates the GCM tag (MAC) during decryption.
  /// Throws a [SecretBoxAuthenticationException] if the ciphertext or MAC is tampered with.
  /// The [ciphertextAndMac] must contain both the ciphertext and the 16-byte MAC.
  Future<List<int>> decryptAesGcm({
    required List<int> ciphertextAndMac,
    required List<int> key,
    required List<int> nonce,
  }) async {
    if (key.length != 32) {
      throw ArgumentError('Key must be exactly 32 bytes (256-bit)');
    }
    if (nonce.length != 12) {
      throw ArgumentError('Nonce must be exactly 12 bytes (96-bit)');
    }
    const macSize = 16;
    if (ciphertextAndMac.length <= macSize) {
      throw ArgumentError('Ciphertext is too short to contain a valid MAC');
    }

    return await _bridge.decryptAesGcm(
      ciphertextAndMac: ciphertextAndMac,
      key: key,
      nonce: nonce,
    );
  }

  /// Wraps a 256-bit Vault Key using the Master Key.
  ///
  /// Security invariant: Generates a unique, fresh 96-bit nonce for each wrap operation.
  /// Returns a concatenated byte array: `nonce (12 bytes) + MAC (16 bytes) + ciphertext (32 bytes)`.
  Future<List<int>> wrapVaultKey({
    required List<int> vaultKey,
    required List<int> masterKey,
  }) async {
    if (vaultKey.length != 32) {
      throw ArgumentError('Vault Key to wrap must be exactly 32 bytes (256-bit)');
    }
    if (masterKey.length != 32) {
      throw ArgumentError('Master Key must be exactly 32 bytes (256-bit)');
    }

    final nonce = generateRandomBytes(12);
    final wrappedCiphertextAndMac = await encryptAesGcm(
      plaintext: vaultKey,
      key: masterKey,
      nonce: nonce,
    );

    // Concatenate Nonce + WrappedCiphertextAndMac
    final result = Uint8List(nonce.length + wrappedCiphertextAndMac.length);
    result.setRange(0, nonce.length, nonce);
    result.setRange(nonce.length, result.length, wrappedCiphertextAndMac);
    return result;
  }

  /// Unwraps a wrapped Vault Key using the Master Key.
  ///
  /// Security invariant: Authenticates the GCM tag (MAC) during decryption.
  /// Throws a [SecretBoxAuthenticationException] if tampered or key is incorrect.
  /// Expects a concatenated byte array: `nonce (12 bytes) + MAC (16 bytes) + ciphertext (32 bytes)`.
  Future<List<int>> unwrapVaultKey({
    required List<int> wrappedVaultKey,
    required List<int> masterKey,
  }) async {
    if (masterKey.length != 32) {
      throw ArgumentError('Master Key must be exactly 32 bytes (256-bit)');
    }
    const nonceSize = 12;
    const macSize = 16;
    const keySize = 32;
    const expectedLength = nonceSize + macSize + keySize;
    if (wrappedVaultKey.length != expectedLength) {
      throw ArgumentError('Wrapped Vault Key has invalid length: ${wrappedVaultKey.length} bytes (Expected: $expectedLength)');
    }

    final nonce = wrappedVaultKey.sublist(0, nonceSize);
    final ciphertextAndMac = wrappedVaultKey.sublist(nonceSize);

    return await decryptAesGcm(
      ciphertextAndMac: ciphertextAndMac,
      key: masterKey,
      nonce: nonce,
    );
  }

  /// Generates a high-entropy 160-bit random Recovery Key encoded as a Base32 string
  /// formatted with hyphens: XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX.
  String generateRecoveryKey() {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final randomBytes = generateRandomBytes(20);
    final buffer = StringBuffer();
    var bitBuffer = 0;
    var bitCount = 0;
    for (final byte in randomBytes) {
      bitBuffer = (bitBuffer << 8) | byte;
      bitCount += 8;
      while (bitCount >= 5) {
        final index = (bitBuffer >> (bitCount - 5)) & 31;
        buffer.write(alphabet[index]);
        bitCount -= 5;
      }
    }
    final rawString = buffer.toString();
    final formatted = StringBuffer();
    for (var i = 0; i < rawString.length; i++) {
      if (i > 0 && i % 4 == 0) {
        formatted.write('-');
      }
      formatted.write(rawString[i]);
    }
    return formatted.toString();
  }

  /// Decodes a formatted Recovery Key string back into its original raw bytes.
  List<int> decodeRecoveryKey(String keyString) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final cleaned = keyString.replaceAll('-', '').toUpperCase();
    if (cleaned.length != 32) {
      throw ArgumentError('Invalid recovery key length');
    }
    final result = Uint8List(20);
    var bitBuffer = 0;
    var bitCount = 0;
    var resultIndex = 0;
    for (var i = 0; i < cleaned.length; i++) {
      final index = alphabet.indexOf(cleaned[i]);
      if (index == -1) {
        throw ArgumentError('Invalid character in recovery key');
      }
      bitBuffer = (bitBuffer << 5) | index;
      bitCount += 5;
      if (bitCount >= 8) {
        result[resultIndex++] = (bitBuffer >> (bitCount - 8)) & 255;
        bitCount -= 8;
      }
    }
    return result;
  }

  /// Derives the 32-byte Recovery KDF Key from the Recovery Key and a salt.
  Future<List<int>> deriveRecoveryKdfKey({
    required String recoveryKey,
    required List<int> salt,
  }) async {
    final cleaned = recoveryKey.replaceAll('-', '').toUpperCase();
    return deriveMasterKey(
      masterPassword: cleaned,
      salt: salt,
    );
  }

  /// Overwrites the sensitive byte array with zeroes.
  void _zeroOut(List<int> bytes) {
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = 0;
    }
  }
}
