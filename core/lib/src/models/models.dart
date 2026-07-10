/// Shared data models for SentinelVault.
library core.models;

export 'vault_item.dart';

/// Represents an encrypted vault item (e.g., password, login credentials).
class EncryptedVaultItem {
  /// Unique identifier of the vault item.
  final String id;
  /// Base64 encoded AES-256-GCM ciphertext of the item details.
  final String encryptedBlob;
  /// Base64 encoded unique initialization vector / nonce used for encryption.
  final String nonce;
  /// Version identifier for conflict-free syncing.
  final int version;
  /// Last modified timestamp.
  final DateTime updatedAt;
  /// Flag indicating if the item is soft-deleted.
  final bool isDeleted;

  /// Creates a new instance of [EncryptedVaultItem].
  ///
  /// Security invariant: No plaintext vault items are held here; only ciphertext
  /// and metadata.
  EncryptedVaultItem({
    required this.id,
    required this.encryptedBlob,
    required this.nonce,
    required this.version,
    required this.updatedAt,
    this.isDeleted = false,
  });

  /// Factory constructor to parse a vault item from JSON.
  factory EncryptedVaultItem.fromJson(Map<String, dynamic> json) {
    return EncryptedVaultItem(
      id: json['id'] as String,
      encryptedBlob: json['encryptedBlob'] as String,
      nonce: json['nonce'] as String,
      version: json['version'] as int,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      isDeleted: json['isDeleted'] as bool? ?? false,
    );
  }

  /// Converts the vault item metadata to JSON for serialization or sync.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'encryptedBlob': encryptedBlob,
      'nonce': nonce,
      'version': version,
      'updatedAt': updatedAt.toIso8601String(),
      'isDeleted': isDeleted,
    };
  }
}
