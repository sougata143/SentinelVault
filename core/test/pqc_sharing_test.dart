import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:core/src/crypto/native_crypto_bridge_selector.dart';
import 'package:core/src/crypto/pqc_sharing.dart';
import 'package:core/src/crypto/native_crypto_bridge.dart';

void main() {
  group('PqcSharingManager Tests', () {
    late NativeCryptoBridge bridge;
    late PqcSharingManager sharing;

    setUp(() {
      bridge = getNativeCryptoBridge();
      sharing = PqcSharingManager(bridge);
    });

    test('Key Generation, Fingerprint, Wrap and Unwrap Round-trip', () async {
      // 1. Generate keypairs for Alice and Bob
      final alice = await bridge.pqcGenerateKeypairs();
      final bob = await bridge.pqcGenerateKeypairs();

      expect(alice.x25519Pub.length, equals(32));
      expect(alice.x25519Priv.length, equals(32));
      expect(alice.ed25519Pub.length, equals(32));
      expect(alice.ed25519Priv.length, equals(32));
      expect(alice.mlkemEk.length, equals(1184));
      expect(alice.mlkemDk.length, equals(2400));
      expect(alice.mldsaVk.length, equals(1952));
      expect(alice.mldsaSeed.length, equals(32));

      // 2. Compute safety numbers (fingerprints)
      final aliceFP = await sharing.computeSafetyNumber(alice);
      final bobFP = await sharing.computeSafetyNumber(bob);
      
      expect(aliceFP, isNotEmpty);
      expect(bobFP, isNotEmpty);
      expect(aliceFP.split(' '), hasLength(10)); // 10 groups of 5 digits

      // 3. Generate Folder Key (32 bytes)
      final folderKey = Uint8List.fromList(List.generate(32, (i) => i));

      // 4. Create signed invitation from Alice to Bob
      final invite = await sharing.createSignedInvitation(
        folderId: '00000000-0000-0000-0000-000000000001',
        recipientUserId: 'bob-id',
        senderUserId: 'alice-id',
        ed25519Priv: alice.ed25519Priv,
        mldsaSeed: alice.mldsaSeed,
        folderKey: folderKey,
        recipientX25519Pub: bob.x25519Pub,
        recipientMlkemEk: bob.mlkemEk,
      );

      expect(invite['signedPayload'], isNotEmpty);
      expect(invite['ed25519Signature'], isNotEmpty);
      expect(invite['mldsaSignature'], isNotEmpty);
      expect(invite['wrappedFolderKey'], isNotNull);

      // 5. Verify invitation
      final verified = await sharing.verifyInvitation(
        signedPayloadB64: invite['signedPayload'] as String,
        ed25519SigB64: invite['ed25519Signature'] as String,
        mldsaSigB64: invite['mldsaSignature'] as String,
        senderEd25519Pub: alice.ed25519Pub,
        senderMldsaVk: alice.mldsaVk,
      );

      expect(verified, isTrue);

      // 6. Unwrap Folder Key by Bob
      final recoveredKey = await sharing.unwrapFolderKey(
        wrappedKeyData: invite['wrappedFolderKey'] as Map<String, dynamic>,
        recipientX25519Priv: bob.x25519Priv,
        recipientMlkemDk: bob.mlkemDk,
      );

      expect(recoveredKey, equals(folderKey));
    });

    test('Verification Fails on Tampered Invitation Payload', () async {
      final alice = await bridge.pqcGenerateKeypairs();
      final bob = await bridge.pqcGenerateKeypairs();
      final folderKey = Uint8List.fromList(List.generate(32, (i) => i + 10));

      final invite = await sharing.createSignedInvitation(
        folderId: '00000000-0000-0000-0000-000000000001',
        recipientUserId: 'bob-id',
        senderUserId: 'alice-id',
        ed25519Priv: alice.ed25519Priv,
        mldsaSeed: alice.mldsaSeed,
        folderKey: folderKey,
        recipientX25519Pub: bob.x25519Pub,
        recipientMlkemEk: bob.mlkemEk,
      );

      // Tamper with payload (substitute one char in base64url)
      final rawPayload = invite['signedPayload'] as String;
      final tamperedPayload = rawPayload.endsWith('A')
          ? rawPayload.substring(0, rawPayload.length - 1) + 'B'
          : rawPayload.substring(0, rawPayload.length - 1) + 'A';

      final verified = await sharing.verifyInvitation(
        signedPayloadB64: tamperedPayload,
        ed25519SigB64: invite['ed25519Signature'] as String,
        mldsaSigB64: invite['mldsaSignature'] as String,
        senderEd25519Pub: alice.ed25519Pub,
        senderMlkemVk: alice.mldsaVk,
      );

      expect(verified, isFalse);
    });

    test('Rotation wraps correctly for remaining recipients', () async {
      final alice = await bridge.pqcGenerateKeypairs();
      final bob = await bridge.pqcGenerateKeypairs();
      final charlie = await bridge.pqcGenerateKeypairs();

      // Alice rotates to a new Folder Key
      final newFolderKey = Uint8List.fromList(List.generate(32, (i) => i * 2));

      // Bob remains, Charlie is revoked (so we only wrap for Bob)
      final remaining = [
        {
          'userId': 'bob-id',
          'x25519Pub': bob.x25519Pub,
          'mlkemEk': bob.mlkemEk,
        }
      ];

      final wraps = await sharing.rotateFolderKey(
        newFolderKey: newFolderKey,
        remainingRecipientsKeys: remaining,
      );

      expect(wraps, hasLength(1));
      expect(wraps[0]['recipientUserId'], equals('bob-id'));

      // Bob can unwrap the new version
      final recovered = await sharing.unwrapFolderKey(
        wrappedKeyData: wraps[0],
        recipientX25519Priv: bob.x25519Priv,
        recipientMlkemDk: bob.mlkemDk,
      );

      expect(recovered, equals(newFolderKey));

      // Charlie cannot unwrap (he has no wrapped copy under new version)
      expect(
        () => sharing.unwrapFolderKey(
          wrappedKeyData: wraps[0], // Bob's wrapped key data
          recipientX25519Priv: charlie.x25519Priv, // Charlie's private key
          recipientMlkemDk: charlie.mlkemDk,
        ),
        throwsArgumentError, // AEAD tag fails
      );
    });
  });
}
