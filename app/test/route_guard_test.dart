import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/auth/route_guard.dart';
import 'package:app/features/auth/login_screen.dart';
import 'package:app/features/auth/unlock_screen.dart';
import 'package:core/core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Route Guard Widget Tests', () {
    setUp(() {
      // Reset VaultLockManager state before each test
      VaultLockManager.instance.logout();
    });

    testWidgets('1. No session → Login screen', (WidgetTester tester) async {
      // Ensure no session exists
      VaultLockManager.instance.logout();

      await tester.pumpWidget(
        const MaterialApp(
          home: RouteGuard(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify we're on the Login screen
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Log in to your account'), findsOneWidget);
      expect(find.text("Don't have an account? Sign up"), findsOneWidget);
    });

    testWidgets('2. Valid session, vault locked → Unlock screen', (WidgetTester tester) async {
      // Simulate having a valid session but locked vault
      VaultLockManager.instance.setSession('fake-session-token');
      // Vault is locked by default (vaultKey is null)

      await tester.pumpWidget(
        const MaterialApp(
          home: RouteGuard(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify we're on the Unlock screen
      expect(find.byType(UnlockScreen), findsOneWidget);
      expect(find.text('Vault is Locked'), findsOneWidget);
      expect(find.text('Master Password'), findsOneWidget);
    });

    testWidgets('3. Valid session, vault already unlocked → Dashboard placeholder', (WidgetTester tester) async {
      // Simulate having a valid session and unlocked vault
      VaultLockManager.instance.setSession('fake-session-token');
      // Unlock the vault with dummy keys
      VaultLockManager.instance.unlock(
        List<int>.filled(32, 1), // dummy master key
        List<int>.filled(32, 2), // dummy vault key
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: RouteGuard(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify we see the "already unlocked" placeholder
      expect(find.text('Vault is already unlocked'), findsOneWidget);
      expect(find.text('Lock Vault'), findsOneWidget);
    });

    testWidgets('4. Lock button clears vault key and returns to locked state', (WidgetTester tester) async {
      // Start with unlocked vault
      VaultLockManager.instance.setSession('fake-session-token');
      VaultLockManager.instance.unlock(
        List<int>.filled(32, 1),
        List<int>.filled(32, 2),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: RouteGuard(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify vault is unlocked
      expect(VaultLockManager.instance.isLocked, false);
      expect(find.text('Vault is already unlocked'), findsOneWidget);

      // Tap the Lock button
      await tester.tap(find.text('Lock Vault'));
      await tester.pumpAndSettle();

      // Verify vault is now locked
      expect(VaultLockManager.instance.isLocked, true);
      // Session should still be valid
      expect(VaultLockManager.instance.isLoggedIn, true);
    });

    testWidgets('5. Logout clears session and vault keys', (WidgetTester tester) async {
      // Start with logged in and unlocked vault
      VaultLockManager.instance.setSession('fake-session-token');
      VaultLockManager.instance.unlock(
        List<int>.filled(32, 1),
        List<int>.filled(32, 2),
      );

      // Verify state
      expect(VaultLockManager.instance.isLoggedIn, true);
      expect(VaultLockManager.instance.isLocked, false);

      // Logout
      VaultLockManager.instance.logout();

      // Verify both session and vault keys are cleared
      expect(VaultLockManager.instance.isLoggedIn, false);
      expect(VaultLockManager.instance.isLocked, true);
      expect(VaultLockManager.instance.vaultKey, null);
      expect(VaultLockManager.instance.masterKey, null);
    });
  });
}
