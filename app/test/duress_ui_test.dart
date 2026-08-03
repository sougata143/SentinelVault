import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:core/core.dart';
import 'package:app/features/auth/unlock_screen.dart';
import 'package:app/features/settings/duress_setup_screen.dart';

// ---------------------------------------------------------------------------
// Pre-computed test fixtures (derived once via test/scratch_derive_keys.dart
// with Argon2id memory=1024, iterations=1).
//
// Passwords used:
//   masterPassword  = 'MasterP@ssw0rd!'
//   duressPassword  = 'Duress@123secret'
// ---------------------------------------------------------------------------

List<int> _fromHex(String hex) {
  final len = hex.length ~/ 2;
  return List.generate(
      len, (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16));
}

const _alphaSaltHex     = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _betaSaltHex      = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _alphaVaultKeyHex = 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
const _alphaWrappedHex  = '4403f17b405d6d970c5d60eba5f02f8f12e05f2c0ad67df07b91d43bf5d315fb7d6f558d9263e9f904aff5f95af3167febb98bce58d8532fb893e57d';
const _betaWrappedHex   = '924e6957922c5b926c0c39b431a4a6ed1e007a90ff9fd5db6de888f538011897892ac7d960a7aeff10d99af02aba35fabf12b6b39539a66ba908dcf1';
const _alphaMasterKeyHex = '3cc086df393d23170947cd6be88ba74c0542b490fd54fcc65cf2f8a55c2ab0d7';
// Duress KDF key (derived from duressPassword + betaSalt)
const _duressKdfKeyHex  = '3c2a3215f484b3fa35b0e9cdec63c416040a6b6c38ef309aacd7042bf770db11';

const _masterPassword = 'MasterP@ssw0rd!';
const _duressPassword  = 'Duress@123secret';

// ---------------------------------------------------------------------------
// FakeVaultCrypto: returns pre-computed values instantly, bypassing Argon2id.
// Only KDF methods are overridden; all other methods delegate to real crypto.
// ---------------------------------------------------------------------------
class FakeVaultCrypto extends VaultCrypto {
  final Map<String, List<int>> _kdfOverrides;

  FakeVaultCrypto(this._kdfOverrides);

  /// Returns the pre-computed master key if the password matches, otherwise
  /// delegates to the real (slow) implementation.
  @override
  Future<List<int>> deriveMasterKey({
    required String masterPassword,
    required List<int> salt,
  }) async {
    final key = '${masterPassword}_${_toHex(salt)}';
    return _kdfOverrides[key] ?? super.deriveMasterKey(masterPassword: masterPassword, salt: salt);
  }

  /// Returns the pre-computed recovery KDF key if the key+salt matches.
  @override
  Future<List<int>> deriveRecoveryKdfKey({
    required String recoveryKey,
    required List<int> salt,
  }) async {
    final key = '${recoveryKey}_${_toHex(salt)}';
    return _kdfOverrides[key] ?? super.deriveRecoveryKdfKey(recoveryKey: recoveryKey, salt: salt);
  }

