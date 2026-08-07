import 'package:test/test.dart';
import 'package:core/core.dart';

void main() {
  group('PasskeyVaultItem & PasskeyFields Unit Tests', () {
    final crypto = VaultCrypto();

    test('1. PasskeyVaultItem serialization and sign count increment round-trip', () {
      final item = PasskeyVaultItem(
        rpId: 'github.com',
        userHandle: 'user-handle-123',
        userName: 'dev@sentinelvault.io',
        credentialId: 'cred-id-abc-789',
        privateKeyPem: const ConcealedValue.plain('-----BEGIN EC PRIVATE KEY-----\nMIG...\n-----END EC PRIVATE KEY-----'),
        publicKeyRaw: 'BA123...',
        cosePublicKey: 'pKV...',
        signCount: 5,
        createdAt: DateTime.utc(2026, 8, 7, 12, 0, 0),
      );

      final json = item.toJson();
      final parsed = PasskeyVaultItem.fromJson(json);

      expect(parsed.rpId, equals('github.com'));
      expect(parsed.userHandle, equals('user-handle-123'));
      expect(parsed.userName, equals('dev@sentinelvault.io'));
      expect(parsed.credentialId, equals('cred-id-abc-789'));
      expect(parsed.signCount, equals(5));
      expect(parsed.privateKeyPem.plaintext, contains('EC PRIVATE KEY'));

      final updated = parsed.incrementSignCount();
      expect(updated.signCount, equals(6));
      expect(updated.lastUsedAt, isNotNull);
    });

    test('2. Encrypt and decrypt VaultItem containing PasskeyFields', () async {
      final vaultKey = crypto.generateRandomBytes(32);

      final fields = PasskeyFields(
        rpId: 'google.com',
        userHandle: 'user-google-456',
        userName: 'alice@google.com',
        credentialId: 'cred-google-789',
        privateKeyPem: const ConcealedValue.plain('secret_private_key_pem_data'),
        publicKeyRaw: 'pub_key_bytes',
        cosePublicKey: 'cose_bytes',
        signCount: 1,
      );

      final vaultItem = VaultItem(
        id: 'passkey-item-uuid-1',
        type: VaultItemType.passkey,
        title: 'Google Passkey',
        tags: ['passkey', 'work'],
        favorite: true,
        vaultId: 'main-vault',
        createdAt: DateTime.utc(2026, 8, 7, 10, 0, 0),
        updatedAt: DateTime.utc(2026, 8, 7, 10, 0, 0),
        fields: fields,
        customFields: const [],
        notes: const ConcealedValue.plain('Google Account Passkey'),
      );

      final encrypted = await vaultItem.encrypt(vaultKey, crypto);
      expect(encrypted.encryptedBlob, isNotEmpty);

      final decrypted = await VaultItem.decrypt(encrypted, vaultKey, crypto);
      expect(decrypted.type, equals(VaultItemType.passkey));
      expect(decrypted.title, equals('Google Passkey'));

      final decryptedPasskeyFields = decrypted.fields as PasskeyFields;
      expect(decryptedPasskeyFields.rpId, equals('google.com'));
      expect(decryptedPasskeyFields.privateKeyPem.plaintext, equals('secret_private_key_pem_data'));
    });
  });
}
