import 'package:test/test.dart';
import 'package:core/core.dart';

void main() {
  group('VaultLockManager Unit Tests', () {
    late VaultLockManager lockManager;

    setUp(() {
      lockManager = VaultLockManager.instance;
      // Reset state
      lockManager.logout();
    });

    test('1. unlock sets session token and key materials in memory', () {
      const token = 'session-token-123';
      final masterKey = List<int>.generate(32, (i) => i + 1);
      final vaultKey = List<int>.generate(32, (i) => i + 10);

      lockManager.setSession(token);
      lockManager.unlock(masterKey, vaultKey);

      expect(lockManager.sessionToken, token);
      expect(lockManager.masterKey, masterKey);
      expect(lockManager.vaultKey, vaultKey);
      expect(lockManager.isLocked, false);
      expect(lockManager.isLoggedIn, true);
    });

    test('2. lock clears key material but preserves session token', () {
      const token = 'session-token-123';
      final masterKey = List<int>.generate(32, (i) => i + 1);
      final vaultKey = List<int>.generate(32, (i) => i + 10);

      lockManager.setSession(token);
      lockManager.unlock(masterKey, vaultKey);

      // Lock
      lockManager.lock();

      expect(lockManager.sessionToken, token);
      expect(lockManager.masterKey, isNull);
      expect(lockManager.vaultKey, isNull);
      expect(lockManager.isLocked, true);
      expect(lockManager.isLoggedIn, true);
    });

    test('3. logout clears both session token and key material', () {
      const token = 'session-token-123';
      final masterKey = List<int>.generate(32, (i) => i + 1);
      final vaultKey = List<int>.generate(32, (i) => i + 10);

      lockManager.setSession(token);
      lockManager.unlock(masterKey, vaultKey);

      // Logout
      lockManager.logout();

      expect(lockManager.sessionToken, isNull);
      expect(lockManager.masterKey, isNull);
      expect(lockManager.vaultKey, isNull);
      expect(lockManager.isLocked, true);
      expect(lockManager.isLoggedIn, false);
    });
  });
}
