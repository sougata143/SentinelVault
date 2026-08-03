/// Shared data models for SentinelVault.
library core.models;

import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

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
  /// Optional folder / vault ID this item belongs to.
  final String? folderId;

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
    this.folderId,
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
      folderId: json['folderId'] as String?,
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
      if (folderId != null) 'folderId': folderId,
    };
  }
}

/// Returns a valid 36-character UUID string for any given folderId.
/// If input is already a 36-character UUID, returns it unchanged (lowercased).
/// Otherwise, generates a deterministic UUID (SHA-256 derived) for the folder string.
String getFolderUuid(String folderId) {
  final trimmed = folderId.trim();
  if (trimmed.isEmpty) return '81232196-2b98-47af-a62b-92c041fe48cd';
  if (trimmed.length == 36 && trimmed.contains('-')) return trimmed.toLowerCase();

  final bytes = utf8.encode(trimmed);
  final digest = sha256.convert(bytes).bytes;
  final hex = digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-4${hex.substring(13, 16)}-a${hex.substring(17, 20)}-${hex.substring(20, 32)}';
}

/// Derives a deterministic 32-byte Folder Key from masterVaultKey and folderId using HMAC-SHA256.
Uint8List deriveFolderKey(List<int> masterVaultKey, String folderId) {
  final targetUuid = getFolderUuid(folderId);
  final hmac = Hmac(sha256, masterVaultKey);
  final digest = hmac.convert(utf8.encode('sentinelvault_folder_key_$targetUuid'));
  return Uint8List.fromList(digest.bytes);
}
