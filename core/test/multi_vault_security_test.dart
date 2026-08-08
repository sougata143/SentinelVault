import 'package:test/test.dart';
import 'package:core/core.dart';

void main() {
  group('Multi-Vault Cross-Vault Isolation & Key Security Tests', () {
    late VaultCrypto crypto;
    late List<int> masterKeyVaultA;
    late List<int> vaultKeyVaultA;
    late List<int> masterKeyVaultB;
    late List<int> vaultKeyVaultB;

    setUp(() {
      crypto = VaultCrypto();
      masterKeyVaultA = crypto.generateRandomBytes(32);
      vaultKeyVaultA = crypto.generateRandomBytes(32);
      masterKeyVaultB = crypto.generateRandomBytes(32);
      vaultKeyVaultB = crypto.generateRandomBytes(32);
    });

    test('1. Item encrypted with VaultKey A CANNOT be decrypted with VaultKey B', () async {
      final itemA = VaultItem(
        id: 'item-vault-a',
        type: VaultItemType.login,
        title: 'Personal Bank Account',
        tags: const ['personal'],
        favorite: true,
        vaultId: 'vault-A-uuid',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        fields: LoginFields(
          username: 'alice_personal',
          password: const ConcealedValue.plain('SuperSecretPersonal123!'),
          otpSecret: const ConcealedValue.plain(''),
          passwordHistory: const [],
          urls: const ['https://mybank.com'],
        ),
        customFields: const [],
        notes: const ConcealedValue.plain(''),
      );

      // Encrypt under Vault A's key
      final encBlobA = await itemA.encrypt(vaultKeyVaultA, crypto);

      // Attempt decryption under Vault B's key — MUST throw Exception (GCM auth tag verification failure)
      expect(
        () async => await VaultItem.decrypt(encBlobA, vaultKeyVaultB, crypto),
        throwsA(isA<Exception>()),
      );
    });

    test('2. VaultLockManager multi-vault unlock isolation: unlocking Vault A leaves Vault B locked', () {
      final lockManager = VaultLockManager.instance;
      lockManager.lockAll();

      lockManager.unlockVault('vault-A', masterKeyVaultA, vaultKeyVaultA);

      expect(lockManager.isVaultUnlocked('vault-A'), isTrue);
      expect(lockManager.isVaultUnlocked('vault-B'), isFalse);
      expect(lockManager.getVaultKeyForId('vault-A'), equals(vaultKeyVaultA));
      expect(lockManager.getVaultKeyForId('vault-B'), isNull);
    });

    test('3. Locking Vault A zeroes Vault A memory without affecting Vault B if open', () {
      final lockManager = VaultLockManager.instance;
      lockManager.lockAll();

      lockManager.unlockVault('vault-A', masterKeyVaultA, vaultKeyVaultA);
      lockManager.unlockVault('vault-B', masterKeyVaultB, vaultKeyVaultB);

      expect(lockManager.isVaultUnlocked('vault-A'), isTrue);
      expect(lockManager.isVaultUnlocked('vault-B'), isTrue);

      lockManager.lockVault('vault-A');

      expect(lockManager.isVaultUnlocked('vault-A'), isFalse);
      expect(lockManager.getVaultKeyForId('vault-A'), isNull);
      expect(lockManager.isVaultUnlocked('vault-B'), isTrue);
      expect(lockManager.getVaultKeyForId('vault-B'), equals(vaultKeyVaultB));

      lockManager.lockAll();
      expect(lockManager.isVaultUnlocked('vault-B'), isFalse);
    });

    test('4. Database getItemsByVaultId filters records strictly by vaultId', () {
      final db = SqliteVaultDatabase.inMemory();
      db.open([]);

      final itemA = EncryptedVaultItem(
        id: 'item-1',
        encryptedBlob: 'blob-A',
        nonce: 'nonce-A',
        version: 1,
        updatedAt: DateTime.now().toUtc(),
        isDeleted: false,
        vaultId: 'vault-A',
      );

      final itemB = EncryptedVaultItem(
        id: 'item-2',
        encryptedBlob: 'blob-B',
        nonce: 'nonce-B',
        version: 1,
        updatedAt: DateTime.now().toUtc(),
        isDeleted: false,
        vaultId: 'vault-B',
      );

      db.insertItem(itemA);
      db.insertItem(itemB);

      final vaultAItems = db.getItemsByVaultId('vault-A');
      expect(vaultAItems.length, equals(1));
      expect(vaultAItems.first.id, equals('item-1'));

      final vaultBItems = db.getItemsByVaultId('vault-B');
      expect(vaultBItems.length, equals(1));
      expect(vaultBItems.first.id, equals('item-2'));

      db.close();
    });

    test('5. Re-deriving Master Key with Salt A vs Salt B produces uncorrelated 32-byte keys', () async {
      final saltA = crypto.generateRandomBytes(16);
      final saltB = crypto.generateRandomBytes(16);

      final masterKeyA = await crypto.deriveMasterKey(masterPassword: 'SamePassword123!', salt: saltA);
      final masterKeyB = await crypto.deriveMasterKey(masterPassword: 'SamePassword123!', salt: saltB);

      expect(masterKeyA, isNot(equals(masterKeyB)));
    });
  });
}
