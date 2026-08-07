import 'package:flutter_test/flutter_test.dart';
import 'package:core/core.dart';
import 'package:app/features/auth/biometric_vault_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BiometricVaultManager Unit Tests', () {
    final sampleVaultKey = List<int>.generate(32, (i) => i + 1);
    const masterPassword = 'MySecretMasterPassword!123';

    setUp(() async {
      SecureStorage.instance = InMemorySecureStorage();
      await BiometricVaultManager.purgeCachedKey();
      await BiometricVaultManager.setBiometricsEnabled(false);
    });

    test('Master Password is NEVER cached or stored in secure storage', () async {
      await BiometricVaultManager.setBiometricsEnabled(true);
      await BiometricVaultManager.cacheVaultKey(sampleVaultKey);

      final storedKey = await SecureStorage.instance.readString(BiometricVaultManager.keyCachedVaultKey);
      expect(storedKey, isNotNull);
      expect(storedKey, isNot(contains(masterPassword)));
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
      final storedKey = await SecureStorage.instance.readString(BiometricVaultManager.keyCachedVaultKey);
      expect(storedKey, isNull);
    });

    test('Expired TTL correctly invalidates and purges cached Vault Key', () async {
      await BiometricVaultManager.setBiometricsEnabled(true);
      await BiometricVaultManager.setAutoLockTtlSeconds(10); // 10 seconds TTL
      await BiometricVaultManager.cacheVaultKey(sampleVaultKey);

      expect(await BiometricVaultManager.hasValidCachedKey(), isTrue);

      // Artificially simulate 15 seconds passing
      final oldTimestamp = DateTime.now().millisecondsSinceEpoch - 15000;
      await SecureStorage.instance.writeString(BiometricVaultManager.keyCachedTimestamp, oldTimestamp.toString());

      // Should return false and auto-purge
      final isValid = await BiometricVaultManager.hasValidCachedKey();
      expect(isValid, isFalse);

      final storedKey = await SecureStorage.instance.readString(BiometricVaultManager.keyCachedVaultKey);
      expect(storedKey, isNull);
    });

    test('Explicit purgeCachedKey clears secure storage and metadata', () async {
      await BiometricVaultManager.setBiometricsEnabled(true);
      await BiometricVaultManager.cacheVaultKey(sampleVaultKey);

      await BiometricVaultManager.purgeCachedKey();

      expect(await BiometricVaultManager.hasValidCachedKey(), isFalse);
      expect(await SecureStorage.instance.readString(BiometricVaultManager.keyCachedVaultKey), isNull);
    });
  });
}
