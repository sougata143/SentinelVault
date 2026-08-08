import 'package:test/test.dart';
import 'package:core/core.dart';

void main() {
  group('SsoAuthHelper & Zero-Knowledge Security Boundary Tests', () {
    late VaultCrypto crypto;

    setUp(() {
      crypto = VaultCrypto();
    });

    test('1. Extracts domain from email correctly', () {
      expect(SsoAuthHelper.extractDomainFromEmail('alice@acme.corp'), equals('@acme.corp'));
      expect(SsoAuthHelper.extractDomainFromEmail('BOB@ENTERPRISE.ORG '), equals('@enterprise.org'));
      expect(SsoAuthHelper.extractDomainFromEmail('invalid-email'), isNull);
    });

    test('2. Generates valid PKCE S256 verifier and challenge pair', () {
      final pkce = SsoAuthHelper.generatePkceChallenge(crypto);

      expect(pkce.codeVerifier, isNotEmpty);
      expect(pkce.codeChallenge, isNotEmpty);
      expect(pkce.codeChallengeMethod, equals('S256'));
      expect(pkce.codeVerifier, isNot(equals(pkce.codeChallenge)));
    });

    test('3. ZERO-KNOWLEDGE BOUNDARY: Setting SSO session token leaves vault LOCKED until Master Password entry', () {
      final lockManager = VaultLockManager.instance;
      lockManager.lockAll();

      // Simulate receiving session JWT from SSO callback
      const mockSsoSessionToken = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.sso_session';
      lockManager.setSession(mockSsoSessionToken);

      // Verify identity token state
      expect(lockManager.isLoggedIn, isTrue);
      expect(lockManager.sessionToken, equals(mockSsoSessionToken));

      // STRICT ZERO-KNOWLEDGE INVARIANT ASSERTIONS:
      // Vault MUST remain locked, and no vault keys must be loaded in memory!
      expect(lockManager.isLocked, isTrue);
      expect(lockManager.vaultKey, isNull);
      expect(lockManager.masterKey, isNull);
      expect(lockManager.activeVaultId, isNull);
    });
  });
}
