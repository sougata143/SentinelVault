import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:core/core.dart';
import 'package:app/app_shell.dart';
import 'package:app/features/auth/unlock_screen.dart';
import 'package:app/features/auth/login_screen.dart';
import 'package:app/features/settings/settings_screen.dart';

void main() {
  group('Lock and Logout Flow Widget Tests', () {
    const email = 'auditor@sentinelvault.io';
    late VaultDatabase db;
    late List<int> vaultKey;
    late List<int> masterKey;
    late AuthClient authClient;

    late String saltHex;
    late String wrappedKeyHex;
    late http.Client mockHttpClient;

    setUpAll(() async {
      final crypto = VaultCrypto();
      vaultKey = crypto.generateRandomBytes(32);
      masterKey = crypto.generateRandomBytes(32);

      final salt = crypto.generateRandomBytes(16);
      final derivedMasterKey = await crypto.deriveMasterKey(
        masterPassword: 'myMasterPassword123!',
        salt: salt,
      );
      final tempVaultKey = crypto.generateRandomBytes(32);
      final wrappedVaultKey = await crypto.wrapVaultKey(
        vaultKey: tempVaultKey,
        masterKey: derivedMasterKey,
      );

      saltHex = salt.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      wrappedKeyHex = wrappedVaultKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      mockHttpClient = MockClient((request) async {
        if (request.url.path == '/sync/vault-key') {
          return http.Response(
            json.encode({
              'salt': saltHex,
              'wrappedKey': wrappedKeyHex,
            }),
            200,
          );
        }
        return http.Response('', 404);
      });

      authClient = AuthClient(
        baseUrl: 'http://fake-auth',
        httpClient: mockHttpClient,
      );
    });

    setUp(() {
      db = SqliteVaultDatabase.inMemory();
      db.open(vaultKey);

      // Pre-set VaultLockManager state
      VaultLockManager.instance.logout();
      VaultLockManager.instance.setSession('session-token-xyz');
      VaultLockManager.instance.unlock(masterKey, vaultKey);
    });

    tearDown(() {
      db.close();
    });

    testWidgets('1. Manual Lock preserves session token but clears keys and returns to UnlockScreen', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppShell(
            db: db,
            vaultKey: vaultKey,
            currentEmail: email,
            authClient: authClient,
            httpClient: mockHttpClient,
            syncBaseUrl: 'http://fake-sync',
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Open Settings
      final settingsButton = find.byTooltip('Settings');
      expect(settingsButton, findsOneWidget);
      await tester.tap(settingsButton);
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);

      // Scroll to "Lock Vault Now" tile and tap it
      final lockTile = find.byKey(const Key('settings-lock-tile'));
      await tester.scrollUntilVisible(lockTile, 100.0);
      await tester.pumpAndSettle();
      expect(lockTile, findsOneWidget);
      await tester.tap(lockTile);

      // Pump to process navigation
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Verify returned to UnlockScreen
      expect(find.byType(UnlockScreen), findsOneWidget);

      // Verify VaultLockManager state
      expect(VaultLockManager.instance.isLocked, true);
      expect(VaultLockManager.instance.sessionToken, 'session-token-xyz');
    });

    testWidgets('2. Manual Log out clears both session token and keys and returns to LoginScreen', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppShell(
            db: db,
            vaultKey: vaultKey,
            currentEmail: email,
            authClient: authClient,
            httpClient: mockHttpClient,
            syncBaseUrl: 'http://fake-sync',
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Open Settings
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      // Scroll to "Log Out" tile and tap it
      final logoutTile = find.byKey(const Key('settings-logout-tile'));
      await tester.scrollUntilVisible(logoutTile, 100.0);
      await tester.pumpAndSettle();
      expect(logoutTile, findsOneWidget);
      await tester.tap(logoutTile);

      // Pump to process navigation
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Verify returned to LoginScreen
      expect(find.byType(LoginScreen), findsOneWidget);

      // Verify VaultLockManager state
      expect(VaultLockManager.instance.isLocked, true);
      expect(VaultLockManager.instance.sessionToken, isNull);
    });

    testWidgets('3. Inactivity triggers automatic locking', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppShell(
            db: db,
            vaultKey: vaultKey,
            currentEmail: email,
            authClient: authClient,
            httpClient: mockHttpClient,
            syncBaseUrl: 'http://fake-sync',
            autoLockTimeoutOverride: const Duration(seconds: 2),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Advance by 1 second (should not lock yet)
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(UnlockScreen), findsNothing);

      // Trigger user interaction to reset timer
      final listenerFinder = find.byKey(const Key('app-shell-root-listener'));
      expect(listenerFinder, findsOneWidget);
      await tester.tap(listenerFinder);
      await tester.pump();

      // Advance by 1 second again (timer reset, should not lock)
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(UnlockScreen), findsNothing);

      // Wait 2 seconds (timeout fires)
      await tester.pump(const Duration(seconds: 2));
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Verify auto-locked and navigated to UnlockScreen
      expect(find.byType(UnlockScreen), findsOneWidget);
      expect(VaultLockManager.instance.isLocked, true);
    });

    testWidgets('4. App backgrounding triggers automatic locking', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppShell(
            db: db,
            vaultKey: vaultKey,
            currentEmail: email,
            authClient: authClient,
            httpClient: mockHttpClient,
            syncBaseUrl: 'http://fake-sync',
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Send background lifecycle state (triggers lock)
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      // Transition back to resumed through hidden and inactive
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.idle();
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Verify locked and navigated to UnlockScreen
      expect(find.byType(UnlockScreen), findsOneWidget);
      expect(VaultLockManager.instance.isLocked, true);
    });
  });
}
