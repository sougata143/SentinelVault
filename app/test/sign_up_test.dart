import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core/core.dart';
import 'package:app/features/auth/sign_up_screen.dart';
import 'package:app/features/auth/master_password_setup_screen.dart';
import 'package:app/features/auth/login_screen.dart';

class FakeAuthClient implements AuthClient {
  final bool shouldFailWithDuplicate;
  final bool shouldFailWithOther;
  String? registeredEmail;
  String? registeredPassword;

  FakeAuthClient({
    this.shouldFailWithDuplicate = false,
    this.shouldFailWithOther = false,
  });

  @override
  String get baseUrl => 'http://fake';

  @override
  Future<void> register(String email, String password) async {
    if (shouldFailWithDuplicate) {
      throw DuplicateEmailException('Username already exists');
    }
    if (shouldFailWithOther) {
      throw Exception('Server error');
    }
    registeredEmail = email;
    registeredPassword = password;
  }
}

void main() {
  group('SignUpScreen Widget Tests', () {
    testWidgets('1. Successful registration navigates to MasterPasswordSetupScreen', (WidgetTester tester) async {
      final fakeClient = FakeAuthClient();
      await tester.pumpWidget(
        MaterialApp(
          home: SignUpScreen(authClient: fakeClient),
        ),
      );

      // Enter signup details
      await tester.enterText(find.byKey(const Key('email-field')), 'newuser@example.com');
      await tester.enterText(find.byKey(const Key('password-field')), 'secureAccountPass123');
      await tester.enterText(find.byKey(const Key('confirm-password-field')), 'secureAccountPass123');
      await tester.pump();

      // Click sign up
      await tester.tap(find.byKey(const Key('register-button')));
      await tester.pumpAndSettle();

      // Check registration parameters were called correctly
      expect(fakeClient.registeredEmail, 'newuser@example.com');
      expect(fakeClient.registeredPassword, 'secureAccountPass123');

      // Check it navigated to MasterPasswordSetupScreen, not the dashboard
      expect(find.byType(MasterPasswordSetupScreen), findsOneWidget);
      expect(find.text('Create Master Password'), findsOneWidget);
    });

    testWidgets('2. Duplicate-email registration displays a clear error', (WidgetTester tester) async {
      final fakeClient = FakeAuthClient(shouldFailWithDuplicate: true);
      await tester.pumpWidget(
        MaterialApp(
          home: SignUpScreen(authClient: fakeClient),
        ),
      );

      // Enter signup details
      await tester.enterText(find.byKey(const Key('email-field')), 'duplicate@example.com');
      await tester.enterText(find.byKey(const Key('password-field')), 'somePassword123');
      await tester.enterText(find.byKey(const Key('confirm-password-field')), 'somePassword123');
      await tester.pump();

      // Click sign up
      await tester.tap(find.byKey(const Key('register-button')));
      await tester.pumpAndSettle();

      // Verify clear error is displayed
      expect(find.text('Email address already registered'), findsOneWidget);
      expect(find.byType(MasterPasswordSetupScreen), findsNothing);
    });

    testWidgets('3. Navigation link switches to Login screen', (WidgetTester tester) async {
      final fakeClient = FakeAuthClient();
      await tester.pumpWidget(
        MaterialApp(
          home: SignUpScreen(authClient: fakeClient),
        ),
      );

      // Click already have an account link
      await tester.tap(find.byKey(const Key('login-link')));
      await tester.pumpAndSettle();

      // Verify LoginScreen is shown
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Log in to your account'), findsOneWidget);
    });
  });
}
