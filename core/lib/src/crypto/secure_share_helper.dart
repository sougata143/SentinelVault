import 'dart:convert';
import 'dart:typed_data';
import 'crypto.dart';

/// Helper result container for client-side encrypted share link creation.
class ShareEncryptionResult {
  /// Base64 encoded AES-256-GCM ciphertext.
  final String encryptedBlob;
  /// Base64 encoded 12-byte initialization vector.
  final String nonce;
  /// Hex-encoded 32-byte ephemeral decryption key (to be included ONLY in URL fragment).
  final String shareKeyHex;

  /// Creates a new [ShareEncryptionResult] instance.
  const ShareEncryptionResult({
    required this.encryptedBlob,
    required this.nonce,
    required this.shareKeyHex,
  });
}

/// Utility for client-side encryption/decryption of time-limited secure share links.
///
/// Security Invariants:
/// 1. The ephemeral 32-byte key [shareKeyHex] travels ONLY in the URL fragment (`#`).
/// 2. The server NEVER sees or receives [shareKeyHex].
class SecureShareHelper {
  /// Encrypts plaintext [jsonPayload] with a fresh random 32-byte share key.
  static Future<ShareEncryptionResult> encryptSharePayload({
    required String jsonPayload,
    required VaultCrypto crypto,
  }) async {
    final shareKeyBytes = crypto.generateRandomBytes(32);
    final nonceBytes = crypto.generateRandomBytes(12);

    final ciphertextAndMac = await crypto.encryptAesGcm(
      plaintext: utf8.encode(jsonPayload),
      key: shareKeyBytes,
      nonce: nonceBytes,
    );

    final shareKeyHex = shareKeyBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    return ShareEncryptionResult(
      encryptedBlob: base64.encode(ciphertextAndMac),
      nonce: base64.encode(nonceBytes),
      shareKeyHex: shareKeyHex,
    );
  }

  /// Decrypts [encryptedBlobBase64] using the ephemeral key [shareKeyHex] from the URL fragment.
  static Future<String> decryptSharePayload({
    required String encryptedBlobBase64,
    required String nonceBase64,
    required String shareKeyHex,
    required VaultCrypto crypto,
  }) async {
    if (shareKeyHex.length != 64) {
      throw ArgumentError('Invalid share key length: expected 64 hex characters');
    }

    final shareKeyBytes = Uint8List.fromList(
      List.generate(32, (i) => int.parse(shareKeyHex.substring(i * 2, i * 2 + 2), radix: 16)),
    );
    final ciphertextBytes = base64.decode(encryptedBlobBase64);
    final nonceBytes = base64.decode(nonceBase64);

    final decBytes = await crypto.decryptAesGcm(
      ciphertextAndMac: ciphertextBytes,
      key: shareKeyBytes,
      nonce: nonceBytes,
    );

    return utf8.decode(decBytes);
  }

  /// Constructs full Share Link URL with the secret key in the `#` fragment.
  static String buildShareUrl({
    required String baseUrl,
    required String shareId,
    required String shareKeyHex,
  }) {
    final cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return '$cleanBase/share/view/$shareId#$shareKeyHex';
  }

  /// Parses `shareId` and fragment `shareKeyHex` from a full Share URL.
  static Map<String, String>? parseShareUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final shareKeyHex = uri.fragment.trim();
      final pathSegments = uri.pathSegments;

      final viewIndex = pathSegments.indexOf('view');
      if (viewIndex != -1 && viewIndex + 1 < pathSegments.length) {
        final shareId = pathSegments[viewIndex + 1];
        return {
          'shareId': shareId,
          'shareKeyHex': shareKeyHex,
        };
      }
    } catch (_) {}
    return null;
  }
}
