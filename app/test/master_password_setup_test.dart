import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app/features/auth/master_password_setup_screen.dart';
import 'package:app/features/settings/settings_screen.dart';
import 'package:app/app_shell.dart';

void main() {
  group('MasterPasswordSetupScreen Widget Tests', () {
    testWidgets('1. Successful setup uploads only salt and wrapped key (zero-knowledge)', (WidgetTester tester) async {
      AppSettings.autoLockEnabled = false;
      const email = 'newuser@example.com';
      const masterPasswordInput = 'mySecureMasterPassword99!';
      var requestChecked = false;

      // Intercept network call and verify zero-knowledge compliance
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/sync/vault-key');
        expect(request.headers['x-user-id'], email);
        expect(request.headers['Content-Type'], 'application/json');

        final body = json.decode(request.body) as Map<String, dynamic>;
        expect(body.containsKey('salt'), isTrue);
        expect(body.containsKey('wrappedKey'), isTrue);

        // Security Invariant Assertions:
        // 1. Raw password must NEVER cross the network
        expect(request.body.contains(masterPasswordInput), isFalse);
        expect(request.url.toString().contains(masterPasswordInput), isFalse);
        for (var headerValue in request.headers.values) {
          expect(headerValue.contains(masterPasswordInput), isFalse);
        }

        // 2. The derived Master Key must NEVER cross the network
        // The wrapped vault key has length of 12 + 16 + 32 = 60 bytes (120 hex characters)
        expect(body['wrappedKey'].length, 120);

        requestChecked = true;
        return http.Response(json.encode({'success': true}), 200);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: MasterPasswordSetupScreen(
            email: email,
            syncBaseUrl: 'http://fake-sync',
            httpClient: mockClient,
          ),
        ),
      );

      // Verify page details
      expect(find.text('Create Master Password'), findsOneWidget);
      expect(find.text('No Password Entered'), findsOneWidget);

      // Input Master Password
      await tester.enterText(find.byKey(const Key('master-password-field')), masterPasswordInput);
      await tester.pump();

      // Check strength meter updates
      expect(find.text('Strength: Very Strong'), findsOneWidget);

      // Input Confirm Password
      await tester.enterText(find.byKey(const Key('confirm-master-password-field')), masterPasswordInput);
      await tester.pump();

      // Scroll button into view to ensure it is hit-testable in test viewport
      final buttonFinder = find.byKey(const Key('create-master-button'));
      await tester.ensureVisible(buttonFinder);
      await tester.pumpAndSettle();

      // Submit
      await tester.runAsync(() async {
        await tester.tap(buttonFinder);
        var checks = 0;
        while (!requestChecked && checks < 200) {
          await Future.delayed(const Duration(milliseconds: 50));
          checks++;
        }
      });
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }





      // Check that the network request occurred and passed security checks
      expect(requestChecked, isTrue);

      // Tap "Do it later" on the Emergency Kit setup dialog
      final skipBtn = find.byKey(const Key('setup-recovery-skip-button'));
      expect(skipBtn, findsOneWidget);
      await tester.tap(skipBtn);
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Check that we successfully navigated to the dashboard shell (AppShell)
      expect(find.byType(AppShell), findsOneWidget);
    });

    testWidgets('2. Password validation and mismatch error display', (WidgetTester tester) async {
      final mockClient = MockClient((request) async {
        return http.Response('Error', 500);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: MasterPasswordSetupScreen(
            email: 'test@example.com',
            httpClient: mockClient,
          ),
        ),
      );

      // Submit empty password
      await tester.tap(find.byKey(const Key('create-master-button')));
      await tester.pumpAndSettle();

      expect(find.text('Master password is required'), findsOneWidget);

      // Submit short password
      await tester.enterText(find.byKey(const Key('master-password-field')), 'short');
      await tester.tap(find.byKey(const Key('create-master-button')));
      await tester.pumpAndSettle();

      expect(find.text('Password must be at least 8 characters'), findsOneWidget);

      // Submit password mismatch
      await tester.enterText(find.byKey(const Key('master-password-field')), 'validPassword123');
      await tester.enterText(find.byKey(const Key('confirm-master-password-field')), 'differentPassword123');
      await tester.tap(find.byKey(const Key('create-master-button')));
      await tester.pumpAndSettle();

      expect(find.text('Passwords do not match'), findsOneWidget);
    });
  });
}
