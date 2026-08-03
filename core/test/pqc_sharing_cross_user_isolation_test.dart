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

    test('Shared item wrapped from Account 1 to Account 2 is visible to Account 2 but NOT Account 3', () async {
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

      // 3. POSITIVE VERIFICATION: Intended recipient (Account 2 - test-b) accepts & unwraps
      final isVerifiedForAccount2 = await sharing.verifyInvitation(
        signedPayloadB64: invite['signedPayload'] as String,
        ed25519SigB64: invite['ed25519Signature'] as String,
        mldsaSigB64: invite['mldsaSignature'] as String,
        senderEd25519Pub: account1.ed25519Pub,
        senderMldsaVk: account1.mldsaVk,
      );
      expect(isVerifiedForAccount2, isTrue, reason: 'Legitimate recipient test-b must pass signature verification');

      final recoveredFolderKeyByAccount2 = await sharing.unwrapFolderKey(
        wrappedKeyData: invite['wrappedFolderKey'] as Map<String, dynamic>,
        recipientX25519Priv: account2.x25519Priv,
        recipientMlkemDk: account2.mlkemDk,
      );
      expect(recoveredFolderKeyByAccount2, equals(folderKey), reason: 'Legitimate recipient test-b must be able to decrypt the Folder Key');

      // 4. NEGATIVE VERIFICATION: Uninvited third party (Account 3 - test-a@sentinelvault.local) attempts unwrap
      expect(
        () => sharing.unwrapFolderKey(
          wrappedKeyData: invite['wrappedFolderKey'] as Map<String, dynamic>,
          recipientX25519Priv: account3.x25519Priv,
          recipientMlkemDk: account3.mlkemDk,
        ),
        throwsA(anything),
        reason: 'Account 3 (test-a@sentinelvault.local - uninvited) MUST NOT be able to decrypt Folder Key wrapped for test-b',
      );
    });

    test('Rotated Folder Key remains accessible to remaining recipients but fails for revoked recipient', () async {
      // Account 1: Owner
      final account1 = await bridge.pqcGenerateKeypairs();
      // Account 2: Remaining recipient (Bob)
      final account2 = await bridge.pqcGenerateKeypairs();
      // Account 3: Revoked recipient (Charlie)
      final account3 = await bridge.pqcGenerateKeypairs();

      final rotatedFolderKey = Uint8List.fromList(List.generate(32, (i) => i ^ 0xAA));

      // Re-wrap rotated folder key for Owner (account1) and remaining recipient (Bob)
      final rotatedWraps = await sharing.rotateFolderKey(
        newFolderKey: rotatedFolderKey,
        remainingRecipientsKeys: [
          {
            'userId': 'owner@sentinelvault.local',
            'x25519Pub': account1.x25519Pub,
            'mlkemEk': account1.mlkemEk,
          },
          {
            'userId': 'bob@sentinelvault.local',
            'x25519Pub': account2.x25519Pub,
            'mlkemEk': account2.mlkemEk,
          },
        ],
      );

      // Owner (account1) can decrypt rotated key
      final ownerWrap = rotatedWraps.firstWhere((w) => w['recipientUserId'] == 'owner@sentinelvault.local');
      final ownerRecovered = await sharing.unwrapFolderKey(
        wrappedKeyData: ownerWrap,
        recipientX25519Priv: account1.x25519Priv,
        recipientMlkemDk: account1.mlkemDk,
      );
      expect(ownerRecovered, equals(rotatedFolderKey), reason: 'Owner Account 1 must be able to decrypt rotated Folder Key');

      final bobWrap = rotatedWraps.firstWhere((w) => w['recipientUserId'] == 'bob@sentinelvault.local');

      // Bob (remaining recipient) can decrypt rotated key
      final bobRecovered = await sharing.unwrapFolderKey(
        wrappedKeyData: bobWrap,
        recipientX25519Priv: account2.x25519Priv,
        recipientMlkemDk: account2.mlkemDk,
      );
      expect(bobRecovered, equals(rotatedFolderKey), reason: 'Remaining recipient Bob must be able to decrypt rotated Folder Key');

      // Charlie (revoked recipient) cannot decrypt Bob's wrapped key
      expect(
        () => sharing.unwrapFolderKey(
          wrappedKeyData: bobWrap,
          recipientX25519Priv: account3.x25519Priv,
          recipientMlkemDk: account3.mlkemDk,
        ),
        throwsA(anything),
        reason: 'Revoked recipient Charlie MUST NOT be able to decrypt rotated Folder Key wrapped for Bob',
      );
    });
  });
}
