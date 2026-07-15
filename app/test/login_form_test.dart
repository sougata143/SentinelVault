import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/main.dart';
import 'package:app/features/vault/item_detail.dart';
import 'package:core/core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Login Form Widget Tests', () {
    testWidgets('1. Login Form Validation Checks', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp(home: VaultHomeScreen()));

      // Open Type Picker
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Tap Login
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle();

      // Tap Save without entering Title, Username or Password
      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();

      // Verify validation error messages are displayed
      expect(find.text('Title is required'), findsOneWidget);
      expect(find.text('Username is required'), findsOneWidget);
      expect(find.text('Password is required'), findsOneWidget);
    });

    testWidgets('2. Password Generator and Websites and OTP setup', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp(home: VaultHomeScreen()));

      // Open Type Picker
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Tap Login
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle();

      // Initially password field is empty
      final Finder pwFinder = find.byKey(const Key('password-field'));
      expect(tester.widget<TextFormField>(pwFinder).controller?.text, isEmpty);

      // Tap Generate Button
      final Finder genBtnFinder = find.byKey(const Key('generate-button'));
      await tester.tap(genBtnFinder);
      await tester.pump();

      // Verify password field is now populated with a 16-character generated password
      final generatedPassword = tester.widget<TextFormField>(pwFinder).controller?.text ?? '';
      expect(generatedPassword.length, equals(16));

      // Test Website URLs list interaction
      await tester.enterText(find.byType(TextFormField).at(3), 'https://github.com'); // Website input
      await tester.tap(find.byKey(const Key('add-url-button')));
      await tester.pump();
      expect(find.text('https://github.com'), findsOneWidget);

      // Test QR Scanner mock
      await tester.tap(find.byKey(const Key('scan-qr-button')));
      await tester.pump();
      expect(find.text('JBSWY3DPEHPK3PXP'), findsOneWidget);
    });

    testWidgets('3. Item Detail Reveal Toggle, Copy, and Clipboard Auto-Clear', (WidgetTester tester) async {
      final mockItem = VaultItem(
        id: 'test-detail-id',
        type: VaultItemType.login,
        title: 'Secret Service',
        tags: const [],
        favorite: false,
        vaultId: 'vault-1',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        notes: const ConcealedValue.plain(''),
        customFields: const [],
        fields: LoginFields(
          username: 'admin@vault.io',
          password: const ConcealedValue.plain('SuperSecretPassword99!'),
          urls: const [],
          otpSecret: const ConcealedValue.plain(''),
          passwordHistory: const [],
        ),
      );

      // Initialize clipboard channel to mock Clipboard actions
      final List<ClipboardData> clipboardLog = [];
      // Set up a mock handler for the clipboard channel
      // ignore: deprecated_member_use
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.setData') {
            final Map<String, dynamic> args = Map<String, dynamic>.from(call.arguments as Map);
            clipboardLog.add(ClipboardData(text: args['text'] as String));
            return null;
          }
          if (call.method == 'Clipboard.getData') {
            if (clipboardLog.isEmpty) return null;
            return {'text': clipboardLog.last.text};
          }
          return null;
        },
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ItemDetailPane(item: mockItem),
        ),
      ));

      // 1. Verify password is obscured by default
      expect(find.text('••••••••••••••••'), findsOneWidget);
      expect(find.text('SuperSecretPassword99!'), findsNothing);

      // 2. Tap the eye reveal icon to show the password
      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pump();

      // Verify password is now shown in plaintext
      expect(find.text('SuperSecretPassword99!'), findsOneWidget);
      expect(find.text('••••••••••••••••'), findsNothing);

      // 3. Tap the copy button for Password
      // Password is the second field (Username is first copy icon, Password is second)
      await tester.tap(find.byIcon(Icons.copy_outlined).at(1));
      await tester.pump();

      // Verify copied SnackBar is displayed
      expect(find.textContaining('Copied Password'), findsOneWidget);
      expect(clipboardLog.last.text, equals('SuperSecretPassword99!'));

      // 4. Wait for the clipboard timer timeout (30 seconds)
      for (int i = 0; i < 30; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump(); // Let SnackBar animation frame trigger

      // Verify clipboard is auto-cleared (last entry in clipboardLog is empty)
      expect(clipboardLog.last.text, isEmpty);
      expect(find.text('Clipboard auto-cleared for security'), findsOneWidget);
    });
  });
}
