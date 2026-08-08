import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:core/core.dart';
import 'package:app/features/auth/login_screen.dart';
import 'package:app/features/auth/sign_up_screen.dart';
import 'package:app/features/auth/master_password_setup_screen.dart';
import 'package:app/features/auth/unlock_screen.dart';

class MockAuthClient implements AuthClient {
  bool loginCalled = false;
  bool registerCalled = false;
  String? lastEmail;
  String? lastPassword;

  @override
  String get baseUrl => 'http://mock-auth';

  @override
  Future<String> login(String email, String password) async {
    loginCalled = true;
    lastEmail = email;
    lastPassword = password;
    return 'mock-jwt-token';
  }

  @override
  Future<String> register(String email, String password) async {
    registerCalled = true;
    lastEmail = email;
    lastPassword = password;
    return 'mock-jwt-token';
  }

  @override
  Future<List<Map<String, dynamic>>> getSessions(String jwtToken) async => [];

  @override
  Future<bool> revokeSession(String jwtToken, String sessionId) async => true;

  @override
  List<int> hexToBytes(String hex) => [];
}

void main() {
  group('Enter/Return Key Form Submission Widget Tests', () {
    testWidgets('1. LoginScreen: Enter on email moves focus; Enter on password triggers login', (WidgetTester tester) async {
      final mockAuth = MockAuthClient();
      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(authClient: mockAuth),
        ),
      );

      final emailFinder = find.byKey(const Key('login-email-field'));
      final passwordFinder = find.byKey(const Key('login-password-field'));

      // Enter valid email and submit field via testTextInput
      await tester.enterText(emailFinder, 'test@example.com');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();

      // Enter password and trigger onFieldSubmitted (Enter key)
      await tester.enterText(passwordFinder, 'mySecretPass123');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(mockAuth.loginCalled, isTrue);
      expect(mockAuth.lastEmail, 'test@example.com');
      expect(mockAuth.lastPassword, 'mySecretPass123');
    });

    testWidgets('2. SignUpScreen: Enter shifts focus, final Enter triggers registration', (WidgetTester tester) async {
      final mockAuth = MockAuthClient();
      await tester.pumpWidget(
        MaterialApp(
          home: SignUpScreen(authClient: mockAuth),
        ),
      );

      final emailFinder = find.byKey(const Key('email-field'));
      final passwordFinder = find.byKey(const Key('password-field'));
      final confirmPasswordFinder = find.byKey(const Key('confirm-password-field'));

      await tester.enterText(emailFinder, 'newuser@example.com');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();

      await tester.enterText(passwordFinder, 'AccountPass123!');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();

      await tester.enterText(confirmPasswordFinder, 'AccountPass123!');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(mockAuth.registerCalled, isTrue);
      expect(mockAuth.lastEmail, 'newuser@example.com');
      expect(mockAuth.lastPassword, 'AccountPass123!');
    });

    testWidgets('3. MasterPasswordSetupScreen: Enter on confirm field triggers validation & setup', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MasterPasswordSetupScreen(
            email: 'user@example.com',
            syncBaseUrl: 'http://fake-sync',
          ),
        ),
      );

      final masterPwFinder = find.byKey(const Key('master-password-field'));
      final confirmPwFinder = find.byKey(const Key('confirm-master-password-field'));

      // Test validation: submit mismatched passwords via Enter
      await tester.enterText(masterPwFinder, 'MasterPassword123!');
      await tester.enterText(confirmPwFinder, 'MismatchPassword123!');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('Passwords do not match'), findsOneWidget);
    });

    testWidgets('4. UnlockScreen: Enter on password field triggers validation & unlock path', (WidgetTester tester) async {
      final mockClient = MockClient((request) async {
        return http.Response(
          json.encode({
            'salt': '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff',
            'wrappedKey': '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff',
          }),
          200,
        );
      });

      await tester.pumpWidget(
        MaterialApp(
          home: UnlockScreen(
            email: 'user@example.com',
            authClient: MockAuthClient(),
            syncBaseUrl: 'http://fake-sync',
            httpClient: mockClient,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final passwordFinder = find.byKey(const Key('unlock-password-field'));
      expect(passwordFinder, findsOneWidget);

      // Focus field and trigger Enter action
      await tester.tap(passwordFinder);
      await tester.pump();

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('Master password is required'), findsOneWidget);
    });
  });
}
