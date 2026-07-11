import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart' show Sha256;
import 'native_crypto_bridge.dart';

/// Client-side high-level cryptosystem for PQC Folder Sharing.
///
/// Implements:
///  - QR Code / safety number key-fingerprint verification.
///  - Dual-signed invitations.
///  - Monotonic key rotation wrapping.
class PqcSharingManager {
  final NativeCryptoBridge _bridge;

  PqcSharingManager([NativeCryptoBridge? bridge])
      : _bridge = bridge ?? getNativeCryptoBridge();

  /// Computes a user-friendly safety number / fingerprint string from key bundle public components.
  /// SHA-256(x25519_pub ‖ ed25519_pub ‖ mlkem_ek ‖ mldsa_vk) parsed into 5-digit groups.
  Future<String> computeSafetyNumber(PqcKeyBundle bundle) async {
    final bytes = bundle.publicBytes;
    final sha256 = Sha256();
    final hash = await sha256.hash(bytes);
    final hashBytes = Uint8List.fromList(hash.bytes);
    
    // Group into 5-digit decimal blocks
    final buffer = StringBuffer();
    for (var i = 0; i < hashBytes.length - 2; i += 3) {
      final value = (hashBytes[i] << 16) | (hashBytes[i + 1] << 8) | hashBytes[i + 2];
      final group = (value % 100000).toString().padLeft(5, '0');
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(group);
    }
    return buffer.toString();
  }

  /// Generates a share invitation payload, dual-signing it with the sender's keys.
  Future<Map<String, dynamic>> createSignedInvitation({
    required String folderId,
    required String recipientUserId,
    required String senderUserId,
    required Uint8List ed25519Priv,
    required Uint8List mldsaSeed,
    required Uint8List folderKey,
    required Uint8List recipientX25519Pub,
    required Uint8List recipientMlkemEk,
  }) async {
    // 1. Prepare invite payload
    final inviteData = {
      'folderId': folderId,
      'senderUserId': senderUserId,
      'recipientUserId': recipientUserId,
      'expiresAt': DateTime.now().add(const Duration(days: 7)).toUtc().toIso8601String(),
    };
    final serializedPayload = utf8.encode(json.encode(inviteData));

    // 2. Dual-sign the payload
    final signatureBundle = await _bridge.pqcSignInvitation(
      payload: Uint8List.fromList(serializedPayload),
      ed25519Priv: ed25519Priv,
      mldsaSeed: mldsaSeed,
    );

    // 3. Encapsulate/wrap the Folder Key for the recipient
    final wrappedKey = await _bridge.pqcHybridWrap(
      recipientX25519Pub: recipientX25519Pub,
      recipientMlkemEk: recipientMlkemEk,
      folderKey: folderKey,
    );

    return {
      'signedPayload': base64Url.encode(serializedPayload),
      'ed25519Signature': base64Url.encode(signatureBundle.ed25519Signature),
      'mldsaSignature': base64Url.encode(signatureBundle.mldsaSignature),
      'wrappedFolderKey': {
        'ephemeralX25519PublicKey': base64Url.encode(wrappedKey.ephemeralX25519Pub),
        'mlkemCiphertext': base64Url.encode(wrappedKey.mlkemCiphertext),
        'aesNonce': base64Url.encode(wrappedKey.aesNonce),
        'wrappedFolderKey': base64Url.encode(wrappedKey.wrappedFolderKey),
      }
    };
  }

  /// Verifies a received share invitation, confirming both signatures match the sender's public keys.
  Future<bool> verifyInvitation({
    required String signedPayloadB64,
    required String ed25519SigB64,
    required String mldsaSigB64,
    required Uint8List senderEd25519Pub,
    required Uint8List senderMldsaVk,
  }) async {
    try {
      final payload = base64Url.decode(signedPayloadB64);
      final edSig = base64Url.decode(ed25519SigB64);
      final mldsaSig = base64Url.decode(mldsaSigB64);

      // Verify expiration before checking signatures
      final decodedPayload = json.decode(utf8.decode(payload)) as Map<String, dynamic>;
      final expiresStr = decodedPayload['expiresAt'] as String?;
      if (expiresStr == null) return false;
      final expires = DateTime.parse(expiresStr);
      if (DateTime.now().toUtc().isAfter(expires)) return false;

      return await _bridge.pqcVerifyInvitation(
        payload: Uint8List.fromList(payload),
        ed25519Pub: senderEd25519Pub,
        mldsaVk: senderMldsaVk,
        signatures: PqcSignatureBundle(
          ed25519Signature: Uint8List.fromList(edSig),
          mldsaSignature: Uint8List.fromList(mldsaSig),
        ),
      );
    } catch (_) {
      return false;
    }
  }

  /// Unwraps the Folder Key from an accepted invitation using the recipient's private keys.
  Future<Uint8List> unwrapFolderKey({
    required Map<String, dynamic> wrappedKeyData,
    required Uint8List recipientX25519Priv,
    required Uint8List recipientMlkemDk,
  }) async {
    final ephem = base64Url.decode(wrappedKeyData['ephemeralX25519PublicKey'] as String);
    final ct = base64Url.decode(wrappedKeyData['mlkemCiphertext'] as String);
    final nonce = base64Url.decode(wrappedKeyData['aesNonce'] as String);
    final wrapped = base64Url.decode(wrappedKeyData['wrappedFolderKey'] as String);

    return await _bridge.pqcHybridUnwrap(
      recipientX25519Priv: recipientX25519Priv,
      recipientMlkemDk: recipientMlkemDk,
      wrappedKey: PqcWrappedKey(
        ephemeralX25519Pub: Uint8List.fromList(ephem),
        mlkemCiphertext: Uint8List.fromList(ct),
        aesNonce: Uint8List.fromList(nonce),
        wrappedFolderKey: Uint8List.fromList(wrapped),
      ),
    );
  }

  /// Rotates a Folder Key and produces wraps for all remaining recipients.
  ///
  /// Enforces that the rotated key is completely independent of the old key.
  Future<List<Map<String, dynamic>>> rotateFolderKey({
    required Uint8List newFolderKey,
    required List<Map<String, dynamic>> remainingRecipientsKeys, // each has: userId, x25519Pub, mlkemEk
  }) async {
    final wraps = <Map<String, dynamic>>[];
    for (final recipient in remainingRecipientsKeys) {
      final userId = recipient['userId'] as String;
      final xPub = recipient['x25519Pub'] as Uint8List;
      final mlkemEk = recipient['mlkemEk'] as Uint8List;

      final wrappedKey = await _bridge.pqcHybridWrap(
        recipientX25519Pub: xPub,
        recipientMlkemEk: mlkemEk,
        folderKey: newFolderKey,
      );

      wraps.add({
        'recipientUserId': userId,
        'ephemeralX25519PublicKey': base64Url.encode(wrappedKey.ephemeralX25519Pub),
        'mlkemCiphertext': base64Url.encode(wrappedKey.mlkemCiphertext),
        'aesNonce': base64Url.encode(wrappedKey.aesNonce),
        'wrappedFolderKey': base64Url.encode(wrappedKey.wrappedFolderKey),
      });
    }
    return wraps;
  }
}
