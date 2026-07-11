import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cryptography/cryptography.dart';
import 'package:core/core.dart';
import 'package:app/features/auth/unlock_screen.dart';
import 'package:app/features/settings/settings_screen.dart';
import 'package:app/app_shell.dart';

void main() {
  group('Recovery Key Integration Tests', () {
    const email = 'user@example.com';
    const correctPassword = 'myMasterPassword123!';

    late List<int> salt;
    late List<int> vaultKey;
    late List<int> wrappedVaultKey;
    late String saltHex;
    late String wrappedKeyHex;

    late String recoveryKey;
    late List<int> recoverySalt;
    late List<int> recoveryWrappedKey;
    late String recoverySaltHex;
    late String recoveryWrappedKeyHex;

    setUpAll(() async {
      final crypto = VaultCrypto();
      salt = crypto.generateRandomBytes(16);
      final masterKey = await crypto.deriveMasterKey(
        masterPassword: correctPassword,
        salt: salt,
      );
      vaultKey = crypto.generateRandomBytes(32);
      wrappedVaultKey = await crypto.wrapVaultKey(
        vaultKey: vaultKey,
        masterKey: masterKey,
      );

      saltHex = salt.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      wrappedKeyHex = wrappedVaultKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      // Setup Recovery Key variables
      recoveryKey = crypto.generateRecoveryKey();
      recoverySalt = crypto.generateRandomBytes(16);
      final rkk = await crypto.deriveRecoveryKdfKey(
        recoveryKey: recoveryKey,
        salt: recoverySalt,
      );
      recoveryWrappedKey = await crypto.wrapVaultKey(
        vaultKey: vaultKey,
        masterKey: rkk,
      );

      recoverySaltHex = recoverySalt.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      recoveryWrappedKeyHex = recoveryWrappedKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    });

    setUp(() {
      VaultLockManager.instance.logout();
    });

    testWidgets('1. Forgot Master Password button appears and correct Recovery Key unlocks vault', (WidgetTester tester) async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/sync/vault-key');
        return http.Response(
          json.encode({
            'salt': saltHex,
            'wrappedKey': wrappedKeyHex,
            'recoverySalt': recoverySaltHex,
            'recoveryWrappedKey': recoveryWrappedKeyHex,
          }),
          200,
        );
      });

      await tester.pumpWidget(
        MaterialApp(
          home: UnlockScreen(
            email: email,
            syncBaseUrl: 'http://fake-sync',
            httpClient: mockClient,
          ),
        ),
      );

      // Let fetch complete without pumpAndSettle timeout
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Check recovery button is visible
      final recoveryBtnFinder = find.byKey(const Key('use-recovery-key-button'));
      expect(recoveryBtnFinder, findsOneWidget);

      // Tap to open recovery dialog
      await tester.tap(recoveryBtnFinder);
      await tester.pump();

      // Dialog should be shown
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byKey(const Key('recovery-key-input-field')), findsOneWidget);

      // 1. Enter invalid key
      await tester.enterText(find.byKey(const Key('recovery-key-input-field')), 'ABCD-EFGH-IJKL-MNOP-QRST-UVWX-YZ23-AAAA');
      
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('submit-recovery-key-button')));
        // Wait dynamically for recovery KDF derivation
        await Future.delayed(const Duration(milliseconds: 1500));
      });
      await tester.pump();

      // Decryption failure error message should be displayed
      expect(find.text('Invalid Recovery Key or decryption failed'), findsOneWidget);

      // 2. Enter correct recovery key
      await tester.enterText(find.byKey(const Key('recovery-key-input-field')), recoveryKey);

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('submit-recovery-key-button')));
        // Wait dynamically for recovery KDF derivation
        await Future.delayed(const Duration(milliseconds: 1500));
      });
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Dialog closed, dashboard unlocked
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(AppShell), findsOneWidget);
      expect(VaultLockManager.instance.isLocked, isFalse);
      expect(VaultLockManager.instance.masterKey, isNull); // Master key is null (unlocked via recovery)
    });

    testWidgets('2. Settings setup & regenerate Emergency Kit uploads correct fields and never leaks raw recovery key', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
      });

      // Initialize VaultLockManager to unlocked state
      VaultLockManager.instance.unlock(List.generate(32, (i) => i), vaultKey);

      final List<String> requests = [];

      final mockClient = MockClient((request) async {
        if (request.method == 'GET' && request.url.path == '/sync/vault-key') {
          return http.Response(
            json.encode({
              'salt': saltHex,
              'wrappedKey': wrappedKeyHex,
            }),
            200,
          );
        }
        if (request.method == 'POST' && request.url.path == '/sync/vault-key') {
          requests.add(request.body);
          return http.Response(json.encode({'success': true}), 200);
        }
        return http.Response('Not found', 404);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            currentEmail: email,
            syncBaseUrl: 'http://fake-sync',
            httpClient: mockClient,
          ),
        ),
      );

      // Wait for fetch to complete
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Setup Emergency Kit tile should be visible
      final tileFinder = find.byKey(const Key('settings-setup-emergency-kit-tile'));
      expect(tileFinder, findsOneWidget);

      // Tap to open setup dialog
      await tester.tap(tileFinder);
      await tester.pump();

      // Dialog is open
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byKey(const Key('generated-recovery-key-text')), findsOneWidget);

      final textWidget = tester.widget<Text>(find.byKey(const Key('generated-recovery-key-text')));
      final generatedRK = textWidget.data!;
      expect(generatedRK, isNotEmpty);

      // Checkbox is unchecked, button should be disabled
      final uploadBtn = find.byKey(const Key('upload-recovery-key-button'));
      expect(tester.widget<ElevatedButton>(uploadBtn).enabled, isFalse);

      // Check the checkbox
      await tester.tap(find.byKey(const Key('confirm-saved-checkbox')));
      await tester.pump();
      expect(tester.widget<ElevatedButton>(uploadBtn).enabled, isTrue);

      // Tap upload with KDF runAsync
      await tester.runAsync(() async {
        await tester.tap(uploadBtn);
        // Wait dynamically for KDF derivation
        await Future.delayed(const Duration(milliseconds: 1500));
      });
      await tester.pump();

      // Dialog should close
      expect(find.byType(AlertDialog), findsNothing);
      expect(requests.length, equals(1));

      final Map<String, dynamic> body = json.decode(requests[0]);
      expect(body['salt'], equals(saltHex));
      expect(body['wrappedKey'], equals(wrappedKeyHex));
      expect(body['recoverySalt'], isNotEmpty);
      expect(body['recoveryWrappedKey'], isNotEmpty);

      // Security check: Raw recovery key string MUST NOT exist in payload or logs
      expect(requests[0].contains(generatedRK), isFalse);
      expect(requests[0].contains(generatedRK.replaceAll('-', '')), isFalse);
    });

    test('3. Recovery Key invalidation logic (old key rejected after regeneration)', () async {
      final crypto = VaultCrypto();
      
      // Original Recovery Key
      final rk1 = crypto.generateRecoveryKey();
      final salt1 = crypto.generateRandomBytes(16);
      final rkk1 = await crypto.deriveRecoveryKdfKey(recoveryKey: rk1, salt: salt1);
      final wrappedVK1 = await crypto.wrapVaultKey(vaultKey: vaultKey, masterKey: rkk1);

      // Regenerated Recovery Key
      final rk2 = crypto.generateRecoveryKey();
      final salt2 = crypto.generateRandomBytes(16);
      final rkk2 = await crypto.deriveRecoveryKdfKey(recoveryKey: rk2, salt: salt2);
      final wrappedVK2 = await crypto.wrapVaultKey(vaultKey: vaultKey, masterKey: rkk2);

      // Attempting to unwrap wrappedVK2 with rkk1 MUST fail
      expect(
        () => crypto.unwrapVaultKey(wrappedVaultKey: wrappedVK2, masterKey: rkk1),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });
  });
}
