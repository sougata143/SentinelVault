import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:core/core.dart';
import 'package:app/features/auth/unlock_screen.dart';
import 'package:app/features/settings/duress_setup_screen.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
List<int> _hexToBytes(String hex) {
  final result = <int>[];
  for (var i = 0; i + 1 < hex.length; i += 2) {
    result.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return result;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
void main() {
  group('Duress / Decoy Vault UI Tests', () {
    late VaultCrypto crypto;
    late List<int> alphaVaultKey;
    late List<int> betaVaultKey;
    late List<int> alphaSalt;     // simulates sync-server salt
    late List<int> betaSalt;      // stored locally for duress
    late List<int> alphaWrapped;  // wrapped under master password KDF
    late List<int> betaWrapped;   // wrapped under duress password KDF

    const masterPassword = 'MasterP@ssw0rd!';
    const duressPassword = 'Duress@123secret';

    setUpAll(() async {
      crypto = VaultCrypto();
      alphaSalt = crypto.generateRandomBytes(16);
      betaSalt = crypto.generateRandomBytes(16);
      alphaVaultKey = crypto.generateRandomBytes(32);
      betaVaultKey = crypto.generateRandomBytes(32);

      final alphaMasterKey = await crypto.deriveMasterKey(
        masterPassword: masterPassword,
        salt: alphaSalt,
      );
      alphaWrapped = await crypto.wrapVaultKey(
        masterKey: alphaMasterKey,
        vaultKey: alphaVaultKey,
      );

      final duressKdfKey = await crypto.deriveRecoveryKdfKey(
        recoveryKey: duressPassword,
        salt: betaSalt,
      );
      betaWrapped = await crypto.wrapVaultKey(
        masterKey: duressKdfKey,
        vaultKey: betaVaultKey,
      );
    });

    tearDownAll(() {
      VaultLockManager.instance.lock();
    });

    // -----------------------------------------------------------------------
    // Test 1: DuressSetupScreen shows limitations disclosure and form.
    // -----------------------------------------------------------------------
    testWidgets('1. DuressSetupScreen shows limitations and form fields',
        (WidgetTester tester) async {
      // Ensure duress is NOT configured for Test 1
      await SecureStorage.instance.deleteString(DualVaultManager.duressConfiguredKey);
      await SecureStorage.instance.deleteString(DualVaultManager.duressSaltKey);
      await SecureStorage.instance.deleteString(DualVaultManager.duressWrappedKeyKey);

      await tester.pumpWidget(const MaterialApp(home: DuressSetupScreen()));
      await tester.pumpAndSettle();

      // Must show the limitations warning — non-negotiable from the skill spec
      expect(find.text('Important Limitations'), findsOneWidget);
      expect(find.textContaining('cannot guarantee'), findsNWidgets(2));
      expect(find.textContaining('Multiple encrypted database files'), findsOneWidget);

      // Must show all form fields
      expect(find.byKey(const Key('duress-password-field')), findsOneWidget);
      expect(find.byKey(const Key('confirm-duress-field')), findsOneWidget);
      expect(find.byKey(const Key('master-password-verify-field')), findsOneWidget);
      expect(find.byKey(const Key('limitations-ack-checkbox')), findsOneWidget);
      expect(find.byKey(const Key('enable-decoy-button')), findsOneWidget);

      // Unlock screen itself must NOT show the word "Duress"
      // (label must be confined to the setup screen only)
      expect(find.text('Duress Password'), findsNothing);
    });

    // -----------------------------------------------------------------------
    // Test 2: Entering the Duress Password on the Unlock screen opens
    // Vault Beta, fires the wipe hook, and sets isDuressMode=true.
    // Vault Alpha's biometric cache must be wiped; its data is untouched.
    // -----------------------------------------------------------------------
    testWidgets('2. Duress Password opens Vault Beta and wipes biometric cache',
        (WidgetTester tester) async {
      // Setup duress config in mock SecureStorage
      final betaSaltHex = betaSalt.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final betaWrappedHex = betaWrapped.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      await SecureStorage.instance.writeString(DualVaultManager.duressSaltKey, betaSaltHex);
      await SecureStorage.instance.writeString(DualVaultManager.duressWrappedKeyKey, betaWrappedHex);
      await SecureStorage.instance.writeString(DualVaultManager.duressConfiguredKey, 'true');

      // Prepopulate biometric cache to verify wipe hook fires
      final alphaMasterKey = await crypto.deriveMasterKey(
        masterPassword: masterPassword,
        salt: alphaSalt,
      );
      await SecureStorage.instance.writeBiometricWrappedVaultKey(
        alphaMasterKey,
        alphaVaultKey,
      );

      final alphaSaltHex = alphaSalt.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final alphaWrappedHex = alphaWrapped.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      final mockClient = MockClient((request) async {
        if (request.method == 'GET' && request.url.path == '/sync/vault-key') {
          return http.Response(
            json.encode({
              'salt': alphaSaltHex,
              'wrappedKey': alphaWrappedHex,
            }),
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
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify biometric cache is present before duress trigger
      var cached = await SecureStorage.instance.readBiometricWrappedVaultKey();
      expect(cached, isNotNull, reason: 'Biometric cache should be populated before duress');

      // Enter the Duress Password — visually identical to a normal unlock
      await tester.enterText(
        find.byKey(const Key('unlock-password-field')),
        duressPassword,
      );
      await tester.pump();

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('decrypt-unlock-button')));
        await Future.delayed(const Duration(milliseconds: 1500));
      });
      await tester.pumpAndSettle();

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
    // Test 3: Vault Alpha's existence is never revealed via the Unlock screen.
    // An incorrect password returns the same error regardless of duress config.
    // -----------------------------------------------------------------------
    testWidgets('3. Wrong password gives identical error — Vault Alpha existence not revealed',
        (WidgetTester tester) async {
      VaultLockManager.instance.lock();

      final alphaSaltHex = alphaSalt.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final alphaWrappedHex = alphaWrapped.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      final mockClient = MockClient((request) async {
        if (request.method == 'GET' && request.url.path == '/sync/vault-key') {
          return http.Response(
            json.encode({'salt': alphaSaltHex, 'wrappedKey': alphaWrappedHex}),
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

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('decrypt-unlock-button')));
        await Future.delayed(const Duration(milliseconds: 1500));
      });
      await tester.pumpAndSettle();

      // Error message must be the generic one — no mention of "duress",
      // "alpha", "beta", or any vault differentiation
      expect(find.text('Incorrect master password'), findsOneWidget);
      expect(find.textContaining('Vault Alpha'), findsNothing);
      expect(find.textContaining('duress'), findsNothing);
      expect(find.textContaining('decoy'), findsNothing);
    });
  });
}
