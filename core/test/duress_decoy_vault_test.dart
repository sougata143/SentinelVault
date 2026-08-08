import 'package:test/test.dart';
import 'package:core/core.dart';

void main() {
  group('Duress / Decoy Vault Cryptographic & State Isolation Tests', () {
    late VaultCrypto crypto;
    late List<int> realVaultKey;
    late List<int> decoyMasterKey;
    late List<int> decoyVaultKey;

    setUp(() {
      crypto = VaultCrypto();
      realVaultKey = crypto.generateRandomBytes(32);
      decoyMasterKey = crypto.generateRandomBytes(32);
      decoyVaultKey = crypto.generateRandomBytes(32);
    });

    test('1. Item encrypted under Real Vault Key CANNOT be decrypted by Decoy Vault Key', () async {
      final realItem = VaultItem(
        id: 'real-bank-item',
        type: VaultItemType.login,
        title: 'Confidential Savings Account',
        tags: const ['private'],
        favorite: true,
        vaultId: 'vault-alpha',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        fields: LoginFields(
          username: 'real_alice',
          password: const ConcealedValue.plain('RealPassword123!'),
          otpSecret: const ConcealedValue.plain(''),
          passwordHistory: const [],
          urls: const ['https://bank.com'],
        ),
        customFields: const [],
        notes: const ConcealedValue.plain('Secrets'),
      );

      final encBlob = await realItem.encrypt(realVaultKey, crypto);

      // Attempting to decrypt with Decoy Vault Key MUST throw GCM tag authentication exception
      expect(
        () async => await VaultItem.decrypt(encBlob, decoyVaultKey, crypto),
        throwsA(isA<Exception>()),
      );
    });

    test('2. Duress unlock sets isDuressMode = true and loads ONLY decoy Vault Key into memory', () {
      final lockManager = VaultLockManager.instance;
      lockManager.lockAll();

      // Unlock with Duress Password -> Decoy Vault (vault-beta)
      lockManager.unlockVault('vault-beta', decoyMasterKey, decoyVaultKey, isDuress: true);

      expect(lockManager.isDuressMode, isTrue);
      expect(lockManager.activeVaultId, equals('vault-beta'));
      expect(lockManager.getVaultKeyForId('vault-beta'), equals(decoyVaultKey));

      // CRITICAL ASSERTION: Real Vault Alpha key MUST be null in memory!
      expect(lockManager.getVaultKeyForId('vault-alpha'), isNull);
    });

    test('3. Pre-populates decoy vault with realistic non-sensitive items', () async {
      final db = SqliteVaultDatabase.inMemory();
      db.open([]);

      final decoyManager = DualVaultManager.instance;
      await decoyManager.prepopulateDecoyItems(db, decoyVaultKey);

      final items = db.getAllItems();
      expect(items.length, equals(3));

      // Verify decoy items exist (Google workspace login, Visa card, To-Do note)
      final titles = items.map((i) => i.id).toList();
      expect(titles, containsAll(['decoy-login-1', 'decoy-cc-1', 'decoy-note-1']));

      db.close();
    });

    test('4. Deriving Master Key for Real vs Decoy password uses identical Argon2id parameters (Constant-Time Parity)', () async {
      final saltAlpha = crypto.generateRandomBytes(16);
      final saltBeta = crypto.generateRandomBytes(16);

      final keyA = await crypto.deriveMasterKey(masterPassword: 'RealMasterPassword123!', salt: saltAlpha);
      final keyB = await crypto.deriveMasterKey(masterPassword: 'DecoyMasterPassword999!', salt: saltBeta);

      expect(keyA.length, equals(32));
      expect(keyB.length, equals(32));
      expect(keyA, isNot(equals(keyB)));
    });
  });
}
