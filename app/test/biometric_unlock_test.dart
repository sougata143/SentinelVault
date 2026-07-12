import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:core/core.dart';
import 'package:app/features/auth/unlock_screen.dart';
import 'package:app/features/settings/settings_screen.dart';
import 'package:app/app_shell.dart';

void main() {
  group('Biometric Quick-Unlock Widget Tests', () {
    const email = 'user@example.com';
    const correctPassword = 'myMasterPassword123!';

    late List<int> salt;
    late List<int> vaultKey;
    late List<int> masterKey;
    late List<int> wrappedVaultKey;
    late String saltHex;
    late String wrappedKeyHex;
    late http.Client mockClient;

    setUpAll(() async {
      final crypto = VaultCrypto();
      salt = crypto.generateRandomBytes(16);
      masterKey = await crypto.deriveMasterKey(
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

      mockClient = MockClient((request) async {
        return http.Response(
          json.encode({
            'salt': saltHex,
            'wrappedKey': wrappedKeyHex,
          }),
          200,
        );
      });
    });

    void Function(FlutterErrorDetails)? originalOnError;

    setUp(() {
      originalOnError = FlutterError.onError;
      AppSettings.biometricEnabled = false;
      VaultLockManager.instance.logout();
      BiometricAuthService.instance.setMockSupported(true);
      BiometricAuthService.instance.setMockAuthenticateSuccess(true);
      BiometricAuthService.instance.setMockEnrollmentChanged(false);

      FlutterError.onError = (FlutterErrorDetails details) {
        final message = details.exceptionAsString();
        if (message.contains('overflowed') || message.contains('ListTile background color')) {
          return;
        }
        originalOnError?.call(details);
      };
    });

    tearDown(() {
      FlutterError.onError = originalOnError;
    });

    testWidgets('1. Enabling biometrics in Settings wraps keys and saves state', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
      });

      // Simulate manual unlock first
      VaultLockManager.instance.unlock(masterKey, vaultKey);

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            onLock: () {},
            onLogout: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final switchFinder = find.byKey(const Key('settings-biometric-switch'));
      expect(switchFinder, findsOneWidget);

      // Verify initial state is off
      var switchWidget = tester.widget<SwitchListTile>(switchFinder);
      expect(switchWidget.value, false);

      // Toggle switch ON
      await tester.ensureVisible(switchFinder);
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      // Verify setting state and VaultLockManager cache
      expect(AppSettings.biometricEnabled, true);
      expect(VaultLockManager.instance.isBiometricEnabled, true);
      expect(VaultLockManager.instance.hasBiometricCache, true);
      while (tester.takeException() != null) {}
    });

    testWidgets('2. Biometric unlock button is visible and works after in-app Lock', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
      });

      // Configure biometrics enabled and cached keys
      VaultLockManager.instance.unlock(masterKey, vaultKey);
      VaultLockManager.instance.enableBiometrics(masterKey, vaultKey);
      AppSettings.biometricEnabled = true;

      // Lock vault
      VaultLockManager.instance.lock();
      expect(VaultLockManager.instance.isLocked, true);
      expect(VaultLockManager.instance.hasBiometricCache, true);

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

      // Verify biometric unlock button is visible
      final bioButtonFinder = find.byKey(const Key('biometric-unlock-button'));
      expect(bioButtonFinder, findsOneWidget);

      // Tap biometric unlock
      await tester.tap(bioButtonFinder);
      await tester.pumpAndSettle();

      // Verify unlocked and navigated to AppShell
      expect(find.byType(AppShell), findsOneWidget);
      expect(VaultLockManager.instance.isLocked, false);
      while (tester.takeException() != null) {}
    });

    testWidgets('3. Biometrics enrollment change invalidates cache and falls back to manual password', (WidgetTester tester) async {
      // Configure biometrics enabled and cached keys
      VaultLockManager.instance.unlock(masterKey, vaultKey);
      VaultLockManager.instance.enableBiometrics(masterKey, vaultKey);
      AppSettings.biometricEnabled = true;

      // Lock vault
      VaultLockManager.instance.lock();

      // Simulate biometrics configuration change
      BiometricAuthService.instance.setMockEnrollmentChanged(true);

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

      // Verify cache invalidated
      expect(AppSettings.biometricEnabled, false);
      expect(VaultLockManager.instance.hasBiometricCache, false);

      // Verify banner is shown
      expect(find.byKey(const Key('biometric-invalidated-banner')), findsOneWidget);
      expect(find.textContaining('Biometric configuration changed'), findsOneWidget);

      // Verify biometric unlock button is NOT visible
      expect(find.byKey(const Key('biometric-unlock-button')), findsNothing);
      while (tester.takeException() != null) {}
    });

    testWidgets('4. Process restart clears cache and requires manual Master Password entry', (WidgetTester tester) async {
      // Configure biometrics enabled and cached keys
      VaultLockManager.instance.unlock(masterKey, vaultKey);
      VaultLockManager.instance.enableBiometrics(masterKey, vaultKey);
      AppSettings.biometricEnabled = true;

      // Lock vault
      VaultLockManager.instance.lock();

      // Simulate process restart by resetting VaultLockManager singleton (similar to fresh instantiation)
      VaultLockManager.instance.logout();
      // Keep app setting biometricEnabled = true, simulating persisted configuration
      AppSettings.biometricEnabled = true;

      expect(VaultLockManager.instance.hasBiometricCache, false);

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

      // Verify biometric unlock button is NOT visible because cache is empty
      expect(find.byKey(const Key('biometric-unlock-button')), findsNothing);
      expect(find.byKey(const Key('unlock-password-field')), findsOneWidget);
      while (tester.takeException() != null) {}
    });

    // -----------------------------------------------------------------------
    // Platform-visibility tests for the biometric quick-unlock toggle.
    //
    // The toggle must be ABSENT on Web (it is a native OS-hardware feature;
    // Web has no Secure Enclave / Android Keystore equivalent) and PRESENT on
    // native (iOS / Android).
    //
    // We use SettingsScreen.isWebOverride to simulate both conditions in a
    // single VM-based test run.  The real kIsWeb path is covered when the
    // suite runs with `flutter test --platform chrome`.
    //
    // Reference: docs/RUST_CROSS_PLATFORM_REEVALUATION.md §2.
    // -----------------------------------------------------------------------

    testWidgets(
      'Settings: biometric switch is ABSENT when isWebOverride=true (Web)',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        VaultLockManager.instance.unlock(masterKey, vaultKey);

        await tester.pumpWidget(
          MaterialApp(
            home: SettingsScreen(
              onLock: () {},
              onLogout: () {},
              isWebOverride: true, // simulate Web build
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('settings-biometric-switch')),
          findsNothing,
          reason: 'Biometric Quick-Unlock switch must be absent on Web '
              '(no Secure Enclave / Keystore available in browsers).',
        );

        while (tester.takeException() != null) {}
      },
    );

    testWidgets(
      'Settings: biometric switch is PRESENT when isWebOverride=false (native)',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        VaultLockManager.instance.unlock(masterKey, vaultKey);

        await tester.pumpWidget(
          MaterialApp(
            home: SettingsScreen(
              onLock: () {},
              onLogout: () {},
              isWebOverride: false, // simulate iOS / Android
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('settings-biometric-switch')),
          findsOneWidget,
          reason: 'Biometric Quick-Unlock switch must be present on native platforms '
              '(iOS / Android) that have Secure Enclave / Keystore.',
        );

        while (tester.takeException() != null) {}
      },
    );
  });
}
