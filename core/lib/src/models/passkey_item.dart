import 'dart:convert';
import 'vault_item.dart';

/// Represents a WebAuthn / FIDO2 Passkey credential stored inside the vault.
///
/// Security Invariant: The [privateKeyPem] MUST be held as a [ConcealedValue]
/// and encrypted with the user's derived Vault Key — never stored unencrypted.
class PasskeyVaultItem {
  /// Unique relying party identifier (e.g. "github.com", "google.com").
  final String rpId;

  /// User handle / account ID provided by the relying party.
  final String userHandle;

  /// Display username / email associated with the passkey (e.g. "dev@example.com").
  final String userName;

  /// Unique base64-encoded credential ID generated during WebAuthn registration.
  final String credentialId;

  /// Encrypted P-256 SEC1 / PKCS#8 PEM private key.
  final ConcealedValue privateKeyPem;

  /// Base64-encoded uncompressed P-256 public key (65 bytes: 0x04 || X || Y).
  final String publicKeyRaw;

  /// Base64-encoded COSE-formatted public key (CBOR map).
  final String cosePublicKey;

  /// Monotonically increasing signature counter used for WebAuthn replay prevention.
  final int signCount;

  /// ISO-8601 timestamp when the passkey was created.
  final DateTime createdAt;

  /// ISO-8601 timestamp when the passkey was last used for authentication.
  final DateTime? lastUsedAt;

  /// Creates a new [PasskeyVaultItem].
  const PasskeyVaultItem({
    required this.rpId,
    required this.userHandle,
    required this.userName,
    required this.credentialId,
    required this.privateKeyPem,
    required this.publicKeyRaw,
    required this.cosePublicKey,
    this.signCount = 0,
    required this.createdAt,
    this.lastUsedAt,
  });

  /// Converts this passkey object to a JSON-encodable map.
  Map<String, dynamic> toJson() {
    return {
      'rpId': rpId,
      'userHandle': userHandle,
      'userName': userName,
      'credentialId': credentialId,
      'privateKeyPem': privateKeyPem.toJson(),
      'publicKeyRaw': publicKeyRaw,
      'cosePublicKey': cosePublicKey,
      'signCount': signCount,
      'createdAt': createdAt.toIso8601String(),
      if (lastUsedAt != null) 'lastUsedAt': lastUsedAt!.toIso8601String(),
    };
  }

  /// Deserializes a [PasskeyVaultItem] from a JSON map.
  factory PasskeyVaultItem.fromJson(Map<String, dynamic> json) {
    return PasskeyVaultItem(
      rpId: json['rpId'] as String,
      userHandle: json['userHandle'] as String? ?? '',
      userName: json['userName'] as String? ?? '',
      credentialId: json['credentialId'] as String,
      privateKeyPem: ConcealedValue.fromJson(json['privateKeyPem'] as Map<String, dynamic>),
      publicKeyRaw: json['publicKeyRaw'] as String,
      cosePublicKey: json['cosePublicKey'] as String? ?? '',
      signCount: (json['signCount'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastUsedAt: json['lastUsedAt'] != null ? DateTime.parse(json['lastUsedAt'] as String) : null,
    );
  }

  /// Creates a copy of this object with an updated sign count and last used timestamp.
  PasskeyVaultItem incrementSignCount() {
    return PasskeyVaultItem(
      rpId: rpId,
      userHandle: userHandle,
      userName: userName,
      credentialId: credentialId,
      privateKeyPem: privateKeyPem,
      publicKeyRaw: publicKeyRaw,
      cosePublicKey: cosePublicKey,
      signCount: signCount + 1,
      createdAt: createdAt,
      lastUsedAt: DateTime.now().toUtc(),
    );
  }
}
