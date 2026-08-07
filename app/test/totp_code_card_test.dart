import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/vault/totp_code_card.dart';
import 'package:core/core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TotpCodeCard Widget Tests', () {
    testWidgets('Renders issuer, account name, formatted code, and progress indicator', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TotpCodeCard(
              issuer: 'GitHub',
              accountName: 'user@example.com',
              secret: 'JBSWY3DPEHPK3PXP',
              algorithm: 'SHA1',
              digits: 6,
              period: 30,
            ),
          ),
        ),
      );

      // Verify text elements
      expect(find.text('GitHub'), findsOneWidget);
      expect(find.text('user@example.com'), findsOneWidget);

      // Verify progress indicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Verify code formatted text exists (formatted with space: 3 digits space 3 digits)
      final codeFinder = find.byWidgetPredicate((widget) {
        return widget is Text && widget.style?.fontFamily == 'monospace';
      });
      expect(codeFinder, findsOneWidget);
    });

    testWidgets('Renders properly via TotpCodeCard.fromFields constructor', (WidgetTester tester) async {
      final fields = TotpFields(
        issuer: 'Google',
        accountName: 'admin@sentinelvault.local',
        secret: const ConcealedValue.plain('JBSWY3DPEHPK3PXP'),
        algorithm: 'SHA256',
        digits: 8,
        period: 30,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TotpCodeCard.fromFields(fields: fields),
          ),
        ),
      );

      expect(find.text('Google'), findsOneWidget);
      expect(find.text('admin@sentinelvault.local'), findsOneWidget);
    });
  });
}
