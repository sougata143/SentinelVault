import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:core/src/crypto/native_crypto_bridge_selector.dart';
import 'package:core/src/crypto/pqc_sharing.dart';
import 'package:core/src/crypto/native_crypto_bridge.dart';

void main() {
  setUpAll(() async {
    await ensureWasmReady();
  });

  group('PQC Sharing Cross-User Isolation (3-Account Negative Case)', () {
    late NativeCryptoBridge bridge;
    late PqcSharingManager sharing;

    setUp(() {
      bridge = getNativeCryptoBridge();
      sharing = PqcSharingManager(bridge);
    });

    test('Shared item wrapped from Account 1 to Account 2 cannot be decrypted by Account 3', () async {
      // Account 1: test-a@sentinelvault.local (Sender)
      final account1 = await bridge.pqcGenerateKeypairs();
      const account1UserId = 'test-a@sentinelvault.local';

      // Account 2: test-b@sentinelvault.local (Authorized Recipient)
      final account2 = await bridge.pqcGenerateKeypairs();
      const account2UserId = 'test-b@sentinelvault.local';

      // Account 3: test-a@sentinelvault.local (Uninvited Third Party)
      final account3 = await bridge.pqcGenerateKeypairs();

      // 1. Account 1 generates a 32-byte secret Folder Key
      final folderKey = Uint8List.fromList(List.generate(32, (i) => i ^ 0x55));

      // 2. Account 1 creates a signed invitation & wrapped key for Account 2 ONLY
      final invite = await sharing.createSignedInvitation(
        folderId: 'folder-uuid-12345',
        recipientUserId: account2UserId,
        senderUserId: account1UserId,
        ed25519Priv: account1.ed25519Priv,
        mldsaSeed: account1.mldsaSeed,
        folderKey: folderKey,
        recipientX25519Pub: account2.x25519Pub,
        recipientMlkemEk: account2.mlkemEk,
      );

      // 3. Positive verification: Account 2 accepts invite and successfully unwraps Folder Key
      final isVerifiedForAccount2 = await sharing.verifyInvitation(
        signedPayloadB64: invite['signedPayload'] as String,
        ed25519SigB64: invite['ed25519Signature'] as String,
        mldsaSigB64: invite['mldsaSignature'] as String,
        senderEd25519Pub: account1.ed25519Pub,
        senderMldsaVk: account1.mldsaVk,
      );
      expect(isVerifiedForAccount2, isTrue);

      final recoveredFolderKeyByAccount2 = await sharing.unwrapFolderKey(
        wrappedKeyData: invite['wrappedFolderKey'] as Map<String, dynamic>,
        recipientX25519Priv: account2.x25519Priv,
        recipientMlkemDk: account2.mlkemDk,
      );
      expect(recoveredFolderKeyByAccount2, equals(folderKey));

      // 4. Negative verification: Account 3 (test-a@sentinelvault.local) attempts to unwrap Account 2's wrapped key payload
      expect(
        () => sharing.unwrapFolderKey(
          wrappedKeyData: invite['wrappedFolderKey'] as Map<String, dynamic>,
          recipientX25519Priv: account3.x25519Priv,
          recipientMlkemDk: account3.mlkemDk,
        ),
        throwsA(anything),
        reason: 'Account 3 (uninvited) must not be able to decrypt Folder Key wrapped for Account 2',
      );
    });
  });
}
