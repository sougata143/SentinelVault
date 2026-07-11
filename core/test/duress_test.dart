import 'package:test/test.dart';
import 'package:core/core.dart';

void main() {
  group('Duress / Decoy Vault Tests', () {
    late SqliteVaultDatabase dbAlpha;
    late SqliteVaultDatabase dbBeta;
    late List<int> keyAlpha;
    late List<int> keyBeta;
    late VaultCrypto crypto;

    setUp(() async {
      crypto = VaultCrypto();
      // Generate entirely independent keys and salts for both vaults.
      keyAlpha = crypto.generateRandomBytes(32);
      keyBeta = crypto.generateRandomBytes(32);

      dbAlpha = SqliteVaultDatabase.inMemory();
      dbBeta = SqliteVaultDatabase.inMemory();

      dbAlpha.open(keyAlpha);
      dbBeta.open(keyBeta);

      // Prepopulate Vault Alpha with a sensitive item.
      final now = DateTime.now().toUtc();
      final realItem = VaultItem(
        id: 'real-login-1',
        type: VaultItemType.login,
        title: 'Sensitive Master Account',
        tags: const [],
        favorite: false,
        vaultId: '',
        createdAt: now,
        updatedAt: now,
        notes: const ConcealedValue.plain('Critical account.'),
        customFields: const [],
        fields: LoginFields(
          username: 'admin@company.com',
          password: const ConcealedValue.plain('super-secret-password-123'),
          urls: const [],
          otpSecret: const ConcealedValue.plain(''),
          passwordHistory: const [],
        ),
      );
      final encRealItem = await realItem.encrypt(keyAlpha, crypto);
      dbAlpha.insertItem(encRealItem);
    });

    tearDown(() {
      dbAlpha.close();
      dbBeta.close();
      VaultLockManager.instance.lock();
    });

    // -----------------------------------------------------------------------
    // Test 1: DualVaultManager prepopulates decoy items correctly.
    // -----------------------------------------------------------------------
    test('1. DualVaultManager prepopulates 3 decoy items in Vault Beta', () async {
      await DualVaultManager.instance.prepopulateDecoyItems(dbBeta, keyBeta);
      final items = dbBeta.getAllItems();
      expect(items.length, equals(3));

      // Decrypt the first item to verify it is harmless
      final firstItem = await VaultItem.decrypt(items[0], keyBeta, crypto);
      expect(firstItem.title, equals('Google Workspace Account'));
      expect(firstItem.notes.plaintext, contains('Work-related backup account'));
    });

    // -----------------------------------------------------------------------
    // Test 2: Vault Alpha's encrypted data is untouched after duress trigger.
    // Only the biometric cache is cleared — the actual ciphertext is intact.
    // -----------------------------------------------------------------------
    test('2. triggerDuressWipeHook clears biometric cache but leaves Vault Alpha data intact',
        () async {
      // 1. Write mock biometric-cached key for Vault Alpha.
      final mockStorage = SecureStorage.instance;
      await mockStorage.writeBiometricWrappedVaultKey(
        List.generate(32, (i) => i),
        keyAlpha,
      );

      // Confirm cache is populated.
      var cached = await mockStorage.readBiometricWrappedVaultKey();
      expect(cached, isNotNull);

      // 2. Insert a sentinel item into Vault Alpha.
      final now = DateTime.now().toUtc();
      final sentinel = EncryptedVaultItem(
        id: 'sentinel-alpha',
        encryptedBlob: 'some-encrypted-ciphertext',
        nonce: 'some-nonce',
        version: 1,
        updatedAt: now,
      );
      dbAlpha.insertItem(sentinel);

      // 3. Fire duress wipe hook.
      await triggerDuressWipeHook();

      // 4. Biometric cache is wiped.
      cached = await mockStorage.readBiometricWrappedVaultKey();
      expect(cached, isNull, reason: 'Biometric quick-unlock cache must be cleared');

      // 5. Vault Alpha's encrypted database is completely untouched.
      final alphaItems = dbAlpha.getAllItems(includeDeleted: true);
      expect(
        alphaItems.any((i) => i.id == 'sentinel-alpha'),
        isTrue,
        reason: 'Vault Alpha encrypted data must remain intact after duress trigger',
      );
      final retrieved = dbAlpha.getItem('sentinel-alpha');
      expect(retrieved?.encryptedBlob, equals('some-encrypted-ciphertext'),
          reason: 'Vault Alpha ciphertext must be byte-for-byte identical');
    });

    // -----------------------------------------------------------------------
    // Test 3: isDuressMode flag prevents sync from leaking decoy state.
    // -----------------------------------------------------------------------
    test('3. isDuressMode=true causes VaultSyncManager.sync() to no-op', () async {
      VaultLockManager.instance.unlock(
        List.generate(32, (i) => i),
        keyBeta,
        isDuress: true,
      );
      expect(VaultLockManager.instance.isDuressMode, isTrue);

      final mockApi = _MockSyncApiClient();
      final syncManager = VaultSyncManager(
        localDb: dbBeta,
        api: mockApi,
      );

      await syncManager.sync();

      expect(
        mockApi.pullCalled,
        isFalse,
        reason: 'Sync must be a no-op in duress mode to protect both vault states',
      );
    });

    // -----------------------------------------------------------------------
    // Test 4: VaultBeta key cannot decrypt VaultAlpha data.
    // -----------------------------------------------------------------------
    test('4. Vault Beta key fails to decrypt Vault Alpha ciphertext', () async {
      await DualVaultManager.instance.prepopulateDecoyItems(dbBeta, keyBeta);

      // Grab a real encrypted item from Vault Alpha.
      final alphaItems = dbAlpha.getAllItems();
      expect(alphaItems, isNotEmpty, reason: 'Setup should have inserted at least one item');
      final alphaEnc = alphaItems.first;

      // Attempt to decrypt Vault Alpha item using Vault Beta key — must fail.
      var threw = false;
      try {
        await VaultItem.decrypt(alphaEnc, keyBeta, crypto);
      } catch (_) {
        threw = true;
      }
      expect(
        threw,
        isTrue,
        reason: 'Vault Beta key must not be able to decrypt Vault Alpha ciphertext',
      );
    });
  });
}

class _MockSyncApiClient implements SyncApiClient {
  bool pullCalled = false;

  @override
  Future<List<EncryptedVaultItem>> pull() async {
    pullCalled = true;
    return [];
  }

  @override
  Future<SyncPushResult> push(List<EncryptedVaultItem> items) async {
    return SyncPushResult.success();
  }
}
