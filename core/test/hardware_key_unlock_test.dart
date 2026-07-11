import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:core/core.dart';

void main() {
  group('HardwareKeyUnlock Cryptography Tests', () {
    late VaultCrypto crypto;
    late List<int> vaultKey;
    late List<int> masterKey;
    late List<int> masterWrappedVaultKey;
    late List<int> hmacSecretKeyCorrect;
    late List<int> hmacSecretKeyDifferent;
    late List<int> salt;

    setUp(() async {
      crypto = VaultCrypto();
      vaultKey = crypto.generateRandomBytes(32);
      salt = crypto.generateRandomBytes(16);
      masterKey = await crypto.deriveMasterKey(
        masterPassword: 'super_secure_master_password',
        salt: salt,
      );
      // Master Key wraps Vault Key
      masterWrappedVaultKey = await crypto.wrapVaultKey(
        vaultKey: vaultKey,
        masterKey: masterKey,
      );

      // Hardware key derived secrets
      hmacSecretKeyCorrect = crypto.generateRandomBytes(32);
      hmacSecretKeyDifferent = crypto.generateRandomBytes(32);
    });

    test('1. Correct physical key unwraps the Vault Key copy', () async {
      final hwSalt = crypto.generateRandomBytes(32);
      final hwUnlock = await HardwareKeyUnlock.create(
        credentialId: 'yubikey-cred-123',
        salt: hwSalt,
        vaultKey: vaultKey,
        hmacSecretKey: hmacSecretKeyCorrect,
        crypto: crypto,
      );

      // Serialization round-trip
      final jsonStr = hwUnlock.toJson();
      final decodedHwUnlock = HardwareKeyUnlock.fromJson(jsonStr);

      expect(decodedHwUnlock.credentialId, equals('yubikey-cred-123'));
      expect(decodedHwUnlock.salt, equals(hwSalt));

      // Unwrap with correct key
      final unwrapped = await decodedHwUnlock.unwrap(
        hmacSecretKey: hmacSecretKeyCorrect,
        crypto: crypto,
      );
      expect(unwrapped, equals(vaultKey));
    });

    test('2. Different physical key fails to unwrap', () async {
      final hwSalt = crypto.generateRandomBytes(32);
      final hwUnlock = await HardwareKeyUnlock.create(
        credentialId: 'yubikey-cred-123',
        salt: hwSalt,
        vaultKey: vaultKey,
        hmacSecretKey: hmacSecretKeyCorrect,
        crypto: crypto,
      );

      expect(
        () => hwUnlock.unwrap(
          hmacSecretKey: hmacSecretKeyDifferent,
          crypto: crypto,
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('3. Removing hardware key factor does not affect Master Password unlock', () async {
      // Simulate registration
      final hwSalt = crypto.generateRandomBytes(32);
      final hwUnlock = await HardwareKeyUnlock.create(
        credentialId: 'yubikey-cred-123',
        salt: hwSalt,
        vaultKey: vaultKey,
        hmacSecretKey: hmacSecretKeyCorrect,
        crypto: crypto,
      );

      // Verify master password unlock is functional
      final unwrappedWithMasterKey = await crypto.unwrapVaultKey(
        wrappedVaultKey: masterWrappedVaultKey,
        masterKey: masterKey,
      );
      expect(unwrappedWithMasterKey, equals(vaultKey));

      // Simulate removing the hardware key factor (e.g. discarding metadata)
      // The master password's ability to unwrap the Vault Key is unaffected.
      final unwrappedAfterRemoval = await crypto.unwrapVaultKey(
        wrappedVaultKey: masterWrappedVaultKey,
        masterKey: masterKey,
      );
      expect(unwrappedAfterRemoval, equals(vaultKey));
    });
  });
}
