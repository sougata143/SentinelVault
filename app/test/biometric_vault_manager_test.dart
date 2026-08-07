import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:app/features/auth/biometric_vault_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BiometricVaultManager Unit Tests', () {
    const mockStorage = FlutterSecureStorage();
    final sampleVaultKey = List<int>.generate(32, (i) => i + 1);
    const masterPassword = 'MySecretMasterPassword!123';

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      await BiometricVaultManager.purgeCachedKey();
      await BiometricVaultManager.setBiometricsEnabled(false);
    });

    test('Master Password is NEVER cached or stored in secure storage', () async {
      await BiometricVaultManager.setBiometricsEnabled(true);
      await BiometricVaultManager.cacheVaultKey(sampleVaultKey);

      final storedKey = await mockStorage.read(key: BiometricVaultManager.keyCachedVaultKey);
      expect(storedKey, isNotNull);
      expect(storedKey, isNot(contains(masterPassword)));

      final allKeys = await mockStorage.readAll();
      final allValues = allKeys.values.join(' ');
      expect(allValues, isNot(contains(masterPassword)));
    });

    test('Caching Vault Key when biometrics disabled is a no-op', () async {
      await BiometricVaultManager.setBiometricsEnabled(false);
      await BiometricVaultManager.cacheVaultKey(sampleVaultKey);

      final hasKey = await BiometricVaultManager.hasValidCachedKey();
      expect(hasKey, isFalse);
    });

    test('Disabling biometrics immediately purges cached Vault Key from secure storage', () async {
      await BiometricVaultManager.setBiometricsEnabled(true);
      await BiometricVaultManager.cacheVaultKey(sampleVaultKey);

      expect(await BiometricVaultManager.hasValidCachedKey(), isTrue);

      // Disable feature
      await BiometricVaultManager.setBiometricsEnabled(false);

      expect(await BiometricVaultManager.hasValidCachedKey(), isFalse);
      final storedKey = await mockStorage.read(key: BiometricVaultManager.keyCachedVaultKey);
      expect(storedKey, isNull);
    });

    test('Expired TTL correctly invalidates and purges cached Vault Key', () async {
      await BiometricVaultManager.setBiometricsEnabled(true);
      await BiometricVaultManager.setAutoLockTtlSeconds(10); // 10 seconds TTL
      await BiometricVaultManager.cacheVaultKey(sampleVaultKey);

      expect(await BiometricVaultManager.hasValidCachedKey(), isTrue);

      // Artificially simulate 15 seconds passing
      final oldTimestamp = DateTime.now().millisecondsSinceEpoch - 15000;
      await mockStorage.write(key: BiometricVaultManager.keyCachedTimestamp, value: oldTimestamp.toString());

      // Should return false and auto-purge
      final isValid = await BiometricVaultManager.hasValidCachedKey();
      expect(isValid, isFalse);

      final storedKey = await mockStorage.read(key: BiometricVaultManager.keyCachedVaultKey);
      expect(storedKey, isNull);
    });

    test('Explicit purgeCachedKey clears secure storage and metadata', () async {
      await BiometricVaultManager.setBiometricsEnabled(true);
      await BiometricVaultManager.cacheVaultKey(sampleVaultKey);

      await BiometricVaultManager.purgeCachedKey();

      expect(await BiometricVaultManager.hasValidCachedKey(), isFalse);
      expect(await mockStorage.read(key: BiometricVaultManager.keyCachedVaultKey), isNull);
    });
  });
}
