import 'dart:convert';
import 'dart:typed_data';
import 'crypto.dart';

/// Manages wrapping and unwrapping the Vault Key using a hardware-token derived secret
/// (via the CTAP2 hmac-secret extension).
class HardwareKeyUnlock {
  /// The FIDO2 credential ID identifying the hardware key.
  final String credentialId;

  /// The unique salt used to trigger the hmac-secret calculation.
  final List<int> salt;

  /// The Vault Key wrapped using the derived hmac-secret key via AES-256-GCM.
  final List<int> wrappedVaultKey;

  /// Creates a new [HardwareKeyUnlock] instance.
  HardwareKeyUnlock({
    required this.credentialId,
    required this.salt,
    required this.wrappedVaultKey,
  });

  /// Serializes the hardware key unlock configuration to a JSON string.
  String toJson() {
    return json.encode({
      'credentialId': base64Url.encode(utf8.encode(credentialId)),
      'salt': base64Url.encode(salt),
      'wrappedVaultKey': base64Url.encode(wrappedVaultKey),
    });
  }

  /// Deserializes a [HardwareKeyUnlock] instance from a JSON string.
  factory HardwareKeyUnlock.fromJson(String jsonStr) {
    final Map<String, dynamic> data = json.decode(jsonStr);
    return HardwareKeyUnlock(
      credentialId: utf8.decode(base64Url.decode(data['credentialId'] as String)),
      salt: base64Url.decode(data['salt'] as String),
      wrappedVaultKey: base64Url.decode(data['wrappedVaultKey'] as String),
    );
  }

  /// Wraps the Vault Key with the CTAP2 derived [hmacSecretKey].
  ///
  /// Security Invariant: The wrapping process generates a fresh, unique nonce per run
  /// and uses vetted AES-256-GCM from [VaultCrypto].
  static Future<HardwareKeyUnlock> create({
    required String credentialId,
    required List<int> salt,
    required List<int> vaultKey,
    required List<int> hmacSecretKey,
    required VaultCrypto crypto,
  }) async {
    final wrapped = await crypto.wrapVaultKey(
      vaultKey: vaultKey,
      masterKey: hmacSecretKey,
    );
    return HardwareKeyUnlock(
      credentialId: credentialId,
      salt: salt,
      wrappedVaultKey: wrapped,
    );
  }

  /// Unwraps the Vault Key with the CTAP2 derived [hmacSecretKey].
  ///
  /// Security Invariant: Throws authentication exception if the key is incorrect or data is tampered.
  Future<List<int>> unwrap({
    required List<int> hmacSecretKey,
    required VaultCrypto crypto,
  }) async {
    return await crypto.unwrapVaultKey(
      wrappedVaultKey: wrappedVaultKey,
      masterKey: hmacSecretKey,
    );
  }
}