  static String _toHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
void main() {
  group('Duress / Decoy Vault UI Tests', () {
    // Pre-decode all fixture values — zero KDF computation
    final alphaVaultKey  = _fromHex(_alphaVaultKeyHex);
    final alphaMasterKey = _fromHex(_alphaMasterKeyHex);

    // Build a FakeVaultCrypto that maps password+salt → pre-computed key
    late FakeVaultCrypto fakeCrypto;

    setUp(() {
      fakeCrypto = FakeVaultCrypto({
        '${_masterPassword}_$_alphaSaltHex': _fromHex(_alphaMasterKeyHex),
        '${_duressPassword}_$_betaSaltHex':  _fromHex(_duressKdfKeyHex),
      });
    });

    tearDownAll(() {
      VaultLockManager.instance.lock();
    });

    // -----------------------------------------------------------------------
    // Test 1: DuressSetupScreen shows limitations disclosure and form.
    // -----------------------------------------------------------------------
    testWidgets('1. DuressSetupScreen shows limitations and form fields',
        (WidgetTester tester) async {
      await SecureStorage.instance.deleteString(DualVaultManager.duressConfiguredKey);
      await SecureStorage.instance.deleteString(DualVaultManager.duressSaltKey);
      await SecureStorage.instance.deleteString(DualVaultManager.duressWrappedKeyKey);

      await tester.pumpWidget(const MaterialApp(home: DuressSetupScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Important Limitations'), findsOneWidget);
      expect(find.textContaining('cannot guarantee'), findsNWidgets(2));
      expect(find.textContaining('Multiple encrypted database files'), findsOneWidget);
      expect(find.byKey(const Key('duress-password-field')), findsOneWidget);
      expect(find.byKey(const Key('confirm-duress-field')), findsOneWidget);
      expect(find.byKey(const Key('master-password-verify-field')), findsOneWidget);
      expect(find.byKey(const Key('limitations-ack-checkbox')), findsOneWidget);
      expect(find.byKey(const Key('enable-decoy-button')), findsOneWidget);
      expect(find.text('Duress Password'), findsNothing);
    });

    // -----------------------------------------------------------------------
    // Test 2: Entering the Duress Password on the Unlock screen opens
    // Vault Beta, fires the wipe hook, and sets isDuressMode=true.
    // -----------------------------------------------------------------------
    testWidgets('2. Duress Password opens Vault Beta and wipes biometric cache',
        (WidgetTester tester) async {
      VaultLockManager.instance.lock();

      // Inject pre-computed duress config into SecureStorage
      await SecureStorage.instance.writeString(DualVaultManager.duressSaltKey, _betaSaltHex);
      await SecureStorage.instance.writeString(DualVaultManager.duressWrappedKeyKey, _betaWrappedHex);
      await SecureStorage.instance.writeString(DualVaultManager.duressConfiguredKey, 'true');

      // Prepopulate biometric cache using pre-computed alphaMasterKey + alphaVaultKey
      await SecureStorage.instance.writeBiometricWrappedVaultKey(
        alphaMasterKey,
        alphaVaultKey,
      );

      final mockClient = MockClient((request) async {
        if (request.method == 'GET' && request.url.path == '/sync/vault-key') {
          return http.Response(
            json.encode({'salt': _alphaSaltHex, 'wrappedKey': _alphaWrappedHex}),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: UnlockScreen(
            email: 'user@example.com',
            syncBaseUrl: 'http://fake-sync',
            httpClient: mockClient,
            cryptoOverride: fakeCrypto,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify biometric cache is present before duress trigger
      var cached = await SecureStorage.instance.readBiometricWrappedVaultKey();
      expect(cached, isNotNull, reason: 'Biometric cache should be populated before duress');

      // Enter the Duress Password
      await tester.enterText(
        find.byKey(const Key('unlock-password-field')),
        _duressPassword,
      );
      await tester.pump();

      // Tap unlock — FakeVaultCrypto returns instantly, no Argon2id wait needed
      await tester.tap(find.byKey(const Key('decrypt-unlock-button')));
      await tester.pump();
      await tester.runAsync(() async {
        // Even with fake KDF, AES-GCM unwrap + navigation are async
        await Future.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // isDuressMode must be set — decoy vault is active
      expect(
        VaultLockManager.instance.isDuressMode,
        isTrue,
        reason: 'VaultLockManager.isDuressMode must be true after duress unlock',
      );

      // Biometric cache for Vault Alpha must now be wiped
      cached = await SecureStorage.instance.readBiometricWrappedVaultKey();
      expect(
        cached,
        isNull,
        reason: 'Biometric quick-unlock cache for Vault Alpha must be cleared by wipe hook',
      );
    });

    // -----------------------------------------------------------------------
    // Test 3: Wrong password gives identical error — no vault differentiation.
    // -----------------------------------------------------------------------
    testWidgets('3. Wrong password gives identical error — Vault Alpha existence not revealed',
        (WidgetTester tester) async {
      VaultLockManager.instance.lock();

      // Duress still configured from test 2 (betaSalt + betaWrapped in SecureStorage)
      final mockClient = MockClient((request) async {
        if (request.method == 'GET' && request.url.path == '/sync/vault-key') {
          return http.Response(
            json.encode({'salt': _alphaSaltHex, 'wrappedKey': _alphaWrappedHex}),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      // FakeVaultCrypto has no override for 'wrong-password', so it will call
      // real Argon2id. We make a FakeCrypto that throws immediately for unknown
      // passwords to simulate a fast KDF failure.
      final fastFailCrypto = _FastFailVaultCrypto();

      await tester.pumpWidget(
        MaterialApp(
          home: UnlockScreen(
            email: 'user@example.com',
            syncBaseUrl: 'http://fake-sync',
            httpClient: mockClient,
            cryptoOverride: fastFailCrypto,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter a completely wrong password
      await tester.enterText(
        find.byKey(const Key('unlock-password-field')),
        'completely-wrong-password-99',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('decrypt-unlock-button')));
      await tester.pump();
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Error message must be the generic one — no vault differentiation
      expect(find.text('Incorrect master password'), findsOneWidget);
      expect(find.textContaining('Vault Alpha'), findsNothing);
      expect(find.textContaining('duress'), findsNothing);
      expect(find.textContaining('decoy'), findsNothing);
    });
  });
}

/// A VaultCrypto that throws [SecretBoxAuthenticationError] instantly for any
/// KDF call — simulates a wrong password without running actual Argon2id.
class _FastFailVaultCrypto extends VaultCrypto {
  @override
  Future<List<int>> deriveMasterKey({
    required String masterPassword,
    required List<int> salt,
  }) async {
    // Return a random-looking key so unwrapVaultKey will fail with auth error
    return List<int>.filled(32, 0xDE);
  }

  @override
  Future<List<int>> deriveRecoveryKdfKey({
    required String recoveryKey,
    required List<int> salt,
  }) async {
    return List<int>.filled(32, 0xAD);
  }
}
