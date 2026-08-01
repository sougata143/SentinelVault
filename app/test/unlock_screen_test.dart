import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:core/core.dart';
import 'package:app/features/auth/unlock_screen.dart';
import 'package:app/features/auth/master_password_setup_screen.dart';
import 'package:app/app_shell.dart';

void main() {
  group('UnlockScreen Widget Tests', () {
    const email = 'user@example.com';
    const correctPassword = 'myMasterPassword123!';
    const incorrectPassword = 'wrongMasterPassword';

    late List<int> salt;
    late List<int> vaultKey;
    late List<int> wrappedVaultKey;
    late String saltHex;
    late String wrappedKeyHex;

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
    });

    testWidgets('1. Correct Master Password succeeds and navigates to AppShell', (WidgetTester tester) async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/sync/vault-key');
        expect(request.headers['x-user-id'], email);
        return http.Response(
          json.encode({
            'salt': saltHex,
            'wrappedKey': wrappedKeyHex,
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

      // Verify loading is spinner is shown first, then loaded
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();

      expect(find.text('Vault is Locked'), findsOneWidget);
      expect(find.byKey(const Key('unlock-password-field')), findsOneWidget);

      // Input correct password
      await tester.enterText(find.byKey(const Key('unlock-password-field')), correctPassword);
      await tester.pump();

      // Submit
      final buttonFinder = find.byKey(const Key('decrypt-unlock-button'));
      await tester.ensureVisible(buttonFinder);
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(buttonFinder);
        // Wait dynamically for KDF derivation to complete
        await Future.delayed(const Duration(milliseconds: 1500));
      });
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Verify we navigated to AppShell
      expect(find.byType(AppShell), findsOneWidget);
    });

    testWidgets('2. Incorrect password displays generic error', (WidgetTester tester) async {
      final mockClient = MockClient((request) async {
        return http.Response(
          json.encode({
            'salt': saltHex,
            'wrappedKey': wrappedKeyHex,
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

      await tester.pumpAndSettle();

      // Input incorrect password
      await tester.enterText(find.byKey(const Key('unlock-password-field')), incorrectPassword);
      await tester.pump();

      // Submit
      final buttonFinder = find.byKey(const Key('decrypt-unlock-button'));
      await tester.ensureVisible(buttonFinder);
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(buttonFinder);
        await Future.delayed(const Duration(milliseconds: 1500));
      });
      await tester.pumpAndSettle();

      // Verify error is shown
      expect(find.text('Incorrect master password'), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
    });

    testWidgets('3. Repeated failures trigger increasing client-side lockout delay', (WidgetTester tester) async {
      final mockClient = MockClient((request) async {
        return http.Response(
          json.encode({
            'salt': saltHex,
            'wrappedKey': wrappedKeyHex,
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

      await tester.pumpAndSettle();

      final buttonFinder = find.byKey(const Key('decrypt-unlock-button'));
      await tester.ensureVisible(buttonFinder);
      await tester.pumpAndSettle();

      // Helper to submit incorrect password
      Future<void> submitIncorrectPassword() async {
        await tester.enterText(find.byKey(const Key('unlock-password-field')), incorrectPassword);
        await tester.pump();
        await tester.runAsync(() async {
          await tester.tap(buttonFinder);
          await Future.delayed(const Duration(milliseconds: 1500));
        });
        for (int i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      // 1st failure
      await submitIncorrectPassword();
      expect(find.textContaining('Locked for'), findsNothing);

      // 2nd failure
      await submitIncorrectPassword();
      expect(find.textContaining('Locked for'), findsNothing);

      // 3rd failure (triggers 2s delay)
      await submitIncorrectPassword();
      expect(find.textContaining('Locked for'), findsOneWidget);

      // Wait 2 seconds for lockout to expire in real time
      await tester.runAsync(() async {
        await Future.delayed(const Duration(seconds: 2));
      });
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.textContaining('Locked for'), findsNothing);

      // 4th failure (no increase yet, triggers 2s delay again)
      await submitIncorrectPassword();
      expect(find.textContaining('Locked for'), findsOneWidget);

      // Wait 2 seconds in real time
      await tester.runAsync(() async {
        await Future.delayed(const Duration(seconds: 2));
      });
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.textContaining('Locked for'), findsNothing);

      // 5th failure (triggers 5s delay)
      await submitIncorrectPassword();
      expect(find.textContaining('Locked for'), findsOneWidget);
    });

    testWidgets('4. 404 Not Found on key fetch redirects to MasterPasswordSetupScreen', (WidgetTester tester) async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/sync/vault-key');
        return http.Response(
          json.encode({
            'statusCode': 404,
            'message': 'Vault key not set',
          }),
          404,
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

      // Verify loading spinner is shown first
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();

      // Verify we navigated to MasterPasswordSetupScreen
      expect(find.byType(MasterPasswordSetupScreen), findsOneWidget);
    });
  });
}

