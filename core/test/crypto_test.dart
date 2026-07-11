import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:core/core.dart';

void main() {
  group('VaultCrypto Tests', () {
    late VaultCrypto crypto;
    late List<int> masterKey;
    late List<int> salt;

    setUp(() async {
      crypto = VaultCrypto();
      salt = List.generate(16, (i) => i);
      masterKey = await crypto.deriveMasterKey(
        masterPassword: 'test_master_password',
        salt: salt,
      );
    });

    test('Argon2id Master Key Derivation', () async {
      expect(masterKey.length, equals(32)); // 256 bits

      // Key derivation with the same inputs should produce the same key
      final key2 = await crypto.deriveMasterKey(
        masterPassword: 'test_master_password',
        salt: salt,
      );
      expect(key2, equals(masterKey));

      // Key derivation with different password should produce a different key
      final key3 = await crypto.deriveMasterKey(
        masterPassword: 'test_master_password_different',
        salt: salt,
      );
      expect(key3, isNot(equals(masterKey)));

      // Key derivation with different salt should produce a different key
      final differentSalt = List.generate(16, (i) => i + 1);
      final key4 = await crypto.deriveMasterKey(
        masterPassword: 'test_master_password',
        salt: differentSalt,
      );
      expect(key4, isNot(equals(masterKey)));
    });

    test('AES-256-GCM Encrypt/Decrypt Round-trip', () async {
      final plaintext = utf8.encode('Top secret vault credentials 123!');
      final nonce = crypto.generateRandomBytes(12);

      // Encrypt
      final encryptedBlob = await crypto.encryptAesGcm(
        plaintext: plaintext,
        key: masterKey,
        nonce: nonce,
      );

      // Decrypt
      final decryptedBytes = await crypto.decryptAesGcm(
        ciphertextAndMac: encryptedBlob,
        key: masterKey,
        nonce: nonce,
      );

      expect(utf8.decode(decryptedBytes), equals('Top secret vault credentials 123!'));
    });

    test('Ciphertext Tampering Causes Authentication Failure', () async {
      final plaintext = utf8.encode('Secret data');
      final nonce = crypto.generateRandomBytes(12);

      final encryptedBlob = await crypto.encryptAesGcm(
        plaintext: plaintext,
        key: masterKey,
        nonce: nonce,
      );

      // Create a mutable copy of the blob
      final tamperedBlob = Uint8List.fromList(encryptedBlob);

      // Tamper with the ciphertext (e.g. flip a bit in the first byte)
      tamperedBlob[0] = tamperedBlob[0] ^ 1;

      expect(
        () => crypto.decryptAesGcm(
          ciphertextAndMac: tamperedBlob,
          key: masterKey,
          nonce: nonce,
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );

      // Create another copy and tamper with the MAC (last 16 bytes of the blob)
      final tamperedMacBlob = Uint8List.fromList(encryptedBlob);
      final lastIndex = tamperedMacBlob.length - 1;
      tamperedMacBlob[lastIndex] = tamperedMacBlob[lastIndex] ^ 1;

      expect(
        () => crypto.decryptAesGcm(
          ciphertextAndMac: tamperedMacBlob,
          key: masterKey,
          nonce: nonce,
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('Vault Key Wrapping and Unwrapping', () async {
      final vaultKey = crypto.generateRandomBytes(32); // Random 256-bit Vault Key

      // Wrap
      final wrappedVaultKey = await crypto.wrapVaultKey(
        vaultKey: vaultKey,
        masterKey: masterKey,
      );

      // Expected length: 12 (nonce) + 16 (MAC) + 32 (ciphertext) = 60 bytes
      expect(wrappedVaultKey.length, equals(60));

      // Unwrap
      final unwrappedKey = await crypto.unwrapVaultKey(
        wrappedVaultKey: wrappedVaultKey,
        masterKey: masterKey,
      );

      expect(unwrappedKey, equals(vaultKey));

      // Tampering with the wrapped vault key should cause authentication failure
      final tamperedWrappedKey = Uint8List.fromList(wrappedVaultKey);
      tamperedWrappedKey[15] = tamperedWrappedKey[15] ^ 1; // Flip a bit in ciphertext/MAC area

      expect(
        () => crypto.unwrapVaultKey(
          wrappedVaultKey: tamperedWrappedKey,
          masterKey: masterKey,
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('Nonce Uniqueness Across 1000+ Calls', () {
      final nonces = <String>{};
      const count = 1050;

      for (var i = 0; i < count; i++) {
        final nonce = crypto.generateRandomBytes(12);
        expect(nonce.length, equals(12));
        
        final hexString = nonce.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        nonces.add(hexString);
      }

      // Check that all generated nonces are unique (i.e. size of set matches count)
      expect(nonces.length, equals(count));
    });

    test('Recovery Key Generation, Decoding and Round-Trip', () async {
      final key = crypto.generateRecoveryKey();
      
      // Match the pattern XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX (8 groups of 4 chars separated by dashes)
      final regExp = RegExp(r'^[A-Z2-7]{4}-[A-Z2-7]{4}-[A-Z2-7]{4}-[A-Z2-7]{4}-[A-Z2-7]{4}-[A-Z2-7]{4}-[A-Z2-7]{4}-[A-Z2-7]{4}$');
      expect(regExp.hasMatch(key), isTrue);

      final decoded = crypto.decodeRecoveryKey(key);
      expect(decoded.length, equals(20)); // 160 bits

      // Generating a new key should be random
      final key2 = crypto.generateRecoveryKey();
      expect(key2, isNot(equals(key)));

      // Recovery Key wrapping/unwrapping roundtrip
      final vaultKey = crypto.generateRandomBytes(32);
      final rkSalt = crypto.generateRandomBytes(16);
      
      final rkk = await crypto.deriveRecoveryKdfKey(
        recoveryKey: key,
        salt: rkSalt,
      );
      expect(rkk.length, equals(32));

      final wrapped = await crypto.wrapVaultKey(
        vaultKey: vaultKey,
        masterKey: rkk,
      );

      final unwrapped = await crypto.unwrapVaultKey(
        wrappedVaultKey: wrapped,
        masterKey: rkk,
      );
      expect(unwrapped, equals(vaultKey));
    });
  });
}
